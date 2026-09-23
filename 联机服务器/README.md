# 电子蜂 · 中继服务器（准生产）

> 最后更新：2026-09-21 · 迭代061 检查点 1
> 口径依据：《边界约束》**T7 v1.12** · 规划 `实时开发记录/迭代记录/迭代061/规划.md`
> 分工：**功能实现由 AI 提供（本目录）**；面板/域名/证书/进程由人（宝塔）管理
> 📍 **本目录位于游戏仓**：`Godot版Games代码/电子蜂/联机服务器/`（2026-09-21 由文档仓迁入，便于异地备份与交付）。
> ⚠️ 目录内含**空文件 `.gdignore`** —— 依据引擎文档 `tutorials/best_practices/project_organization.html`「Ignoring specific folders」，
> 该目录**不被 Godot 编辑器扫描**（否则会去索引 `node_modules` 的上千文件）。`node_modules/` `.backup/` `*.log` `.env` 不入库（见同目录 `.gitignore`）。

## 一、这是什么

《电子蜂》双人联机的**传统中继服务器**：只做**房间管理 + 操作转发**。

**硬口径（写在代码里，勿改）**：

- **不跑规则、不裁决、不持有对局状态、不解释 payload**（服务器只把 `payload` 原样转发）
- **只传玩家操作数据**（没有状态下发）
- 一方掉线 → **对局立即结束**（不做重连）
- **版本不匹配拒绝入房**（`hello.proto` ≠ 配置 `proto` 即断开）
- **棋盘镜像由客户端负责**

## 二、目录

| 文件 | 说明 |
|---|---|
| `server.js` | 服务器主体（零硬编码，一切读配置） |
| `config.test.json` | **测试参数**（域名/服务器为测试用；代码按准生产写） |
| `config.prod.json` | **生产参数模板**（同代码，只换参数） |
| `index.html` | 房间/状态页（可选，`serve_index` 控制） |
| `tools/smoke_client.js` | 检查点 1 冒烟（本地回环：建房/加入/转发/版本拒绝/掉线即结束） |
| `tools/update.sh` | **一键更新工具**（备份→覆盖→装依赖→重启→健康检查→失败回滚） |

## 三、本地跑（检查点 1）

```bash
npm install --omit=dev          # 只依赖 ws
npm run start:test              # 起服（config.test.json, 默认 0.0.0.0:8080 /relay）
npm run smoke                   # 另一个终端：跑回环冒烟
curl http://127.0.0.1:8080/healthz
```

冒烟覆盖：① 版本不匹配被拒并断开 ② 建房返回 6 位房间码 ③ 第二名以 seat=1 加入 ④ 开局下发同一 `seed/first_side`
⑤ 操作转发附 `seat/sseq` ⑥ **payload 原样透传**（证明服务器不解释）⑦ 消息类型全在白名单（无状态下发）⑧ 掉线 → `peer_left{ended:true}`

## 三之二、自检总表（本地 · 按顺序照抄即可）

| # | 目的 | 命令 / 操作 | 期望结果 |
|---|---|---|---|
| 1 | 起服（测试档，端口见 `config.test.json`＝**8091**） | `npm run start:test` | 日志 `server.listen … port 8091`；`curl http://127.0.0.1:8091/healthz` → `ok:true` |
| 2 | 服务端中继自检 | 另开终端：`npm run smoke` | **14 PASS / 0 FAIL** |
| 3 | 内置管理面板 | 浏览器 `http://127.0.0.1:8091/admin` | 面板显示房间/连接/日志；未配 token 时标「仅环回可访问」 |
| 4 | 面板鉴权（token 档） | `SB_ADMIN_TOKEN=secret1234 SB_PORT=8092 npm run start:test` → 无 token 访问 `/admin/api/summary` | **401**；带 `Authorization: Bearer secret1234` → **200** |
| 5 | 生产档门禁演练（不改代码） | `SB_PORT=8093 node server.js --config config.prod.json` → 用明文 `ws` 连 | 收 `{"t":"err","code":"NEED_WSS"}` → 关闭 `1008` |
| 6 | 造真实对局（看面板/GUI） | `node tools/demo_session.js --config config.test.json --hold=180` | 打印房间号/seed 并保持 180s |
| 7 | **客户端层 + 确定性自检（Godot 内）** | ① 先做 ⓵（中继在 8091）② 编辑器 **F6** 打开 `verification/iter061_net_check.tscn` | **26 PASS / 0 FAIL**（中继未起时网络段会 FAIL 并提示） |
| 8 | 客户端档位切换（test↔prod） | 编辑器「调试 → 自定义参数」加 `--net-profile=prod` | 打印 URL 变为 `wss://www.ourwangzhan.com:443/relay` |

