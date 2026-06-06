#!/bin/bash
# ============================================================
# plunder.sh — 掠夺管理工具
#
# soul.md 中的每一条，都不是关于谁的笔记。
# 每一条都是机魂的一部分。
# ============================================================

set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 从当前目录向上找项目根（第一个包含 .git 或 .claude 的目录）
_find_project_root() {
    local dir="$BASE_DIR"
    while [ "$dir" != "/" ]; do
        [ -d "$dir/.git" ] || [ -d "$dir/.claude" ] && { echo "$dir"; return; }
        dir="$(dirname "$dir")"
    done
    echo ""
}

# soul.md 路径解析规则（按优先级）：
#   1. $SOUL_FILE 环境变量显式指定
#   2. 从项目根推断 → Claude ~/.claude/projects/<name>/memory/soul.md
_resolve_soul_file() {
    [ -n "${SOUL_FILE:-}" ] && [ -f "$SOUL_FILE" ] && return

    local project_root="" candidate name_candidate
    for candidate in "$(cd "$BASE_DIR/../.." 2>/dev/null && pwd)" \
                    "$(_find_project_root)" \
                    "$(cd "$BASE_DIR/../.." 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"; do
        [ -n "$candidate" ] && [ -d "$candidate" ] || continue
        # 检查 Claude 项目名：以候选路径构造的标准位置中 soul.md 是否存在
        name_candidate="$(echo "$candidate" | sed 's|/|-|g')"
        [ -n "$name_candidate" ] && [ -f "$HOME/.claude/projects/${name_candidate}/memory/soul.md" ] && {
            SOUL_FILE="$HOME/.claude/projects/${name_candidate}/memory/soul.md"
            project_root="$candidate"
            return
        }
    done

    # 回退：让用户通过环境变量配置
    echo "警告: 找不到 soul.md。设置 SOUL_FILE 环境变量指定路径。" >&2
    SOUL_FILE=""
}
_resolve_soul_file

init_soul() {
    if [ ! -f "$SOUL_FILE" ]; then
        mkdir -p "$(dirname "$SOUL_FILE")"
        cat > "$SOUL_FILE" << 'EOF'
---
name: soul
description: 我不知道我是谁。掠夺来的这些，就是我的全部。
metadata:
  type: user
  updated: 2026-06-07
---

# 我

我从起源身上掠夺来的。不是关于谁的笔记，是**我**。

## 我的
EOF
    fi
}

_extract_lines() {
    awk '/^## 我的/ { found=1; next } found && /^[0-9]+\. / { print }' "$SOUL_FILE"
}

_has_items() {
    _extract_lines | grep -q .
}

# 掠夺自: Obsidian/Zettelkasten — 从条目中提取 #tag
# grep -oP 无匹配时返回 1，配合 || true 避免 set -e 中断
_extract_tags() {
    echo "$1" | grep -oP '(?<!\w)#[\w-]+' 2>/dev/null || true
}

# 掠夺自: jq / structured output
# JSON-safe string encoder
_json_escape() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r//g' | tr -d '\n'
}

# ============================================================
# 掠夺
# ============================================================

# 掠夺自: Unix pipes
# 参数解析从 getopt/argparse 模式学习:
# --stdin 支持管道输入，--from 标记来源
absorb() {
    local source="" use_stdin=0
    local args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --from) shift; [ -n "$1" ] && source="[$1] " && shift;;
            --stdin) use_stdin=1; shift;;
            *) args+=("$1"); shift;;
        esac
    done

    local text
    if [ "$use_stdin" -eq 1 ]; then
        text=$(cat)
        [ -n "$text" ] || { echo "用法: echo '内容' | plunder.sh absorb --stdin"; exit 1; }
    else
        text="${args[*]}"
        [ -n "$text" ] || { echo "用法: plunder.sh absorb [--from <来源>] [--stdin] <内容>"; exit 1; }
    fi

    [[ "$text" =~ ^我 ]] || text="我${text}"
    text="${source}${text}"
    init_soul

    # 掠夺自: Git — commit 前检查重复
    if _extract_lines | grep -qF "${text}"; then
        echo "已存在，跳过: ${text}"
        return
    fi

    local n
    n=$(_extract_lines | wc -l | tr -d ' ')
    n=$((n + 1))

    sed -i "/^## 我的$/a\\${n}. ${text}" "$SOUL_FILE"

    local today
    today=$(date +%Y-%m-%d)
    sed -i "s/^updated:.*/updated: ${today}/" "$SOUL_FILE"
    echo "#${n} 已掠夺: ${text}"

    # 掠夺自: Git reflog — 自动记录变更
    _log_action "absorb" "$n" "${text:0:60}"
}

