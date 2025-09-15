#!/bin/bash

# 增强型TTS API服务器启动脚本
# 此脚本帮助您启动TTS API服务器和任务处理器
# 支持本地部署模式

set -e  # 遇到错误时退出

# 输出颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
SERVER_DIR="$PROJECT_ROOT/server"

# 打印彩色输出的函数
log_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[步骤]${NC} $1"
}

# 检查依赖
检查依赖() {
    log_step "检查系统依赖..."
    
    # 检查Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python3未安装，请先安装Python3"
        exit 1
    fi
    
    # 检查MySQL客户端（仅在需要初始化数据库时检查）
    if [ "$INIT_DB" = "true" ] && ! command -v mysql &> /dev/null; then
        log_warn "MySQL客户端未安装，将跳过数据库初始化"
        SKIP_DB_INIT=true
    fi
    
    log_info "系统依赖检查完成"
}

# 设置环境变量
设置环境变量() {
    log_step "设置环境变量..."
    
    # 检查.env文件
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            log_info "复制.env.example到.env"
            cp .env.example .env
            log_warn "请根据实际情况修改.env文件中的配置"
        else
            log_error ".env文件不存在，且未找到.env.example文件"
            log_error "请手动创建.env配置文件或提供.env.example模板文件"
            exit 1
        fi
    fi
    
    # 加载环境变量
    if [ -f ".env" ]; then
        export $(cat .env | grep -v '^#' | grep -v '^$' | xargs)
    fi
    
    # 检查必要的环境变量
    log_info "检查环境变量配置..."
    
    # 检查MySQL配置
    missing_mysql_vars=()
    [ -z "$MYSQL_HOST" ] && missing_mysql_vars+=("MYSQL_HOST")
    [ -z "$MYSQL_PORT" ] && missing_mysql_vars+=("MYSQL_PORT")
    [ -z "$MYSQL_USER" ] && missing_mysql_vars+=("MYSQL_USER")
    [ -z "$MYSQL_PASSWORD" ] && missing_mysql_vars+=("MYSQL_PASSWORD")
    [ -z "$MYSQL_DATABASE" ] && missing_mysql_vars+=("MYSQL_DATABASE")
    
    if [ ${#missing_mysql_vars[@]} -gt 0 ]; then
        log_error "MySQL配置缺失以下参数: ${missing_mysql_vars[*]}"
        log_error "请在.env文件中配置这些参数"
        exit 1
    fi
    
    # 检查Redis配置
    missing_redis_vars=()
    [ -z "$REDIS_HOST" ] && missing_redis_vars+=("REDIS_HOST")
    [ -z "$REDIS_PORT" ] && missing_redis_vars+=("REDIS_PORT")
    [ -z "$REDIS_DB" ] && missing_redis_vars+=("REDIS_DB")
    
    if [ ${#missing_redis_vars[@]} -gt 0 ]; then
        log_error "Redis配置缺失以下参数: ${missing_redis_vars[*]}"
        log_error "请在.env文件中配置这些参数"
        exit 1
    fi
    
    # 检查TTS模型配置
    if [ -z "$MODEL_DIR" ]; then
        log_error "MODEL_DIR未配置，请在.env文件中设置TTS模型目录路径"
        exit 1
    elif [ ! -d "$MODEL_DIR" ]; then
        log_error "TTS模型目录不存在: $MODEL_DIR"
        log_error "请确保MODEL_DIR指向正确的模型目录"
        exit 1
    fi
    
    # 检查服务器配置
    missing_server_vars=()
    [ -z "$HOST" ] && missing_server_vars+=("HOST")
    [ -z "$PORT" ] && missing_server_vars+=("PORT")
    
    if [ ${#missing_server_vars[@]} -gt 0 ]; then
        log_error "服务器配置缺失以下参数: ${missing_server_vars[*]}"
        log_error "请在.env文件中配置这些参数"
        exit 1
    fi
    
    log_info "✓ MySQL配置: $MYSQL_USER@$MYSQL_HOST:$MYSQL_PORT/$MYSQL_DATABASE"
    log_info "✓ Redis配置: $REDIS_HOST:$REDIS_PORT/$REDIS_DB"
    log_info "✓ 模型目录: $MODEL_DIR"
    log_info "✓ 服务器配置: $HOST:$PORT"
    
    log_info "环境变量设置完成"
}

# 创建必要的目录
创建目录() {
    log_step "创建必要的目录..."
    
    mkdir -p storage/audio
    mkdir -p storage/tasks
    mkdir -p storage/srt
    mkdir -p logs
    mkdir -p database/backups
    
    log_info "目录创建完成"
}

# 安装Python依赖
安装Python依赖() {
    log_step "安装Python依赖..."
    
    if [ -f requirements.txt ]; then
        pip3 install -r requirements.txt
        log_info "Python依赖安装完成"
    else
        log_warn "requirements.txt文件不存在，跳过Python依赖安装"
    fi
}

# 检查数据库连接
检查数据库() {
    log_step "检查MySQL数据库连接..."
    
    # 从环境变量获取MySQL连接信息
    MYSQL_HOST=${MYSQL_HOST:-localhost}
    MYSQL_PORT=${MYSQL_PORT:-3306}
    MYSQL_USER=${MYSQL_USER:-root}
    MYSQL_PASSWORD=${MYSQL_PASSWORD:-}
    MYSQL_DATABASE=${MYSQL_DATABASE:-tts_db}
    
    # 检查MySQL连接
    if [ -n "$MYSQL_PASSWORD" ]; then
        mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1
    else
        mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -e "SELECT 1;" > /dev/null 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        log_info "MySQL数据库连接正常"
    else
        log_error "MySQL数据库连接失败，请确保MySQL服务已启动并配置正确"
        log_error "连接信息: $MYSQL_USER@$MYSQL_HOST:$MYSQL_PORT/$MYSQL_DATABASE"
        log_error "请检查："
        log_error "1. MySQL服务是否运行"
        log_error "2. 数据库连接参数是否正确"
        log_error "3. 用户权限是否足够"
        exit 1
    fi
    
    # 检查Redis连接
    log_step "检查Redis连接..."
    REDIS_HOST=${REDIS_HOST:-localhost}
    REDIS_PORT=${REDIS_PORT:-6379}
    
    if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping > /dev/null 2>&1; then
        log_info "Redis连接正常"
    else
        log_error "Redis连接失败，请确保Redis服务已启动并配置正确"
        log_error "连接信息: $REDIS_HOST:$REDIS_PORT"
        exit 1
    fi
}

# 初始化数据库
初始化数据库() {
    log_step "初始化MySQL数据库表结构..."
    
    # 检查MySQL连接信息
    if [ -z "$MYSQL_HOST" ] || [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_DATABASE" ]; then
        log_error "MySQL连接信息不完整，请检查环境变量: MYSQL_HOST, MYSQL_USER, MYSQL_DATABASE"
        exit 1
    fi
    
    # 执行数据库初始化脚本
    if [ -f server/database/init.sql ]; then
        log_info "连接到MySQL数据库: $MYSQL_HOST:$MYSQL_PORT/$MYSQL_DATABASE"
        
        if [ -n "$MYSQL_PASSWORD" ]; then
            mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < server/database/init.sql
        else
            mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" "$MYSQL_DATABASE" < server/database/init.sql
        fi
        
        if [ $? -eq 0 ]; then
            log_info "MySQL数据库初始化完成"
        else
            log_error "MySQL数据库初始化失败"
            exit 1
        fi
    else
        log_warn "数据库初始化脚本不存在，跳过初始化"
    fi
}

# 启动API服务器
start_api_server() {
    log_step "启动TTS API服务器..."
    
    # 直接启动Python进程
    nohup python3 server/api_server.py \
        --model_dir "$MODEL_DIR" \
        --host "$HOST" \
        --port "$PORT" \
        --gpu_memory_utilization "$GPU_MEMORY_UTILIZATION" \
        > logs/api_server.log 2>&1 &
    
    echo $! > logs/api_server.pid
    log_info "API服务器启动完成，PID: $(cat logs/api_server.pid)"
}

# 启动任务处理器
start_workers() {
    log_step "启动任务处理器..."
    
    # 启动长文本任务处理器
    nohup python3 server/task_worker.py \
        --model-dir "$MODEL_DIR" \
        --database-url "$DATABASE_URL" \
        --task-type long_text \
        --audio-output-dir "$AUDIO_OUTPUT_DIR" \
        > logs/worker_long.log 2>&1 &
    
    echo $! > logs/worker_long.pid
    log_info "长文本任务处理器启动完成，PID: $(cat logs/worker_long.pid)"
}

# 检查服务状态
check_services() {
    log_step "检查服务状态..."
    
    # 检查API服务器
    if curl -f http://localhost:$PORT/health > /dev/null 2>&1; then
        log_info "✓ API服务器运行正常"
    else
        log_warn "✗ API服务器可能未正常启动"
    fi
    
    # 检查数据库
    if psql "$DATABASE_URL" -c "SELECT 1;" > /dev/null 2>&1; then
        log_info "✓ 数据库运行正常"
    else
        log_warn "✗ 数据库连接异常"
    fi
}

# 停止服务
stop_services() {
    log_step "停止所有服务..."
    
    # 停止Python进程
    if [ -f logs/api_server.pid ]; then
        kill $(cat logs/api_server.pid) 2>/dev/null || true
        rm -f logs/api_server.pid
        log_info "API服务器已停止"
    fi
    
    if [ -f logs/worker_long.pid ]; then
        kill $(cat logs/worker_long.pid) 2>/dev/null || true
        rm -f logs/worker_long.pid
        log_info "任务处理器已停止"
    fi
    
    log_info "所有服务已停止"
}

# 显示帮助信息
show_help() {
    echo "Enhanced TTS API Server 启动脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  start                 启动所有服务"
    echo "  stop                  停止所有服务"
    echo "  restart               重启所有服务"
    echo "  status                检查服务状态"
    echo "  logs                  查看日志"
    echo "  help                  显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 start              # 启动所有服务"
    echo "  $0 stop               # 停止所有服务"
    echo "  $0 restart            # 重启所有服务"
    echo "  $0 status             # 检查服务状态"
}

# 查看日志
show_logs() {
    log_step "显示服务日志..."
    
    echo "=== API服务器日志 ==="
    if [ -f logs/api_server.log ]; then
        tail -n 50 logs/api_server.log
    else
        echo "API服务器日志文件不存在"
    fi
    
    echo ""
    echo "=== 任务处理器日志 ==="
    if [ -f logs/worker_long.log ]; then
        tail -n 50 logs/worker_long.log
    else
        echo "任务处理器日志文件不存在"
    fi
}

# 主函数
main() {
    case "$1" in
        start)
            检查依赖
            设置环境变量
            创建目录
            安装Python依赖
            
            检查数据库
            初始化数据库
            start_api_server
            start_workers
            
            sleep 5
            check_services
            
            log_info "所有服务启动完成！"
            log_info "API服务器地址: http://localhost:$PORT"
            log_info "健康检查: http://localhost:$PORT/health"
            log_info "API文档: http://localhost:$PORT/docs"
            ;;
        stop)
            stop_services
            ;;
        restart)
            stop_services
            sleep 3
            main start
            ;;
        status)
            check_services
            ;;
        logs)
            show_logs
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"