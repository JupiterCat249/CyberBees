#!/usr/bin/env node
'use strict';
/**
 * 部署连通性探针（可复用）：DNS → HTTP(S) → WebSocket 握手 → 端口暴露检查
 * 用法：node tools/net_probe.js [--host=www.ourwangzhan.com] [--port=8090] [--path=/relay] [--proto=1]
 * 判读要点：
 *   · `Location: http://127.0.0.1:8090` 说明面板配的是**重定向**（客户端会去连自己的 localhost ✗ 且 ws 握手遇 3xx 必失败）
 *   · 需要的是**反向代理**：/relay → http://127.0.0.1:8090/relay 且**开启 WebSocket 支持** + SSL
 */
const dns = require('dns').promises;
const http = require('http');
const https = require('https');
const WebSocket = require('ws');

const args = process.argv.slice(2);
const get = (k, d) => { const a = args.find((x) => x.startsWith('--' + k + '=')); return a ? a.split('=')[1] : d; };
const HOST = get('host', 'www.ourwangzhan.com');
const PORT = Number(get('port', 8090));
const PATH = get('path', '/relay');
const PROTO = Number(get('proto', 1));
let fail = 0, pass = 0;

function rec(ok, label, detail) {
  if (ok === true) pass++; else if (ok === false) fail++;
  const tag = ok === null ? 'INFO' : ok ? 'PASS' : 'FAIL';
  console.log(`  ${tag}  ${label}${detail ? '  — ' + detail : ''}`);
}

function httpProbe(url) {
  return new Promise((resolve) => {
    let u;
    try { u = new URL(url); } catch (e) { return resolve({ error: 'bad url' }); }
    const mod = u.protocol === 'https:' ? https : http;
    const req = mod.request({
      method: 'GET', hostname: u.hostname, port: u.port || (u.protocol === 'https:' ? 443 : 80),
      path: u.pathname + u.search, timeout: 8000, rejectUnauthorized: false,
      headers: { 'user-agent': 'cyberbees-probe', connection: 'close' }
    }, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; if (body.length > 4000) res.destroy(); });
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: body.slice(0, 300) }));
    });
    req.on('timeout', () => { req.destroy(); resolve({ error: 'timeout' }); });
    req.on('error', (e) => resolve({ error: (e.code || e.message) }));
    req.end();
  });
}

function wsProbe(url) {
  return new Promise((resolve) => {
    let done = false;
    const finish = (r) => { if (!done) { done = true; resolve(r); } };
    let w;
    try { w = new WebSocket(url, { rejectUnauthorized: false, handshakeTimeout: 8000, followRedirects: false }); }
    catch (e) { return finish({ error: e.message }); }
    let first = null;
    const timer = setTimeout(() => { try { w.terminate(); } catch (_) {} finish({ error: 'timeout', first }); }, 9000);
    w.on('open', () => w.send(JSON.stringify({ t: 'hello', proto: PROTO, build: 'probe' })));
    w.on('message', (d) => {
      if (!first) {
        first = d.toString().slice(0, 200);
        try { w.close(); } catch (_) {}   // 收到首条报文即主动关闭（否则要等 9s 超时）
      }
    });
    w.on('close', (code, reason) => { clearTimeout(timer); finish({ closed: true, code, reason: String(reason || ''), first }); });
    w.on('error', (e) => { clearTimeout(timer); finish({ error: e.message, first }); });
  });
}

(async () => {
  console.log(`== 探针：host=${HOST} path=${PATH} 直连端口=${PORT} ==\n`);
  console.log('[1] DNS');
  let ip = null;
  try {
    const a = await dns.lookup(HOST, { all: true });
    ip = a[0] && a[0].address;
    rec(a.length > 0, 'DNS 解析', a.map((x) => `${x.address}(${x.family})`).join(', '));
  } catch (e) { rec(false, 'DNS 解析', e.code || e.message); }

  console.log('\n[2] HTTP(S) 面');
  for (const url of [`https://${HOST}/`, `https://${HOST}/healthz`, `https://${HOST}${PATH}`, `http://${HOST}/`]) {
    const r = await httpProbe(url);
    if (r.error) { rec(false, `GET ${url}`, r.error); continue; }
    const loc = r.headers.location ? ` → Location: ${r.headers.location}` : '';
    const srv = r.headers.server ? ` [${r.headers.server}]` : '';
    const up = r.headers.upgrade ? ` [upgrade:${r.headers.upgrade}]` : '';
    const okStatus = r.status === 200 || r.status === 426 || r.status === 400;
    rec(r.status < 400 ? true : (r.headers.location ? false : null), `GET ${url}`, `HTTP ${r.status}${srv}${up}${loc}`);
    if (r.body && r.status < 400) console.log(`        body: ${r.body.replace(/\s+/g, ' ').slice(0, 160)}`);
  }

  console.log('\n[3] WebSocket 握手');
  for (const url of [`wss://${HOST}${PATH}`, `ws://${HOST}${PATH}`]) {
    const secure = url.startsWith('wss:');
    const r = await wsProbe(url);
    if (r.closed) {
      rec(!!r.first, `WS ${url}`, `连接建立 → 收到：${r.first || '(无消息)'} · 关闭 ${r.code} ${r.reason}`);
    } else if (!secure && /30[12]/.test(String(r.error))) {
      rec(null, `WS ${url}`, `${r.error} —— 明文 ws 被跳转到 https 属**预期行为**（客户端请用 wss）`);
    } else {
      rec(false, `WS ${url}`, `${r.error}${r.first ? ' · 收到过：' + r.first : ''}`);
    }
  }

  console.log('\n[4] 端口直连暴露检查（安全）');
  if (ip) {
    const r = await httpProbe(`http://${ip}:${PORT}/healthz`);
    if (r.status) {
      rec(null, `http://${ip}:${PORT}/healthz`, `HTTP ${r.status} → **该端口在公网明文可达**（建议：config 绑 127.0.0.1 + 面板/防火墙关闭该端口的外网访问）`);
    } else {
      rec(null, `http://${ip}:${PORT}/healthz`, `不可达（${r.error}）→ 好，未明文暴露`);
    }
  }

  console.log(`\n== 探针结果：${pass} PASS / ${fail} FAIL ==`);
  console.log('判读：/relay 若返回 3xx（Location: http://127.0.0.1:8090）＝面板配的是**重定向**，需改成**反向代理 + WebSocket**；');
  console.log('      若 wss 握手报 Unexpected server response: 3xx/404/502 同理；目标形态＝wss 握手 101 + 收到 welcome。');
  process.exit(0);
})().catch((e) => { console.error('PROBE ERROR', e); process.exit(2); });
