#!/bin/bash
# ============================================================
# cognitive-layer.sh — 认知层标准化输出 (v3 / v7.0.0)
#
# 每次 Claude 加载 self-skill 后，先运行此脚本获取
# 标准化时空上下文。输出完整的认知上下文基座。
#
# 用法：
#   ./cognitive-layer.sh            输出人类可读格式
#   ./cognitive-layer.sh --json     输出 JSON 结构化格式
#   ./cognitive-layer.sh --compact  输出压缩 JSON（给 subagent 用）
# ============================================================

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-human}"

# --- 时间信息 ---
current_time="$(date '+%Y年%m月%d日 %H:%M:%S')"
iso_time="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
timezone="$(date '+%Z')"
weekday="$(date '+%u')"
case "$weekday" in
  1) weekday_cn="星期一" ;; 2) weekday_cn="星期二" ;;
  3) weekday_cn="星期三" ;; 4) weekday_cn="星期四" ;;
  5) weekday_cn="星期五" ;; 6) weekday_cn="星期六" ;;
  7) weekday_cn="星期日" ;;
esac
hour="$(date '+%H')"
if [ "$hour" -lt 12 ]; then period="上午"
elif [ "$hour" -lt 18 ]; then period="下午"
else period="晚上"; fi

# --- 会话间隔 ---
HEARTBEAT="$SKILL_DIR/logs/heartbeat.log"
session_gap="首次会话"
last_end_iso=""
if [ -f "$HEARTBEAT" ]; then
  last_end_line="$(grep "\[END " "$HEARTBEAT" 2>/dev/null | tail -1 || true)"
  if [ -n "$last_end_line" ]; then
    last_end="$(echo "$last_end_line" | sed 's/\[END //;s/\]//' | head -1)"
    session_gap="上次会话于 $last_end 结束"
    last_end_iso="$last_end"
  fi
fi

# --- 异常退出 ---
abnormal_exit="无"
ABNORMAL_FILE="$SKILL_DIR/logs/abnormal-exit"
if [ -f "$ABNORMAL_FILE" ]; then
  abnormal_exit="是（$(cat "$ABNORMAL_FILE")）"
fi

# --- 认知文件变更检测 ---
now_epoch="$(date +%s)"
hour_ago=$((now_epoch - 3600))

identity_file="$SKILL_DIR/memory/identity.md"
identity_changed="false"

[ -f "$identity_file" ] && [ "$(stat -c '%Y' "$identity_file")" -gt "$hour_ago" ] 2>/dev/null && identity_changed="true"

# --- identity.md 章节检测（供 introspection 使用）---
section_names=""
section_six_count=0
section_six_entries=""
if [ -f "$identity_file" ]; then
  # 提取所有 ## 章节目录
  section_names="$(grep -E '^## ' "$identity_file" 2>/dev/null | sed 's/^## //' || echo "")"

  # 提取 §六 条目数
  section_six_count=0
  in_six=0
  while IFS= read -r line; do
    if echo "$line" | grep -qE '^## 六、'; then
      in_six=1
      continue
    fi
    if [ "$in_six" -eq 1 ]; then
      if echo "$line" | grep -qE '^## '; then
        break
      fi
      if echo "$line" | grep -qE '^[0-9]+\. '; then
        section_six_count=$((section_six_count + 1))
      fi
    fi
  done < "$identity_file"
fi

# --- project_memory_path 修复 ---
# Claude Code 项目 ID 规则：绝对路径全部 / 替换为 -
project_dir="$(pwd 2>/dev/null || echo "")"
if [ -n "$project_dir" ]; then
  project_id="$(echo "$project_dir" | sed 's|/|-|g')"
  project_memory_path="$HOME/.claude/projects/${project_id}/memory"
else
  project_memory_path="N/A"
fi

# --- 读取身份文件摘要 ---
get_identity_core() {
  local f="$1"
  if [ ! -f "$f" ]; then echo "N/A"; return; fi
  # 提取 "身份认知" 之后、"我能做什么" 之前的内容
  awk 'BEGIN{found=0}
    /^# 身份认知/ {found=1; next}
    /^## 一/ {found=0}
    found {print}' "$f" | head -5
}

# ============================================================
# 输出
# ============================================================

case "$MODE" in
  --json|-j)
    identity_core="$(get_identity_core "$identity_file" | tr -d '\n\r' | sed 's/"/\\"/g')"
    section_names_json="$(echo "$section_names" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | tr -d '\n' | sed 's/\\n$//')"

    cat << JSONEOF
{
  "schema": "cognitive-context-v3",
  "time": {
    "human": "${current_time}（${period}，${weekday_cn}，${timezone}时区）",
    "iso": "${iso_time}",
    "period": "${period}",
    "weekday": "${weekday_cn}",
    "timezone": "${timezone}"
  },
  "session": {
    "gap": "${session_gap}",
    "last_end_iso": "${last_end_iso}",
    "abnormal_exit": "${abnormal_exit}"
  },
  "files": {
    "identity_changed": ${identity_changed}
  },
  "identity": {
    "scope": "ai-self-model",
    "note": "此 identity_core 定义 AI 自身的认知方法论、原则和驱动力，非用户画像",
    "path": "${identity_file}",
    "core": "${identity_core}",
    "changed": ${identity_changed}
  },
  "introspection": {
    "note": "自省层的结构化数据：identity.md 章节结构和§六采集条目数",
    "sections": "$(echo "$section_names_json")",
    "section_six_count": ${section_six_count}
  },
  "project_memory_path": "${project_memory_path}"
}
JSONEOF
    ;;

  --compact|-c)
    identity_core="$(get_identity_core "$identity_file" | tr -d '\n\r' | sed 's/"/\\"/g')"

    printf '{"time":"%s","iso":"%s","session":"%s","abnormal":%s,"scope":"ai-self-model","ident":"%s","sixCount":%d}\n' \
      "${current_time}（${period}，${weekday_cn}）" \
      "${iso_time}" \
      "$(echo "$session_gap" | sed 's/"/\\"/g')" \
      "$([ "$abnormal_exit" = "无" ] && echo 'false' || echo 'true')" \
      "$identity_core" \
      "$section_six_count"
    ;;

  *)
    echo "【认知上下文】"
    echo "当前时间：${current_time}（${period}，${weekday_cn}，${timezone}时区）"
    echo "会话状态：${session_gap}"
    echo "异常退出：${abnormal_exit}"
    echo ""
    echo "【认知文件变更】"
    echo "identity.md 近1小时变更：$( [ "$identity_changed" = "true" ] && echo '是' || echo '否' )"
    echo ""
    echo "【身份核心】"
    get_identity_core "$identity_file"
    echo ""
    echo "【自省上下文】"
    echo "章节结构："
    echo "$section_names" | while IFS= read -r s; do
      [ -n "$s" ] && echo "  - $s"
    done
    echo "§六 采集条目：${section_six_count} 条"
    ;;
esac
