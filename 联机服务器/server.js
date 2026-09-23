#!/usr/bin/env node
'use strict';
/**
 * 《电子蜂》中继服务器（relay）· 准生产 v1
 * ============================================================================
 * 口径（《边界约束》T7 v1.12 —— 硬约束，改动须走边界修订）：
 *   · 服务器**只做房间管理与操作转发**：不跑规则、不裁决、不持有对局状态、**不解释 payload**
 *   · **只传玩家操作数据**（客户端不发状态、服务器不下发状态）
 *   · 一方掉线 → 对局结束（本实现：立即结束并把房间回收）
 *   · 版本不匹配 → 拒绝入房（hello.proto 与配置 proto 不符即断）
 *   · 棋盘镜像由**客户端**负责（服务器不感知敌我上下）
 * 传输：WebSocket。生产建议由面板（宝塔）反向代理终止 TLS → wss（本进程亦可自持证书，见 README）
 * 配置：node server.js --config config.prod.json    或    CONFIG=config.prod.json node server.js
 *        环境变量可覆盖：SB_HOST / SB_PORT / SB_PATH / SB_PROTO / SB_LOG_PRETTY
 * 协议：见 系统维护/网络联机/扩展-001-中继协议v1.md（与客户端 scripts/net/ 同源）
 * ============================================================================
 */

const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');

/** 错误码（客户端 scripts/net/relay_client.gd 同表） */
const ERR = {
  VERSION_MISMATCH: 'VERSION_MISMATCH',
  BAD_MSG: 'BAD_MSG',
  NOT_HELLO: 'NOT_HELLO',
  ALREADY_HELLO: 'ALREADY_HELLO',
  ROOM_FULL: 'ROOM_FULL',
  ROOM_NOT_FOUND: 'ROOM_NOT_FOUND',
  NEED_TWO_PLAYERS: 'NEED_TWO_PLAYERS',
  NOT_IN_ROOM: 'NOT_IN_ROOM',
  NOT_HOST: 'NOT_HOST',
  NOT_STARTED: 'NOT_STARTED',
  RATE_LIMIT: 'RATE_LIMIT',
  ORIGIN_REJECTED: 'ORIGIN_REJECTED',
  NEED_WSS: 'NEED_WSS'
};

/** 消息 schema：只校验**结构与类型**，绝不解释 payload 内容（T7） */
const SCHEMA = {
  hello: { proto: 'number', build: 'string?' },
  create: {},
  join: { code: 'string' },
  leave: {},
  start: {},
  op: { seq: 'number', frame: 'number', payload: 'any' },
  ping: { t: 'number?' }
};

// ---------------------------------------------------------------------------
// 配置
// ---------------------------------------------------------------------------
function loadConfig(argv) {
  let file = process.env.CONFIG || 'config.test.json';
  const i = argv.indexOf('--config');
  if (i >= 0 && argv[i + 1]) file = argv[i + 1];
  const abs = path.isAbsolute(file) ? file : path.join(__dirname, file);
  const cfg = JSON.parse(fs.readFileSync(abs, 'utf8'));
  const envMap = {
    SB_HOST: 'host', SB_PORT: 'port', SB_PATH: 'path', SB_PROTO: 'proto',
    SB_LOG_PRETTY: 'log_pretty', SB_ADMIN_TOKEN: 'admin_token', SB_REQUIRE_WSS: 'require_wss'
  };
  for (const [envKey, key] of Object.entries(envMap)) {
    const raw = process.env[envKey];
    if (raw === undefined || raw === '') continue;
    cfg[key] = raw === 'true' ? true : raw === 'false' ? false : (isNaN(Number(raw)) ? raw : Number(raw));
  }
  cfg.__file = path.basename(abs);
  return cfg;
}

// ---------------------------------------------------------------------------
// 日志（结构化；**永不打印 payload 内容**，只记长度）
// ---------------------------------------------------------------------------
/** 内置管理系统：最近日志环形缓冲（最多 500 条；**日志本身就不打印 payload 内容**，故不含玩家操作） */
const LOG_RING = [];
const LOG_RING_MAX = 500;

