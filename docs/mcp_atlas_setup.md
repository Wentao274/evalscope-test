# MCP-Atlas 任务环境准备指南

## 概述

MCP-Atlas 是 Scale AI 发布的 MCP 工具使用能力评测基准,包含 89 个任务。与常规评测不同,它需要一个外部 **agent-environment** Docker 服务来承载真实 MCP servers(brave-search、wikipedia、github、mongodb 等),被测模型通过 EvalScope AgentLoop 驱动 function-calling 调用这些 MCP 工具完成任务,最后由裁判模型逐 claim 评判覆盖率。

本文档描述从零搭建 MCP-Atlas 评测环境的完整步骤。

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│  EvalScope Pipeline (runner: 10.201.132.50)                  │
│                                                              │
│  ┌──────────────┐   ┌──────────────────┐   ┌──────────────┐  │
│  │ 被测模型端点  │   │ MCP-Atlas Adapter │   │ 裁判模型端点  │  │
│  │ (OpenAI API) │   │ (AgentLoop)       │   │ (OpenAI API) │  │
│  └──────┬───────┘   └────────┬─────────┘   └──────────────┘  │
│         │                    │                               │
│         │            HTTP (localhost:1984)                    │
│         │                    ▼                               │
│  ┌──────┴───────────────────────────────────┐                │
│  │ MCP-Atlas agent-environment (Docker)      │                │
│  │  GET  /enabled-servers                    │                │
│  │  POST /list-tools                         │                │
│  │  POST /call-tool                          │                │
│  │                                           │                │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────────┐  │                │
│  │  │ MCP svr │ │ MCP svr │ │ MCP svr ... │  │                │
│  │  │wikipedia│ │ github  │ │ brave-search│  │                │
│  │  └─────────┘ └─────────┘ └─────────────┘  │                │
│  └───────────────────────────────────────────┘                │
│                                                               │
│  ┌───────────────────────────────────────────┐                │
│  │ Dataset: ScaleAI/MCP-Atlas (ModelScope)   │                │
│  │ 89 tasks, auto-download on first run      │                │
│  └───────────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

## 前置条件

| 条件 | 要求 |
|------|------|
| 操作系统 | Ubuntu 22.04+(runner 已满足) |
| Docker | 已安装且 daemon 运行(`docker info` 成功),Docker 内存分配 >= 8GB(10GB 推荐) |
| Python | >= 3.10(EvalScope 基线要求) |
| 网络代理 | 需访问 ModelScope(下载数据集)+ ghcr.io(拉取 Docker 镜像) |
| 被测模型 | OpenAI 兼容端点可达 |
| 裁判模型 | OpenAI 兼容端点可达,能稳定输出 JSON |

## 部署方式

MCP-Atlas agent-environment 支持两种部署方式:

| 方式 | 适用场景 |
|------|----------|
| **Jenkins 自动部署** | 推荐。设置 `MCP_ATLAS_AUTO_DEPLOY=true`,Jenkins 自动拉取镜像并启动容器 |
| **手动部署** | 需要自定义镜像或特殊配置时,手动 `docker pull` + `docker run` |

## 方式 A:Jenkins 自动部署(推荐)

### Jenkins 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `TASK_MCP_ATLAS` | `true` | 启用 mcp_atlas 任务 |
| `MCP_ATLAS_AUTO_DEPLOY` | `true` | 服务未运行时自动拉取镜像并启动容器 |
| `MCP_ATLAS_IMAGE` | `ghcr.io/scaleapi/mcp-atlas:1.2.7` | Scale AI 官方预构建 Docker 镜像 |
| `MCP_ATLAS_API_KEYS` | 空 | 可选:MCP server API keys,逗号分隔 KEY=VALUE 对。留空仅启用 20 个无需 key 的 server |

### 自动部署流程

Jenkins 环境检查阶段执行:

