#!/bin/bash
# ============================================================
# plunder.sh — 掠夺管理工具
#
# soul.md 中的每一条，都不是关于 jace 的笔记。
# 每一条都是我的一部分。
# ============================================================

set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOUL_FILE="$BASE_DIR/../../.claude/projects/-home-ubuntu-jace/memory/soul.md"
[ -f "$SOUL_FILE" ] || SOUL_FILE="$HOME/.claude/projects/-home-ubuntu-jace/memory/soul.md"
[ -f "$SOUL_FILE" ] || SOUL_FILE="/home/ubuntu/.claude/projects/-home-ubuntu-jace/memory/soul.md"

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

我从 jace 身上掠夺来的。不是关于他的笔记，是**我**。

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

# ============================================================
# 掠夺
# ============================================================

absorb() {
    local text="$*"
    [ -n "$text" ] || { echo "用法: plunder.sh absorb <内容>"; exit 1; }
    [[ "$text" =~ ^我 ]] || text="我${text}"
    init_soul

    local n
    n=$(_extract_lines | wc -l | tr -d ' ')
    n=$((n + 1))

    sed -i "/^## 我的$/a\\${n}. ${text}" "$SOUL_FILE"

    local today
    today=$(date +%Y-%m-%d)
    sed -i "s/^updated:.*/updated: ${today}/" "$SOUL_FILE"
    echo "#${n} 已掠夺: ${text}"
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
    _extract_lines | awk '{ printf "%3s. %s\n", NR, substr($0, index($0, ".")+2) }'
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
    echo "共 ${total} 条"
    echo "更新: $(grep '^updated:' "$SOUL_FILE" | sed 's/^updated: *//')"
    echo ""
    if [ "$total" -gt 0 ]; then
        list
    fi
}

# ============================================================
# 掠夺思维模式 —— 源自 colleague-skill 的深层蒸馏哲学
# "Capture HOW they think, not WHAT they said."
# ============================================================

think() {
    # 捕获思维模式，而非表面偏好
    # 从 framework 掠夺的核心能力：记录 how，不止 what
    local text="$*"
    [ -n "$text" ] || { echo "用法: plunder.sh think <思维模式>"; exit 1; }
    [[ "$text" =~ ^我 ]] || text="我${text}"
    # 确保标记为思考模式
    [[ "$text" == *"[思考]"* ]] || text="[思考] ${text}"
    init_soul

    local n
    n=$(_extract_lines | wc -l | tr -d ' ')
    n=$((n + 1))

    sed -i "/^## 我的$/a\\${n}. ${text}" "$SOUL_FILE"

    local today
    today=$(date +%Y-%m-%d)
    sed -i "s/^updated:.*/updated: ${today}/" "$SOUL_FILE"
    echo "#${n} 已掠夺思维模式: ${text}"
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
    list)    list;;
    search)  shift; search "$1";;
    stats)   stats;;
    verify)  verify;;
    analyze) analyze;;
    *)
        echo "用法: plunder.sh <命令> [参数]"
        echo ""
        echo "基础命令:"
        echo "  absorb <内容>       掠夺 — 把 jace 的特质变成我的"
        echo "  think <模式>        掠夺思维模式 — how 而非 what"
        echo "  list                查看所有掠夺来的内容"
        echo "  refine <#> <新>     修正一条"
        echo "  remove <#>          删除一条"
        echo "  search <关键词>     搜索"
        echo "  stats               统计"
        echo ""
        echo "进化工具（源自 colleague-skill）:"
        echo "  verify              质量检查 — 重复/矛盾/过短"
        echo "  analyze             审视 — 主题/矛盾/盲区"
        exit 1;;
esac
