#!/bin/bash

# ============================================
# HttpProxy 停止脚本
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/proxy.pid"

stop_service() {
    if [ ! -f "$PID_FILE" ]; then
        log_warn "PID 文件不存在: $PID_FILE"
        log_info "尝试查找进程..."
        
        # 通过进程名查找
        PIDS=$(pgrep -f "httpproxy-1.0-SNAPSHOT-all.jar" || true)
        if [ -z "$PIDS" ]; then
            log_info "服务未运行"
            exit 0
        else
            log_info "找到进程: $PIDS"
            for PID in $PIDS; do
                kill "$PID" 2>/dev/null || true
            done
            sleep 2
            # 强制杀死仍在运行的进程
            for PID in $PIDS; do
                if ps -p "$PID" > /dev/null 2>&1; then
                    log_warn "进程 $PID 仍在运行，强制终止..."
                    kill -9 "$PID" 2>/dev/null || true
                fi
            done
            log_info "服务已停止"
            exit 0
        fi
    fi
    
    PID=$(cat "$PID_FILE")
    
    if ! ps -p "$PID" > /dev/null 2>&1; then
        log_warn "进程不存在 (PID: $PID)"
        rm -f "$PID_FILE"
        exit 0
    fi
    
    log_info "停止服务 (PID: $PID)..."
    kill "$PID" 2>/dev/null || true
    
    # 等待进程结束
    for i in {1..10}; do
        if ! ps -p "$PID" > /dev/null 2>&1; then
            log_info "服务已停止"
            rm -f "$PID_FILE"
            exit 0
        fi
        sleep 1
    done
    
    # 如果还在运行，强制终止
    if ps -p "$PID" > /dev/null 2>&1; then
        log_warn "进程仍在运行，强制终止..."
        kill -9 "$PID" 2>/dev/null || true
        sleep 1
    fi
    
    rm -f "$PID_FILE"
    log_info "服务已停止"
}

main() {
    log_info "============================================"
    log_info "HttpProxy 停止脚本"
    log_info "============================================"
    
    stop_service
    
    log_info "============================================"
}

main "$@"

