#!/usr/bin/env node
'use strict';
/**
 * 检查点 1 冒烟：本地回环验证中继（建房 / 加入 / 转发 / **payload 原样透传** / 版本拒绝 / 掉线即结束）
 * 用法：node tools/smoke_client.js --config config.test.json     （需先起服）
 */
const WebSocket = require('ws');
const { loadConfig } = require('../server.js');

const cfg = loadConfig(process.argv.slice(2));
// 目标 URL：默认本机测试档；用 `--url=wss://域名/relay` 可对**公网域名**跑同一套断言（跨机联机验证）
const urlArg = process.argv.slice(2).find((a) => a.startsWith('--url='));
const URL = urlArg ? urlArg.slice(6) : `ws://127.0.0.1:${cfg.port}${cfg.path}`;
const PROTO = Number(cfg.proto) || 1;
const results = [];
let failed = 0;

function check(ok, label, detail) {
  results.push({ ok, label });
  if (!ok) failed++;
  console.log(`${ok ? '  PASS' : '  FAIL'}  ${label}${detail ? '  — ' + detail : ''}`);
}
function mk(proto) {
  const ws = new WebSocket(URL);
  ws.__inbox = [];
  ws.on('message', (d) => { try { ws.__inbox.push(JSON.parse(d.toString('utf8'))); } catch (_) {} });
  // 加固：连接级错误不能让脚本崩（如服务未起/端口被占回 404）→ 记录后由断言体现
  ws.on('error', (e) => { ws.__error = String(e && e.message); });
  return ws;
}
function wait(ws, t, timeout = 2500) {
  return new Promise((res) => {
    const t0 = Date.now();
    const iv = setInterval(() => {
      const i = ws.__inbox.findIndex((m) => m.t === t);
      if (i >= 0) { clearInterval(iv); res(ws.__inbox.splice(i, 1)[0]); }
      else if (Date.now() - t0 > timeout) { clearInterval(iv); res(null); }
    }, 15);
  });
}
/** ⚠️ 先查 readyState：socket 可能在监听器挂上前就已 open（事件错过 → await 永久挂起） */
const open = (ws) => new Promise((r) => {
  if (ws.readyState === 1) return r();
  ws.once('open', r);
  ws.once('error', () => r());
  ws.once('close', () => r());
});
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  console.log(`== 目标 ${URL} · server proto=${PROTO} · config=${cfg.__file} ==`);

  // 0) 版本不匹配 → 拒绝并断开（T7）
  const c = mk(PROTO + 98);
  await open(c);
  c.send(JSON.stringify({ t: 'hello', proto: PROTO + 98, build: 'mismatch-tester' }));
  const e0 = await wait(c, 'err');
  check(!!e0 && e0.code === 'VERSION_MISMATCH', '版本不匹配被拒绝', e0 ? e0.code : '无 err');
  await sleep(120);
  check(c.readyState !== c.OPEN, '拒绝后连接被关闭', 'readyState=' + c.readyState);

  // 1) 建房 + 加入
  const a = mk(PROTO);
  await open(a);
  a.send(JSON.stringify({ t: 'hello', proto: PROTO, build: 'A-tester' }));
  check(!!(await wait(a, 'welcome')), 'A 握手收到 welcome');
  a.send(JSON.stringify({ t: 'create' }));
  const room = await wait(a, 'room');
  check(!!room && /^[A-Z0-9]{6}$/.test(String(room.code || '')), '建房返回 6 位房间码', room ? room.code : '无');
  check(!!room && room.seat === 0, '房主座位 seat=0');

  const b = mk(PROTO);
  await open(b);
  b.send(JSON.stringify({ t: 'hello', proto: PROTO, build: 'B-tester' }));
  await wait(b, 'welcome');
  b.send(JSON.stringify({ t: 'join', code: room.code }));
  const rb = await wait(b, 'room');
  check(!!rb && rb.seat === 1, 'B 以座位 1 加入', rb ? 'seat=' + rb.seat : '无');
  check(!!(await wait(a, 'peer_joined')), 'A 收到 peer_joined');

  // 2) 开局（种子/先手由服务器统一发，两端一致）
  a.send(JSON.stringify({ t: 'start' }));
  const sa = await wait(a, 'start');
  const sb = await wait(b, 'start');
  check(!!sa && !!sb && sa.seed === sb.seed && sa.first_side === sb.first_side,
    '双端收到同一 seed / first_side', sa ? `seed=${sa.seed} first_side=${sa.first_side}` : '无');

  // 3) 操作转发 + payload 原样透传（证明"服务器不解释 payload"）
  const payload = { kind: 'deploy', card: '蜂巢', cell: [2, 0], nested: { a: [1, 2, { b: true }] }, 中文: '保留' };
  a.send(JSON.stringify({ t: 'op', seq: 1, frame: 1, payload }));
  const ob = await wait(b, 'op');
  const ack = await wait(a, 'op_ack');
  check(!!ob && ob.seat === 0 && ob.seq === 1 && ob.frame === 1 && ob.sseq >= 1,
    'A 的操作转发到 B（附 seat/sseq）', ob ? `seat=${ob.seat} sseq=${ob.sseq}` : '无');
  check(JSON.stringify(ob && ob.payload) === JSON.stringify(payload), 'payload 原样透传（未被解释/改写）');
  check(!!ack, 'A 收到 op_ack');

  b.send(JSON.stringify({ t: 'op', seq: 1, frame: 2, payload: { kind: 'move', from: [1, 0], to: [1, 1] } }));
  const oa = await wait(a, 'op');
  check(!!oa && oa.seat === 1 && oa.frame === 2, 'B 的操作转发到 A', oa ? `seat=${oa.seat} frame=${oa.frame}` : '无');

  // 4) "只传操作"：收到的消息类型必须全在白名单内（服务器不得下发状态）
  //    ⚠️ 2026-09-24 补：迭代062 新增的大厅/快速匹配消息此前漏登记 → 本断言对**本地与公网**都误报 FAIL。
  //    其中 `lobby` **只含存在性统计**（online/waiting/playing），不含任何对局状态，符合 T7「服务器不持对局状态」；
  //    `queued`/`unqueued`/`matched` 为房间管理与配对回执。
  const allow = new Set([
    'welcome', 'room', 'peer_joined', 'peer_left', 'start', 'op', 'op_ack', 'pong', 'err', 'left',
    'queued', 'unqueued', 'matched', 'lobby',
  ]);
  const weird = [...a.__inbox, ...b.__inbox].filter((m) => !allow.has(m.t));
  check(weird.length === 0, '消息类型全在白名单（无状态下发）', weird.length ? JSON.stringify(weird.slice(0, 3)) : '');

  // 5) 掉线即结束（T7）
  a.close();
  const left = await wait(b, 'peer_left', 3000);
  check(!!left && left.ended === true, 'A 掉线 → B 收 peer_left{ended:true}', left ? JSON.stringify(left) : '无');

  b.close();
  await sleep(150);
  console.log(`\n=== 检查点1 冒烟：${results.length - failed} PASS / ${failed} FAIL ===`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('SMOKE ERROR', e); process.exit(2); });