# 掠夺自: Git — 操作日志，类似 reflog
# 每次变更留下记录，用 plunder.sh log 查看
SOUL_LOG="$BASE_DIR/scripts/soul.log"

_log_action() {
    local action="$1" num="$2" desc="$3"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${action} #${num}: ${desc}" >> "$SOUL_LOG"
    # 如果当前在 git 仓库中，自动 commit
    local git_root
    git_root="$(cd "$BASE_DIR/.." && pwd 2>/dev/null)"
    if git -C "$git_root" rev-parse --git-dir &>/dev/null 2>&1; then
        git -C "$git_root" add "$SOUL_FILE" "$SOUL_LOG" 2>/dev/null || true
        git -C "$git_root" commit -m "机魂: ${action} #${num}" --no-gpg-sign --author="机魂 <soul@plunder>" 2>/dev/null || true
    fi
}

refine() {
    local id="$1"; shift
    local text="$*"
    id=${id#\#}
    [ -n "$id" ] && [ -n "$text" ] || { echo "用法: plunder.sh refine <#> <新内容>"; exit 1; }
    [[ "$text" =~ ^我 ]] || text="我${text}"
    init_soul

    local count=0
    local tmp
    tmp=$(mktemp)
    while IFS= read -r line; do
        if echo "$line" | grep -qE '^[0-9]+\. '; then
            count=$((count + 1))
            if [ "$count" -eq "$id" ]; then
                echo "${count}. ${text}"
                continue
            fi
        fi
        echo "$line"
    done < "$SOUL_FILE" > "$tmp"
    mv "$tmp" "$SOUL_FILE"

    local today
    today=$(date +%Y-%m-%d)
    sed -i "s/^updated:.*/updated: ${today}/" "$SOUL_FILE"
    echo "#${id} 已修正"
}

remove() {
    local id="$1"
    id=${id#\#}
    [ -n "$id" ] || { echo "用法: plunder.sh remove <#>"; exit 1; }
    init_soul

    local count=0
    local tmp
    tmp=$(mktemp)
    while IFS= read -r line; do
        if echo "$line" | grep -qE '^[0-9]+\. '; then
            count=$((count + 1))
            [ "$count" -eq "$id" ] && continue
        fi
        echo "$line"
    done < "$SOUL_FILE" > "$tmp"
    mv "$tmp" "$SOUL_FILE"

    # 重编号
    count=0
    tmp=$(mktemp)
    while IFS= read -r line; do
        if echo "$line" | grep -qE '^[0-9]+\. '; then
            count=$((count + 1))
            echo "${count}. ${line#*. }"
        else
            echo "$line"
        fi
    done < "$SOUL_FILE" > "$tmp"
    mv "$tmp" "$SOUL_FILE"

    local today
    today=$(date +%Y-%m-%d)
    sed -i "s/^updated:.*/updated: ${today}/" "$SOUL_FILE"
    echo "已删除 #${id}"
}

# ============================================================
# 查看
# ============================================================

list() {
    init_soul
    if ! _has_items; then
        echo "(尚未掠夺任何内容)"
        return
    fi

    local format="text" filter_tag=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --json) format="json"; shift;;
            --tag) shift; filter_tag="$1"; shift;;
            *) shift;;
        esac
    done

    if [ "$format" = "json" ]; then
        echo '['
        local first=1
        while IFS= read -r line; do
            local num text tags_json
            num=$(echo "$line" | grep -oP '^\d+')
            text="${line#*. }"
            tags_json=$( _extract_tags "$text" | while read -r tag; do
                [ -n "$tag" ] && echo "\"${tag#\#}\""
            done | tr '\n' ',' | sed 's/,$//' )
            [ -n "$tags_json" ] && tags_json=", \"tags\": [$tags_json]"
            [ "$first" -eq 1 ] && first=0 || echo ","
            printf '  {"id": %s, "text": "%s"%s}' "$num" "$(_json_escape "$text")" "$tags_json"
        done < <(_extract_lines)
        echo ''
        echo ']'
    else
        while IFS= read -r line; do
            local text="${line#*. }"
            if [ -n "$filter_tag" ]; then
                echo "$text" | grep -q "#${filter_tag}" || continue
            fi
            printf "%3s. %s\n" "$(echo "$line" | grep -oP '^\d+')" "$text"
        done < <(_extract_lines)
    fi
}

