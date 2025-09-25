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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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
check_dependencies() {
    log_step "检查系统依赖..."
    
    # 检查Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python3未安装，请先安装Python3"
        exit 1
    fi
    
    log_info "系统依赖检查完成"
}

# 检查数据库服务状态
check_db_services() {
    log_step "检查数据库服务状态..."
    
    # 调用db_services.sh脚本检查服务状态
    "$SCRIPT_DIR/db_services.sh" status
}

# 启动数据库服务
start_db_services() {
    log_step "启动数据库服务..."
    
    # 调用db_services.sh脚本启动服务
    "$SCRIPT_DIR/db_services.sh" start
}

# 设置环境变量
setup_environment() {
    log_step "设置环境变量..."
    
    # 检查.env文件
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        if [ -f "$PROJECT_ROOT/.env.example" ]; then
            log_info "复制.env.example到.env"
            cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
            log_warn "请根据实际情况修改.env文件中的配置"
        else
            log_error ".env文件不存在，且未找到.env.example文件"
            log_error "请手动创建.env配置文件或提供.env.example模板文件"
            exit 1
        fi
    fi
    
    # 加载环境变量
    if [ -f "$PROJECT_ROOT/.env" ]; then
        export $(cat "$PROJECT_ROOT/.env" | grep -v '^#' | grep -v '^$' | xargs)
    fi
    
    # 检查数据库配置文件是否存在，如果不存在则创建
    if [ ! -f "$SERVER_DIR/database/mysql.cnf" ] || [ ! -f "$SERVER_DIR/cache/redis.conf" ]; then
        log_info "创建数据库配置文件..."
        "$SCRIPT_DIR/db_services.sh" config
    fi
    
    # 检查必要的环境变量
    log_info "检查环境变量配置..."
    
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
    
    log_info "✓ 模型目录: $MODEL_DIR"
    log_info "✓ 服务器配置: $HOST:$PORT"
    
    log_info "环境变量设置完成"
}

# 创建必要的目录
create_directories() {
    log_step "创建必要的目录..."
    
    cd "$PROJECT_ROOT"
    mkdir -p storage/audio
    mkdir -p storage/tasks
    mkdir -p storage/srt
    mkdir -p logs
    mkdir -p database/backups
    
    log_info "目录创建完成"
}

# 安装Python依赖
install_python_dependencies() {
    log_step "安装Python依赖..."
    
    cd "$PROJECT_ROOT"
    if [ -f requirements.txt ]; then
        log_info "开始安装Python依赖包..."
        PIP_ERROR=$(pip3 install -r requirements.txt 2>&1)
        PIP_EXIT_CODE=$?
        
        if [ $PIP_EXIT_CODE -eq 0 ]; then
            log_info "Python依赖安装完成"
        else
            log_error "Python依赖安装失败"
            log_error "错误详情: $PIP_ERROR"
            exit 1
        fi
    else
        log_error "requirements.txt文件不存在"
        exit 1
    fi
}

# 检查数据库连接
check_database() {
    log_step "检查数据库连接..."
    log_info "使用云服务数据库，跳过本地数据库检查"
}

# 检查数据库表是否存在
check_database_tables() {
    log_step "检查数据库表结构..."
    
    # 检查MySQL连接信息
    if [ -z "$MYSQL_HOST" ] || [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_DATABASE" ]; then
        log_error "MySQL连接信息不完整，无法检查表结构"
        log_error "缺少环境变量: MYSQL_HOST, MYSQL_USER, MYSQL_DATABASE"
        exit 1
    fi
    
    # 检查tts_tasks表是否存在
    log_info "检查tts_tasks表..."
    if [ -n "$MYSQL_PASSWORD" ]; then
        TTS_TASKS_EXISTS=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'tts_tasks';" -s -N 2>/dev/null)
    else
        TTS_TASKS_EXISTS=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" "$MYSQL_DATABASE" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'tts_tasks';" -s -N 2>/dev/null)
    fi
    
    # 检查voice_configs表是否存在
    log_info "检查voice_configs表..."
    if [ -n "$MYSQL_PASSWORD" ]; then
        VOICE_CONFIGS_EXISTS=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'voice_configs';" -s -N 2>/dev/null)
    else
        VOICE_CONFIGS_EXISTS=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" "$MYSQL_DATABASE" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'voice_configs';" -s -N 2>/dev/null)
    fi
    
    log_info "表存在性检查结果: tts_tasks=$TTS_TASKS_EXISTS, voice_configs=$VOICE_CONFIGS_EXISTS"
    
    # 如果表不存在，则创建
    if [ "$TTS_TASKS_EXISTS" = "0" ] || [ "$VOICE_CONFIGS_EXISTS" = "0" ]; then
        log_info "发现缺失的表，开始创建..."
        create_database_tables
    else
        log_info "所有必需的表都已存在"
        # 检查DDL是否有变化
        check_database_schema_changes
    fi
}

