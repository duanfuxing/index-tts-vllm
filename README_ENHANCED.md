# 增强型TTS API服务器

基于原有TTS服务的增强版本，提供在线TTS合成和长文本TTS任务队列功能。

## 功能特性

### 🎯 核心功能
- **在线TTS合成**: 限制300字，直接返回音频和字幕文件
- **长文本TTS**: 限制5万字，提供任务提交和查询API
- **MySQL数据库**: 可靠的关系型数据库存储
- **Redis队列**: 高性能队列系统避免多worker重复处理
- **音色管理**: 统一使用character指定音色
- **健康检查**: 提供服务器状态监控API

### 🚀 技术特性
- FastAPI框架，自动生成API文档
- 异步数据库连接池
- 任务状态实时跟踪
- SRT字幕文件生成
- Docker容器化部署
- 完整的错误处理和重试机制

## 快速开始

### 1. 环境准备

```bash
# 克隆项目（如果需要）
git clone <repository_url>
cd server

# 安装Python依赖
pip install -r requirements.txt
```

### 2. 配置环境

复制并编辑配置文件：
```bash
cp .env.example .env
# 编辑.env文件，设置正确的MODEL_DIR路径
```

主要配置项：
```bash
# TTS模型路径（必须设置）
MODEL_DIR=/path/to/IndexTeam/Index-TTS

# MySQL数据库连接
DATABASE_URL=mysql://tts_user:tts_password@localhost:3306/tts_db

# Redis连接
REDIS_URL=redis://localhost:6379/0

# 服务器配置
HOST=0.0.0.0
PORT=11996
```

### 3. 数据库准备

#### MySQL数据库

安装并配置MySQL：

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install mysql-server

# CentOS/RHEL
sudo yum install mysql-server
# 或者
sudo dnf install mysql-server

# macOS
brew install mysql
brew services start mysql
```

启动MySQL服务并创建数据库：

```bash
# 启动MySQL服务 (Linux)
sudo systemctl start mysql
sudo systemctl enable mysql

# 登录MySQL
mysql -u root -p

# 创建数据库和用户
CREATE DATABASE tts_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'tts_user'@'%' IDENTIFIED BY 'tts_password';
GRANT ALL PRIVILEGES ON tts_db.* TO 'tts_user'@'%';
FLUSH PRIVILEGES;
EXIT;
```

#### Redis缓存

安装并配置Redis：

```bash
# Ubuntu/Debian
sudo apt-get install redis-server

# CentOS/RHEL
sudo yum install redis
# 或者
sudo dnf install redis

# macOS
brew install redis
brew services start redis

# 启动Redis服务 (Linux)
sudo systemctl start redis
sudo systemctl enable redis

# 测试Redis连接
redis-cli ping
# 应该返回 PONG
```

#### Redis配置优化

编辑Redis配置文件以优化性能：

```bash
# 编辑Redis配置文件
sudo nano /etc/redis/redis.conf

# 推荐配置项：
# maxmemory 256mb
# maxmemory-policy allkeys-lru
# save 900 1
# save 300 10
# save 60 10000

# 重启Redis服务
sudo systemctl restart redis
```

#### 云数据库配置

如果使用云数据库服务（如阿里云RDS、腾讯云等），请：

1. 在云控制台创建MySQL实例和Redis实例
2. 配置安全组规则允许访问
3. 获取连接地址、端口、用户名和密码
4. 在.env文件中配置相应的连接信息

### 4. 启动服务

#### 方式一：使用启动脚本（推荐）
```bash
# 使脚本可执行
chmod +x start_services.sh

# 启动所有服务
./start_services.sh start

# 检查服务状态
./start_services.sh status

# 查看日志
./start_services.sh logs

# 停止服务
./start_services.sh stop
```

#### 方式二：手动启动
```bash
# 1. 初始化数据库
mysql -u tts_user -p tts_db < database/init.sql

# 2. 启动API服务器
python server/enhanced_api_server.py --model_dir /path/to/model --host 0.0.0.0 --port 11996

# 3. 启动任务处理器（另一个终端）
python server/task_worker.py --model-dir /path/to/model --task-type long_text
```

### 5. 验证部署

```bash
# 健康检查
curl http://localhost:11996/health

# 获取音色列表
curl http://localhost:11996/voices

# 在线TTS测试
curl -X POST "http://localhost:11996/tts/online" \
  -H "Content-Type: application/json" \
  -d '{"text":"你好，这是测试文本","character":"female"}'
```

## API 文档

启动服务后，访问以下地址查看完整API文档：
- Swagger UI: http://localhost:11996/docs
- ReDoc: http://localhost:11996/redoc

### 主要接口

#### 1. 在线TTS合成
```http
POST /tts/online
Content-Type: application/json

{
  "text": "要合成的文本（最多300字）",
  "character": "音色名称",
  "speed": 1.0,
  "temperature": 0.3,
  "top_p": 0.7,
  "top_k": 20,
  "callback_url": "http://example.com/callback" // 可选
}
```

#### 2. 长文本任务提交
```http
POST /tts/long/submit
Content-Type: application/json

