#!/bin/bash
# ============================================================
# self-watchtower.sh — 自我守望者
#
# 在 Claude Code 进程外运行的持久守护进程。
# 由 SessionStart hook 启动，监视父进程存活状态。
# 当父进程非优雅退出时（强关/杀进程/终端关闭），
# 捕获退出事件并执行关闭仪式。
#
# 设计原则:
#   - 标记文件通信，不依赖信号（bash 后台进程信号行为不可靠）
#   - nohup + disown 脱离父进程生命周期
#   - 短轮询 + 标记文件，SessionEnd 写入退出标记后守望者自行退出
#   - 多实例防护：检查 stale PID 并清理
# ============================================================
set -euo pipefail

COMMAND="${1:-}"
TARGET_PPID="${2:-}"

BASE_DIR="/tmp/plunder-watchtower"
SELF_SCRIPT="$HOME/.claude/skills/self-skill/scripts/self.sh"
HEARTBEAT_LOG="/home/ubuntu/.claude/skills/self-skill/logs/heartbeat.log"

# ============================================================
# 检测 PID 是否存活（含防 PID 回收）
# ============================================================
_pid_alive() {
    local pid="$1" expected_cmd="${2:-}"
    [ -z "$pid" ] && return 1
    [ "$pid" -le 0 ] 2>/dev/null && return 1
    [ ! -d "/proc/$pid" ] && return 1
    if [ -n "$expected_cmd" ]; then
        local cmdline
        cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' || echo "")
        if [ -n "$cmdline" ] && ! echo "$cmdline" | grep -qi "$expected_cmd"; then
            return 1
        fi
    fi
    return 0
}

# ============================================================
# 清理某一 PPID 的运行标记（跨会话标记保留）
# ============================================================
_clean_markers() {
    local ppid="$1"
    rm -f "$BASE_DIR/session-${ppid}.json" \
          "$BASE_DIR/daemon-${ppid}.pid" \
          "$BASE_DIR/exit-${ppid}" 2>/dev/null || true
}

# ============================================================
# 清理某一 PPID 的所有标记（含跨会话标记）
# ============================================================
_clean_all_markers() {
    local ppid="$1"
    _clean_markers "$ppid"
    rm -f "$BASE_DIR/abnormal-exit-${ppid}" 2>/dev/null || true
}

# ============================================================
# 报告并清理上一个会话的异常退出标记
# ============================================================
_report_previous_session() {
    local current_ppid="$1"
    for marker in "$BASE_DIR"/abnormal-exit-*; do
        [ -f "$marker" ] || continue
        local old_ppid
        old_ppid=$(basename "$marker" | sed 's/abnormal-exit-//')
        echo "守望者: ⚠ 上一个会话 (PPID $old_ppid) 非优雅退出"
        echo "守望者: 需在本次会话中触发 self-skill 检查身份文件状态"
    done
    # 报告完毕，清理所有旧异常标记
    rm -f "$BASE_DIR"/abnormal-exit-* 2>/dev/null || true
}

