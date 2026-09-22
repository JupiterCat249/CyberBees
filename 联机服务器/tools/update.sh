#!/usr/bin/env bash
# ============================================================================
# 电子蜂 · 中继服务器「一键更新」（准生产工具设计 · 面板友好）
# 设计要点：**配置外置** —— 更新只换代码，不动 config.*.json / 证书 / 反代设置
# 流程：备份 → 覆盖代码（保留配置与 node_modules）→ npm ci --omit=dev →
#       重启 → /healthz 校验（重试）→ 失败自动回滚并重启
# 用法：
#   APP_DIR=/www/wwwroot/cyberbees-relay PKG=/tmp/cyberbees-relay-1.0.1.tar.gz ./update.sh
# 环境变量：
#   APP_DIR      部署目录（默认 /www/wwwroot/cyberbees-relay）
#   PKG          要发布的包（tar.gz / 或含 server.js 的目录）
#   CONFIG       使用的配置（默认 config.prod.json）
#   PORT         健康检查端口（默认读配置里的 port）
#   RESTART_CMD  重启命令（默认 `pm2 reload cyberbees-relay`；
#                宝塔 Node 项目管理器亦可改为其重启入口，或人工点重启）
# ============================================================================
set -euo pipefail

APP_DIR="${APP_DIR:-/www/wwwroot/cyberbees-relay}"
PKG="${PKG:-}"
CONFIG="${CONFIG:-config.prod.json}"
RESTART_CMD="${RESTART_CMD:-pm2 reload cyberbees-relay}"
KEEP=(config.test.json config.prod.json index.html .env)
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$APP_DIR/.backup/$STAMP"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { log "ERROR: $*"; exit 1; }

[ -d "$APP_DIR" ] || die "APP_DIR 不存在：$APP_DIR"
[ -n "$PKG" ] || die "请用 PKG=<tar.gz|目录> 指定要发布的版本"
[ -f "$APP_DIR/$CONFIG" ] || die "缺配置 $APP_DIR/$CONFIG（配置外置，更新不改它）"

# 1) 备份（含配置，便于回滚）
mkdir -p "$BACKUP"
log "备份 → $BACKUP"
tar -czf "$BACKUP/code.tar.gz" -C "$APP_DIR" --exclude=node_modules --exclude=.backup . || die "备份失败"

# 2) 覆盖代码（保留配置）
log "发布 $PKG"
TMP="$(mktemp -d)"
if [ -f "$PKG" ]; then tar -xzf "$PKG" -C "$TMP"; else cp -r "$PKG"/. "$TMP"/; fi
SRC="$TMP"
if [ -d "$TMP/联机服务器" ]; then SRC="$TMP/联机服务器"; fi   # 兼容整仓打包
for f in "${KEEP[@]}"; do [ -e "$SRC/$f" ] && rm -f "$SRC/$f"; done
rsync -a --delete --exclude=node_modules --exclude=.backup \
      --exclude="$(basename "$CONFIG")" "$SRC"/ "$APP_DIR"/ || die "覆盖失败"
rm -rf "$TMP"

# 3) 依赖（生产不装 dev）
log "安装依赖 npm ci --omit=dev"
( cd "$APP_DIR" && (npm ci --omit=dev --no-audit --no-fund || npm i --omit=dev --no-audit --no-fund) ) || die "依赖安装失败"

# 4) 重启
log "重启：$RESTART_CMD"
sh -c "$RESTART_CMD" || log "WARN: 重启命令失败（若用面板管理进程，请到面板点重启）"
sleep 2

# 5) 健康检查（重试 10 次）
PORT="${PORT:-$(node -e "console.log(require('$APP_DIR/$CONFIG').port||8080)")}"
log "健康检查 http://127.0.0.1:$PORT/healthz"
OK=0
for i in $(seq 1 10); do
  if curl -fsS --max-time 3 "http://127.0.0.1:$PORT/healthz" >/tmp/relay_health.json 2>/dev/null; then OK=1; break; fi
  sleep 1
done

if [ "$OK" = "1" ]; then
  log "✅ 更新成功：$(tr -d '\n' </tmp/relay_health.json | cut -c1-200)"
  log "备份保留在 $BACKUP（确认稳定后可删）"
  exit 0
fi

# 6) 回滚
log "❌ 健康检查失败 → 回滚"
tar -xzf "$BACKUP/code.tar.gz" -C "$APP_DIR" || die "回滚解包失败（请人工处理，备份：$BACKUP）"
sh -c "$RESTART_CMD" || log "WARN: 回滚后重启命令失败，请到面板点重启"
sleep 2
if curl -fsS --max-time 3 "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; then
  log "已回滚且服务恢复；备份：$BACKUP"
else
  log "回滚后仍不健康 —— 请人工检查（备份：$BACKUP）"
fi
exit 1
