#!/bin/bash

# MySQL和Redis管理脚本
# 此脚本用于管理MySQL和Redis服务，包括安装、配置、启动、停止等功能

set -e  # 遇到错误时退出

# 输出颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$PROJECT_ROOT/server"
DATA_DIR="$PROJECT_ROOT/data"
MYSQL_DATA_DIR="$DATA_DIR/mysql"
REDIS_DATA_DIR="$DATA_DIR/redis"
MYSQL_CONFIG_FILE="$SERVER_DIR/database/mysql.cnf"
REDIS_CONFIG_FILE="$SERVER_DIR/cache/redis.conf"

# 打印彩色输出的函数
log_info() { echo -e "${GREEN}[信息]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[警告]${NC} $1"; }
log_error() { echo -e "${RED}[错误]${NC} $1"; }
log_step() { echo -e "${BLUE}[步骤]${NC} $1"; }

# 加载环境变量
load_env() {
    if [ -f "$PROJECT_ROOT/.env" ]; then
        export $(cat "$PROJECT_ROOT/.env" | grep -v '^#' | grep -v '^$' | xargs)
    else
        log_error ".env文件不存在，请先创建.env文件"
        exit 1
    fi
}

# 检查服务是否已安装
check_mysql_installed() { command -v mysql &> /dev/null; }
check_redis_installed() { command -v redis-server &> /dev/null; }

# 创建配置文件
create_configs() {
    log_step "创建配置文件..."
    
    # 加载环境变量
    load_env
    
    # 确保目录存在
    mkdir -p "$(dirname "$MYSQL_CONFIG_FILE")" "$(dirname "$REDIS_CONFIG_FILE")"
    mkdir -p "$MYSQL_DATA_DIR" "$REDIS_DATA_DIR"
    
    # 创建MySQL配置文件
    cat > "$MYSQL_CONFIG_FILE" << EOF
[client]
host=${MYSQL_HOST:-localhost}
port=${MYSQL_PORT:-3306}
user=${MYSQL_USER:-tts_user}
password=${MYSQL_PASSWORD:-tts_password}
database=${MYSQL_DATABASE:-tts_db}

[mysqld]
port=${MYSQL_PORT:-3306}
datadir=${MYSQL_DATA_DIR}
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
default-time-zone='+8:00'
EOF
    
    # 创建Redis配置文件
    cat > "$REDIS_CONFIG_FILE" << EOF
# Redis配置文件
port ${REDIS_PORT:-6379}
bind 127.0.0.1
dir ${REDIS_DATA_DIR}

# 如果设置了密码，将使用此密码
requirepass ${REDIS_PASSWORD:-}

# 数据库数量
databases ${REDIS_DB:-0}

# 队列前缀
# 注意：这不是Redis标准配置，仅用于应用程序识别
# ${REDIS_QUEUE_PREFIX:-tts_queue}
EOF
    
    log_info "配置文件已创建"
}

# 安装服务
install_services() {
    log_step "安装MySQL和Redis..."
    
    # 根据操作系统类型安装
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            if ! check_mysql_installed; then
                log_info "安装MySQL..."
                brew install mysql
            fi
            
            if ! check_redis_installed; then
                log_info "安装Redis..."
                brew install redis
            fi
        else
            log_error "未找到Homebrew，请先安装Homebrew"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command -v apt-get &> /dev/null; then
            if ! check_mysql_installed; then
                log_info "安装MySQL..."
                apt-get update
                apt-get install -y mysql-server
            fi
            
            if ! check_redis_installed; then
                log_info "安装Redis..."
                apt-get update
                apt-get install -y redis-server
            fi
        elif command -v yum &> /dev/null; then
            if ! check_mysql_installed; then
                log_info "安装MySQL..."
                yum install -y mysql-server
            fi
            
            if ! check_redis_installed; then
                log_info "安装Redis..."
                yum install -y redis
            fi
        else
            log_error "不支持的Linux发行版"
            exit 1
        fi
    else
        log_error "不支持的操作系统"
        exit 1
    fi
    
    log_info "安装完成"
}