> **没有自动化测试的部分（如实登记，不硬编）**：`tools/update.sh`（部署脚本，只在真机/演练时用）· **检查点 4 的"呈现半"**（`BoardMirror` 接线尚未做，故无测试；逻辑半已有 3 条断言）· **检查点 8** 真机跨连 · `index.html`（可选状态页，**未实现**，`serve_index:true` 时会回 404 而不报错）。

## 四、部署到服务器（宝塔面板）

1. **站点/项目**：在宝塔「Node 项目」中新建，**启动文件＝`server.js`**，启动参数 `--config config.prod.json`，端口取 `config.prod.json` 的 `port`（模板为 8090，绑 `127.0.0.1` 更安全）。
2. **依赖**：在项目目录执行 `npm ci --omit=dev`（或面板的依赖安装）。
3. **反向代理 + wss**：把站点 `https://www.ourwangzhan.com` 的 **`/relay`** 反代到 `http://127.0.0.1:8090`（`/relay`），**务必开启 WebSocket 支持**；证书用面板「SSL → Let's Encrypt」自动签发即可 → 客户端连 `wss://www.ourwangzhan.com/relay`。
4. **参数**：`config.prod.json` 里 `proto`（协议版本）· `build`（构建标识）· `allow_origins`（站点白名单）· `require_wss: true`（生产强制 wss，反代会带 `X-Forwarded-Proto: https`）按实际填。
5. **验证**：`curl https://www.ourwangzhan.com/healthz`（若反代只暴露 /relay，则本机 `curl http://127.0.0.1:8090/healthz`）。

> **测试与生产的唯一差别＝参数**：`config.test.json` ↔ `config.prod.json`（端口/路径/wss/白名单/日志格式）。代码零改动（检查点 7 会做替换演练）。

## 四之二、为什么「重定向」不行 & 正确配法（2026-09-23 实测）

实测现状（`node tools/net_probe.js --host=www.ourwangzhan.com --port=8090 --path=/relay`）：

| 探测项 | 结果 |
|---|---|
| DNS | `www.ourwangzhan.com → 121.36.34.150` ✅ |
| TLS 证书 | **有效**（curl 默认校验通过，且带 `Strict-Transport-Security`）✅ → Godot 用默认 `TLSOptions` 即可，无需降级 |
| `GET https://…/` · `/healthz` · `/relay` · `/admin` | **全部 301 → `http://127.0.0.1:8090/...`** ✗ |
| `wss://…/relay` · `ws://…/relay` 握手 | ✗ `Unexpected server response: 301` |
| 公网直连 `http://121.36.34.150:8090/healthz` | 超时 —— 该端口**未明文暴露** ✅（好事） |

**为什么「重定向」不行**：面板里那条是**重定向**（3xx 让客户端自己去访问 `http://127.0.0.1:8090`）——
① 远端玩家跟随后会去连**他自己**的 localhost ✗ ② WebSocket 握手必须是 `101`，遇 3xx 直接失败 ✗ ③ 顺带把 HTTPS 降级成 HTTP ✗

**正确配法（反向代理）**：宝塔 → 站点 `www.ourwangzhan.com` → **「反向代理」→ 添加反向代理**：

| 字段 | 值 |
|---|---|
| 代理名称 | `relay` |
| 代理目录 | `/`（整站；或分 `/relay` + `/healthz` 两条） |
| 目标 URL | `http://127.0.0.1:8090` |
| 发送域名 | `$host` |
| **WebSocket 支持** | **必须开启**（面板有开关；或手工加下面三行） |

```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_read_timeout 300s;      # 长连接/心跳不被掐断
```

然后**删除原来那条「重定向」**，复验：

