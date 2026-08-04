# AI 新闻简报

每日 AI 科技新闻汇总，通过 GitHub Pages 静态发布。

- 首页（列表）：<https://liushengxian.github.io/ai-news/>
- 日报（渲染页）：<https://liushengxian.github.io/ai-news/report.html>
- 数据源：dimagent 的 `ai-news-daily` workflow（抓取 → 清洗 → 输出 JSON）

## 结构

```
├── index.html          # 首页：读取 reports.json 渲染期数列表
├── report.html         # 日报渲染页：读取 data/YYYY-MM-DD.json 动态渲染（分类筛选）
├── reports.json        # 清单（日期 / 条数）——update.sh 自动重建
├── data/               # 每日新闻数据 JSON（workflow 直接写入，与仓库绑定）
│   └── YYYY-MM-DD.json
├── .dim/workflows/     # workflow 脚本 + launchd 定时脚本（版本化管理）
│   ├── ai-news-daily.mjs        # 与 ~/.dimcode/.../saved/ 同步的注册源
│   └── run-ai-news-daily.sh     # launchd 每天 09:00 触发，cd 到仓库后运行
├── update.sh           # 重建清单 + 提交推送
└── output/             # workflow 运行日志（git 忽略）
```

## 数据格式（data/YYYY-MM-DD.json）

```json
{
  "date": "2026-08-04",
  "count": 17,
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

   脚本会自动：重建 `reports.json` → 提交（含 data/ 与 .dim/ 变更）→ 推送到 `main`。
   GitHub Pages 几分钟内生效，首页与新渲染页自动出现最新一期。

> 修改 workflow 后，记得同步：`cp .dim/workflows/ai-news-daily.mjs ~/.dimcode/v2/data/workflows/saved/`
