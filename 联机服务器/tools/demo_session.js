#!/usr/bin/env node
'use strict';
/**
 * 演示/联调用：一对客户端建立房间并持续对局（让管理面板/GUI 看到真实数据）
 * 用法：node tools/demo_session.js --config config.test.json --hold=180 --ops=6
 */
const WebSocket = require('ws');
const { loadConfig } = require('../server.js');

const args = process.argv.slice(2);
const cfg = loadConfig(args);
const holdArg = args.find((a) => a.startsWith('--hold='));
const opsArg = args.find((a) => a.startsWith('--ops='));
const HOLD_S = holdArg ? Number(holdArg.split('=')[1]) : 180;
const OPS = opsArg ? Number(opsArg.split('=')[1]) : 6;
const URL = `ws://127.0.0.1:${cfg.port}${cfg.path}`;
const PROTO = Number(cfg.proto) || 1;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function client(name) {
  const ws = new WebSocket(URL);
  ws.inbox = [];
  ws.on('message', (d) => { try { ws.inbox.push(JSON.parse(d.toString('utf8'))); } catch (_) {} });
  ws.on('error', (e) => console.log(`[${name}] error`, e.message));
  return ws;
}
const open = (ws) => new Promise((r) => ws.once('open', r));
const wait = (ws, t, ms = 3000) => new Promise((res) => {
  const t0 = Date.now();
  const iv = setInterval(() => {
    const i = ws.inbox.findIndex((m) => m.t === t);
    if (i >= 0) { clearInterval(iv); res(ws.inbox.splice(i, 1)[0]); }
    else if (Date.now() - t0 > ms) { clearInterval(iv); res(null); }
  }, 20);
});

(async () => {
  console.log(`== demo_session 目标 ${URL}（保持 ${HOLD_S}s，转发 ${OPS} 次操作）==`);
  const a = client('A'), b = client('B');
  await open(a); await open(b);
  a.send(JSON.stringify({ t: 'hello', proto: PROTO, build: 'demo-A' }));
  b.send(JSON.stringify({ t: 'hello', proto: PROTO, build: 'demo-B' }));
  await wait(a, 'welcome'); await wait(b, 'welcome');
  a.send(JSON.stringify({ t: 'create' }));
  const room = await wait(a, 'room');
  console.log('  房间号', room.code);
  b.send(JSON.stringify({ t: 'join', code: room.code }));
  await wait(b, 'room');
  a.send(JSON.stringify({ t: 'start' }));
  const st = await wait(a, 'start');
  console.log('  开局 seed', st.seed, '先手', st.first_side);
  let seq = 0;
  for (let i = 0; i < OPS; i++) {
    seq++;
    a.send(JSON.stringify({
      t: 'op', seq, frame: i + 1,
      payload: { k: 'deploy', hand_index: i % 2, cell: [2 + (i % 2), i % 4], demo: true }
    }));
    await wait(b, 'op', 2000);
    b.send(JSON.stringify({ t: 'op', seq, frame: i + 1, payload: { k: 'move', from: [1, 0], to: [1, 1], demo: true } }));
    await wait(a, 'op', 2000);
    await sleep(250);
  }
  console.log(`  已转发 ${seq * 2} 次操作；保持连接 ${HOLD_S}s（Ctrl+C 结束）…`);
  await sleep(HOLD_S * 1000);
  a.close(); b.close();
  console.log('  demo 结束');
  process.exit(0);
})().catch((e) => { console.error('DEMO ERROR', e); process.exit(2); });
