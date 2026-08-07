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
mkdir -p "$LOGDIR"

cd "$WORKDIR"

echo "===== $(date '+%Y-%m-%d %H:%M:%S') 开始运行 ai-news-daily =====" >> "$LOGDIR/ai-news-daily.log"

# 用 heredoc 把 workflow 源文件(.mjs)原样传给 dim exec，避免脚本与源文件不同步
# dim exec 的无头 agent 会用 workflow 工具以 inline script 方式运行
{
  echo "请用 workflow 工具运行以下 inline script。直接调用 workflow 工具，把下面整个脚本作为 script 参数传入，不要修改、不要省略、不要添加任何解释："
  echo ""
  cat "$WORKFLOW_FILE"
} | dim exec 2>&1 >> "$LOGDIR/ai-news-daily.log"

# 兜底发布：workflow 内部已执行 update.sh，这里再跑一次保证定时任务一定发布（无变化时不会重复提交）
if ./update.sh >> "$LOGDIR/ai-news-daily.log" 2>&1; then
  echo "✓ 已发布 GitHub Pages" >> "$LOGDIR/ai-news-daily.log"
else
  echo "⚠ update.sh 发布失败，请检查上方日志" >> "$LOGDIR/ai-news-daily.log"
fi

echo "===== $(date '+%Y-%m-%d %H:%M:%S') 运行结束 =====" >> "$LOGDIR/ai-news-daily.log"