function makeLogger(cfg) {
  const pretty = cfg.log_pretty !== false;
  return function log(level, evt, fields) {
    const rec = { ts: new Date().toISOString(), level, evt, ...(fields || {}) };
    LOG_RING.push(rec);
    if (LOG_RING.length > LOG_RING_MAX) LOG_RING.shift();
    if (pretty) {
      const { ts, level: lv, evt: e, ...rest } = rec;
      console.log(`[${ts}] ${String(lv).toUpperCase().padEnd(5)} ${e} ${Object.keys(rest).length ? JSON.stringify(rest) : ''}`);
    } else {
      console.log(JSON.stringify(rec));
    }
  };
}

// ---------------------------------------------------------------------------
// 服务器
// ---------------------------------------------------------------------------
function createServer(cfg) {
  const log = makeLogger(cfg);
  const proto = Number(cfg.proto) || 1;
  const roomMax = Number(cfg.room_max) || 2;
  const idleMs = Number(cfg.idle_timeout_ms) || 60000;
  const hbMs = Number(cfg.hb_interval_ms) || 15000;
  const maxMsg = Number(cfg.max_msg_bytes) || 32768;
  const rl = cfg.rate_limit || {};
  const rlBurst = Number(rl.burst) || 60;
  const rlPerSec = Number(rl.per_sec) || 30;
  const allowOrigins = Array.isArray(cfg.allow_origins) ? cfg.allow_origins : [];

  const stats = {
    started_at: Date.now(), conns: 0, conns_total: 0, rooms_created: 0,
    ops_relayed: 0, rejects: 0, version_rejects: 0, payload_bytes: 0
  };
  const rooms = new Map();
  const conns = new Set();
  let sseqCounter = 0;

  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 去掉易混字符 I/O/0/1
  function newCode() {
    let s = '';
    do {
      s = '';
      for (let i = 0; i < 6; i++) s += alphabet[crypto.randomInt(alphabet.length)];
    } while (rooms.has(s));
    return s;
  }

  // ---- 发送 / 拒绝 ----
  function send(conn, obj) {
    if (!conn || conn.ws.readyState !== conn.ws.OPEN) return false;
    try {
      const s = JSON.stringify(obj);
      conn.ws.send(s);
      conn.bytes_out += Buffer.byteLength(s); // 管理面板统计
      return true;
    } catch (e) { log('warn', 'send.fail', { sid: conn.sid, err: String(e && e.message) }); return false; }
  }
  function fail(conn, code, msg, fatal) {
    stats.rejects++;
    if (code === ERR.VERSION_MISMATCH) stats.version_rejects++;
    log('info', 'reject', { sid: conn.sid, code, msg: msg || '' });
    send(conn, { t: 'err', code, msg: msg || '' });
    if (fatal) {
      // ⚠️ 先让 err 出网再关闭：立即 close 可能让客户端丢掉最后一条报文（迭代061 检查点2 实测踩到）
      setTimeout(() => { try { conn.ws.close(1008, code); } catch (_) {} }, 120);
    }
    return false;
  }
  function validate(type, msg) {
    const spec = SCHEMA[type];
    if (!spec) return 'unknown type: ' + type;
    for (const [field, kind] of Object.entries(spec)) {
      const optional = kind.endsWith('?');
      const k = optional ? kind.slice(0, -1) : kind;
      if (msg[field] === undefined) { if (!optional) return 'missing field: ' + field; else continue; }
      if (k === 'any') continue;
      if (typeof msg[field] !== k) return 'bad type: ' + field + ' (want ' + k + ')';
      if (k === 'number' && !Number.isFinite(msg[field])) return 'bad number: ' + field;
    }
    return null;
  }

  // ---- 房间 ----
  function createRoom(conn) {
    if (conn.room) { detach(conn, 'recreate'); }
    const room = {
      code: newCode(), state: 'waiting', created_at: Date.now(),
      started_at: 0, ops_relayed: 0, payload_bytes: 0,
      peers: new Array(roomMax).fill(null), seed: 0, first_side: 0
    };
    rooms.set(room.code, room);
    stats.rooms_created++;
    conn.room = room; conn.seat = 0; room.peers[0] = conn;
    send(conn, { t: 'room', code: room.code, seat: 0, players: [conn.name, null] });
    log('info', 'room.created', { code: room.code, sid: conn.sid, name: conn.name });
    return true;
  }
  function joinRoom(conn, code) {
    const room = rooms.get(String(code || '').toUpperCase());
    if (!room) return fail(conn, ERR.ROOM_NOT_FOUND);
    if (conn.room) detach(conn, 'rejoin');
    let seat = -1;
    for (let i = 0; i < roomMax; i++) if (!room.peers[i]) { seat = i; break; }
    if (seat < 0) return fail(conn, ERR.ROOM_FULL);
    if (room.state !== 'waiting') return fail(conn, ERR.ROOM_FULL, 'room already playing');
    room.peers[seat] = conn; conn.room = room; conn.seat = seat;
    send(conn, { t: 'room', code: room.code, seat, players: room.peers.map(p => (p ? p.name : null)) });
    for (let i = 0; i < roomMax; i++) {
      const p = room.peers[i];
      if (p && p !== conn) send(p, { t: 'peer_joined', seat, name: conn.name });
    }
    log('info', 'room.joined', { code: room.code, sid: conn.sid, seat, name: conn.name });
    return true;
  }
  function startMatch(conn) {
    const room = conn.room;
    if (!room) return fail(conn, ERR.NOT_IN_ROOM);
    if (conn.seat !== 0) return fail(conn, ERR.NOT_HOST);
    const filled = room.peers.filter(Boolean).length;
    if (filled < 2) return fail(conn, ERR.NEED_TWO_PLAYERS);
    room.state = 'playing';
    room.started_at = Date.now();
    room.seed = crypto.randomInt(1, 2147483647);
    room.first_side = crypto.randomInt(0, 2); // 0=绿方先手（与引擎 SIDE_ALLY 对齐）
    const payload = { t: 'start', seed: room.seed, first_side: room.first_side, proto };
    for (const p of room.peers) if (p) send(p, payload);
    log('info', 'match.started', { code: room.code, seed: room.seed, first_side: room.first_side });
    return true;
  }
  function relayOp(conn, msg) {
    const room = conn.room;
    if (!room) return fail(conn, ERR.NOT_IN_ROOM);
    if (room.state !== 'playing') return fail(conn, ERR.NOT_STARTED);
    const payloadSize = JSON.stringify(msg.payload === undefined ? null : msg.payload).length;
    stats.payload_bytes += payloadSize;
    room.payload_bytes += payloadSize;
    const out = {
      t: 'op', seat: conn.seat, seq: msg.seq, frame: msg.frame,
      payload: msg.payload, sseq: ++sseqCounter
    };
    stats.ops_relayed++;
    room.ops_relayed++; // 内置管理系统：按房统计
    for (const p of room.peers) if (p && p !== conn) send(p, out);
    send(conn, { t: 'op_ack', seq: msg.seq, sseq: out.sseq });
    return true;
  }
  function detach(conn, reason) {
    const room = conn.room;
    if (!room) { conn.room = null; conn.seat = null; return; }
    const seat = conn.seat;
    if (room.peers[seat] === conn) room.peers[seat] = null;
    conn.room = null; conn.seat = null;
    const others = room.peers.filter(Boolean);
    if (others.length) {
      // T7：一方掉线 → 对局结束（立即结束，不做重连）
      for (const p of others) {
        send(p, { t: 'peer_left', seat, reason: reason || 'left', ended: true });
        p.room = null; p.seat = null;
      }
      room.peers = new Array(roomMax).fill(null);
    }
    room.state = 'closed';
    rooms.delete(room.code);
    log('info', 'room.closed', { code: room.code, reason: reason || 'left', by_seat: seat, had_peer: others.length > 0 });
  }

  // ---- HTTP（健康检查 + 索引页）----
  const indexFile = path.join(__dirname, 'index.html');
  const server = http.createServer((req, res) => {
    let pathname = '/';
    try { pathname = new URL(req.url, 'http://placeholder').pathname; } catch (_) {}
    // ---- 内置管理系统（/admin）----
    if (pathname === '/admin' || pathname === '/admin.html' || pathname.startsWith('/admin/')) {
      handleAdmin(req, res, pathname);
      return;
    }
    if (pathname === '/healthz') {
      const body = JSON.stringify(health(), null, 2);
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      res.end(body);
      return;
    }
    if ((pathname === '/' || pathname === '/index.html') && cfg.serve_index !== false && fs.existsSync(indexFile)) {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(fs.readFileSync(indexFile));
      return;
    }
    res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    res.end('not found');
  });

  function health() {
    return {
      ok: true,
      proto,
      build: cfg.build || '',
      config: cfg.__file,
      uptime_s: Math.round((Date.now() - stats.started_at) / 1000),
      conns: stats.conns,
      conns_total: stats.conns_total,
      rooms: rooms.size,
      rooms_created: stats.rooms_created,
      ops_relayed: stats.ops_relayed,
      payload_bytes: stats.payload_bytes,
      rejects: stats.rejects,
      version_rejects: stats.version_rejects,
      require_wss: !!cfg.require_wss
    };
  }

  // ========================================================================
  //  内置管理系统（/admin）—— 只做「观察 + 运维处置」
  //  ★ 与 T7 不冲突：面板**不能**注入操作、不能改对局数据；只能「看」与「关房/踢线」
  //  鉴权：① 配了 admin_token → 需 Bearer token（或 ?token=），常量时间比较
  //        ② 未配 token → **仅允许环回地址**（127.0.0.1/::1），外网一律 403
  //  端点：GET  /admin（页面）· /admin/api/summary|rooms|conns|log
  //        POST /admin/api/room/close · /admin/api/conn/kick · /admin/api/rooms/close_all
  // ========================================================================
  const ADMIN_TOKEN = String(cfg.admin_token || '');
  // 管理口令必须是 **ASCII 可见字符**：HTTP 头只能承载 latin-1 → 含中文会在浏览器 / nginx 侧被拒或乱码
  if (ADMIN_TOKEN !== '' && /[^\x20-\x7E]/.test(ADMIN_TOKEN)) {
    log('error', 'admin_token.invalid', {
      hint: 'admin_token 只能含 ASCII 可见字符；请改用随机 ASCII 串（例：openssl rand -hex 24）后重启'
    });
    throw new Error('admin_token 含非 ASCII 字符');
  }
  if (ADMIN_TOKEN !== '' && ADMIN_TOKEN.length < 12) {
    log('warn', 'admin_token.weak', { len: ADMIN_TOKEN.length, hint: '建议 ≥24 位随机 ASCII' });
  }
  const ADMIN_MAX_BODY = 4096;

  function timingEq(a, b) {
    const x = Buffer.from(String(a)), y = Buffer.from(String(b));
    if (x.length !== y.length) return false;
    return crypto.timingSafeEqual(x, y);
  }
  /** ⚠️ 判定必须**只看 socket 地址**：X-Forwarded-For 客户端可伪造（迭代061 修缺陷） */
  function isLoopback(req) {
    const ip = String((req.socket && req.socket.remoteAddress) || '');
    return ip === '127.0.0.1' || ip === '::1' || ip === '::ffff:127.0.0.1';
  }
  /** 是否经过反向代理：宝塔 Node 项目默认对 `/` 做反代 → socket 恒为 127.0.0.1，光看地址判不出内外 */
  function isProxied(req) {
    return !!(req.headers['x-forwarded-for'] || req.headers['x-forwarded-proto'] || req.headers['x-real-ip']);
  }
  function adminAuth(req, url) {
    if (ADMIN_TOKEN !== '') {
      const h = String(req.headers.authorization || '');
      const bearer = h.startsWith('Bearer ') ? h.slice(7) : '';
      const q = String(url.searchParams.get('token') || '');
      const ok = (bearer !== '' && timingEq(bearer, ADMIN_TOKEN)) || (q !== '' && timingEq(q, ADMIN_TOKEN));
      return ok ? null : 'TOKEN_REQUIRED';
    }
    // ⚠️ 关键修复（2026-09-23）：反代场景下 socket 恒为 127.0.0.1 —— 若未配 admin_token，
    //    仅凭 socket 判定会让公网请求直接穿透到管理面板 → 带代理头的一律拒绝
    if (isProxied(req)) return 'PROXY_DENIED';
    return isLoopback(req) ? null : 'LOOPBACK_ONLY';
  }
  function readBody(req, cb) {
    let raw = '';
    req.on('data', (c) => { raw += c; if (raw.length > ADMIN_MAX_BODY) req.destroy(); });
    req.on('end', () => {
      if (!raw) return cb({});
      try { cb(JSON.parse(raw)); } catch (_) { cb(null); }
    });
  }
  function sendJson(res, code, obj) {
    res.writeHead(code, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
    res.end(JSON.stringify(obj, null, 2));
  }
  function connView(c) {
    return {
      sid: c.sid, ip: c.peer_ip, room: c.room ? c.room.code : null, seat: c.seat,
      name: c.name, hello: c.hello,
      age_s: Math.round((Date.now() - c.created_at) / 1000),
      idle_s: Math.round((Date.now() - c.last_seen) / 1000),
      msgs: c.msgs, bytes_in: c.bytes_in, bytes_out: c.bytes_out
    };
  }
  function roomView(r) {
    return {
      code: r.code, state: r.state,
      age_s: Math.round((Date.now() - r.created_at) / 1000),
      playing_s: r.state === 'playing' ? Math.round((Date.now() - r.started_at) / 1000) : 0,
      seed: r.seed, first_side: r.first_side,
      ops_relayed: r.ops_relayed, payload_bytes: r.payload_bytes,
      seats: r.peers.map((p, i) => (p
        ? { seat: i, name: p.name, ip: p.peer_ip, sid: p.sid, idle_s: Math.round((Date.now() - p.last_seen) / 1000) }
        : { seat: i, empty: true }))
    };
  }
  function closeRoomByCode(code, reason) {
    const room = rooms.get(String(code || '').toUpperCase());
    if (!room) return false;
    for (const p of room.peers) {
      if (!p) continue;
      send(p, { t: 'peer_left', seat: p.seat, reason: reason || 'admin_close', ended: true });
      p.room = null; p.seat = null;
      setTimeout(() => { try { p.ws.close(1001, 'admin_close'); } catch (_) {} }, 120);
    }
    room.peers = new Array(roomMax).fill(null);
    room.state = 'closed';
    rooms.delete(room.code);
    log('warn', 'admin.room_close', { code: room.code, reason: reason || 'admin_close' });
    return true;
  }
  function handleAdmin(req, res, pathname) {
    let url;
    try { url = new URL(req.url, 'http://placeholder'); } catch (_) { return sendJson(res, 400, { ok: false, error: 'BAD_URL' }); }
    // 面板页本身不含机密 → **免鉴权**（API 一律鉴权）；否则浏览器打不开页面、也就没地方填 token
    if (pathname === '/admin' || pathname === '/admin.html') {
      const f = path.join(__dirname, 'admin.html');
      if (!fs.existsSync(f)) return sendJson(res, 404, { ok: false, error: 'admin.html missing' });
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
      return res.end(fs.readFileSync(f));
    }
    const deny = adminAuth(req, url);
    if (deny) {
      log('warn', 'admin.denied', { path: pathname, reason: deny, ip: req.socket.remoteAddress });
      return sendJson(res, deny === 'TOKEN_REQUIRED' ? 401 : 403, { ok: false, error: deny });
    }
    const api = pathname.replace(/^\/admin\/api\/?/, '');
    if (req.method === 'GET') {
      if (api === 'summary') {
        return sendJson(res, 200, {
          ok: true, health: health(),
          admin: { token_required: ADMIN_TOKEN !== '', loopback_only: ADMIN_TOKEN === '' },
          log_ring: LOG_RING.length
        });
      }
      if (api === 'rooms') return sendJson(res, 200, { ok: true, rooms: [...rooms.values()].map(roomView) });
      if (api === 'conns') return sendJson(res, 200, { ok: true, conns: [...conns].map(connView) });
      if (api === 'log') {
        const n = Math.min(Number(url.searchParams.get('n')) || 100, LOG_RING_MAX);
        return sendJson(res, 200, { ok: true, lines: LOG_RING.slice(-n) });
      }
      return sendJson(res, 404, { ok: false, error: 'unknown admin api: ' + api });
    }
    if (req.method === 'POST') {
      return readBody(req, (body) => {
        if (body === null) return sendJson(res, 400, { ok: false, error: 'BAD_JSON' });
        if (api === 'room/close') {
          const okc = closeRoomByCode(body.code, body.reason || 'admin_close');
          return sendJson(res, okc ? 200 : 404, { ok: okc, code: body.code || '' });
        }
        if (api === 'conn/kick') {
          const target = [...conns].find((c) => c.sid === String(body.sid || ''));
          if (!target) return sendJson(res, 404, { ok: false, error: 'conn not found' });
          log('warn', 'admin.kick', { sid: target.sid, reason: body.reason || 'admin_kick' });
          detach(target, 'admin_kick');
          try { target.ws.close(1008, 'admin_kick'); } catch (_) {}
          return sendJson(res, 200, { ok: true, sid: target.sid });
        }
        if (api === 'rooms/close_all') {
          const codes = [...rooms.keys()];
          for (const c of codes) closeRoomByCode(c, body.reason || 'admin_close_all');
          return sendJson(res, 200, { ok: true, closed: codes.length });
        }
        return sendJson(res, 404, { ok: false, error: 'unknown admin api: ' + api });
      });
    }
    return sendJson(res, 405, { ok: false, error: 'method not allowed' });
  }

  // ---- WebSocket ----
  const wss = new WebSocketServer({ server, path: cfg.path || '/relay', maxPayload: maxMsg });

  // 准生产：监听级错误要给出可操作提示，而不是只抛 uncaught
  server.on('error', (e) => {
    log('error', 'server.error', { code: e && e.code, err: String(e && e.message) });
    if (e && e.code === 'EADDRINUSE') {
      log('error', 'hint', { hint: `端口被占用：改 config 的 port，或用 SB_PORT=<空闲端口> node server.js --config <cfg> 覆盖` });
    }
    process.exit(1);
  });
  wss.on('error', (e) => log('error', 'wss.error', { err: String(e && e.message) }));

  wss.on('connection', (ws, req) => {
    const origin = String(req.headers.origin || '');
    const xfproto = String(req.headers['x-forwarded-proto'] || '').split(',')[0].trim();
    const secure = !!(req.socket && req.socket.encrypted) || xfproto === 'https';
    const conn = {
      sid: crypto.randomBytes(6).toString('hex'),
      ws, room: null, seat: null, name: null, hello: false,
      alive: true, last_seen: Date.now(), bucket: rlBurst, bucket_ts: Date.now(),
      created_at: Date.now(), msgs: 0, bytes_in: 0, bytes_out: 0,
      peer_ip: (req.headers['x-forwarded-for'] || '').split(',')[0].trim() || (req.socket.remoteAddress || '')
    };
    conns.add(conn);
    stats.conns = conns.size; stats.conns_total++;
    log('info', 'conn.open', { sid: conn.sid, ip: conn.peer_ip, origin, secure });

    if (allowOrigins.length && origin && !allowOrigins.includes(origin)) {
      fail(conn, ERR.ORIGIN_REJECTED, origin, true);
      return;
    }
    if (cfg.require_wss && !secure) {
      fail(conn, ERR.NEED_WSS, 'wss required', true);
      return;
    }

    ws.on('pong', () => { conn.alive = true; conn.last_seen = Date.now(); });
    ws.on('close', () => {
      detach(conn, 'disconnect');
      conns.delete(conn);
      stats.conns = conns.size;
      log('info', 'conn.close', { sid: conn.sid, code: ws.readyState });
    });
    ws.on('error', (e) => log('warn', 'conn.error', { sid: conn.sid, err: String(e && e.message) }));

    ws.on('message', (data, isBinary) => {
      conn.last_seen = Date.now();
      conn.msgs++;
      conn.bytes_in += data.length;
      // 令牌桶限流
      const now = Date.now();
      if (now - conn.bucket_ts >= 1000) {
        conn.bucket = rlBurst; conn.bucket_ts = now;
      }
      if (conn.bucket <= 0) return fail(conn, ERR.RATE_LIMIT);
      conn.bucket--;
      if (isBinary) return fail(conn, ERR.BAD_MSG, 'binary not supported in proto 1');
      const raw = data.toString('utf8');
      if (raw.length > maxMsg) return fail(conn, ERR.BAD_MSG, 'too large', true);
      let msg;
      try { msg = JSON.parse(raw); } catch (_) { return fail(conn, ERR.BAD_MSG, 'invalid json'); }
      if (!msg || typeof msg !== 'object' || typeof msg.t !== 'string') return fail(conn, ERR.BAD_MSG, 'missing t');
      const bad = validate(msg.t, msg);
      if (bad) return fail(conn, ERR.BAD_MSG, bad);

      if (msg.t !== 'hello' && !conn.hello) return fail(conn, ERR.NOT_HELLO, '', true);

      switch (msg.t) {
        case 'hello': {
          if (conn.hello) return fail(conn, ERR.ALREADY_HELLO);
          if (Number(msg.proto) !== proto) return fail(conn, ERR.VERSION_MISMATCH, `server proto=${proto}`, true);
          conn.hello = true;
          conn.name = String(msg.build || '').slice(0, 32) || null; // build 仅作展示名用途，不参与判定
          send(conn, { t: 'welcome', sid: conn.sid, proto, build: cfg.build || '', server_time: Date.now() });
          log('info', 'conn.hello', { sid: conn.sid, client_build: msg.build || '' });
          return;
        }
        case 'ping': return void send(conn, { t: 'pong', t: msg.t === undefined ? 0 : msg.t });
        case 'create': return void createRoom(conn);
        case 'join': return void joinRoom(conn, msg.code);
        case 'leave': return void (detach(conn, 'leave'), send(conn, { t: 'left' }));
        case 'start': return void startMatch(conn);
        case 'op': return void relayOp(conn, msg);
        default: return fail(conn, ERR.BAD_MSG, 'unhandled type ' + msg.t);
      }
    });
  });

  // ---- 心跳 & 空闲回收 ----
  const hbTimer = setInterval(() => {
    const now = Date.now();
    for (const conn of conns) {
      if (!conn.alive) { log('info', 'conn.dead', { sid: conn.sid }); try { conn.ws.terminate(); } catch (_) {} continue; }
      conn.alive = false;
      try { conn.ws.ping(); } catch (_) {}
      if (now - conn.last_seen > idleMs) { log('info', 'conn.idle', { sid: conn.sid }); try { conn.ws.close(1001, 'idle'); } catch (_) {} }
    }
  }, hbMs);
  hbTimer.unref();

  function shutdown(sig) {
    log('info', 'shutdown.begin', { sig });
    clearInterval(hbTimer);
    for (const c of wss.clients) { try { c.close(1001, 'server shutting down'); } catch (_) {} }
    server.close(() => { log('info', 'shutdown.done', {}); process.exit(0); });
    setTimeout(() => process.exit(0), 3000).unref();
  }

  return { server, wss, cfg, log, stats, rooms, conns, health, shutdown };
}

function main() {
  const cfg = loadConfig(process.argv.slice(2));
  const app = createServer(cfg);
  app.server.listen(Number(cfg.port) || 8080, cfg.host || '0.0.0.0', () => {
    app.log('info', 'server.listen', {
      host: cfg.host, port: cfg.port, path: cfg.path, proto: cfg.proto,
      build: cfg.build, require_wss: !!cfg.require_wss, room_max: cfg.room_max,
      max_msg_bytes: cfg.max_msg_bytes, config: cfg.__file
    });
  });
  ['SIGTERM', 'SIGINT'].forEach((s) => process.on(s, () => app.shutdown(s)));
  process.on('uncaughtException', (e) => { app.log('error', 'uncaught', { err: String(e && e.stack || e) }); process.exit(1); });
  process.on('unhandledRejection', (e) => { app.log('error', 'unhandled', { err: String(e) }); process.exit(1); });
}

if (require.main === module) main();
module.exports = { loadConfig, createServer, ERR, SCHEMA };
