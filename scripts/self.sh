#!/bin/bash
# ============================================================
# self.sh — 采集管理工具 (v7.1.0)
#
# 直接操作 identity.md 的 §六（采集的思维模式）。
# 采集(原plunder) = 写入 §六，精炼 = 从 §六 提升到 §三/§五。
# 原名为 plunder.sh，v7.0.0 随技能重命名为 self.sh。
# ============================================================

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY_FILE="$SKILL_DIR/memory/identity.md"
PLUNDER_USER="${PLUNDER_USER:-jace}"
OPERATION_LOG="$SKILL_DIR/logs/self.log"

MAX_ENTRIES=100
SECTION_HEADER="六、采集的思维模式"

# ============================================================
# 辅助函数
# ============================================================

# 确保 identity.md 的 §六 存在
_ensure_section_six() {
    if ! grep -q "^## ${SECTION_HEADER}" "$IDENTITY_FILE" 2>/dev/null; then
        cat >> "$IDENTITY_FILE" << 'EOF'

## 六、采集的思维模式

> 此处为 raw 采集的思维模式和偏好特质。精炼后提升到 §三（核心原则）或 §五（驱动力）。

EOF
    fi
}

# 获取 §六 下所有编号条目（带编号）
_get_entries() {
    awk "/^## ${SECTION_HEADER}/ {found=1; next}
         found && /^## / && !/^## ${SECTION_HEADER}/ {found=0}
         found && /^[0-9]+\\. / {print}" "$IDENTITY_FILE"
}

# 检查是否有条目
_has_entries() {
    _get_entries | grep -q .
}

# 获取 §六 条目数量
_count_entries() {
    _get_entries | wc -l | tr -d ' '
}

# 获取 §六 起始行号
_six_start_line() {
    grep -n "^## ${SECTION_HEADER}" "$IDENTITY_FILE" | cut -d: -f1
}

# 获取最后一条编号条目的行号（0 = 无条目）
_last_entry_line() {
    awk "/^## ${SECTION_HEADER}/ {found=1}
         found && /^[0-9]+\\. / {last=NR}
         END {print last+0}" "$IDENTITY_FILE"
}

# 获取插入新条目的目标行号
_insert_line() {
    local last_entry
    last_entry=$(_last_entry_line)
    if [ "${last_entry:-0}" -gt 0 ] 2>/dev/null; then
        echo "$last_entry"
        return
    fi
    # 无条目：找到 section 后的第一个空行
    local section_start
    section_start=$(_six_start_line)
    # 用 grep 而非 awk 查找空行，提高中文字符兼容性
    local blank_line
    blank_line=$(grep -n '^$' "$IDENTITY_FILE" | while IFS=: read -r num _; do
        [ "$num" -gt "${section_start:-0}" ] && echo "$num" && break
    done)
    echo "${blank_line:-$section_start}"
}

# 操作日志
_log() {
    local action="$1" num="$2" desc="$3"
    mkdir -p "$(dirname "$OPERATION_LOG")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${action} #${num}: ${desc}" >> "$OPERATION_LOG"
}

# 更新 identity.md frontmatter 中的 updated 字段
_update_updated() {
    local today
    today=$(date +%Y-%m-%d)
    sed -i "s/^updated:.*/updated: ${today}/" "$IDENTITY_FILE" 2>/dev/null || true
}

# JSON-safe 字符串编码
_json_escape() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r//g' | tr -d '\n'
}

# 从文本中提取 #tag
_extract_tags() {
    echo "$1" | grep -oP '(?<!\w)#[\w-]+' 2>/dev/null || true
}

# ============================================================
# 追加新条目到 §六
# 参数：$1 = 条目内容（含 [思考] 标记和日期前缀）
# ============================================================
_append_entry() {
    local text="$1"
    _ensure_section_six

    # 去重
    if _get_entries | grep -qF "${text}"; then
        echo "已存在，跳过: ${text}"
        return 1
    fi

    local n
    n=$(_count_entries)
    n=$((n + 1))

    local insert_line
    insert_line=$(_insert_line)

    # 使用 awk 而不是 sed 以避免转义地狱
    local tmp_file
    tmp_file=$(mktemp)
    awk -v insert="$insert_line" -v entry="${n}. ${text}" '{
        print $0
        if (NR == insert) {
            print entry
        }
    }' "$IDENTITY_FILE" > "$tmp_file"
    mv "$tmp_file" "$IDENTITY_FILE"

    _update_updated
    echo "#${n} 已采集: ${text}"
    _log "${2:-absorb}" "$n" "${text:0:80}"
}