# 创建数据库表
create_database_tables() {
    log_step "创建数据库表..."
    
    # 执行数据库初始化脚本
    if [ -f "$PROJECT_ROOT/server/database/init.sql" ]; then
        log_info "执行数据库初始化脚本: $PROJECT_ROOT/server/database/init.sql"
        
        if [ -n "$MYSQL_PASSWORD" ]; then
            MYSQL_INIT_ERROR=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < "$PROJECT_ROOT/server/database/init.sql" 2>&1)
            MYSQL_INIT_EXIT_CODE=$?
        else
            MYSQL_INIT_ERROR=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" "$MYSQL_DATABASE" < "$PROJECT_ROOT/server/database/init.sql" 2>&1)
            MYSQL_INIT_EXIT_CODE=$?
        fi
        
        if [ $MYSQL_INIT_EXIT_CODE -eq 0 ]; then
            log_info "数据库表创建完成"
        else
            log_error "数据库表创建失败"
            log_error "错误详情: $MYSQL_INIT_ERROR"
            exit 1
        fi
    else
        log_error "数据库初始化脚本不存在: $PROJECT_ROOT/server/database/init.sql"
        exit 1
    fi
}

# 检查数据库架构变化
check_database_schema_changes() {
    log_step "检查数据库架构变化..."
    
    # 生成当前表结构的校验和
    if [ -n "$MYSQL_PASSWORD" ]; then
        CURRENT_SCHEMA=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "
            SELECT CONCAT(table_name, ':', column_name, ':', data_type, ':', is_nullable, ':', column_default) 
            FROM information_schema.columns 
            WHERE table_schema = DATABASE() AND table_name IN ('tts_tasks', 'voice_configs') 
            ORDER BY table_name, ordinal_position;
        " -s -N 2>/dev/null)
    else
        CURRENT_SCHEMA=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" "$MYSQL_DATABASE" -e "
            SELECT CONCAT(table_name, ':', column_name, ':', data_type, ':', is_nullable, ':', column_default) 
            FROM information_schema.columns 
            WHERE table_schema = DATABASE() AND table_name IN ('tts_tasks', 'voice_configs') 
            ORDER BY table_name, ordinal_position;
        " -s -N 2>/dev/null)
    fi
    
    # 计算当前架构的MD5
    CURRENT_SCHEMA_MD5=$(echo "$CURRENT_SCHEMA" | md5sum | cut -d' ' -f1)
    
    # 计算期望架构的MD5（基于init.sql）
    if [ -f "$PROJECT_ROOT/server/database/init.sql" ]; then
        EXPECTED_SCHEMA_MD5=$(grep -E "CREATE TABLE|ADD COLUMN|MODIFY COLUMN" "$PROJECT_ROOT/server/database/init.sql" | md5sum | cut -d' ' -f1)
    else
        log_error "数据库初始化脚本不存在: $PROJECT_ROOT/server/database/init.sql"
        exit 1
    fi
    
    log_info "当前架构MD5: $CURRENT_SCHEMA_MD5"
    log_info "期望架构MD5: $EXPECTED_SCHEMA_MD5"
    
    if [ "$CURRENT_SCHEMA_MD5" != "$EXPECTED_SCHEMA_MD5" ]; then
        log_warn "检测到数据库架构变化，需要更新表结构"
        update_database_schema
    else
        log_info "数据库架构无变化，跳过更新"
    fi
}