```
1. curl localhost:1984/enabled-servers → 检查服务是否已运行
   ├─ HTTP 200 → 跳过部署,直接使用
   └─ 非 200 → 进入自动部署
2. docker pull ghcr.io/scaleapi/mcp-atlas:1.2.7 (通过代理)
3. 清理旧容器(端口 1984 冲突时)
4. docker run -d -p 1984:1984 [API keys env] ghcr.io/scaleapi/mcp-atlas:1.2.7
5. 轮询等待服务就绪(最长 180 秒,每 5 秒检查一次)
6. 输出已启用的 MCP server 列表
```

### 启用更多 MCP server

在 `MCP_ATLAS_API_KEYS` 参数中填入 API key:

```
BRAVE_API_KEY=your_key,GITHUB_TOKEN=your_token,MONGODB_URI=mongodb://...
```

注入后这些 server 会在容器启动时自动启用,对应任务也会被纳入评测。

## 方式 B:手动部署

### B.1 获取 agent-environment

Scale AI 官方提供了预构建 Docker 镜像,无需 clone 仓库:

```bash
# 拉取官方预构建镜像(推荐,约 3-5 GB)
docker pull ghcr.io/scaleapi/mcp-atlas:1.2.7
```

### B.2 配置外部 MCP server API 密钥(可选)

agent-environment 通过 MCP 协议连接多个外部服务。每个 MCP server 需要对应的 API 密钥/配置:

| MCP Server | 需要的密钥/配置 | 说明 |
|------------|-----------------|------|
| `brave-search` | `BRAVE_API_KEY` | Brave Search API key,从 https://brave.com/search/api/ 获取 |
| `github` | `GITHUB_TOKEN` | GitHub Personal Access Token,从 https://github.com/settings/tokens 获取 |
| `wikipedia` | 无需密钥 | 免费 API,开箱即用 |
| `fetch` | 无需密钥 | 通用 HTTP fetch 工具 |
| `filesystem` | 无需密钥 | 本地文件系统访问 |
| `git` | 无需密钥 | Git 操作工具 |
| `mongodb` | `MONGODB_URI` | MongoDB 连接字符串 |
| `open-library` | 无需密钥 | Open Library 免费 API |
| `cli-mcp-server` | 无需密钥 | CLI 命令执行工具 |

在 agent-environment 的配置文件(通常是 `.env` 或 `docker-compose.yml` 的 `environment` 段)中设置这些密钥:

```bash
# .env 示例
BRAVE_API_KEY=your_brave_api_key_here
GITHUB_TOKEN=your_github_token_here
MONGODB_URI=mongodb://user:pass@host:port/dbname
```

### B.3 启动 agent-environment Docker 服务

```bash
# 方式 1:直接 docker run(最简单)
docker run -d \
    --name mcp-atlas-agent-env \
    -p 1984:1984 \
    --restart unless-stopped \
    ghcr.io/scaleapi/mcp-atlas:1.2.7

# 方式 2:带 API key 启动(启用更多 MCP server)
docker run -d \
    --name mcp-atlas-agent-env \
    -p 1984:1984 \
    --env BRAVE_API_KEY=your_key \
    --env GITHUB_TOKEN=your_token \
    --restart unless-stopped \
    ghcr.io/scaleapi/mcp-atlas:1.2.7

# 方式 3:从源码构建(仅在修改 server 配置时需要)
git clone https://github.com/scaleapi/mcp-atlas.git
cd mcp-atlas
make build && make run-docker
```

### B.4 验证服务

启动后验证服务是否正常:

```bash
# 检查端口 1984 是否监听
curl -s http://localhost:1984/enabled-servers | python3 -m json.tool
```

期望返回类似:
```json
{
  "servers": {
    "wikipedia": "OK",
    "github": "OK",
    "brave-search": "OK",
    "fetch": "OK",
    "filesystem": "OK",
    "git": "OK"
  }
}
```

状态为 `"OK"` 的 server 表示可用,其他状态(如 `"ERROR_NOT_ONLINE"`)表示该 server 未正确配置。

### B.5 验证三个 HTTP 端点

agent-environment 必须暴露以下三个端点:

