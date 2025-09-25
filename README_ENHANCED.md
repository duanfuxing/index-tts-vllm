中文 ｜ <a href="README_EN.md">English</a>

<div align="center">

# IndexTTS-vLLM
</div>

Working on IndexTTS2 support, coming soon... 0.0

## 项目简介
该项目在 [index-tts](https://github.com/index-tts/index-tts) 的基础上使用 vllm 库重新实现了 gpt 模型的推理，加速了 index-tts 的推理过程。

推理速度在单卡 RTX 4090 上的提升为：
- 单个请求的 RTF (Real-Time Factor)：≈0.3 -> ≈0.1
- 单个请求的 gpt 模型 decode 速度：≈90 token / s -> ≈280 token / s
- 并发量：gpu_memory_utilization设置为0.5（约12GB显存）的情况下，vllm 显示 `Maximum concurrency for 608 tokens per request: 237.18x`，两百多并发，man！当然考虑 TTFT 以及其他推理成本（bigvgan 等），实测 16 左右的并发无压力（测速脚本参考 `simple_test.py`）

## 功能特性

### 🎯 核心功能
- **基础TTS合成**: 支持WebUI和API调用
- **多角色音频混合**: 可以传入多个参考音频，TTS 输出的角色声线为多个参考音频的混合版本
- **在线TTS合成**: 限制300字，直接返回音频和字幕文件
- **长文本TTS**: 限制5万字，提供任务提交和查询API
- **OpenAI兼容接口**: 支持 /audio/speech 和 /audio/voices API
- **Docker一键部署**: 支持 `docker compose up` 全自动化部署

### 🚀 技术特性
- vLLM加速推理，大幅提升并发性能
- FastAPI框架，自动生成API文档
- MySQL数据库可靠存储
- Redis队列系统避免多worker重复处理
- 异步数据库连接池
- 任务状态实时跟踪
- SRT字幕文件生成
- 完整的错误处理和重试机制

## 性能对比
Word Error Rate (WER) Results for IndexTTS and Baseline Models on the [**seed-test**](https://github.com/BytedanceSpeech/seed-tts-eval)

| model                   | zh    | en    |
| ----------------------- | ----- | ----- |
| Human                   | 1.254 | 2.143 |
| index-tts (num_beams=3) | 1.005 | 1.943 |
| index-tts (num_beams=1) | 1.107 | 2.032 |
| index-tts-vllm      | 1.12  | 1.987 |

基本保持了原项目的性能

## 更新日志

- **[2025-08-07]** 支持 Docker 全自动化一键部署 API 服务：`docker compose up`
- **[2025-08-06]** 支持 openai 接口格式调用：
    1. 添加 /audio/speech api 路径，兼容 OpenAI 接口
    2. 添加 /audio/voices api 路径， 获得 voice/character 列表
    - 对应：[createSpeech](https://platform.openai.com/docs/api-reference/audio/createSpeech)

## 快速开始

### 方式一：Docker 一键部署（推荐）

```bash
# 克隆项目
git clone https://github.com/Ksuriuri/index-tts-vllm.git
cd index-tts-vllm

# 一键启动所有服务
docker compose up
```

### 方式二：手动部署

#### 1. 克隆项目
```bash
git clone https://github.com/Ksuriuri/index-tts-vllm.git
cd index-tts-vllm
```

#### 2. 优化缓存配置（可选，适用于云服务器）
```bash
# 设置 pip 缓存到数据盘
mkdir -p /root/autodl-tmp/pip_cache
pip config set global.cache-dir /root/autodl-tmp/pip_cache

# 设置 conda 缓存到数据盘
conda config --add pkgs_dirs /root/autodl-tmp/conda_cache
```

#### 3. 创建并激活 conda 环境
```bash
# 标准方式
conda create -n index-tts-vllm python=3.12
conda activate index-tts-vllm

# 或者指定路径（适用于数据盘）
conda create --prefix conda_envs/index-tts-vllm python=3.12
conda activate conda_envs/index-tts-vllm
```

#### 4. 安装 PyTorch
```bash
# 优先建议安装 pytorch 2.7.0（对应 vllm 0.9.0）
# 具体安装指令请参考：https://pytorch.org/get-started/locally/

# CUDA 12.1 版本示例
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# 若显卡不支持，请安装 pytorch 2.5.1（对应 vllm 0.7.3）
# 并将 requirements.txt 中 vllm==0.9.0 修改为 vllm==0.7.3
```

#### 5. 安装依赖
```bash
# 使用清华源加速安装
pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple/

# 安装特定版本的 transformers（如果需要）
pip install transformers==4.51.1
```

#### 6. 下载模型权重

此为官方权重文件，下载到本地任意路径即可，支持 IndexTTS-1.5 的权重

| **HuggingFace**                                          | **ModelScope** |
|----------------------------------------------------------|----------------------------------------------------------|
| [IndexTTS](https://huggingface.co/IndexTeam/Index-TTS) | [IndexTTS](https://modelscope.cn/models/IndexTeam/Index-TTS) |
| [😁IndexTTS-1.5](https://huggingface.co/IndexTeam/IndexTTS-1.5) | [IndexTTS-1.5](https://modelscope.cn/models/IndexTeam/IndexTTS-1.5) |

#### 7. 模型权重转换

```bash
bash convert_hf_format.sh /path/to/your/model_dir
```

此操作会将官方的模型权重转换为 transformers 库兼容的版本，保存在模型权重路径下的 `vllm` 文件夹中，方便后续 vllm 库加载模型权重

#### 8. 启动服务

##### WebUI 启动
将 [`webui.py`](webui.py) 中的 `model_dir` 修改为模型权重下载路径，然后运行：

```bash
VLLM_USE_V1=0 python webui.py
```

##### API 服务启动
```bash
VLLM_USE_V1=0 python api_server.py --model_dir /your/path/to/Index-TTS --port 11996
```

**注意**：一定要带上 `VLLM_USE_V1=0`，因为本项目没有对 vllm 的 v1 版本做兼容

第一次启动可能会久一些，因为要对 bigvgan 进行 cuda 核编译

## 增强型 API 服务部署

### 环境配置

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

### 数据库准备

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

### 启动增强型服务

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

### 验证部署

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

## 基础 API 使用

### 启动参数
- `--model_dir`: 模型权重下载路径
- `--host`: 服务ip地址
- `--port`: 服务端口
- `--gpu_memory_utilization`: vllm 显存占用率，默认设置为 `0.25`

### 基础请求示例
```python
import requests

url = "http://0.0.0.0:11996/tts_url"
data = {
    "text": "还是会想你，还是想登你",
    "audio_paths": [  # 支持多参考音频
        "audio1.wav",
        "audio2.wav"
    ]
}

response = requests.post(url, json=data)
with open("output.wav", "wb") as f:
    f.write(response.content)
```

### OpenAI 兼容接口
- 添加 /audio/speech api 路径，兼容 OpenAI 接口
- 添加 /audio/voices api 路径， 获得 voice/character 列表

详见：[createSpeech](https://platform.openai.com/docs/api-reference/audio/createSpeech)

### 并发测试
参考 [`simple_test.py`](simple_test.py)，需先启动 API 服务

## 增强型 API 文档

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
