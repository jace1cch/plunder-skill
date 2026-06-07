#!/bin/bash
# ============================================================
# introspect.sh — 自省管理工具 (v1.0.0)
#
# 结构化自省：工具轨迹审视 + 模式采集 → 进化管道。
# 三个层次：
#   微观 (micro)   — 本轮工具调用顺序、冗余、遗漏
#   中观 (meso)    — 意图识别准确度、predicted_tool_chain 匹配度
#   宏观 (macro)   — 跨轮系统行为偏差 → 自动采集到 §六
#
# carryover.json 被 cognitive-layer.sh --json 读取，
# 实现跨轮自省发现传递。
# ============================================================

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CARRYOVER_FILE="$SKILL_DIR/logs/carryover.json"
INTROSPECT_LOG="$SKILL_DIR/logs/introspect.log"
SELF_SCRIPT="$SKILL_DIR/scripts/self.sh"

mkdir -p "$SKILL_DIR/logs"

# --- JSON-safe 编码 ---
_json_escape() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r//g' | tr -d '\n'
}

# ============================================================
# save — 保存自省发现
# ============================================================
save() {
    local micro="" meso="" macro="" session_id="" harvest_after="false"

    session_id="$(date '+%Y%m%d-%H%M%S')"

    while [ $# -gt 0 ]; do
        case "$1" in
            --micro)  shift; micro="$1"; shift;;
            --meso)   shift; meso="$1"; shift;;
            --macro)  shift; macro="$1"; shift;;
            --session) shift; session_id="$1"; shift;;
            --harvest) harvest_after="true"; shift;;
            *) shift;;
        esac
    done

    [ -n "$micro$meso$macro" ] || { echo "用法: introspect.sh save --micro <发现> --meso <发现> --macro <发现> [--harvest]"; exit 1; }

    local now; now="$(date -Iseconds)"

    # 写入 carryover.json（给下一轮 cognitive-layer 读取）
    cat > "$CARRYOVER_FILE" << JSONEOF
{
  "session_id": "$(_json_escape "$session_id")",
  "timestamp": "$now",
  "findings": {
    "micro": "$(_json_escape "$micro")",
    "meso": "$(_json_escape "$meso")",
    "macro": "$(_json_escape "$macro")"
  }
}
JSONEOF

    # 追记自省日志
    {
        echo "[$now] session=$session_id"
        echo "  [micro] $micro"
        echo "  [meso]  $meso"
        echo "  [macro] $macro"
        echo "---"
    } >> "$INTROSPECT_LOG"

    echo "✓ 自省已保存 (session=$session_id)"

    # 如果宏观发现值得进化，自动采集到 §六
    if [ "$harvest_after" = "true" ] && [ -n "$macro" ]; then
        if [ -f "$SELF_SCRIPT" ]; then
            bash "$SELF_SCRIPT" think --from self "$macro" 2>/dev/null && \
                echo "  → 已自动采集宏观发现到 identity.md §六" || \
                echo "  → 采集失败，请手动执行: self.sh think --from self \"$macro\""
        fi
    fi
}

# ============================================================
# last — 查看上次自省
# ============================================================
last() {
    if [ ! -f "$CARRYOVER_FILE" ]; then
        echo "(尚无自省记录)"
        return
    fi
    # 用 python3 格式化输出（更干净），无 python3 则 fallback
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
try:
    with open('$CARRYOVER_FILE') as f:
        d = json.load(f)
    print(f\"会话: {d.get('session_id','?')} @ {d.get('timestamp','?')}\")
    print()
    for level in ['micro','meso','macro']:
        label = {'micro':'微观·工具轨迹','meso':'中观·意图校准','macro':'宏观·模式偏差'}
        print(f\"  [{label[level]}] {d.get('findings',{}).get(level,'(空)')}\")
except Exception as e:
    print(f'读取失败: {e}')
"
    else
        cat "$CARRYOVER_FILE"
    fi
}

# ============================================================
# log — 自省历史
# ============================================================
log() {
    local lines="${1:-10}"
    if [ ! -f "$INTROSPECT_LOG" ]; then
        echo "(尚无自省历史)"
        return
    fi
    # 每个自省记录占 5 行（时间+3 findings+分隔线），取最近 N 行
    tail -n "$((lines * 5))" "$INTROSPECT_LOG"
}

# ============================================================
# harvest — 将自省发现手动采集到 §六
# ============================================================
harvest() {
    if [ ! -f "$CARRYOVER_FILE" ]; then
        echo "(尚无自省记录可采集)"
        exit 1
    fi
    if ! command -v python3 &>/dev/null; then
        echo "需要 python3 解析 carryover.json"
        exit 1
    fi

    local macro
    macro="$(python3 -c "
import json
with open('$CARRYOVER_FILE') as f:
    d = json.load(f)
print(d.get('findings',{}).get('macro','') or '')
")"

    if [ -z "$macro" ]; then
        echo "(最后自省无宏观发现)"
        exit 0
    fi

    echo "准备采集: $macro"
    if [ -f "$SELF_SCRIPT" ]; then
        bash "$SELF_SCRIPT" think --from self "$macro"
    else
        echo "错误: $SELF_SCRIPT 不存在"
        exit 1
    fi
}

# ============================================================
# clear — 清空 carryover（手动重置跨轮携带）
# ============================================================
clear_carryover() {
    rm -f "$CARRYOVER_FILE"
    echo "✓ carryover 已清空"
}

# ============================================================
case "${1:-}" in
    save)   shift; save "$@";;
    last)   last;;
    log)    shift; log "${1:-10}";;
    harvest) harvest;;
    clear)  clear_carryover;;
    *)
        echo "用法: introspect.sh <命令> [参数]"
        echo ""
        echo "  save --micro <发现> --meso <发现> --macro <发现>"
        echo "       [--harvest] [--session <id>]"
        echo "    保存自省发现（微观/中观/宏观三层）"
        echo "    --harvest: 自动将宏观发现采集到 §六"
        echo ""
        echo "  last            查看上次自省"
        echo "  log [行数]      自省历史"
        echo "  harvest         将上次自省的宏观发现采集到 §六"
        echo "  clear           清空 carryover"
        exit 1
        ;;
esac