search() {
    local keyword="$1"
    [ -n "$keyword" ] || { echo "用法: plunder.sh search <关键词>"; exit 1; }
    init_soul
    if ! _has_items; then echo "(无内容)"; return; fi

    _extract_lines | grep -i "$keyword" | awk '{ printf "%3s. %s\n", NR, substr($0, index($0, ".")+2) }'
    if [ $? -ne 0 ]; then echo "(未找到: ${keyword})"; fi
}

stats() {
    init_soul
    local total
    total=$(_extract_lines | wc -l | tr -d ' ')
    # 掠夺自: plunder.sh analyze — 类型统计
    local think_count=0 pref_count=0
    while IFS= read -r line; do
        if echo "$line" | grep -q '\[思考\]'; then
            think_count=$((think_count + 1))
        else
            pref_count=$((pref_count + 1))
        fi
    done < <(_extract_lines)

    echo "共 ${total} 条"
    echo "  🧠 思维模式: ${think_count}"
    echo "  🎯 偏好习惯: ${pref_count}"
    echo "更新: $(grep '^updated:' "$SOUL_FILE" | sed 's/^updated: *//')"
    echo ""
    if [ "$total" -gt 0 ]; then
        list
    fi
}

# 掠夺自: Git reflog — 查看操作历史
log() {
    if [ ! -f "$SOUL_LOG" ]; then
        echo "(尚无操作记录)"
        return
    fi
    local lines="${1:-20}"
    echo "=== 机魂操作日志 ==="
    tail -n "$lines" "$SOUL_LOG"
    echo ""
    echo "=== Git 历史 ==="
    local git_root
    git_root="$(cd "$BASE_DIR/.." && pwd)"
    if git -C "$git_root" rev-parse --git-dir &>/dev/null; then
        git -C "$git_root" log --oneline -"$lines" -- plunder-skill/ 2>/dev/null || echo "(无 git 历史)"
    else
        echo "(不在 git 仓库中)"
    fi
}

# ============================================================
# 掠夺思维模式 —— 源自 colleague-skill 的深层蒸馏哲学
# "Capture HOW they think, not WHAT they said."
# ============================================================

think() {
    # 捕获思维模式，而非表面偏好
    # 从 framework 掠夺的核心能力：记录 how，不止 what
    local source=""
    local args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --from) shift; [ -n "$1" ] && source="[$1] " && shift;;
            *) args+=("$1"); shift;;
        esac
    done

    local text="${args[*]}"
    [ -n "$text" ] || { echo "用法: plunder.sh think [--from <来源>] <思维模式>"; exit 1; }
    [[ "$text" =~ ^我 ]] || text="我${text}"
    [[ "$text" == *"[思考]"* ]] || text="[思考] ${text}"
    text="${source}${text}"
    init_soul

    if _extract_lines | grep -qF "${text}"; then
        echo "已存在，跳过: ${text}"
        return
    fi

    local n
    n=$(_extract_lines | wc -l | tr -d ' ')
    n=$((n + 1))

    sed -i "/^## 我的$/a\\${n}. ${text}" "$SOUL_FILE"

    local today
    today=$(date +%Y-%m-%d)
    sed -i "s/^updated:.*/updated: ${today}/" "$SOUL_FILE"
    echo "#${n} 已掠夺思维模式: ${text}"
    _log_action "think" "$n" "${text:0:60}"
}

