#!/bin/bash

# ============================================
# HttpProxy 启动脚本
# ============================================
# 功能：
#   1. 安装 JDK 17 和 Maven（如果未安装）
#   2. 加载环境变量
#   3. 构建项目
#   4. 使用 nohup 方式启动服务
# ============================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
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

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 配置变量
PROJECT_DIR="$SCRIPT_DIR"
CONFIG_FILE="${PROJECT_DIR}/proxy.properties"
JAR_FILE="${PROJECT_DIR}/target/httpproxy-1.0-SNAPSHOT-all.jar"
LOG_FILE="${PROJECT_DIR}/proxy.log"
PID_FILE="${PROJECT_DIR}/proxy.pid"
ENV_FILE="/etc/profile.d/jdk17-maven.sh"

# 检查配置文件是否存在
check_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        log_info "请创建配置文件或指定正确的配置文件路径"
        exit 1
    fi
    log_info "配置文件: $CONFIG_FILE"
}

# 检查并安装依赖
check_and_install_dependencies() {
    log_step "检查依赖环境..."
    
    # 检查 Java
    if ! command -v java &> /dev/null; then
        log_warn "Java 未安装，开始安装 JDK 17 和 Maven..."
        if [ ! -f "${PROJECT_DIR}/install-jdk17-maven.sh" ]; then
            log_error "安装脚本不存在: ${PROJECT_DIR}/install-jdk17-maven.sh"
            exit 1
        fi
        
        # 检查是否有 root 权限
        if [ "$EUID" -ne 0 ]; then
            log_error "安装 JDK 和 Maven 需要 root 权限"
            log_info "请运行: sudo bash ${PROJECT_DIR}/install-jdk17-maven.sh"
            exit 1
        fi
        
        bash "${PROJECT_DIR}/install-jdk17-maven.sh"
    else
        JAVA_VERSION=$(java -version 2>&1 | head -n 1 | grep -oE 'version "?([0-9]+)' | grep -oE '[0-9]+' | head -n 1)
        if [ "$JAVA_VERSION" != "17" ]; then
            log_warn "检测到 Java 版本: $JAVA_VERSION，需要 JDK 17"
            log_info "请运行安装脚本: sudo bash ${PROJECT_DIR}/install-jdk17-maven.sh"
            exit 1
        fi
        log_info "Java 17 已安装"
    fi
    
    # 检查 Maven
    if ! command -v mvn &> /dev/null; then
        log_warn "Maven 未安装，开始安装..."
        if [ "$EUID" -ne 0 ]; then
            log_error "安装 Maven 需要 root 权限"
            log_info "请运行: sudo bash ${PROJECT_DIR}/install-jdk17-maven.sh"
            exit 1
        fi
        bash "${PROJECT_DIR}/install-jdk17-maven.sh"
    else
        log_info "Maven 已安装"
    fi
}

# 加载环境变量
load_environment() {
    log_step "加载环境变量..."
    
    if [ -f "$ENV_FILE" ]; then
        log_info "加载环境变量文件: $ENV_FILE"
        . "$ENV_FILE"
        log_info "环境变量已加载"
    else
        log_warn "环境变量文件不存在: $ENV_FILE"
        log_warn "如果 Java 或 Maven 命令不可用，请运行: sudo bash ${PROJECT_DIR}/install-jdk17-maven.sh"
    fi
    
    # 验证环境变量
    if [ -z "$JAVA_HOME" ]; then
        log_warn "JAVA_HOME 未设置，尝试自动检测..."
        if [ -d /usr/lib/jvm/java-17-openjdk-* ]; then
            export JAVA_HOME=$(ls -d /usr/lib/jvm/java-17-openjdk-* | head -n 1)
        fi
    fi
    
    if [ -z "$MAVEN_HOME" ]; then
        log_warn "MAVEN_HOME 未设置，尝试自动检测..."
        if [ -d /opt/maven/apache-maven-3.8.8 ]; then
            export MAVEN_HOME=/opt/maven/apache-maven-3.8.8
        fi
    fi
    
    # 更新 PATH
    if [ -n "$JAVA_HOME" ]; then
        export PATH="$JAVA_HOME/bin:$PATH"
    fi
    if [ -n "$MAVEN_HOME" ]; then
        export PATH="$MAVEN_HOME/bin:$PATH"
    fi
    
    log_info "JAVA_HOME: ${JAVA_HOME:-未设置}"
    log_info "MAVEN_HOME: ${MAVEN_HOME:-未设置}"
}

