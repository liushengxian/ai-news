#!/usr/bin/env bash
# 一键更新流程：
#   1. 先运行 ai-news-daily workflow（产出 output/ai-news-YYYY-MM-DD.html）
#   2. 运行本脚本：归档到 reports/、重建 reports.json、提交并推送
set -euo pipefail
cd "$(dirname "$0")"

latest="$(ls -t output/ai-news-*.html 2>/dev/null | head -1 || true)"
if [[ -z "$latest" ]]; then
  echo "✗ 未找到 output/ai-news-*.html"
  echo "  请先运行 ai-news-daily workflow 再执行本脚本。"
  exit 1
fi

date="$(basename "$latest" | sed -E 's/^ai-news-//; s/\.html$//')"
dest="reports/${date}.html"

mkdir -p reports
cp "$latest" "$dest"
echo "✓ 归档: $latest -> $dest"

# 重建 reports.json（最新在前；标题取自 <title>，条数取 <article class="card"> 数量）
python3 - <<'PY'
import json, re, pathlib

reports_dir = pathlib.Path("reports")
items = []
for f in sorted(reports_dir.glob("*.html"), reverse=True):
    date = f.stem
    text = f.read_text(encoding="utf-8", errors="ignore")
    m = re.search(r"<title>(.*?)</title>", text, re.S)
    title = m.group(1).strip() if m else f"AI 科技日报 · {date}"
    count = len(re.findall(r'class="card"', text)) or None
    items.append({"date": date, "title": title, "file": f"{date}.html", "count": count})

manifest = {"updated_at": items[0]["date"] if items else None, "reports": items}
pathlib.Path("reports.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("✓ 清单更新: reports.json (%d 期)" % len(items))
PY

git add reports reports.json
if git diff --cached --quiet; then
  echo "≈ 没有变化，跳过提交"
else
  git commit -m "daily: ${date} AI 新闻简报"
  echo "✓ 已提交"
fi

git push origin main
echo "✓ 已推送 GitHub Pages，几分钟内生效: https://liushengxian.github.io/ai-news/"
