#!/bin/bash

# ============================================
# HttpProxy Systemd 服务安装脚本
# ============================================
# 功能：
#   1. 安装 systemd 服务
#   2. 配置服务自启动
#   3. 启动服务
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "此脚本需要 root 权限运行"
        log_info "请使用: sudo bash $0"
        exit 1
    fi
}

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_FILE="${SCRIPT_DIR}/proxy.service"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/proxy.service"
INSTALL_DIR="/opt/proxy"
JAR_FILE="${SCRIPT_DIR}/target/httpproxy-1.0-SNAPSHOT-all.jar"
CONFIG_FILE="${SCRIPT_DIR}/proxy.properties"

# 检查必要文件
check_files() {
    log_step "检查必要文件..."
    
    if [ ! -f "$SERVICE_FILE" ]; then
        log_error "服务文件不存在: $SERVICE_FILE"
        exit 1
    fi
    
    if [ ! -f "$JAR_FILE" ]; then
        log_warn "JAR 文件不存在: $JAR_FILE"
        log_info "请先运行构建脚本或 start.sh 来构建项目"
        read -p "是否继续安装服务? (y/N): " continue_install
        if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_warn "配置文件不存在: $CONFIG_FILE"
        log_info "请确保配置文件存在: $CONFIG_FILE"
    fi
    
    log_info "文件检查完成"
}

# 创建安装目录
create_install_dir() {
    log_step "创建安装目录..."
    
    mkdir -p "$INSTALL_DIR"
    log_info "安装目录: $INSTALL_DIR"
}

# 复制文件到安装目录
copy_files() {
    log_step "复制文件到安装目录..."
    
    if [ -f "$JAR_FILE" ]; then
        cp "$JAR_FILE" "${INSTALL_DIR}/httpproxy-1.0-SNAPSHOT-all.jar"
        log_info "JAR 文件已复制"
    fi
    
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${INSTALL_DIR}/proxy.properties"
        log_info "配置文件已复制"
    else
        log_warn "配置文件不存在，请手动创建: ${INSTALL_DIR}/proxy.properties"
    fi
    
    # 设置权限
    chown -R root:root "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR"
    if [ -f "${INSTALL_DIR}/httpproxy-1.0-SNAPSHOT-all.jar" ]; then
        chmod 644 "${INSTALL_DIR}/httpproxy-1.0-SNAPSHOT-all.jar"
    fi
    if [ -f "${INSTALL_DIR}/proxy.properties" ]; then
        chmod 644 "${INSTALL_DIR}/proxy.properties"
    fi
}

# 安装 systemd 服务
install_service() {
    log_step "安装 systemd 服务..."
    
    # 更新服务文件中的路径
    sed "s|/opt/proxy|${INSTALL_DIR}|g" "$SERVICE_FILE" > "$SYSTEMD_SERVICE_FILE"
    
    # 如果 Java 不在 /usr/bin/java，需要更新服务文件
    JAVA_PATH=$(which java 2>/dev/null || echo "/usr/bin/java")
    if [ "$JAVA_PATH" != "/usr/bin/java" ]; then
        log_info "检测到 Java 路径: $JAVA_PATH"
        sed -i "s|/usr/bin/java|${JAVA_PATH}|g" "$SYSTEMD_SERVICE_FILE"
    fi
    
    # 重新加载 systemd
    systemctl daemon-reload
    log_info "systemd 服务已安装"
}

# 启用并启动服务
enable_and_start_service() {
    log_step "启用并启动服务..."
    
    # 启用服务（开机自启）
    systemctl enable proxy.service
    log_info "服务已设置为开机自启"
    
    # 启动服务
    systemctl start proxy.service
    sleep 2
    
    # 检查服务状态
    if systemctl is-active --quiet proxy.service; then
        log_info "服务启动成功"
    else
        log_error "服务启动失败"
        log_info "查看服务状态: systemctl status proxy"
        log_info "查看服务日志: journalctl -u proxy -f"
        exit 1
    fi
}

# 显示服务信息
show_service_info() {
    log_info "============================================"
    log_info "服务安装完成！"
    log_info "============================================"
    log_info "服务管理命令："
    log_info "  启动服务: systemctl start proxy"
    log_info "  停止服务: systemctl stop proxy"
    log_info "  重启服务: systemctl restart proxy"
    log_info "  查看状态: systemctl status proxy"
    log_info "  查看日志: journalctl -u proxy -f"
    log_info "  禁用自启: systemctl disable proxy"
    log_info "============================================"
}

# 主函数
main() {
    log_info "============================================"
    log_info "HttpProxy Systemd 服务安装脚本"
    log_info "============================================"
    
    check_root
    check_files
    create_install_dir
    copy_files
    install_service
    
    read -p "是否立即启动服务并设置为开机自启? (Y/n): " start_service
    if [[ ! "$start_service" =~ ^[Nn]$ ]]; then
        enable_and_start_service
        show_service_info
    else
        log_info "服务已安装但未启动"
        log_info "手动启动: systemctl start proxy"
        log_info "设置自启: systemctl enable proxy"
    fi
}

# 执行主函数
main "$@"

