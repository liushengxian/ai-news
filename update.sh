#!/usr/bin/env bash
# 一键发布流程（JSON 版）：
#   1. 先运行 ai-news-daily workflow（数据直接写入 data/YYYY-MM-DD.json，与仓库绑定）
#   2. 运行本脚本：重建 reports.json 清单、提交并推送
set -euo pipefail
cd "$(dirname "$0")"

if ! ls data/*.json >/dev/null 2>&1; then
  echo "✗ data/ 目录下没有数据文件"
  echo "  请先运行 ai-news-daily workflow 再执行本脚本。"
  exit 1
fi

# 重建 reports.json（从 data/*.json 扫描，最新在前；title 取每期 headline 头条）
python3 - <<'PY'
import json, pathlib

data_dir = pathlib.Path("data")
items = []
for f in sorted(data_dir.glob("*.json"), reverse=True):
    try:
        obj = json.loads(f.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as e:
        print(f"⚠ 跳过 {f.name}: {e}")
        continue
    date = obj.get("date") or f.stem
    count = obj.get("count")
    if count is None:
        count = len(obj.get("news", [])) or None
    items.append({
        "date": date,
        "title": obj.get("headline") or f"AI 科技日报 · {date}",
        "count": count,
    })

manifest = {"updated_at": items[0]["date"] if items else None, "reports": items}
pathlib.Path("reports.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("✓ 清单更新: reports.json (%d 期)" % len(items))
PY

git add data reports.json .dim/workflows index.html report.html update.sh README.md
if git diff --cached --quiet; then
  echo "≈ 没有变化，跳过提交"
else
  git commit -m "daily: 更新 AI 新闻数据"
  echo "✓ 已提交"
fi

git push origin main
echo "✓ 已推送 GitHub Pages，几分钟内生效: https://liushengxian.github.io/ai-news/"
