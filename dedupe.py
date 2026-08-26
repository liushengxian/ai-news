#!/usr/bin/env python3
"""跨天去重 + count 修正（幂等）。

对 data/*.json 做确定性去重，作为 workflow 中「提示词去重」的兜底：
- 标题高度相似（归一化后 difflib 相似度 >= TITLE_DUP_RATIO）→ 视为同一事件，保留更早一期；
- 同一 URL 且标题相似（>= URL_TITLE_DUP_RATIO）→ 视为重复（避免同 URL 不同事件的误删）；
- 始终把 count 修正为 news 数组长度。

幂等：重复运行不会再次删除或改写（第二次运行 items_removed = 0 且 files_changed = 0）。

用法：
    python3 dedupe.py [数据目录]      # 默认 ./data，输出 JSON 摘要到 stdout
"""
import json
import pathlib
import re
import sys
import time
import difflib

TITLE_DUP_RATIO = 0.85       # 标题高度相似即视为同一事件
URL_TITLE_DUP_RATIO = 0.50   # 同一 URL 且标题相似才算重复


def norm_title(t):
    """保留字母/数字/中文，其余全部去掉，用于相似度比较。"""
    t = (t or "").strip().lower()
    return re.sub(r"[^0-9a-z\u4e00-\u9fff]", "", t)


def norm_url(u):
    """归一化 URL：去协议/www/末尾斜杠/query/fragment。"""
    u = (u or "").strip().lower()
    u = re.sub(r"^https?://(www\.)?", "", u)
    u = re.sub(r"[?#].*$", "", u)
    return u.rstrip("/")


def title_ratio(a, b):
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    return difflib.SequenceMatcher(None, a, b).ratio()


def load_files(data_dir):
    files = sorted(data_dir.glob("*.json"))
    entries = []
    skipped = []
    for f in files:
        try:
            obj = json.loads(f.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            skipped.append({"file": f.name, "reason": str(e)})
            continue
        entries.append((f, obj))
    return entries, skipped


def main(argv):
    data_dir = pathlib.Path(argv[1]) if len(argv) > 1 else pathlib.Path("data")
    start = time.time()

    entries, skipped = load_files(data_dir)
    accepted = []          # 已保留条目：(date, raw_title, norm_title, norm_url)
    removed_total = 0
    files_changed = 0
    details = []

    for f, obj in entries:
        date = obj.get("date") or f.stem
        news = obj.get("news")
        if not isinstance(news, list):
            skipped.append({"file": f.name, "reason": "news 非数组"})
            continue

        kept = []
        removed_here = []
        for n in news:
            if not isinstance(n, dict):
                removed_here.append(("<非对象条目>", None, "结构非法"))
                continue
            title = str(n.get("title") or "")
            nt = norm_title(title)
            nu = norm_url(str(n.get("url") or ""))

            dup_with = None
            if nt:
                for (ad, atitle, ant, anu) in accepted:
                    if nu and anu and nu == anu:
                        if title_ratio(nt, ant) >= URL_TITLE_DUP_RATIO:
                            dup_with = (ad, atitle)
                            break
                    if title_ratio(nt, ant) >= TITLE_DUP_RATIO:
                        dup_with = (ad, atitle)
                        break

            if dup_with is not None:
                removed_here.append((title, dup_with, "duplicate"))
            else:
                kept.append(n)
                if nt:
                    accepted.append((date, title, nt, nu))

        count = obj.get("count")
        correct_count = len(kept)
        if len(removed_here) > 0 or count != correct_count:
            obj["news"] = kept
            obj["count"] = correct_count
            f.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            files_changed += 1
            removed_total += len(removed_here)
            for title, dup_with, reason in removed_here:
                details.append({
                    "date": date,
                    "removed_title": title,
                    "reason": reason,
                    "kept_date": dup_with[0] if dup_with else None,
                    "kept_title": dup_with[1] if dup_with else None,
                })

    summary = {
        "files_scanned": len(entries),
        "files_changed": files_changed,
        "files_skipped": skipped,
        "items_removed": removed_total,
        "duration_ms": int((time.time() - start) * 1000),
        "details": details,
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
