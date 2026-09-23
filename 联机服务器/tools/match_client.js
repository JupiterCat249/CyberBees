#!/usr/bin/env node
'use strict';
/**
 * 快速匹配自检（本地）：两客户端入队 → 配对 → matched + start + lobby 人数 + 操作互通
 * 用法：node tools/match_client.js --config config.test.json   （需先起服）
 */
const WebSocket = require('ws');
const { loadConfig } = require('../server.js');

const cfg = loadConfig(process.argv.slice(2));
const URL = `ws://127.0.0.1:${cfg.port}${cfg.path}`;
const PROTO = Number(cfg.proto) || 1;
let pass = 0, fail = 0;

function rec(ok, label, detail) {
  if (ok === true) pass++; else if (ok === false) fail++;
  console.log(`  ${ok === null ? 'INFO' : ok ? 'PASS' : 'FAIL'}  ${label}${detail ? '  — ' + detail : ''}`);
}
function mk(name) {
  const ws = new WebSocket(URL);
  ws.inbox = []; ws.name = name;
  ws.on('message', (d) => { try { ws.inbox.push(JSON.parse(d.toString('utf8'))); } catch (_) {} });
  ws.on('error', (e) => console.log(`  [${name}] error ${e.message}`));
  return ws;
}
const open = (ws) => new Promise((r) => { ws.once('open', r); ws.once('error', r); });
const wait = (ws, t, ms = 4000) => new Promise((res) => {
  const t0 = Date.now();
  const iv = setInterval(() => {
    const i = ws.inbox.findIndex((m) => m.t === t);
    if (i >= 0) { clearInterval(iv); res(ws.inbox.splice(i, 1)[0]); }
    else if (Date.now() - t0 > ms) { clearInterval(iv); res(null); }
  }, 20);
});
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
/** 等"类型+条件"都满足的报文（lobby 是去抖广播，队列里可能有旧值 → 不能只按类型取第一条） */
const waitUntil = (ws, t, pred, ms = 5000) => new Promise((res) => {
  const t0 = Date.now();
  const iv = setInterval(() => {
    const i = ws.inbox.findIndex((m) => m.t === t && pred(m));
    if (i >= 0) { clearInterval(iv); res(ws.inbox.splice(i, 1)[0]); }
    else if (Date.now() - t0 > ms) { clearInterval(iv); res(null); }
  }, 20);
});

(async () => {
  console.log(`== 快速匹配自检 ${URL} ==`);
  const a = mk('A'), b = mk('B');
  await open(a); await open(b);
  a.send(JSON.stringify({ t: 'hello', proto: PROTO, build: 'match-A' }));
  b.send(JSON.stringify({ t: 'hello', proto: PROTO, build: 'match-B' }));
  await wait(a, 'welcome'); await wait(b, 'welcome');

  const la = await wait(a, 'lobby', 3000);
  rec(!!la, '① 收到 lobby 人数广播', la ? `online=${la.online} waiting=${la.waiting} playing=${la.playing}` : '无');

  a.send(JSON.stringify({ t: 'queue' }));
  const qa = await wait(a, 'queued');
  rec(!!qa && qa.pos === 1, '② A 入队得到 queued{pos=1}', qa ? 'pos=' + qa.pos : '无');

  b.send(JSON.stringify({ t: 'queue' }));
  const ma = await wait(a, 'matched'), mb = await wait(b, 'matched');
  rec(!!ma && !!mb && ma.code === mb.code && String(ma.code).length === 6, '③ 双方 matched 同一房间码', ma ? ma.code : '无');
  rec(!!ma && ma.seat === 0 && !!mb && mb.seat === 1, '④ 座位分配 0/1', (ma && mb) ? `${ma.seat}/${mb.seat}` : '—');

  const sa = await wait(a, 'start'), sb = await wait(b, 'start');
  rec(!!sa && !!sb && sa.seed === sb.seed && sa.first_side === sb.first_side,
    '⑤ 直接开局：双端同 seed / first_side', sa ? `seed=${sa.seed} first_side=${sa.first_side}` : '无');

  const lb = await waitUntil(b, 'lobby', (m) => m.playing >= 2, 5000);
  rec(!!lb && lb.playing >= 2, '⑥ 对局中人数广播更新（playing≥2）', lb ? `online=${lb.online} playing=${lb.playing}` : '无');

  a.send(JSON.stringify({ t: 'op', seq: 1, frame: 1, payload: { k: 'deploy', cell: [2, 0] } }));
  const opb = await wait(b, 'op');
  rec(!!opb && opb.seat === 0, '⑦ 匹配后可传操作（A→B）', opb ? `seat=${opb.seat}` : '无');

  a.close(); b.close();
  await sleep(150);
  console.log(`\n=== 快速匹配自检：${pass} PASS / ${fail} FAIL ===`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('MATCH ERROR', e); process.exit(2); });
