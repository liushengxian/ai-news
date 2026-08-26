#!/usr/bin/env bash
# 一键发布流程（JSON 版）：
#   1. 先运行 ai-news-daily workflow（数据直接写入 data/YYYY-MM-DD.json，与仓库绑定）
#   2. 运行本脚本：跨天去重 → 重建 reports.json / search-index.json / rss.xml / sitemap.xml / robots.txt，
#      然后 git 提交并推送
# 说明：改成自己的站点时，只需改 BASE_URL 为你的部署地址即可（自定义域名也适用）
set -euo pipefail
cd "$(dirname "$0")"

# 参数解析：--no-push 只本地重建派生文件，跳过 git commit/push
NO_PUSH=0
for arg in "$@"; do
  case "$arg" in
    --no-push) NO_PUSH=1 ;;
    *) echo "⚠ 未知参数: $arg" >&2; exit 2 ;;
  esac
done

BASE_URL="${BASE_URL:-https://liushengxian.github.io/ai-news}"

# 结构化日志：stdout 由定时脚本重定向到 output/ai-news-daily.log
START_SEC=$(date +%s)
TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] $*"; }
json_log() { echo "{\"ts\":\"$TS\",$1}"; }

if ! ls data/*.json >/dev/null 2>&1; then
  echo "✗ data/ 目录下没有数据文件"
  echo "  请先运行 ai-news-daily workflow 再执行本脚本。"
  exit 1
fi

# 0) 跨天去重 + count 修正（幂等，重复运行不会重复删除/改写）
DEDUP_OUT=$(python3 dedupe.py) || DEDUP_OUT='{"items_removed":0}'
DEDUPED=$(printf '%s' "$DEDUP_OUT" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("items_removed", 0))
except Exception:
    print(0)' 2>/dev/null || echo 0)
log "✓ 跨天去重完成: 移除 $DEDUPED 条重复条目"

# 重建 reports.json / search-index.json / rss.xml / sitemap.xml / robots.txt
# （全部由 data/*.json 派生，无需手改）
python3 - "$BASE_URL" <<'PY'
import json, pathlib, html, datetime, sys

BASE = sys.argv[1]
data_dir = pathlib.Path("data")

reports = []
items = []
by_date = {}
skipped_files = 0
for f in sorted(data_dir.glob("*.json"), reverse=True):
    try:
        obj = json.loads(f.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as e:
        print(f"⚠ 跳过 {f.name}: {e}")
        skipped_files += 1
        continue
    date = obj.get("date") or f.stem
    by_date[date] = obj
    count = obj.get("count")
    if count is None:
        count = len(obj.get("news", [])) or None
    reports.append({
        "date": date,
        "title": obj.get("headline") or f"AI 科技日报 · {date}",
        "count": count,
    })
    for n in obj.get("news", []):
        items.append({
            "d": date,
            "t": n.get("title", ""),
            "s": n.get("summary", ""),
            "c": n.get("category", ""),
            "src": n.get("source", ""),
        })

updated = reports[0]["date"] if reports else None

# 1) reports.json —— 首页期数清单
pathlib.Path("reports.json").write_text(
    json.dumps({"updated_at": updated, "reports": reports}, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8")
print(f"✓ 清单更新: reports.json ({len(reports)} 期)")

# 2) search-index.json —— 首页搜索索引（轻量字段，不含 URL）
pathlib.Path("search-index.json").write_text(
    json.dumps({"updated_at": updated, "items": items}, ensure_ascii=False),
    encoding="utf-8")
print(f"✓ 搜索索引: search-index.json ({len(items)} 条)")

# 3) rss.xml —— 每日一期，条目内含当天新闻列表
def rfc2822(d):
    try:
        return datetime.date.fromisoformat(d).strftime("%a, %d %b %Y 09:00:00 +0800")
    except ValueError:
        return datetime.datetime.now().strftime("%a, %d %b %Y %H:%M:%S +0800")

def esc(s):
    return html.escape(str(s), quote=True)

feed_items = []
for r in reports:
    d = r["date"]
    news = (by_date.get(d) or {}).get("news", [])
    lis = "".join(
        f"<li><a href=\"{esc(n.get('url', ''))}\">{esc(n.get('title', ''))}</a>"
        f"<small>　· {esc(n.get('source', ''))}</small><br>{esc(n.get('summary', ''))}</li>"
        for n in news[:10]
    )
    desc = f"<p>{esc(r['title'])} —— 共 {len(news)} 条新闻</p><ul>{lis}</ul>"
    feed_items.append(
        f"    <item>\n"
        f"      <title>{esc(r['title'])} · {d}</title>\n"
        f"      <link>{BASE}/report.html?date={d}</link>\n"
        f"      <guid isPermaLink=\"false\">{BASE}/report.html?date={d}</guid>\n"
        f"      <pubDate>{rfc2822(d)}</pubDate>\n"
        f"      <description><![CDATA[{desc}]]></description>\n"
        f"    </item>"
    )
rss = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">\n'
    "<channel>\n"
    "  <title>AI 新闻简报</title>\n"
    f"  <link>{BASE}/</link>\n"
    "  <description>由 DimAgent 自动生成的每日 AI 科技新闻简报（模型发布 / 前沿研究 / 融资动态 / 政策监管）</description>\n"
    "  <language>zh-cn</language>\n"
    f"  <atom:link href=\"{BASE}/rss.xml\" rel=\"self\" type=\"application/rss+xml\"/>\n"
    f"  <lastBuildDate>{rfc2822(updated) if updated else ''}</lastBuildDate>\n"
    + "\n".join(feed_items) + "\n"
    "</channel>\n"
    "</rss>\n"
)
pathlib.Path("rss.xml").write_text(rss, encoding="utf-8")
print(f"✓ RSS 订阅: rss.xml ({len(feed_items)} 期)")

# 4) sitemap.xml
urls = [f"  <url><loc>{BASE}/</loc>{f'<lastmod>{updated}</lastmod>' if updated else ''}</url>",
        "  <url><loc>" + BASE + "/about.html</loc></url>"]
for r in reports:
    urls.append(f"  <url><loc>{BASE}/report.html?date={r['date']}</loc><lastmod>{r['date']}</lastmod></url>")
sitemap = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    + "\n".join(urls) + "\n"
    "</urlset>\n"
)
pathlib.Path("sitemap.xml").write_text(sitemap, encoding="utf-8")
print(f"✓ Sitemap: sitemap.xml ({len(urls)} 个 URL)")

# 5) robots.txt
pathlib.Path("robots.txt").write_text(
    f"User-agent: *\nAllow: /\n\nSitemap: {BASE}/sitemap.xml\n", encoding="utf-8")
print("✓ Robots: robots.txt")

# 6) 结构化摘要（供脚本/日志解析）
print(json.dumps({
    "stage": "rebuild",
    "reports": len(reports),
    "items": len(items),
    "rss_items": len(feed_items),
    "skipped_files": skipped_files,
}, ensure_ascii=False))
PY

# git 提交并推送（--no-push 时跳过，仅本地重建派生文件）
if [ "$NO_PUSH" -eq 1 ]; then
  log "≈ --no-push：已本地重建 reports.json / search-index.json / rss.xml / sitemap.xml / robots.txt，跳过 git commit/push"
  END_SEC=$(date +%s)
  json_log "\"stage\":\"update.sh\",\"success\":true,\"no_push\":true,\"deduped\":${DEDUPED:-0},\"duration_sec\":$((END_SEC - START_SEC))"
  exit 0
fi

GIT_FAIL=0
if git add data reports.json search-index.json rss.xml sitemap.xml robots.txt \
        index.html report.html about.html update.sh dedupe.py README.md .dim/workflows; then
  if git diff --cached --quiet; then
    log "≈ 没有变化，跳过提交"
  else
    if git commit -m "daily: 更新 AI 新闻数据"; then
      log "✓ 已提交"
    else
      log "⚠ git commit 失败"
      GIT_FAIL=1
    fi
  fi
else
  log "⚠ git add 失败"
  GIT_FAIL=1
fi

if git push origin main; then
  log "✓ 已推送 GitHub Pages"
else
  log "⚠ git push 失败（需人工处理）"
  GIT_FAIL=1
fi

END_SEC=$(date +%s)
json_log "\"stage\":\"update.sh\",\"success\":$([ "$GIT_FAIL" -eq 0 ] && echo true || echo false),\"deduped\":${DEDUPED:-0},\"duration_sec\":$((END_SEC - START_SEC))"
exit "$GIT_FAIL"
