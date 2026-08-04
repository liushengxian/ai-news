# AI 新闻简报

每日 AI 科技新闻汇总，通过 GitHub Pages 静态发布。

- 首页（列表）：<https://liushengxian.github.io/ai-news/>
- 数据源：dimagent 的 `ai-news-daily` workflow（自动抓取整理）

## 结构

```
├── index.html          # 首页：读取 reports.json 渲染期数列表
├── reports.json        # 清单（日期 / 标题 / 条数 / 文件路径）
├── reports/            # 每日简报 HTML（自包含单文件）
│   └── YYYY-MM-DD.html
├── update.sh           # 一键归档 + 更新清单 + 提交推送
└── output/             # workflow 临时输出（git 忽略）
```

## 每日更新流程

1. 运行 workflow 生成简报：

   ```
   ai-news-daily   # 产出 output/ai-news-YYYY-MM-DD.html
   ```

2. 归档并发布：

   ```bash
   ./update.sh
   ```

   脚本会自动：复制到 `reports/` → 重建 `reports.json` → 提交 → 推送到 `main`。
   GitHub Pages 会在几分钟内自动生效，首页会自动出现新一期（无需改首页代码）。

> 说明：`ai-news-daily` 依赖 dimagent 运行，无法放进 GitHub Actions，
> 因此更新是"本地跑 workflow + 推送"的流程。如需定时，可在本地加 cron
> 调用 `dim workflow run ai-news-daily && ./update.sh`。