# 更新数据库架构
update_database_schema() {
    log_step "更新数据库架构..."
    
    # 备份当前数据库结构
    BACKUP_FILE="$PROJECT_ROOT/database/backups/schema_backup_$(date +%Y%m%d_%H%M%S).sql"
    mkdir -p "$PROJECT_ROOT/database/backups"
    
    log_info "备份当前数据库结构到: $BACKUP_FILE"
    if [ -n "$MYSQL_PASSWORD" ]; then
        mysqldump -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" --no-data "$MYSQL_DATABASE" > "$BACKUP_FILE" 2>/dev/null
    else
        mysqldump -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" --no-data "$MYSQL_DATABASE" > "$BACKUP_FILE" 2>/dev/null
    fi
    
    if [ $? -eq 0 ]; then
        log_info "数据库结构备份完成"
    else
        log_warn "数据库结构备份失败，但继续执行更新"
    fi
    
    # 执行架构更新（重新运行init.sql）
    log_info "执行数据库架构更新..."
    create_database_tables
}

# 初始化数据库
initialize_database() {
    log_step "初始化MySQL数据库..."
    
    # 检查MySQL连接信息
    if [ -z "$MYSQL_HOST" ] || [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_DATABASE" ]; then
        log_error "MySQL连接信息不完整，跳过数据库初始化"
        log_error "缺少环境变量: MYSQL_HOST, MYSQL_USER, MYSQL_DATABASE"
        exit 1
    fi
    
    # 检查并创建/更新数据库表
    check_database_tables
}

# 检查supervisor安装
check_supervisor() {
    log_step "检查supervisor安装..."
    
    if ! command -v supervisord &> /dev/null; then
        log_warn "supervisor未安装，将在安装依赖时自动安装"
        return 0
    fi
    
    if ! command -v supervisorctl &> /dev/null; then
        log_warn "supervisorctl未找到，将在安装依赖时重新安装supervisor"
        return 0
    fi
    
    log_info "supervisor检查通过"
}

# 启动supervisor守护进程
start_supervisord() {
    log_step "启动supervisor守护进程..."
    
    # 检查supervisor是否已经在运行
    if pgrep -f "supervisord" > /dev/null; then
        log_info "supervisor守护进程已在运行，跳过启动"
        return 0
    fi
    
    # 设置环境变量供supervisor使用
    export MODEL_DIR="$MODEL_DIR"
    export HOST="$HOST"
    export PORT="$PORT"
    export GPU_MEMORY_UTILIZATION="$GPU_MEMORY_UTILIZATION"
    export DATABASE_URL="$DATABASE_URL"
    export AUDIO_OUTPUT_DIR="$AUDIO_OUTPUT_DIR"
    
    # 设置supervisor进程管理配置
    export SUPERVISOR_AUTOSTART="${SUPERVISOR_AUTOSTART:-true}"
    export SUPERVISOR_AUTORESTART="${SUPERVISOR_AUTORESTART:-true}"
    export SUPERVISOR_STARTSECS="${SUPERVISOR_STARTSECS:-10}"
    export SUPERVISOR_STARTRETRIES="${SUPERVISOR_STARTRETRIES:-3}"
    export SUPERVISOR_LOG_MAXBYTES="${SUPERVISOR_LOG_MAXBYTES:-50MB}"
    export SUPERVISOR_LOG_BACKUPS="${SUPERVISOR_LOG_BACKUPS:-10}"
    export SUPERVISOR_API_PRIORITY="${SUPERVISOR_API_PRIORITY:-100}"
    export SUPERVISOR_WORKER_PRIORITY="${SUPERVISOR_WORKER_PRIORITY:-200}"
    export SUPERVISOR_USER="${SUPERVISOR_USER:-www-data}"
    export SUPERVISOR_PROJECT_DIR="${SUPERVISOR_PROJECT_DIR:-$PROJECT_ROOT}"
    
    # 启动supervisord，使用绝对路径配置文件
    log_info "启动supervisor守护进程..."
    SUPERVISORD_ERROR=$(supervisord -c "$PROJECT_ROOT/server/supervisor/supervisord.conf" 2>&1)
    SUPERVISORD_EXIT_CODE=$?
    
    if [ $SUPERVISORD_EXIT_CODE -eq 0 ]; then
        log_info "supervisor守护进程启动成功"
        sleep 2  # 等待supervisor完全启动
    else
        log_error "supervisor守护进程启动失败"
        log_error "错误详情: $SUPERVISORD_ERROR"
        exit 1
    fi
}

# 启动所有服务
start_services() {
    log_step "通过supervisor启动TTS服务组件..."
    
    # 检查服务是否已经在运行
    if supervisorctl status tts-services:* 2>/dev/null | grep -q "RUNNING"; then
        log_info "部分服务已在运行，检查状态..."
        supervisorctl status tts-services:*
        
        # 只启动未运行的服务
        supervisorctl status tts-services:* | grep -v "RUNNING" | awk '{print $1}' | while read service; do
            if [ -n "$service" ]; then
                log_info "启动服务: $service"
                supervisorctl start "$service"
            fi
        done
    else
        # 启动TTS服务组
        log_info "启动所有TTS服务组件..."
        SUPERVISOR_START_ERROR=$(supervisorctl start tts-services:* 2>&1)
        SUPERVISOR_START_EXIT_CODE=$?
    fi
    
    if [ $SUPERVISOR_START_EXIT_CODE -eq 0 ]; then
        log_info "所有TTS服务组件启动完成"
    else
        log_error "TTS服务组件启动失败"
        log_error "错误详情: $SUPERVISOR_START_ERROR"
        # 显示详细状态
        supervisorctl status tts-services:*
        exit 1
    fi
}

# 检查服务状态
check_services() {
    log_step "检查服务状态..."
    
    # 检查supervisor守护进程
    if ! supervisorctl status > /dev/null 2>&1; then
        log_warn "✗ supervisor守护进程未运行"
        return 1
    fi
    
    log_info "✓ supervisor守护进程运行正常"
    
    # 检查所有服务组件状态
    log_info "服务组件状态:"
    supervisorctl status tts-services:* | while read line; do
        if echo "$line" | grep -q "RUNNING"; then
            service_name=$(echo "$line" | awk '{print $1}')
            log_info "  ✓ $service_name 运行正常"
        elif echo "$line" | grep -q "STOPPED\|FATAL\|EXITED"; then
            service_name=$(echo "$line" | awk '{print $1}')
            status=$(echo "$line" | awk '{print $2}')
            log_warn "  ✗ $service_name 状态异常: $status"
        fi
    done
    
    # 检查服务状态
    log_info "检查服务状态..."
    if supervisorctl status | grep -q "RUNNING"; then
        log_info "✓ 服务运行正常"
    else
        log_warn "✗ 部分服务可能异常"
    fi
    
    # 检查API服务器健康状态
    log_info "检查API服务器健康状态..."
    if curl -f http://localhost:$PORT/health > /dev/null 2>&1; then
        log_info "✓ API服务器健康检查通过"
    else
        log_warn "✗ API服务器健康检查失败"
    fi
    
    # 检查数据库连接
    log_info "检查数据库连接..."
    if psql "$DATABASE_URL" -c "SELECT 1;" > /dev/null 2>&1; then
        log_info "✓ 数据库连接正常"
    else
        log_warn "✗ 数据库连接异常"
    fi
}

# 停止服务
stop_services() {
    log_step "停止所有服务..."
    
    # 检查supervisor是否运行
    if ! supervisorctl status > /dev/null 2>&1; then
        log_warn "supervisor守护进程未运行，无需停止服务"
        return 0
    fi
    
    # 停止TTS服务组
    log_info "正在停止TTS服务组件..."
    supervisorctl stop tts-services:*
    
    if [ $? -eq 0 ]; then
        log_info "TTS服务组件已停止"
    else
        log_warn "停止TTS服务组件时出现问题"
    fi
    
    # 停止supervisor守护进程
    log_info "正在停止supervisor守护进程..."
    supervisorctl shutdown
    
    if [ $? -eq 0 ]; then
        log_info "supervisor守护进程已停止"
    else
        log_warn "停止supervisor守护进程时出现问题"
    fi
    
    # 清理旧的PID文件（兼容性）
    rm -f logs/api_server.pid logs/worker_long.pid 2>/dev/null || true
    
    log_info "所有服务已停止"
}

# supervisor管理命令
supervisor_cmd() {
    if ! supervisorctl status > /dev/null 2>&1; then
        log_error "supervisor守护进程未运行，请先启动服务"
        exit 1
    fi
    
    case "$1" in
        "")
            log_info "supervisor服务状态:"
            supervisorctl status
            ;;
        *)
            log_info "执行supervisor命令: $*"
            supervisorctl "$@"
            ;;
    esac
}