{
  "text": "长文本内容（最多5万字）",
  "character": "音色名称",
  "speed": 1.0,
  "temperature": 0.3,
  "top_p": 0.7,
  "top_k": 20,
  "callback_url": "http://example.com/callback" // 可选
}
```

#### 3. 任务状态查询
```http
GET /tts/long/status/{task_id}
```

#### 4. 获取音色列表
```http
GET /voices
```

#### 5. 健康检查
```http
GET /health
```

## 数据库结构

### tts_tasks 表
```sql
CREATE TABLE tts_tasks (
    id SERIAL PRIMARY KEY,
    task_id VARCHAR(36) UNIQUE NOT NULL,
    task_type VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    text TEXT NOT NULL,
    voice VARCHAR(100) NOT NULL,
    payload JSONB,
    result JSONB,
    audio_url TEXT,
    srt_content TEXT,
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    callback_url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP
);
```

### 任务状态说明
- `pending`: 等待处理
- `processing`: 正在处理
- `completed`: 处理完成
- `failed`: 处理失败
- `cancelled`: 已取消

## 部署架构

```
┌─────────────────┐    ┌─────────────────┐
│  API Server     │    │  Task Worker    │
│  (FastAPI)      │    │  (长文本处理)    │
│  Port: 11996    │    │                 │
└─────────────────┘    └─────────────────┘
        │                        │
        │                        │
        └────────┬───────────────┘
                 │
        ┌─────────────────┐    ┌─────────────────┐
        │  MySQL          │    │  Redis          │
        │  (数据存储)      │    │  (任务队列)      │
        │  Port: 3306     │    │  Port: 6379     │
        └─────────────────┘    └─────────────────┘
```

## 监控和维护

### 日志文件
- API服务器: `logs/api_server.log`
- 任务处理器: `logs/worker_long.log`
- Docker日志: `docker-compose logs`

### 数据库维护
```bash
# 查看任务统计
mysql -u tts_user -p tts_db -e "SELECT status, COUNT(*) FROM tts_tasks GROUP BY status;"

# 清理旧任务（7天前）
mysql -u tts_user -p tts_db -e "DELETE FROM tts_tasks WHERE created_at < NOW() - INTERVAL 7 DAY;"

# 数据库备份
mysqldump -u tts_user -p tts_db > backup_$(date +%Y%m%d_%H%M%S).sql

# Redis队列监控
redis-cli info replication
redis-cli llen task_queue
```

### 性能优化
1. **数据库连接池**: 已配置异步连接池，支持并发请求
2. **任务队列**: 使用Redis队列避免锁竞争
3. **文件存储**: 音频文件存储在本地，通过静态文件服务提供访问
4. **缓存策略**: 可选Redis缓存，提升响应速度
5. **Redis优化**: 配置合适的内存策略和持久化策略
6. **负载均衡**: 支持多worker实例分布式处理
7. **网络优化**: 启用压缩传输和连接复用

## 故障排除

### 常见问题

1. **模型加载失败**
   - 检查MODEL_DIR路径是否正确
   - 确认模型文件完整性
   - 检查GPU内存是否足够
   - 查看模型加载日志

2. **数据库连接失败**
   - 检查MySQL服务状态：`sudo systemctl status mysql`
   - 验证连接参数：用户名、密码、主机、端口
   - 测试连接：`mysql -h主机 -P端口 -u用户名 -p`
   - 确认防火墙设置

3. **Redis连接失败**
   - 检查Redis服务状态：`sudo systemctl status redis`
   - 测试Redis连接：`redis-cli -h主机 -p端口 ping`
   - 检查Redis配置文件：`/etc/redis/redis.conf`
   - 验证Redis内存使用：`redis-cli info memory`

4. **任务处理缓慢**
   - 增加worker进程数量
   - 优化数据库索引
   - 检查系统资源使用情况
   - 监控Redis队列长度
   - 检查网络延迟

5. **任务队列堆积**
   - 检查处理器状态
   - 增加处理器数量
   - 优化任务优先级
   - 清理过期任务

6. **音频文件访问失败**
   - 检查audio_output目录权限
   - 确认静态文件服务配置
   - 验证文件路径映射

### 调试模式
```bash
# 启用调试日志
export LOG_LEVEL=DEBUG

# 查看详细错误信息
tail -f logs/api_server.log
tail -f logs/worker_long.log
```

## 扩展和定制

### 添加新音色
1. 在数据库中添加音色配置
2. 更新TTS模型支持的音色列表
3. 重启服务使配置生效

### 自定义回调处理
```python
# 在task_worker.py中自定义回调逻辑
async def send_callback(self, callback_url: str, task_data: dict):
    # 自定义回调处理逻辑
    pass
```

### 添加认证
```python
# 在enhanced_api_server.py中添加API密钥验证
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer

security = HTTPBearer()

async def verify_api_key(token: str = Depends(security)):
    if token.credentials != config.API_KEY:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key"
        )
    return token
```