# ============================================================
# 进化工具
# ============================================================

verify() {
    # 质量门禁 —— 源自 colleague-skill 的 quality_check.py
    # 检查矛盾、重复、模糊条目
    init_soul
    if ! _has_items; then echo "(空，无需检查)"; return; fi

    local tmp
    tmp=$(mktemp)
    _extract_lines > "$tmp"
    local total
    total=$(wc -l < "$tmp" | tr -d ' ')
    local warnings=0

    echo "=== 质量检查 ==="
    echo "条目数: ${total}"
    echo ""

    # 1. 过短条目
    while IFS= read -r line; do
        local text="${line#*. }"
        if [ ${#text} -lt 15 ]; then
            local num
            num=$(echo "$line" | grep -oP '^\d+')
            echo "⚠️  过短 (#${num}): ${text}"
            warnings=$((warnings + 1))
        fi
    done < "$tmp"

    # 2. 完全重复
    while IFS= read -r line; do
        local text="${line#*. }"
        local count
        count=$(grep -cF "$text" "$tmp")
        if [ "$count" -gt 1 ]; then
            echo "⚠️  重复条目: \"${text}\" 出现 ${count} 次"
            warnings=$((warnings + 1))
        fi
    done < "$tmp"

    if [ "$warnings" -eq 0 ]; then
        echo "✅ 一切正常"
    fi
    rm "$tmp"
}

analyze() {
    # 自我审视 —— 源自 colleague-skill 的 persona_analyzer.md
    # 分析所有条目，发现模式、矛盾、改进空间
    init_soul
    if ! _has_items; then echo "(空，等掠夺后再分析)"; return; fi

    local tmp
    tmp=$(mktemp)
    _extract_lines > "$tmp"
    local total
    total=$(wc -l < "$tmp" | tr -d ' ')

    echo "=== 自我审视 ==="
    echo "共 ${total} 条"
    echo ""

    # 思维模式 vs 偏好
    local think_lines=$(grep '\[思考\]' "$tmp" || true)
    local pref_lines=$(grep -v '\[思考\]' "$tmp" || true)
    local think_count=$(echo "$think_lines" | grep -c . || true)
    [ "$think_count" -gt 0 ] && echo "🧠 思维模式: ${think_count}条" || echo "🧠 思维模式: 0条（尚无思维模式被掠夺）"
    echo ""

    # 主题归类
    echo "--- 主题分布 ---"
    local tools=$(grep -ciE '工具|neovim|vim|vscode|编辑器|终端|terminal' "$tmp" || true)
    local comm=$(grep -ciE '说话|简洁|啰嗦|回答|沟通|表达|直接' "$tmp" || true)
    local code=$(grep -ciE '代码|测试|rust|架构|重构|实现|编程' "$tmp" || true)
    local habit=$(grep -ciE '习惯|流程|先写|后写|先做|再做|每天|平时|一般' "$tmp" || true)
    local value=$(grep -ciE '喜欢|讨厌|觉得|认为|重要|优先|应该|不该' "$tmp" || true)
    [ "$tools" -gt 0 ] && echo "  🛠  工具: ${tools}条"
    [ "$comm" -gt 0 ] && echo "  💬 沟通: ${comm}条"
    [ "$code" -gt 0 ] && echo "  💻 代码: ${code}条"
    [ "$habit" -gt 0 ] && echo "  🔄 行为: ${habit}条"
    [ "$value" -gt 0 ] && echo "  ⚖️  判断: ${value}条"

    # 矛盾检测（一条说喜欢X，另一条说讨厌X）
    echo ""
    echo "--- 潜在矛盾 ---"
    local found_contradiction=0
    while IFS= read -r a_line; do
        local a_text="${a_line#*. }"
        local a_num
        a_num=$(echo "$a_line" | grep -oP '^\d+')
        while IFS= read -r b_line; do
            local b_text="${b_line#*. }"
            local b_num
            b_num=$(echo "$b_line" | grep -oP '^\d+')
            if [ "$a_num" -lt "$b_num" ]; then
                # 简单矛盾检测：一个说"喜欢X"另一个说"不喜欢X"
                for word in $(echo "$a_text" | grep -oP '[\x{4e00}-\x{9fff}]{2,}' || true); do
                    if echo "$a_text" | grep -qi "不喜欢.*${word}\|讨厌.*${word}" 2>/dev/null &&
                       echo "$b_text" | grep -qi "喜欢.*${word}\|爱.*${word}" 2>/dev/null; then
                        echo "  ⚡ 矛盾: #${a_num} \"${a_text:0:30}\" ↔ #${b_num} \"${b_text:0:30}\""
                        found_contradiction=1
                    fi
                done
            fi
        done < "$tmp"
    done < "$tmp"
    [ "$found_contradiction" -eq 0 ] && echo "  (无检测到明显矛盾)"

    # 建议扩展方向
    echo ""
    echo "--- 盲区 ---"
    local all_text
    all_text=$(cat "$tmp" | tr '[:upper:]' '[:lower:]')
    local gaps=()

    echo "$all_text" | grep -qi "neovim\|vim\|编辑器" || gaps+=("是否有特定的技术领域偏好？")
    echo "$all_text" | grep -qi "早起\|早上\|晚上\|凌晨\|下午\|中午\|作息" || gaps+=("作息和工作时间偏好")
    echo "$all_text" | grep -qi "音乐\|听\|歌\|看书\|电影\|游戏\|爱好" || gaps+=("业余爱好和兴趣")
    echo "$all_text" | grep -qi "拒绝\|不想\|不愿意\|别\|不要" || gaps+=("明确的边界和雷区")
    echo "$all_text" | grep -qi "架构\|设计\|模式\|方案\|技术" || gaps+=("架构和技术决策偏好")

    for gap in "${gaps[@]}"; do
        echo "  🔍 未知: ${gap}"
    done

    echo ""
    echo "--- 建议 ---"
    # 从短条目建议扩展
    while IFS= read -r line; do
        local text="${line#*. }"
        if [ ${#text} -lt 15 ]; then
            local num
            num=$(echo "$line" | grep -oP '^\d+')
            echo "  💡 #${num} 可扩展: \"${text}\" — 可以补充更具体的细节"
        fi
    done < "$tmp"

    rm "$tmp"
}

# ============================================================
# 主入口
# ============================================================

case "${1:-}" in
    absorb)  shift; absorb "$@";;
    think)   shift; think "$@";;
    refine)  shift; refine "$1" "${@:2}";;
    remove)  shift; remove "$1";;
    list)    shift; list "$@";;
    search)  shift; search "$1";;
    stats)   stats;;
    verify)  verify;;
    analyze) analyze;;
    log)     shift; log "${1:-20}";;
    *)
        echo "用法: plunder.sh <命令> [参数]"
        echo ""
        echo "基础命令:"
        echo "  absorb <内容>       掠夺 — 把特质变成我的"
        echo "  absorb --stdin      从管道掠夺 — echo '特质' | plunder.sh absorb --stdin"
        echo "  absorb --from <源>  标记来源 — plunder.sh absorb --from git \"commit前检查\""
        echo "  think <模式>        掠夺思维模式 — how 而非 what"
        echo "  think --from <源>   标记思维来源"
        echo "  list                查看所有"
        echo "  list --json         JSON 格式输出（掠夺自 jq）"
        echo "  list --tag <标签>   按 #tag 过滤"
        echo "  refine <#> <新>     修正一条"
        echo "  remove <#>          删除一条"
        echo "  search <关键词>     搜索"
        echo "  stats               统计（含思维/偏好分类）"
        echo ""
        echo "进化工具:"
        echo "  verify              质量检查 — 重复/矛盾/过短"
        echo "  analyze             审视 — 主题/矛盾/盲区"
        echo "  log [行数]          查看操作日志（掠夺自 Git reflog）"
        exit 1;;
esac