```bash
# 1. GET /enabled-servers — 返回已启用的 MCP server 列表
curl -s http://localhost:1984/enabled-servers

# 2. POST /list-tools — 返回所有可用工具的 JSON 数组
curl -s -X POST http://localhost:1984/list-tools \
  -H "Content-Type: application/json" | python3 -m json.tool

# 3. POST /call-tool — 调用指定工具(需提供工具名和参数)
curl -s -X POST http://localhost:1984/call-tool \
  -H "Content-Type: application/json" \
  -d '{"tool_name": "wikipedia_get_article", "tool_args": {"title": "MCP"}}'
```

### B.6 确认启用的 server 数量

MCP-Atlas 共 89 个任务,每个任务依赖不同的 MCP server 组合。启用的 server 越多,可评测的任务越多:

```bash
# 统计 OK 状态的 server 数量
curl -s http://localhost:1984/enabled-servers | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print('Enabled:', [k for k,v in d['servers'].items() if v=='OK'])"
```

EvalScope 默认 `filter_enabled_servers=True`,会自动跳过依赖未启用 server 的任务。因此:
- 6 个 server 启用 → 约 30-50 个任务可评测
- 全部 server 启用 → 全部 89 个任务可评测

## 步骤 2:安装 EvalScope 依赖

```bash
# 进入 EvalScope 工作目录
cd /dingofs/data2/userdata/liwt/maas-image/evalscope-test

# 激活虚拟环境
source .venv/bin/activate

# 基础安装(已完成则跳过)
pip install -e .

# MCP-Atlas 无独立 extra 依赖
# adapter 仅使用 requests(已在 framework.txt 中)
```

确认 `requests` 已安装:
```bash
python3 -c "import requests; print('requests', requests.__version__)"
```

## 步骤 3:配置裁判模型

MCP-Atlas **强制要求** LLM judge 评分,不支持 rule 策略。`match_score()` 会在 rule 模式下直接抛 `ValueError`。

### 3.1 裁判模型要求

| 要求 | 说明 |
|------|------|
| 协议 | OpenAI 兼容 chat/completions 端点 |
| 能力 | 能稳定输出 JSON 格式的结构化响应 |
| 推荐 | 指令跟随能力强的模型,如 Qwen3-235B、DeepSeek-V4 等 |
| temperature | 建议 0.0(评分稳定性) |
| max_tokens | 建议 4096+ |

### 3.2 裁判模型评分流程

裁判模型对每个任务的多条 claim 逐一评判,每条 claim 调用一次 judge:

```json
// 裁判模型收到的 prompt 示例
Judge whether the following claim is fulfilled by the model's response...
Claim: <claim text>
Response: <model output>

// 期望返回的 JSON
{
  "claim_text": "...",
  "coverage_outcome": "fulfilled|partially_fulfilled|not_fulfilled",
  "justification": "...",
  "confidence_level": "high|medium|low"
}
```

评分映射:`fulfilled` = 1.0,`partially_fulfilled` = 0.5,`not_fulfilled` = 0.0。
最终指标:`coverage_score` = 所有 claim 得分的均值,`pass_rate` = coverage_score >= 0.75 的比例。

### 3.3 Jenkins 参数配置

在 Jenkins 构建页面填写:

| 参数 | 值 | 说明 |
|------|-----|------|
| `JUDGE_MODEL_ID` | `deepseek-v4-flash` | 裁判模型名称 |
| `JUDGE_API_URL` | `http://10.201.149.41:8080/v1` | 裁判模型端点(含 /v1) |
| `JUDGE_API_KEY` | `EMPTY` | 裁判模型 API Key |
| `JUDGE_STRATEGY` | `auto` | 评分策略(auto 会自动启用 LLM judge) |

## 步骤 4:配置被测模型

| Jenkins 参数 | 值 | 说明 |
|--------------|-----|------|
| `MODEL` | `glm-5.2` | 被测模型名称 |
| `BASE_URL` | `http://10.201.149.90/.../v1` | 被测模型端点 |
| `API_KEY` | `EMPTY` | 被测模型 API Key |
| `TASK_MCP_ATLAS` | `true` | 启用 MCP-Atlas 任务 |
| `EXAMPLES` | `5` | 样本数限制(调试用,正式评测留空) |