# 启动服务
start_services() {
    log_step "启动服务..."
    
    # 启动MySQL
    if check_mysql_installed; then
        if ! pgrep -x "mysqld" > /dev/null; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                brew services start mysql
            elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                if command -v systemctl &> /dev/null; then
                    systemctl start mysql || systemctl start mysqld
                elif command -v service &> /dev/null; then
                    service mysql start || service mysqld start
                fi
            fi
            log_info "MySQL服务已启动"
        else
            log_info "MySQL服务已在运行"
        fi
    else
        log_warn "MySQL未安装，无法启动"
    fi
    
    # 启动Redis
    if check_redis_installed; then
        if ! pgrep -x "redis-server" > /dev/null; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                brew services start redis
            elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                if command -v systemctl &> /dev/null; then
                    systemctl start redis
                elif command -v service &> /dev/null; then
                    service redis-server start
                fi
            fi
            log_info "Redis服务已启动"
        else
            log_info "Redis服务已在运行"
        fi
    else
        log_warn "Redis未安装，无法启动"
    fi
}

# 停止服务
stop_services() {
    log_step "停止服务..."
    
    # 停止MySQL
    if check_mysql_installed && pgrep -x "mysqld" > /dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew services stop mysql
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command -v systemctl &> /dev/null; then
                systemctl stop mysql || systemctl stop mysqld
            elif command -v service &> /dev/null; then
                service mysql stop || service mysqld stop
            fi
        fi
        log_info "MySQL服务已停止"
    else
        log_info "MySQL服务未在运行"
    fi
    
    # 停止Redis
    if check_redis_installed && pgrep -x "redis-server" > /dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew services stop redis
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command -v systemctl &> /dev/null; then
                systemctl stop redis
            elif command -v service &> /dev/null; then
                service redis-server stop
            fi
        fi
        log_info "Redis服务已停止"
    else
        log_info "Redis服务未在运行"
    fi
}

# 初始化数据库
init_database() {
    log_step "初始化数据库..."
    
    # 加载环境变量
    load_env
    
    # 确保MySQL在运行
    if ! pgrep -x "mysqld" > /dev/null; then
        log_error "MySQL服务未运行，请先启动MySQL服务"
        exit 1
    fi
    
    # 创建数据库和用户
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE:-tts_db} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -u root -e "CREATE USER IF NOT EXISTS '${MYSQL_USER:-tts_user}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD:-tts_password}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE:-tts_db}.* TO '${MYSQL_USER:-tts_user}'@'%';"
    mysql -u root -e "FLUSH PRIVILEGES;"
    
    # 导入初始化SQL
    if [ -f "$SERVER_DIR/database/init.sql" ]; then
        log_info "导入初始化SQL..."
        mysql -u root ${MYSQL_DATABASE:-tts_db} < "$SERVER_DIR/database/init.sql"
    fi
    
    log_info "数据库初始化完成"
}

# 检查服务状态
check_status() {
    log_step "检查服务状态..."
    
    # 检查MySQL
    if check_mysql_installed; then
        if pgrep -x "mysqld" > /dev/null; then
            log_info "MySQL服务正在运行"
        else
            log_warn "MySQL服务未在运行"
        fi
    else
        log_warn "MySQL未安装"
    fi
    
    # 检查Redis
    if check_redis_installed; then
        if pgrep -x "redis-server" > /dev/null; then
            log_info "Redis服务正在运行"
        else
            log_warn "Redis服务未在运行"
        fi
    else
        log_warn "Redis未安装"
    fi
}

# 显示帮助信息
show_help() {
    echo "MySQL和Redis管理脚本"
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  install          安装MySQL和Redis"
    echo "  config           创建配置文件"
    echo "  init             初始化数据库"
    echo "  start            启动服务"
    echo "  stop             停止服务"
    echo "  status           检查服务状态"
    echo "  help             显示此帮助信息"
}

# 主函数
main() {
    # 如果没有参数，显示帮助信息
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    # 处理命令行参数
    case "$1" in
        install)
            install_services
            ;;
        config)
            create_configs
            ;;
        init)
            init_database
            ;;
        start)
            start_services
            ;;
        stop)
            stop_services
            ;;
        status)
            check_status
            ;;
        help)
            show_help
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"