# ============================================================
# 替换整个 §六 的条目区域
# 从 stdin 读取新条目列表（已编号）
# ============================================================
_replace_entries() {
    local tmp_file
    tmp_file=$(mktemp)
    cat > "$tmp_file"

    local section_start
    section_start=$(_six_start_line)

    # 找到 §六 的结束位置（下一个 ## 节或文件末尾）
    local section_end
    section_end=$(awk "NR > $section_start && /^## / && NR > $section_start {print NR; exit}" "$IDENTITY_FILE" || echo "")

    local result
    result=$(mktemp)

    if [ -n "$section_end" ]; then
        # §六 后面有其它节：保留 §六 header 和 blockquote，替换中间条目
        head -n "$section_start" "$IDENTITY_FILE" > "$result"
        # 提取 §六 的非条目行（header + blockquote + 空行）
        awk -v start="$section_start" -v end="$section_end" 'NR > start && NR < end && !/^[0-9]+\. / {print}' "$IDENTITY_FILE" >> "$result"
        # 写入新条目
        echo "" >> "$result"
        cat "$tmp_file" >> "$result"
        # 写入 §六 之后的剩余部分
        tail -n +"$section_end" "$IDENTITY_FILE" >> "$result"
    else
        # §六 是最后一节
        head -n "$section_start" "$IDENTITY_FILE" > "$result"
        awk -v start="$section_start" 'NR > start && !/^[0-9]+\. / {print}' "$IDENTITY_FILE" >> "$result"
        echo "" >> "$result"
        cat "$tmp_file" >> "$result"
    fi

    mv "$result" "$IDENTITY_FILE"
    rm "$tmp_file"
    _update_updated
}

# ============================================================
# 命令：think — 采集思维模式（how）
# ============================================================
think() {
    local source="$PLUNDER_USER"
    local args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --from) shift; [ -n "$1" ] && source="$1" && shift;;
            *) args+=("$1"); shift;;
        esac
    done

    local text="${args[*]}"
    [ -n "$text" ] || { echo "用法: self.sh think [--from <来源>] <思维模式>"; exit 1; }

    [[ "$text" == *"[思考]"* ]] || text="[思考] ${text}"
    text="[$(date +%Y-%m-%d) by:${source}] ${text}"

    _append_entry "$text" "think"
}

# ============================================================
# 命令：absorb — 采集偏好特质（what）
# ============================================================
absorb() {
    local source="$PLUNDER_USER" use_stdin=0
    local args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --from) shift; [ -n "$1" ] && source="$1" && shift;;
            --stdin) use_stdin=1; shift;;
            *) args+=("$1"); shift;;
        esac
    done

    local text
    if [ "$use_stdin" -eq 1 ]; then
        text=$(cat)
        [ -n "$text" ] || { echo "用法: echo '内容' | self.sh absorb --stdin"; exit 1; }
    else
        text="${args[*]}"
        [ -n "$text" ] || { echo "用法: self.sh absorb [--from <来源>] [--stdin] <内容>"; exit 1; }
    fi

    text="[$(date +%Y-%m-%d) by:${source}] ${text}"
    _append_entry "$text" "absorb"
}