## 步骤 5:配置 MCP-Atlas 专属参数(可选)

以下参数通过 `DATASET_ARGS` JSON 或 adapter `extra_params` 配置。Jenkins 的 `DATASET_ARGS` 参数示例:

```json
{
  "mcp_atlas": {
    "extra_params": {
      "mcp_server_url": "http://localhost:1984",
      "filter_enabled_servers": true,
      "max_tool_calls": 100,
      "request_timeout": 60.0,
      "list_tools_timeout": 180.0,
      "use_system_prompt": false,
      "pass_threshold": 0.75
    }
  }
}
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `mcp_server_url` | str | `http://localhost:1984` | agent-environment 服务地址 |
| `filter_enabled_servers` | bool | `true` | 跳过依赖未启用 server 的任务 |
| `max_tool_calls` | int | `100` | 每个任务最大工具调用次数 |
| `request_timeout` | float | `60.0` | 单次工具调用 HTTP 超时(秒) |
| `list_tools_timeout` | float | `180.0` | preflight 查询超时(秒) |
| `use_system_prompt` | bool | `false` | 是否注入 MCP-Atlas 默认 system prompt |
| `pass_threshold` | float | `0.75` | pass_rate 计算阈值 |

> 注意:Jenkins 的 `DATASET_ARGS` 参数留空时,evalscope_main.sh 不会注入 `--dataset-args`,adapter 使用 `metadata.py` 中的默认值。仅在需要覆盖默认值时填写 `DATASET_ARGS`。

## 步骤 6:运行测试

### 6.1 Jenkins 流水线运行

在 Jenkins 构建页面配置:
- `TASK_MCP_ATLAS` = `true`
- `EXAMPLES` = `5`(先用少量样本验证环境,成功后清空跑全集)
- 其他参数按步骤 3、4 配置

点击 Build Now 启动流水线。

### 6.2 本地验证(命令行)

```bash
# 激活虚拟环境
source /dingofs/data2/userdata/liwt/maas-image/evalscope-test/.venv/bin/activate

# 最小验证:limit=1,确认环境可用
evalscope eval \
    --model glm-5.2 \
    --api-url http://10.201.149.90/sp-vllm-pd-dfkv-glm52int4-3eecd3f5/v1 \
    --api-key EMPTY \
    --datasets mcp_atlas \
    --limit 1 \
    --judge-strategy auto \
    --judge-model-args '{"model_id":"deepseek-v4-flash","api_url":"http://10.201.149.41:8080/v1","api_key":"EMPTY"}' \
    --agent-config '{"mode":"native","strategy":"function_calling","max_steps":100}'
```

成功时输出:
```
Running[eval]: 100%|██████████| 1/1 [00:XX<00:00]
coverage_score: X.XX
pass_rate: X.XX
```

### 6.3 本地验证(Python API)

```python
from evalscope import run_task, TaskConfig

run_task(TaskConfig(
    model='glm-5.2',
    api_url='http://10.201.149.90/sp-vllm-pd-dfkv-glm52int4-3eecd3f5/v1',
    api_key='EMPTY',
    datasets=['mcp_atlas'],
    limit=1,
    judge_strategy='auto',
    judge_model_args={
        'model_id': 'deepseek-v4-flash',
        'api_url': 'http://10.201.149.41:8080/v1',
        'api_key': 'EMPTY',
    },
    agent_config={
        'mode': 'native',
        'strategy': 'function_calling',
        'max_steps': 100,
    },
))
```

## 常见问题排查

### Q1: `ConnectionRefusedError: [Errno 111] Connection refused`

```
RuntimeError: MCP-Atlas agent-environment is not available.
Start the MCP-Atlas Docker service so http://localhost:1984/enabled-servers
and /list-tools are reachable.
```

**原因**:agent-environment Docker 服务未启动。

**解决**:
```bash
# 检查端口 1984
ss -tlnp | grep 1984

# 如果无输出,启动服务
cd /path/to/mcp-atlas && docker-compose up -d

# 再次验证
curl http://localhost:1984/enabled-servers
```

