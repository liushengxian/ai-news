# AI 新闻简报

每日 AI 科技新闻汇总，通过 GitHub Pages 静态发布。

- 首页（列表 + 搜索）：<https://liushengxian.github.io/ai-news/>
- 日报（渲染页）：<https://liushengxian.github.io/ai-news/report.html>
- RSS 订阅：<https://liushengxian.github.io/ai-news/rss.xml>
- 数据源：dimagent 的 `ai-news-daily` workflow（抓取 → 清洗 → 输出 JSON）

## 功能

- **每日自动更新**：launchd 每天 09:00 触发 workflow，抓取 → 去重 → 写 JSON → 发布
- **全站搜索**：首页可跨全部期数按标题 / 摘要 / 来源检索（基于 `search-index.json`）
- **RSS 订阅**：`rss.xml` 每日随发布自动更新，可直接加进阅读器
- **日报翻页**：日报页上一篇 / 下一篇 + 键盘 `←` / `→` 切换日期
- **深浅色主题**：右上角切换，默认亮色纸面，跟随系统
- **分类筛选**：日报页按 模型发布 / 前沿研究 / 融资动态 / 政策监管 筛选
- **视觉风格**：基于 [Open Design](https://github.com/nexu-io/open-design)（Apache 2.0）的 `warm-editorial` 设计系统：奶油纸底、衬线标题、青铜色点缀，深色为同契约暖深色变体

## 结构

```
├── index.html          # 首页：读取 reports.json 渲染期数列表 + 全站搜索
├── report.html         # 日报渲染页：读取 data/YYYY-MM-DD.json 动态渲染（分类筛选 / 翻页）
├── about.html          # 关于页（搭建与运维说明）
├── reports.json        # 清单（日期 / 条数）——update.sh 自动重建
├── search-index.json   # 首页搜索索引——update.sh 自动重建
├── rss.xml             # RSS 订阅源——update.sh 自动重建
├── sitemap.xml         # SEO——update.sh 自动重建
├── robots.txt          # SEO——update.sh 自动重建
├── data/               # 每日新闻数据 JSON（workflow 直接写入，与仓库绑定）
│   └── YYYY-MM-DD.json
├── .dim/workflows/     # workflow 脚本 + launchd 定时脚本（版本化管理）
│   ├── ai-news-daily.mjs        # 与 ~/.dimcode/.../saved/ 同步的注册源
│   └── run-ai-news-daily.sh     # launchd 每天 09:00 触发，cd 到仓库后运行
├── update.sh           # 重建清单/搜索索引/RSS/Sitemap + 提交推送
└── output/             # workflow 运行日志（git 忽略）
```

## 数据格式（data/YYYY-MM-DD.json）

```json
{
  "date": "2026-08-04",
  "count": 19,
  "headline": "阿里发布旗舰大模型 Qwen3.8-Max",
  "news": [
    {
      "title": "…",
      "source": "…",
      "url": "…",
      "date": "2026-08-03",
      "category": "model | research | business | policy",
      "summary": "…"
    }
  ]
}
```

`headline` 是本期总标题（由 workflow 从当天新闻中挑选最重要的一条概括生成），首页列表展示它。

## 每日更新流程

1. 运行 workflow（自动写入 `data/YYYY-MM-DD.json`）：

   ```
   ai-news-daily
   ```

   或由 launchd 每天 09:00 自动触发（脚本：`.dim/workflows/run-ai-news-daily.sh`）。

2. 发布：

   ```bash
   ./update.sh
   ```

   脚本会自动：重建 `reports.json` / `search-index.json` / `rss.xml` / `sitemap.xml` / `robots.txt` → 提交（含 data/ 与 .dim/ 变更）→ 推送到 `main`。
   GitHub Pages 几分钟内生效，首页与新渲染页自动出现最新一期。

> 改成自己的站点时，只需设置 `BASE_URL`（如 `BASE_URL=https://your.domain ./update.sh`），RSS/Sitemap/robots 里的链接会自动跟随。

> 修改 workflow 后，记得同步：`cp .dim/workflows/ai-news-daily.mjs ~/.dimcode/v2/data/workflows/saved/`