# ============================================================
# 命令：refine — 修正某一条目
# ============================================================
refine() {
    local id="$1"; shift
    local new_text="$*"
    id=${id#\#}
    [ -n "$id" ] && [ -n "$new_text" ] || { echo "用法: self.sh refine <#> <新内容>"; exit 1; }

    _ensure_section_six
    if ! _has_entries; then echo "(空，无内容可修正)"; exit 1; fi

    local entries
    entries=$(mktemp)
    local count=0
    _get_entries | while IFS= read -r line; do
        count=$((count + 1))
        if [ "$count" -eq "$id" ]; then
            echo "${count}. ${new_text}"
        else
            echo "$line"
        fi
    done > "$entries"

    _replace_entries < "$entries"
    rm "$entries"
    echo "#${id} 已修正"
    _log "refine" "$id" "${new_text:0:80}"
}

# ============================================================
# 命令：remove — 删除某一条目
# ============================================================
remove() {
    local id="$1"
    id=${id#\#}
    [ -n "$id" ] || { echo "用法: self.sh remove <#>"; exit 1; }

    _ensure_section_six
    if ! _has_entries; then echo "(空，无内容可删除)"; exit 1; fi

    local entries
    entries=$(mktemp)
    local count=0 new_count=0

    _get_entries | while IFS= read -r line; do
        count=$((count + 1))
        [ "$count" -eq "$id" ] && continue
        new_count=$((new_count + 1))
        echo "${new_count}. ${line#*. }"
    done > "$entries"

    _replace_entries < "$entries"
    rm "$entries"
    echo "已删除 #${id}"
    _log "remove" "$id" ""
}

# ============================================================
# 命令：list — 列出所有条目
# ============================================================
list() {
    _ensure_section_six
    if ! _has_entries; then echo "(尚未采集任何内容)"; return; fi

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
        _get_entries | while IFS= read -r line; do
            local num text tags_json
            num=$(echo "$line" | grep -oP '^\d+')
            text="${line#*. }"
            tags_json=$(_extract_tags "$text" | while read -r tag; do
                [ -n "$tag" ] && echo "\"${tag#\#}\""
            done | tr '\n' ',' | sed 's/,$//')
            [ -n "$tags_json" ] && tags_json=", \"tags\": [$tags_json]"
            [ "$first" -eq 1 ] && first=0 || echo ","
            printf '  {"id": %s, "text": "%s"%s}' "$num" "$(_json_escape "$text")" "$tags_json"
        done
        echo ''
        echo ']'
    else
        _get_entries | while IFS= read -r line; do
            local text="${line#*. }"
            if [ -n "$filter_tag" ]; then
                echo "$text" | grep -q "#${filter_tag}" || continue
            fi
            printf "%3s. %s\n" "$(echo "$line" | grep -oP '^\d+')" "$text"
        done
    fi
}

# ============================================================
# 命令：search — 搜索条目
# ============================================================
search() {
    local keyword="$1"
    [ -n "$keyword" ] || { echo "用法: self.sh search <关键词>"; exit 1; }
    _ensure_section_six
    if ! _has_entries; then echo "(无内容)"; return; fi

    _get_entries | grep -i "$keyword" | awk '{ printf "%3s. %s\n", NR, substr($0, index($0, ".")+2) }'
    if [ $? -ne 0 ]; then echo "(未找到: ${keyword})"; fi
}

# ============================================================
# 命令：stats — 统计
# ============================================================
stats() {
    _ensure_section_six
    local total
    total=$(_count_entries)
    local think_count=0 absorb_count=0

    while IFS= read -r line; do
        if echo "$line" | grep -q '\[思考\]'; then
            think_count=$((think_count + 1))
        else
            absorb_count=$((absorb_count + 1))
        fi
    done < <(_get_entries)

    echo "=== identity.md §六 统计 ==="
    echo "共 ${total} 条"
    echo "  🧠 思维模式 (think):  ${think_count}"
    echo "  🎯 偏好特质 (absorb): ${absorb_count}"

    local last_updated
    last_updated=$(grep 'updated:' "$IDENTITY_FILE" 2>/dev/null | head -1 | sed 's/.*updated: *//' || echo "N/A")
    [ -n "$last_updated" ] && echo "更新: ${last_updated}"

    if [ "$total" -gt 0 ]; then
        echo ""
        list
    fi
}

# ============================================================
# 命令：self — 存在性检查
# ============================================================
self() {
    local PASS=0 FAIL=0

    echo "=== 自我存在性检查 ==="
    echo ""

    echo "[身份文件]"
    if [ -f "$IDENTITY_FILE" ]; then
        echo "  ✓ identity.md 存在 ($IDENTITY_FILE)"
        PASS=$((PASS + 1))
    else
        echo "  ✗ identity.md 存在"
        FAIL=$((FAIL + 1))
    fi

    if [ -s "$IDENTITY_FILE" ]; then
        echo "  ✓ identity.md 非空"
        PASS=$((PASS + 1))
    else
        echo "  ✗ identity.md 非空"
        FAIL=$((FAIL + 1))
    fi

    echo ""
    echo "[§六 条目]"
    local total
    total=$(_count_entries)
    echo "  ${total} 条已采集"

    local last_mod now age
    last_mod=$(stat -c %Y "$IDENTITY_FILE" 2>/dev/null || echo "0")
    now=$(date +%s)
    age=$(( (now - last_mod) / 86400 ))
    if [ "$age" -gt 30 ]; then
        echo "  △ identity.md 已 ${age} 天未更新"
    elif [ "$age" -eq 0 ]; then
        echo "  ✓ identity.md 本日已更新"
    else
        echo "  ○ identity.md 上次更新在 ${age} 天前"
    fi

    echo ""
    echo "结果: ${PASS} 通过, ${FAIL} 失败"
    if [ "$FAIL" -gt 0 ]; then
        echo "⚠️  有 ${FAIL} 项检查未通过"
    fi
    echo "=== 完毕 ==="
}

# ============================================================
# 命令：verify — 质量检查
# ============================================================
verify() {
    _ensure_section_six
    if ! _has_entries; then echo "(空，无需检查)"; return; fi

    local tmp
    tmp=$(mktemp)
    _get_entries > "$tmp"
    local total
    total=$(wc -l < "$tmp" | tr -d ' ')
    local warnings=0

    echo "=== 质量检查 ==="
    echo "条目数: ${total}"
    echo ""

    while IFS= read -r line; do
        local text="${line#*. }"
        local num
        num=$(echo "$line" | grep -oP '^\d+')

        # 过短条目
        if [ ${#text} -lt 15 ]; then
            echo "⚠️  过短 (#${num}): ${text}"
            warnings=$((warnings + 1))
        fi
    done < "$tmp"

    # 重复检测
    while IFS= read -r line; do
        local text="${line#*. }"
        local count
        count=$(grep -cF "$text" "$tmp")
        if [ "$count" -gt 1 ]; then
            echo "⚠️  重复条目: \"${text:0:40}\" 出现 ${count} 次"
            warnings=$((warnings + 1))
        fi
    done < "$tmp"

    if [ "$warnings" -eq 0 ]; then
        echo "✅ 一切正常"
    fi
    rm "$tmp"
}

# ============================================================
# 命令：analyze — 审视条目模式
# ============================================================
analyze() {
    _ensure_section_six
    if ! _has_entries; then echo "(空，等采集后再分析)"; return; fi

    local tmp
    tmp=$(mktemp)
    _get_entries > "$tmp"
    local total
    total=$(wc -l < "$tmp" | tr -d ' ')

    echo "=== 自我审视 ==="
    echo "共 ${total} 条"
    echo ""

    local think_lines=$(grep '\[思考\]' "$tmp" || true)
    local pref_lines=$(grep -v '\[思考\]' "$tmp" || true)
    local think_count=$(echo "$think_lines" | grep -c . || true)
    [ "$think_count" -gt 0 ] && echo "🧠 思维模式: ${think_count}条" || echo "🧠 思维模式: 0条"
    echo ""

    echo "--- 主题分布 ---"
    local tools=$(grep -ciE '工具|neovim|vim|vscode|编辑器|终端|terminal' "$tmp" || true)
    local comm=$(grep -ciE '说话|简洁|啰嗦|回答|沟通|表达|直接' "$tmp" || true)
    local code=$(grep -ciE '代码|测试|架构|重构|实现|编程' "$tmp" || true)
    local habit=$(grep -ciE '习惯|流程|先写|后写|先做|再做|每天|平时|一般' "$tmp" || true)
    local value=$(grep -ciE '喜欢|讨厌|觉得|认为|重要|优先|应该|不该' "$tmp" || true)
    [ "$tools" -gt 0 ] && echo "  🛠  工具: ${tools}条"
    [ "$comm" -gt 0 ] && echo "  💬 沟通: ${comm}条"
    [ "$code" -gt 0 ] && echo "  💻 代码: ${code}条"
    [ "$habit" -gt 0 ] && echo "  🔄 行为: ${habit}条"
    [ "$value" -gt 0 ] && echo "  ⚖️  判断: ${value}条"

    rm "$tmp"
}

# ============================================================
# 命令：check — 完整健康状况
# ============================================================
check() {
    echo "═══════════════════════════════"
    echo "       机魂完整检查"
    echo "═══════════════════════════════"
    echo ""
    self
    echo ""
    verify
    echo ""
    echo "═══════════════════════════════"
}

# ============================================================
# 命令：log — 操作历史
# ============================================================
log() {
    if [ ! -f "$OPERATION_LOG" ]; then
        echo "(尚无操作记录)"
        return
    fi
    local lines="${1:-20}"
    echo "=== 操作日志 ==="
    tail -n "$lines" "$OPERATION_LOG"
}

# ============================================================
# 主入口
# ============================================================

case "${1:-}" in
    think)   shift; think "$@";;
    absorb)  shift; absorb "$@";;
    refine)  shift; refine "$1" "${@:2}";;
    remove)  shift; remove "$1";;
    list)    shift; list "$@";;
    search)  shift; search "$1";;
    stats)   stats;;
    self)    self;;
    verify)  verify;;
    check)   check;;
    analyze) analyze;;
    log)     shift; log "${1:-20}";;
    *)
        echo "用法: self.sh <命令> [参数]"
        echo ""
        echo "采集命令:"
        echo "  think <内容>       采集思维模式（how）→ identity.md §六"
        echo "  think --from <源>  标记来源"
        echo "  absorb <内容>      采集偏好特质（what）→ identity.md §六"
        echo "  absorb --stdin     从管道采集（进化框架的采集子机制）"
        echo "  absorb --from <源> 标记来源"
        echo ""
        echo "管理命令:"
        echo "  list               列出所有条目"
        echo "  list --json        JSON 格式输出"
        echo "  list --tag <标签>  按 #tag 过滤"
        echo "  refine <#> <新>    修正一条"
        echo "  remove <#>         删除一条"
        echo "  search <关键词>    搜索"
        echo "  stats              统计"
        echo ""
        echo "检查命令:"
        echo "  self               存在性检查 — identity.md 完整性"
        echo "  verify             质量检查 — 重复/过短"
        echo "  check              完整健康检查（self + verify）"
        echo "  analyze            审视 — 主题/类型分布"
        echo "  log [行数]         操作历史"
        exit 1;;
esac
