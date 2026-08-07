export const meta = {
  name: "ai-news-daily",
  description: "每天抓取 AI 相关科技新闻，输出 JSON 数据到仓库 data/ 目录（绑定 ai-news 仓库）"
}

// ============================================================
// ai-news-daily（JSON 版）
// 与仓库绑定：数据直接写入 <repo>/data/YYYY-MM-DD.json
// 前端由 index.html + report.html 读取渲染，无需生成 HTML。
// 运行环境要求：api.cwd 必须是 ai-news 仓库根目录
//   （launchd 定时脚本会 cd 到仓库；手动运行请在仓库目录内执行）
// ============================================================

export default async function workflow(api) {
  const today = new Date().toISOString().slice(0, 10)
  const dataDir = `${api.cwd}/data`
  const outputPath = `${dataDir}/${today}.json`

  api.phase("搜索新闻")

  const topics = [
    { topic: "AI 大模型发布与版本更新", category: "model", label: "模型发布" },
    { topic: "AI 研究与论文突破", category: "research", label: "前沿研究" },
    { topic: "AI 行业融资与商业动态", category: "business", label: "融资动态" },
    { topic: "AI 政策监管与安全伦理", category: "policy", label: "政策监管" }
  ]

  const newsSchema = {
    type: "object",
    properties: {
      news: {
        type: "array",
        description: "挑选的新闻列表",
        items: {
          type: "object",
          properties: {
            title: { type: "string", description: "新闻标题" },
            source: { type: "string", description: "来源媒体或机构名" },
            url: { type: "string", description: "原文链接" },
            date: { type: "string", description: "发布日期，尽量精确到 YYYY-MM-DD" },
            category: {
              type: "string",
              enum: ["model", "research", "business", "policy"],
              description: "分类：model=模型发布, research=前沿研究, business=融资动态, policy=政策监管"
            },
            summary: { type: "string", description: "中文摘要，2-3 句话" }
          },
          required: ["title", "url", "summary", "category"]
        }
      }
    },
    required: ["news"]
  }

  const results = await api.parallel(
    topics.map((t) => () =>
      api.agent(
        `你是科技新闻编辑，负责「${t.topic}」方向。今天是 ${today}。\n用 WebSearch 工具搜索该方向近 2-3 天的 AI 重要新闻（中英文均可）；如果近 3 天内该方向确实没有重磅新闻，可放宽到近 5 天补足。\n从结果里挑选 2-4 条最新、最重要的新闻（宁缺毋滥，没有重磅新闻就少选）。对每条用 WebFetch 抓取页面内容（只读前部分即可）提取摘要。\n要求:\n- summary 用中文写，2-3 句话概括核心信息\n- date 尽量精确到日期\n- source 填媒体或机构名\n- category 一律填 "${t.category}"\n- 优先选近 3 天的新闻，近 5 天内的仅作补充\n完成后调用 workflow_result 返回 JSON。`,
        { label: `搜索: ${t.label}`, schema: newsSchema }
      )
    )
  )

  // 合并各组新闻 + 按标题粗去重
  const allNews = []
  const seenTitles = new Set()
  results.forEach((r, i) => {
    const obj = typeof r === "string" ? JSON.parse(r) : r
    if (obj && Array.isArray(obj.news)) {
      obj.news.forEach((n) => {
        const key = String(n.title || "").replace(/\s+/g, "").toLowerCase().slice(0, 40)
        if (key && !seenTitles.has(key)) {
          seenTitles.add(key)
          allNews.push(n)
        }
      })
    } else {
      api.log(`第 ${i + 1} 组无有效数据`)
    }
  })
  api.log(`共收集 ${allNews.length} 条新闻（已粗去重）`)

  api.phase("清洗并写入 JSON")

  await api.agent(
    `你是数据工程师。下面是今天(${today})收集的 ${allNews.length} 条 AI 新闻数据(JSON):\n\n${JSON.stringify(allNews, null, 2)}\n\n请:\n1. 按标题相似度做语义去重（保留更完整的一条）\n2. 按重要性和时效性排序，最重要的在前\n3. 挑选今天最重要或最有趣的一条新闻，用一行（20 字以内）概括成本期总标题 headline（例如"阿里发布旗舰大模型 Qwen3.8-Max"，不要照抄原标题）\n4. 用 write 工具把严格合法的 JSON 写入文件: ${outputPath}\n   文件内容格式（不要写任何其它内容到该文件）:\n   {\n     "date": "${today}",\n     "count": 去重后的条数,\n     "headline": "本期总标题",\n     "news": [\n       { "title": "...", "source": "...", "url": "...", "date": "YYYY-MM-DD", "category": "model|research|business|policy", "summary": "..." }\n     ]\n   }\n   注意: count 必须等于 news 数组长度；category 必须是四个枚举值之一；每条都必须有 title/url/summary。\n5. 完成后回复文件路径和最终 count。`,
    { label: "清洗数据并写入 JSON" }
  )

  api.phase("发布到 GitHub")
  await api.agent(
    `数据已写入 ${outputPath}。请在仓库目录执行一键发布脚本完成「重建 reports.json 清单 → git 提交 → 推送 GitHub Pages」：\ncd ${api.cwd} && ./update.sh\n\n要求：执行后确认输出包含「✓ 已推送」，没有报错；然后用一两句话简要回复发布结果（commit 号、推送状态）。如果 update.sh 报错，请读取报错内容并重试一次，仍失败则如实回复失败原因。`,
    { label: "发布到 GitHub" }
  )

  api.phase("完成")
  api.log(`数据已写入: ${outputPath}，已发布 GitHub Pages`)
  return { ok: true, file: outputPath, count: allNews.length, date: today, published: true }
}