# 构建项目
build_project() {
    log_step "构建项目..."
    
    load_environment
    
    if [ ! -f "$JAR_FILE" ]; then
        log_info "JAR 文件不存在，开始构建项目..."
        log_info "执行: mvn clean package"
        mvn clean package
        if [ $? -ne 0 ]; then
            log_error "项目构建失败"
            exit 1
        fi
        log_info "项目构建成功"
    else
        log_info "JAR 文件已存在: $JAR_FILE"
        read -p "是否重新构建项目? (y/N): " rebuild
        if [[ "$rebuild" =~ ^[Yy]$ ]]; then
            log_info "重新构建项目..."
            mvn clean package
            if [ $? -ne 0 ]; then
                log_error "项目构建失败"
                exit 1
            fi
            log_info "项目构建成功"
        fi
    fi
    
    if [ ! -f "$JAR_FILE" ]; then
        log_error "JAR 文件不存在: $JAR_FILE"
        log_error "构建可能失败，请检查构建日志"
        exit 1
    fi
}

# 检查服务是否已运行
check_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            log_warn "服务已在运行 (PID: $PID)"
            log_info "如需重启，请先运行: bash stop.sh"
            exit 1
        else
            log_warn "PID 文件存在但进程不存在，删除旧的 PID 文件"
            rm -f "$PID_FILE"
        fi
    fi
}

# 启动服务（nohup 方式）
start_service() {
    log_step "启动服务..."
    
    check_running
    check_config
    
    load_environment
    
    # 创建日志目录
    LOG_DIR=$(dirname "$LOG_FILE")
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
    fi
    
    log_info "启动命令: java --add-opens java.base/java.nio=ALL-UNNAMED -jar $JAR_FILE -c $CONFIG_FILE"
    log_info "日志文件: $LOG_FILE"
    log_info "PID 文件: $PID_FILE"
    
    # 使用 nohup 启动服务（添加 --add-opens 参数用于监控 netty 直接内存）
    nohup java --add-opens java.base/java.nio=ALL-UNNAMED -jar "$JAR_FILE" -c "$CONFIG_FILE" > "$LOG_FILE" 2>&1 &
    PID=$!
    
    # 保存 PID
    echo $PID > "$PID_FILE"
    
    # 等待一下，检查进程是否还在运行
    sleep 2
    if ps -p "$PID" > /dev/null 2>&1; then
        log_info "服务启动成功 (PID: $PID)"
        log_info "查看日志: tail -f $LOG_FILE"
        log_info "停止服务: bash stop.sh 或 kill $PID"
    else
        log_error "服务启动失败，请查看日志: $LOG_FILE"
        rm -f "$PID_FILE"
        exit 1
    fi
}

# 主函数
main() {
    log_info "============================================"
    log_info "HttpProxy 启动脚本"
    log_info "============================================"
    
    # 解析命令行参数
    SKIP_BUILD=false
    SKIP_INSTALL=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --skip-install)
                SKIP_INSTALL=true
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            *)
                log_error "未知参数: $1"
                echo "用法: $0 [--skip-build] [--skip-install] [--config <配置文件路径>]"
                exit 1
                ;;
        esac
    done
    
    if [ "$SKIP_INSTALL" = false ]; then
        check_and_install_dependencies
    fi
    
    if [ "$SKIP_BUILD" = false ]; then
        build_project
    fi
    
    start_service
    
    log_info "============================================"
    log_info "启动完成！"
    log_info "============================================"
}

# 执行主函数
main "$@"

