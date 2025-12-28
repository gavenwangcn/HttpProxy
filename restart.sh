#!/bin/bash

# ============================================
# HttpProxy 重启脚本
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "停止服务..."
bash "${SCRIPT_DIR}/stop.sh"

sleep 2

echo "启动服务..."
bash "${SCRIPT_DIR}/start.sh" "$@"