# 显示帮助信息
show_help() {
    echo "Enhanced TTS API Server 启动脚本 (基于Supervisor)"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  start                 启动所有服务 (包括TTS API、任务处理器)"
    echo "  stop                  停止所有服务"
    echo "  restart               重启所有服务"
    echo "  status                检查服务状态"
    echo "  logs                  查看日志"
    echo "  supervisor [cmd]      执行supervisor命令"
    echo "  help                  显示此帮助信息"
    echo ""
    echo "服务组件:"
    echo "  - TTS API服务器       提供语音合成API接口"
    echo "  - TTS任务处理器       处理长文本语音合成任务"

    echo ""
    echo "示例:"
    echo "  $0 start              # 启动所有服务"
    echo "  $0 stop               # 停止所有服务"
    echo "  $0 restart            # 重启所有服务"
    echo "  $0 status             # 检查服务状态"
    echo "  $0 supervisor         # 查看supervisor状态"
    echo "  $0 supervisor restart tts-api-server  # 重启API服务器"
    echo "  $0 supervisor restart tts-api-server     # 重启API服务器"
}

# 查看日志
show_logs() {
    log_step "显示服务日志..."
    
    echo "=== API服务器日志 ==="
    if [ -f "$PROJECT_ROOT/logs/api_server.log" ]; then
        tail -n 50 "$PROJECT_ROOT/logs/api_server.log"
    else
        echo "API服务器日志文件不存在"
    fi
    
    echo ""
    echo "=== 任务处理器日志 ==="
    if [ -f "$PROJECT_ROOT/logs/worker_long.log" ]; then
        tail -n 50 "$PROJECT_ROOT/logs/worker_long.log"
    else
        echo "任务处理器日志文件不存在"
    fi
    
    echo ""
    echo "=== 服务日志 ==="
    if [ -f "$PROJECT_ROOT/logs/tts_api.log" ]; then
        tail -n 50 "$PROJECT_ROOT/logs/tts_api.log"
    else
        echo "服务日志文件不存在"
    fi
}

# 主函数
main() {
    case "$1" in
        start)
            check_dependencies # 检查依赖
            setup_environment # 配置环境变量
            create_directories # 创建必要的目录
            check_supervisor # 检查supervisor是否安装
            install_python_dependencies # 安装Python依赖
            
            start_supervisord # 启动supervisor守护进程
            
            check_database # 检查数据库连接
            initialize_database # 初始化数据库
            start_services # 启动服务
            
            sleep 5 # 等待服务启动
            check_services # 检查服务状态
            
            log_info "所有服务启动完成！"
            log_info "API服务器地址: http://localhost:$PORT"
            log_info "健康检查: http://localhost:$PORT/health"
            log_info "API文档: http://localhost:$PORT/docs"
            ;;
        stop)
            stop_services # 停止服务
            ;;
        restart)
            stop_services # 停止服务
            sleep 3
            main start
            ;;
        status)
            check_services # 检查服务状态
            ;;
        logs)
            show_logs # 显示日志
            ;;
        supervisor)
            shift
            supervisor_cmd "$@"
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