```bash
node tools/net_probe.js --host=www.ourwangzhan.com --port=8090
# 期望：wss://www.ourwangzhan.com/relay → 连接建立 → 收到 {"t":"welcome","proto":1,...}
```

> ⚠️ **安全**：若整站反代（`/`），`/admin` 会一并暴露到公网 → **必须**给 `config.prod.json` 填 `admin_token`（或只反代 `/relay` + `/healthz`）。
> ⚠️ **Node 侧**：`config.prod.json` 的 `host` 保持 `127.0.0.1`（模板已如此），端口与面板「Node 项目」里的一致（模板 8090）。
> 🔎 **判定服务器上跑的是哪份代码**：在服务器上执行 `curl -s http://127.0.0.1:8090/healthz`
> —— 返回含 `"proto"`/`"build"`/`"config"` 的 JSON ＝ 本目录的 `server.js` ✅；返回别的内容 ＝ 原测试服务（需把本目录部署上去：上传 → `npm ci --omit=dev` → 面板重启）。

## 五、更新工具（本轮交付设计）

```bash
# 在服务器上（或面板的计划任务里）执行：
APP_DIR=/www/wwwroot/cyberbees-relay \
PKG=/tmp/cyberbees-relay-1.0.1.tar.gz \
CONFIG=config.prod.json \
RESTART_CMD="pm2 reload cyberbees-relay" \
bash tools/update.sh
```

**设计要点**：

- **配置外置**：更新只换代码，`config.*.json` / `.env` / `index.html` **不在覆盖范围内**
- **备份 → 覆盖 → 装依赖 → 重启 → `/healthz` 校验（重试 10 次）→ 失败自动回滚并重启**
- 备份留在 `APP_DIR/.backup/<时间戳>/code.tar.gz`
- 进程重启命令可配（`RESTART_CMD`）：pm2 用 `pm2 reload`；**宝塔 Node 项目管理器**可直接用面板重启按钮（或把其重启入口填进 `RESTART_CMD`）
- 若反代只暴露 `/relay`，健康检查走本机 `127.0.0.1:<port>/healthz`（脚本默认如此）

## 五之二、内置管理面板（`/admin`）

浏览器打开 `http://127.0.0.1:8090/admin`（生产建议只从内网/白名单访问）：

- **房间**：房间号 · 状态（等待/对局中）· 存在时长 · 对局时长 · **操作数** · 流量 · seed/先手 · 座位（名称/IP）
- **连接**：sid · IP · 所属房间 · 座位 · 是否握手 · 在线时长 · 消息数 · 收/发字节
- **处置**：关房（通知双方 `peer_left{ended:true}`）· 踢线 · 关闭全部房间
- **日志环**：最近 ≤500 条（**不含玩家操作内容**）

**鉴权（两道，安全默认）**：

| 配置 | 行为 |
|---|---|
| `admin_token` 已填（或 `SB_ADMIN_TOKEN=...`） | 必须 `Authorization: Bearer <token>`（页面里填一次存 localStorage），比较用**常量时间** |
| `admin_token` 留空 | **仅允许环回地址**访问，外网返回 `403` |

> 面板**不能**注入操作、不能改对局数据（T7）。API 清单见 `系统维护/网络联机/基础描述.md` §八之二。
> 联调小工具：`node tools/demo_session.js --config config.test.json --hold=180`（起一对客户端建立真实对局，方便看面板）。

## 六、健康检查字段（`/healthz`）

`ok` · `proto` · `build` · `config`（当前配置文件名）· `uptime_s` · `conns` · `conns_total` · `rooms` · `rooms_created` · `ops_relayed` · `payload_bytes` · `rejects` · `version_rejects` · `require_wss`

> `ops_relayed` / `payload_bytes` 可用于对账"**只传操作**"与流量规模；`version_rejects` 可验证版本门禁是否生效。

## 七、环境变量覆盖（不改文件即可切换）

`SB_HOST` · `SB_PORT` · `SB_PATH` · `SB_PROTO` · `SB_LOG_PRETTY`（例：`SB_PORT=9000 node server.js --config config.prod.json`）

## 八、协议

见 `系统维护/网络联机/扩展-001-中继协议v1.md`（客户端实现 `Godot版Games代码/电子蜂/scripts/net/`，与本服务器同表）。
