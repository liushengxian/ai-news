#!/usr/bin/env bash
# 一键发布流程（JSON 版）：
#   1. 先运行 ai-news-daily workflow（数据直接写入 data/YYYY-MM-DD.json，与仓库绑定）
#   2. 运行本脚本：重建 reports.json / search-index.json / rss.xml / sitemap.xml / robots.txt，
#      然后 git 提交并推送
# 说明：改成自己的站点时，只需改 BASE_URL 为你的部署地址即可（自定义域名也适用）
set -euo pipefail
cd "$(dirname "$0")"

BASE_URL="${BASE_URL:-https://liushengxian.github.io/ai-news}"

if ! ls data/*.json >/dev/null 2>&1; then
  echo "✗ data/ 目录下没有数据文件"
  echo "  请先运行 ai-news-daily workflow 再执行本脚本。"
  exit 1
fi

# 重建 reports.json / search-index.json / rss.xml / sitemap.xml / robots.txt
# （全部由 data/*.json 派生，无需手改）
python3 - "$BASE_URL" <<'PY'
import json, pathlib, html, datetime, sys

BASE = sys.argv[1]
data_dir = pathlib.Path("data")

reports = []
items = []
by_date = {}
for f in sorted(data_dir.glob("*.json"), reverse=True):
    try:
        obj = json.loads(f.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as e:
        print(f"⚠ 跳过 {f.name}: {e}")
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
PY

git add data reports.json search-index.json rss.xml sitemap.xml robots.txt \
        index.html report.html about.html update.sh README.md .dim/workflows
if git diff --cached --quiet; then
  echo "≈ 没有变化，跳过提交"
else
  git commit -m "daily: 更新 AI 新闻数据"
  echo "✓ 已提交"
fi

git push origin main
echo "✓ 已推送 GitHub Pages，几分钟内生效: $BASE_URL/"