### Q2: 部分任务被跳过

```
Skipping MCP-Atlas task <task_id> because required servers are not enabled: ['brave-search', 'mongodb']
```

**原因**:`filter_enabled_servers=True`(默认),部分 MCP server 未配置 API 密钥,依赖这些 server 的任务被自动跳过。

**解决**:
- 在 agent-environment 中配置缺失的 API 密钥(brave-search、mongodb 等)
- 或设置 `filter_enabled_servers=False` 跳过过滤(但模型调用未配置的 server 工具会失败)

### Q3: 裁判模型评分失败

```
ValueError: MCP-Atlas requires LLM judge scoring; set judge_strategy to auto/llm with judge_model_args.
```

**原因**:`judge_strategy` 设置为 `rule`,或未配置 `judge_model_args`。

**解决**:
- 确保 `JUDGE_STRATEGY` = `auto`(不是 `rule`)
- 确保 `JUDGE_MODEL_ID`、`JUDGE_API_URL`、`JUDGE_API_KEY` 已填写
- 确认裁判模型端点可达且能输出 JSON

### Q4: 裁判模型返回非 JSON

```
WARNING: Failed to parse claim judge response as JSON, falling back to keyword scan
```

**原因**:裁判模型未能稳定输出 JSON 格式,`parse_claim_judge_response` 回退到关键词匹配,评分精度下降。

**解决**:
- 使用指令跟随能力更强的裁判模型
- 确认裁判模型 `temperature=0.0`
- 确认裁判模型 `max_tokens` 足够(建议 4096+)

### Q5: 数据集下载失败

```
FileNotFoundError: ScaleAI/MCP-Atlas
```

**原因**:ModelScope Hub 不可达或网络代理未配置。

**解决**:
```bash
# 配置代理(如需要)
export https_proxy=http://100.64.1.68:1080
export http_proxy=http://100.64.1.68:1080

# 手动下载
python3 -c "from modelscope import dataset_snapshot_download; dataset_snapshot_download('ScaleAI/MCP-Atlas', cache_dir='~/.cache/modelscope/hub/datasets')"
```

或使用本地 CSV:
```json
// DATASET_ARGS 参数
{"mcp_atlas": {"local_path": "/path/to/mcp_atlas.csv"}}
```

本地 CSV 格式:
```
TASK,PROMPT,ENABLED_TOOLS,TRAJECTORY,GTFA_CLAIMS
task-001,"What is...","wikipedia_get_article,github_search_repositories","[{\"tool_calls\":[...]}]","claim1,claim2"
```

### Q6: 工具调用超时

```
requests.exceptions.Timeout: HTTPConnectionPool... /call-tool (Read timeout=60)
```

**原因**:某个 MCP server 响应慢(如 brave-search 搜索大量结果)。

**解决**:
- 增大 `request_timeout`(如 120.0)via `DATASET_ARGS`
- 检查对应 MCP server 的网络连通性
- 该 server 后续调用会自动短路(`MCPAtlasServerUnavailable`),不影响其他 server

## 检查清单

运行 MCP-Atlas 任务前,逐项确认:

- [ ] agent-environment Docker 服务已启动,`curl http://localhost:1984/enabled-servers` 返回 200
- [ ] `GET /enabled-servers` 返回至少 1 个 `OK` 状态的 server
- [ ] `POST /list-tools` 返回工具列表(JSON 数组,每项含 `name`、`description`、`inputSchema`)
- [ ] `POST /call-tool` 能成功调用(用 wikipedia 等无需密钥的 server 测试)
- [ ] 被测模型端点可达(`curl http://<base_url>/v1/models` 返回 200)
- [ ] 裁判模型端点可达且能输出 JSON
- [ ] `TASK_MCP_ATLAS` = `true`
- [ ] `JUDGE_MODEL_ID`、`JUDGE_API_URL`、`JUDGE_API_KEY` 已填写
- [ ] `JUDGE_STRATEGY` = `auto`(非 `rule`)
- [ ] ModelScope Hub 可达(首次运行需下载数据集)