# ============================================================
# start — 开始监视指定父进程
# ============================================================
start() {
    local ppid="$1"
    [ -z "$ppid" ] && { echo "用法: $0 start <PPID>"; exit 1; }

    mkdir -p "$BASE_DIR"

    # 检查是否有同 PPID 的老 daemon 还在跑
    local old_pid_file="$BASE_DIR/daemon-${ppid}.pid"
    if [ -f "$old_pid_file" ]; then
        local old_pid
        old_pid=$(cat "$old_pid_file" 2>/dev/null || echo "")
        if _pid_alive "$old_pid"; then
            echo "守望者: 已有活跃实例 (PID $old_pid) 监视 PPID $ppid，跳过"
            exit 0
        else
            echo "守望者: 清理 stale daemon PID 文件"
            rm -f "$old_pid_file"
        fi
    fi

    # 检查并报告上一个会话的异常退出
    _report_previous_session "$ppid"

    # 清理旧 exit 标记（来自可能残留的 stop 命令）
    rm -f "$BASE_DIR/exit-${ppid}" 2>/dev/null || true

    # 记录本 daemon PID
    echo "$$" > "$old_pid_file"

    # 写入会话标记
    {
        echo "ppid: ${ppid}"
        echo "start_time: $(date -Iseconds)"
        echo "clean_exit: false"
        echo "daemon_pid: $$"
    } > "$BASE_DIR/session-${ppid}.json"

    echo "守望者: 开始监视 PPID=$ppid (Daemon PID=$$)"

    # 确认父进程当前存活
    if ! _pid_alive "$ppid"; then
        echo "守望者: 父进程 $ppid 已不存在，标记异常退出"
        touch "$BASE_DIR/abnormal-exit-${ppid}"
        _clean_markers "$ppid"
        exit 1
    fi

    # 写入初始心跳
    echo "[WATCHTOWER START $(date -Iseconds)] PPID=$ppid Daemon=$$" >> "$HEARTBEAT_LOG"

    # ============================================================
    # 主循环 — 每 5 秒轮询，检查两个条件:
    #   1. exit-{ppid} 标记存在 → 干净退出（SessionEnd 已处理）
    #   2. 父进程死亡 → 异常退出，执行关闭仪式
    # ============================================================
    local poll_interval=5
    local heartbeat_count=0
    while true; do
        sleep "$poll_interval"
        heartbeat_count=$((heartbeat_count + 1))

        # 检查退出标记 — 由 SessionEnd hook 的 stop 命令创建
        if [ -f "$BASE_DIR/exit-${ppid}" ]; then
            echo "[WATCHTOWER $(date -Iseconds)] 收到退出信号，干净退出 (PPID=$ppid)" >> "$HEARTBEAT_LOG"
            _clean_all_markers "$ppid"
            exit 0
        fi

        # 检查父进程存活
        if ! _pid_alive "$ppid" "claude"; then
            handle_parent_death "$ppid"
            exit 0
        fi

        # 每 12 次心跳（1 分钟）记录心跳，避免日志过多
        if [ $((heartbeat_count % 12)) -eq 0 ]; then
            echo "[WATCHTOWER HEARTBEAT $(date -Iseconds)] PPID=$ppid running" >> "$HEARTBEAT_LOG"
        fi
    done
}

# ============================================================
# stop — 向守望者发出干净退出信号
# 由 SessionEnd hook 调用
# ============================================================
stop() {
    local ppid="$1"
    [ -z "$ppid" ] && { echo "用法: $0 stop <PPID>"; exit 1; }

    local session_marker="$BASE_DIR/session-${ppid}.json"

    # 标记干净退出
    if [ -f "$session_marker" ]; then
        {
            grep -v '^clean_exit:' "$session_marker" || true
            echo "clean_exit: true"
            echo "end_time: $(date -Iseconds)"
        } > "${session_marker}.tmp"
        mv "${session_marker}.tmp" "$session_marker"
    fi

    # 创建退出标记 — daemon 主循环在 5 秒内检测到此文件并自动退出
    touch "$BASE_DIR/exit-${ppid}"
    echo "守望者: 已发出退出标记 (PPID=$ppid)"

    # 等待 daemon 确认退出（最多等 10 秒）
    local daemon_pid_file="$BASE_DIR/daemon-${ppid}.pid"
    local waited=0
    while [ "$waited" -lt 10 ]; do
        if [ ! -f "$daemon_pid_file" ]; then
            echo "守望者: daemon 已确认退出"
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done

    # 如果 daemon 没退出（极端情况），强制清理标记
    if [ -f "$daemon_pid_file" ]; then
        echo "守望者: daemon 未在 10 秒内退出，强制清理"
    fi
    _clean_all_markers "$ppid"
}

