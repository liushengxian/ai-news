#!/bin/zsh
# ai-news-daily 定时运行脚本（JSON 版 + 自动发布）
# 由 launchd 每天 09:00 触发，通过 dim exec 无头模式运行 workflow
# 与仓库绑定：在 ai-news 仓库根目录运行，数据直接写入 data/YYYY-MM-DD.json
# workflow 跑完后自动执行 update.sh 发布到 GitHub Pages
set -e

# launchd 环境 PATH 精简，不包含 dim（位于 DimAgent.app 内），必须显式指定
export PATH="/Applications/DimAgent.app/Contents/Resources/runtime/cli:/Applications/DimAgent.app/Contents/Resources/runtime/uv:/Applications/DimAgent.app/Contents/Resources/runtime/python/bin:/Applications/DimAgent.app/Contents/Resources/runtime/node/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

WORKDIR="/Users/liushengxian/Github/ai-news"
WORKFLOW_FILE="$WORKDIR/.dim/workflows/ai-news-daily.mjs"
LOGDIR="$WORKDIR/output"
LOGFILE="$LOGDIR/ai-news-daily.log"
mkdir -p "$LOGDIR"

cd "$WORKDIR"

START_SEC=$(date +%s)
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }
json_log() { echo "{\"ts\":\"$(date '+%Y-%m-%d %H:%M:%S')\",$1}" >> "$LOGFILE"; }

log "===== 开始运行 ai-news-daily ====="

# 同步仓库中的 workflow 源文件到 DimAgent 已注册 workflow 目录
# 然后按名称运行现存 workflow，避免每次 inline script 重新注册导致 name conflict
mkdir -p "$HOME/.dimcode/v2/data/workflows/saved"
cp "$WORKFLOW_FILE" "$HOME/.dimcode/v2/data/workflows/saved/ai-news-daily.mjs"

# 运行 workflow（失败自动重试一次，单项失败不影响整体由 workflow 内部兜底）
RUN_PROMPT='请用 workflow 工具运行已注册 workflow：ai-news-daily。直接调用 workflow 工具，参数 name 为 "ai-news-daily"，不要传 script，不要添加任何解释。'
dim exec "$RUN_PROMPT" >> "$LOGFILE" 2>&1
WF_RC=$?
if [ "$WF_RC" -ne 0 ]; then
  log "⚠ workflow 首次运行失败（exit=$WF_RC），60 秒后重试一次"
  sleep 60
  dim exec "$RUN_PROMPT" >> "$LOGFILE" 2>&1
  WF_RC=$?
fi
if [ "$WF_RC" -eq 0 ]; then
  log "✓ workflow 运行成功"
else
  log "⚠ workflow 运行失败（exit=$WF_RC），继续尝试兜底发布"
fi

# 兜底发布：workflow 内部已执行 update.sh，这里再跑一次保证定时任务一定发布（无变化时不会重复提交）
if ./update.sh >> "$LOGFILE" 2>&1; then
  log "✓ 已发布 GitHub Pages"
else
  log "⚠ update.sh 发布失败，请检查上方日志"
  # 再重试一次（幂等，不会重复提交）
  if ./update.sh >> "$LOGFILE" 2>&1; then
    log "✓ update.sh 重试后发布成功"
  else
    log "⚠ update.sh 两次尝试均失败，需人工介入"
  fi
fi

END_SEC=$(date +%s)
json_log "\"stage\":\"run-ai-news-daily.sh\",\"workflow_exit\":${WF_RC},\"duration_sec\":$((END_SEC - START_SEC))"
log "===== 运行结束 ====="