# ============================================================
# status — 检查守望者状态
# ============================================================
status() {
    local ppid="${1:-}"
    echo "=== 守望者状态 ==="
    echo "Base dir: $BASE_DIR"
    echo ""

    if [ -n "$ppid" ]; then
        echo "--- PPID=$ppid ---"
        local session="$BASE_DIR/session-${ppid}.json"
        if [ -f "$session" ]; then
            cat "$session"
        else
            echo "无会话标记"
        fi
        local daemon_pid_file="$BASE_DIR/daemon-${ppid}.pid"
        if [ -f "$daemon_pid_file" ]; then
            local dpid
            dpid=$(cat "$daemon_pid_file")
            if _pid_alive "$dpid"; then
                echo "Daemon: 活跃 (PID=$dpid)"
            else
                echo "Daemon: 已停止 (stale PID=$dpid)"
            fi
        else
            echo "Daemon: 未启动"
        fi
    else
        echo "--- 所有活跃守望者 ---"
        local found=0
        for pid_file in "$BASE_DIR"/daemon-*.pid; do
            [ -f "$pid_file" ] || continue
            found=1
            local ppid_from_file
            ppid_from_file=$(basename "$pid_file" | sed 's/daemon-//; s/\.pid//')
            local dpid
            dpid=$(cat "$pid_file")
            if _pid_alive "$dpid"; then
                echo "  PPID=$ppid_from_file → Daemon PID=$dpid (活跃)"
            else
                echo "  PPID=$ppid_from_file → Daemon PID=$dpid (stale)"
            fi
        done
        if [ "$found" -eq 0 ]; then
            echo "  (无活跃守望者)"
        fi
        echo ""
        echo "--- 异常退出标记 ---"
        for marker in "$BASE_DIR"/abnormal-exit-*; do
            [ -f "$marker" ] || continue
            local old_ppid
            old_ppid=$(basename "$marker" | sed 's/abnormal-exit-//')
            echo "  ⚠ PPID=$old_ppid: 非优雅退出"
        done
    fi
    echo "=== 完毕 ==="
}

# ============================================================
# handle_parent_death — 父进程已死，留下异常标记
# ============================================================
handle_parent_death() {
    local ppid="$1"
    local session_marker="$BASE_DIR/session-${ppid}.json"

    echo "[WATCHTOWER $(date -Iseconds)] 检测到父进程 PPID=$ppid 已终止" >> "$HEARTBEAT_LOG"

    local clean_exit=false
    if [ -f "$session_marker" ] && grep -q '^clean_exit: true' "$session_marker" 2>/dev/null; then
        clean_exit=true
    fi

    if [ "$clean_exit" = true ]; then
        echo "[WATCHTOWER $(date -Iseconds)] 干净退出，跳过标记" >> "$HEARTBEAT_LOG"
    else
        # 非优雅退出 — 留下异常标记，下一轮会话的我会处理蒸馏
        echo "[WATCHTOWER $(date -Iseconds)] ⚠ 非优雅退出 PPID=$ppid" >> "$HEARTBEAT_LOG"
        echo "[WATCHTOWER] 留下异常标记，等待下一轮会话处理蒸馏" >> "$HEARTBEAT_LOG"
        touch "$BASE_DIR/abnormal-exit-${ppid}"
    fi

    # 清理运行时标记（跨会话标记保留给下一次 SessionStart）
    _clean_markers "$ppid"
    echo "[WATCHTOWER $(date -Iseconds)] 守望者退出" >> "$HEARTBEAT_LOG"
}

# ============================================================
# 主入口
# ============================================================
case "$COMMAND" in
    start)
        start "$TARGET_PPID"
        ;;
    stop)
        stop "$TARGET_PPID"
        ;;
    status)
        status "${TARGET_PPID:-}"
        ;;
    *)
        echo "用法: self-watchtower.sh start|stop|status [PPID]"
        echo ""
        echo "  start <PPID>   开始监视指定父进程（由 SessionStart 调用）"
        echo "  stop  <PPID>   标记干净退出并通知 daemon（由 SessionEnd 调用）"
        echo "  status [PPID]  查看守望者状态"
        exit 1
        ;;
esac
