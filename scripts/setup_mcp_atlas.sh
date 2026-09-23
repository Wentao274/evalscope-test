#!/bin/bash
set -e

# Setup MCP-Atlas agent-environment: check running service, auto-deploy if needed.
#
# Env vars (must be set by caller):
#   WORK_DIR, BUILD_NUMBER, TASK_MCP_ATLAS, MCP_ATLAS_AUTO_DEPLOY,
#   MCP_ATLAS_IMAGE, MCP_ATLAS_API_KEYS

echo "=== 检查 MCP-Atlas agent-environment 服务 ==="
if [ "${TASK_MCP_ATLAS}" = "true" ]; then
    echo "TASK_MCP_ATLAS=true,检查 MCP-Atlas agent-environment 服务..."
    CONT_NAME="mcp-atlas-agent-env-${BUILD_NUMBER}"

    # 先检查服务是否已在运行(检查端口,而非容器名,因为容器名每次构建不同)
    # 仅 HTTP 200 不够:旧容器可能因 uvx Python 版本问题导致部分 server offline,
    # 仍在 1984 响应但可用 server 不足。同时校验 online server 数量。
    HTTP_CODE=$(curl -s --noproxy localhost --connect-timeout 5 -o /dev/null -w "%{http_code}" http://localhost:1984/enabled-servers 2>/dev/null) || true
    ONLINE_COUNT=0
    if [ "${HTTP_CODE}" = "200" ]; then
        ONLINE_COUNT=$(curl -s --noproxy localhost http://localhost:1984/enabled-servers 2>/dev/null | \
            python3 -c "import sys,json; d=json.load(sys.stdin); s=d.get('servers',d); print(sum(1 for v in (s.values() if isinstance(s,dict) else [x[1] for x in s if isinstance(x,list)]) if v=='OK'))" 2>/dev/null || echo 0)
    fi
    # 期望至少 15 个 online(镜像预装 20 个无需 key 的 server,容忍 5 个偶发失败:
    # npm servers 如 context7 可能因代理 TLS 问题 ECONNRESET,部分 uvx servers 可能因
    # 依赖解析或网络瞬断离线,不影响 eval 核心功能)
    if [ "${HTTP_CODE}" = "200" ] && [ "${ONLINE_COUNT}" -ge 15 ]; then
        echo "MCP-Atlas agent-environment 服务已运行(HTTP 200, ${ONLINE_COUNT} servers online),预检通过"
        # 输出已启用的 server 列表
        echo "已启用的 MCP servers:"
        curl -s --noproxy localhost http://localhost:1984/enabled-servers | python3 -m json.tool 2>/dev/null || echo "(解析失败,但服务可用)"
    elif [ "${MCP_ATLAS_AUTO_DEPLOY}" = "true" ]; then
        if [ "${HTTP_CODE}" = "200" ]; then
            echo "MCP-Atlas agent-environment 服务在运行但仅 ${ONLINE_COUNT} servers online(< 15),部分 server 可能因网络/代理问题离线,重新部署..."
        else
            echo "MCP-Atlas agent-environment 服务未运行(HTTP ${HTTP_CODE}),开始自动部署..."
        fi
        echo "镜像: ${MCP_ATLAS_IMAGE}"

        # 检查 Docker
        if ! docker info >/dev/null 2>&1; then
            echo "ERROR: Docker daemon 不可用,无法自动部署 MCP-Atlas agent-environment。"
            echo "请确认 Docker 已安装且 daemon 运行,或设置 MCP_ATLAS_AUTO_DEPLOY=false 手动准备。"
            exit 1
        fi

        # 清理所有旧的 MCP-Atlas 容器(按名称前缀匹配,覆盖所有历史构建)
        echo "清理旧的 MCP-Atlas 容器(前缀 mcp-atlas-agent-env*)..."
        OLD_CONTAINERS=$(docker ps -a --filter "name=mcp-atlas-agent-env" --format "{{.ID}} {{.Names}}" 2>/dev/null || echo "")
        if [ -n "${OLD_CONTAINERS}" ]; then
            echo "发现旧容器:"
            echo "${OLD_CONTAINERS}"
            OLD_IDS=$(echo "${OLD_CONTAINERS}" | awk '{print $1}')
            docker rm -f ${OLD_IDS} 2>/dev/null || true
            echo "旧容器已清理"
        else
            # 兜底:按端口匹配(可能有不同名称的旧容器占用 1984)
            OLD_IDS=$(docker ps -a --filter "publish=1984" --format "{{.ID}}" 2>/dev/null || echo "")
            if [ -n "${OLD_IDS}" ]; then
                echo "清理占用端口 1984 的旧容器: ${OLD_IDS}"
                docker rm -f ${OLD_IDS} 2>/dev/null || true
            else
                echo "无旧容器需要清理"
            fi
        fi

        # 拉取镜像:优先复用本地镜像,避免每次构建都强连外网校验 digest
        if docker image inspect ${MCP_ATLAS_IMAGE} >/dev/null 2>&1; then
            echo "本地已有镜像 ${MCP_ATLAS_IMAGE},跳过 pull"
            echo "镜像 ID: $(docker image inspect ${MCP_ATLAS_IMAGE} --format '{{.Id}}' 2>/dev/null)"
        else
            echo "本地无镜像,准备拉取 ${MCP_ATLAS_IMAGE}(可能需要几分钟)..."
            # 注意:Docker CLI 的 export http_proxy/https_proxy 不会传给 daemon,
            # daemon 拉镜像用的是自身进程环境;Jenkins 本身跑在容器内,
            # 不能在此重启 docker 服务(会停掉 Jenkins 容器)。
            # 新机器需事先手动配置 docker daemon 代理,或人工 docker load 镜像。
            if ! docker pull ${MCP_ATLAS_IMAGE} 2>&1; then
                echo "ERROR: 拉取 MCP-Atlas 镜像失败。"
                echo "请手动拉取: docker pull ${MCP_ATLAS_IMAGE}"
                echo "或在新机器上手动配置 docker daemon 代理(systemd drop-in / /etc/docker/daemon.json)"
                echo "或用 docker save/load 离线导入镜像。"
                exit 1
            fi
        fi

        # 构建 docker run 的环境变量参数
        DOCKER_ENV_ARGS=""
        if [ -n "${MCP_ATLAS_API_KEYS}" ]; then
            # 解析逗号分隔的 KEY=VALUE 对,生成 --env 参数
            IFS=',' read -ra KEY_PAIRS <<< "${MCP_ATLAS_API_KEYS}"
            for pair in "${KEY_PAIRS[@]}"; do
                pair=$(echo "$pair" | xargs)  # trim whitespace
                if [ -n "$pair" ]; then
                    DOCKER_ENV_ARGS="${DOCKER_ENV_ARGS} --env $pair"
                fi
            done
            echo "注入 MCP server API keys: $(echo ${DOCKER_ENV_ARGS} | tr ' ' '\n' | grep -- '--env' | wc -l) 个"
        fi

        # 启动容器(限制重启次数避免无限 crash-loop 掩盖错误)
        # 核心问题:mcp/client/stdio/__init__.py 的 get_default_environment() 在 Linux 下只继承
        #   ["HOME","LOGNAME","PATH","SHELL","TERM","USER"] 6 个变量,所有 UV_* 和 PROXY 变量
        #   都不会传给 fastmcp spawn 的 uvx/npx 子进程。导致:
        #   1) uvx 没有 UV_OFFLINE → 尝试访问 pypi.org → 代理/网络超时
        #   2) uvx 没有 UV_PYTHON → 选 3.13 → numpy cp313 wheel 缺失
        # 修复:挂载自定义 entrypoint wrapper,在原 entrypoint 生成 mcp_server_config.json 后,
        #   用 python 脚本给每个 server 的 env 注入 UV_* 和 PROXY 变量,再 exec 原 CMD。
        # UV_NO_SYNC=1: 预构建镜像已含全部依赖,跳过 uv run 的项目级 re-sync
        # UV_OFFLINE=1: 强制 uvx 使用预装缓存(install_mcp_packages.sh 已在镜像构建时装好),不尝试访问 pypi.org
        # UV_PYTHON=3.12: 镜像预装依赖(MCP server uv tool 环境)均基于 cpython-3.12.12 构建;镜像内另含
        #   cpython-3.13.12,uvx 默认会选最新版 Python 重新解析依赖,导致 numpy 等 cp313 wheel 缺失 →
        #   退回访问 pypi.org → 离线/代理下超时,服务无法在 180s 内就绪。锁定 3.12 让 uvx 命中预装缓存。
        # npm_config_offline=true: 容器级 npx 离线(但 NOT 注入到 server env — npm servers
        #   如 clinicaltrialsgov/context7 需通过代理访问 npm registry,cache-only 会 ENOTCACHED)
        # HTTPS_PROXY/HTTP_PROXY: MCP server 运行时访问外部 API(wikipedia/arxiv 等)用
        # NO_PROXY: 内网地址(10.0.0.0/8)及 host.docker.internal(宿主机 MongoDB)不走代理
        # --add-host host.docker.internal:host-gateway: 让容器能通过 host.docker.internal 访问宿主机服务(如 MongoDB)
        # curl --noproxy localhost: runner 宿主机有 HTTP_PROXY 环境变量,不加 --noproxy 会导致
        #   curl http://localhost:1984/... 走代理返回 502 Bad Gateway

        # 创建自定义 entrypoint wrapper 脚本(在宿主机临时文件,挂载进容器)
        ENTRYPOINT_WRAPPER=$(mktemp /tmp/mcp-entrypoint-XXXXXX.sh)
        cat > "${ENTRYPOINT_WRAPPER}" << 'ENTRYPOINT_EOF'
#!/bin/bash
# 1. 执行原 entrypoint 的 envsubst(生成 mcp_server_config.json)
envsubst < /agent-environment/src/agent_environment/mcp_server_template.json > /agent-environment/src/agent_environment/mcp_server_config.json

# 2. 给每个 server 的 env 注入 UV_* 和 PROXY 变量(fastmcp stdio subprocess 只继承 6 个基础变量)
#    注意:不注入 npm_config_offline — npm servers (clinicaltrialsgov,context7) 需通过代理
#    访问 npm registry 下载包,cache-only 模式会因缓存为空而失败 (ENOTCACHED)。
python3 -c "
import json, os
path = '/agent-environment/src/agent_environment/mcp_server_config.json'
with open(path) as f:
    config = json.load(f)
inject = {k: v for k, v in os.environ.items()
          if k.startswith('UV_')
          or k in ('HTTP_PROXY','HTTPS_PROXY','NO_PROXY','http_proxy','https_proxy','no_proxy')}
for name, server in config.get('mcpServers', {}).items():
    env = server.get('env')
    if env is None:
        env = {}
    elif isinstance(env, list):
        env = env[0] if env else {}
    if not isinstance(env, dict):
        env = {}
    env.update(inject)
    server['env'] = env
with open(path, 'w') as f:
    json.dump(config, f, indent=2)
print(f'Injected UV_* and PROXY env into {len(config.get(\"mcpServers\",{}))} servers')
"

# 3. 执行原 CMD
exec "$@"
ENTRYPOINT_EOF
        chmod +x "${ENTRYPOINT_WRAPPER}"

        echo "启动 MCP-Atlas agent-environment 容器(名称: ${CONT_NAME})..."
        docker run -d \
            --name ${CONT_NAME} \
            --add-host=host.docker.internal:host-gateway \
            -p 1984:1984 \
            ${DOCKER_ENV_ARGS} \
            --env UV_NO_SYNC=1 \
            --env UV_OFFLINE=1 \
            --env UV_PYTHON=3.12 \
            --env npm_config_offline=true \
            --env HTTPS_PROXY=http://10.201.136.68:1080 \
            --env HTTP_PROXY=http://10.201.136.68:1080 \
            --env NO_PROXY=localhost,127.0.0.1,10.0.0.0/8,host.docker.internal \
            -v "${ENTRYPOINT_WRAPPER}:/agent-environment/entrypoint_wrapper.sh:ro" \
            --entrypoint /agent-environment/entrypoint_wrapper.sh \
            --restart on-failure:3 \
            ${MCP_ATLAS_IMAGE} \
            uv run python -m uvicorn agent_environment.main:app --host 0.0.0.0 --port 1984 2>&1 || {
                echo "ERROR: 启动 MCP-Atlas 容器失败。"
                docker logs ${CONT_NAME} 2>&1 | tail -20 || true
                rm -f "${ENTRYPOINT_WRAPPER}" 2>/dev/null || true
                exit 1
            }

        # 快速检查容器是否立即退出(crash-loop 第一轮)
        sleep 3
        CONT_STATUS=$(docker inspect ${CONT_NAME} --format '{{.State.Status}}' 2>/dev/null || echo "inspect_failed")
        if [ "${CONT_STATUS}" = "exited" ]; then
            echo "ERROR: 容器在启动后 3 秒内即退出。"
            echo "退出码: $(docker inspect ${CONT_NAME} --format '{{.State.ExitCode}}' 2>/dev/null)"
            echo "错误信息: $(docker inspect ${CONT_NAME} --format '{{.State.Error}}' 2>/dev/null)"
            echo "容器日志(最后 50 行):"
            docker logs ${CONT_NAME} 2>&1 | tail -50 || true
            exit 1
        fi
        echo "容器状态: ${CONT_STATUS},开始等待服务就绪..."

        # 等待服务就绪(官方文档说启动需要 1+ 分钟,最长等 5 分钟)
        echo "等待 MCP-Atlas agent-environment 启动(最长 300 秒)..."
        READY=false
        for i in $(seq 1 60); do
            sleep 5
            HTTP_CODE=$(curl -s --noproxy localhost --connect-timeout 3 -o /dev/null -w "%{http_code}" http://localhost:1984/enabled-servers 2>/dev/null) || true
            if [ "${HTTP_CODE}" = "200" ]; then
                READY=true
                echo "MCP-Atlas agent-environment 启动完成(等待 $((i * 5)) 秒)"
                break
            fi
            echo "  等待中... ($((i * 5))s, HTTP ${HTTP_CODE})"
        done

        if [ "${READY}" != "true" ]; then
            echo "ERROR: MCP-Atlas agent-environment 在 300 秒内未就绪。"
            echo ""
            echo "=== 容器状态 ==="
            docker ps -a --filter "name=mcp-atlas-agent-env" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
            echo ""
            echo "=== 容器详细信息 ==="
            echo "Status:    $(docker inspect ${CONT_NAME} --format '{{.State.Status}}' 2>/dev/null || echo 'N/A')"
            echo "ExitCode:  $(docker inspect ${CONT_NAME} --format '{{.State.ExitCode}}' 2>/dev/null || echo 'N/A')"
            echo "RestartCount: $(docker inspect ${CONT_NAME} --format '{{.State.RestartCount}}' 2>/dev/null || echo 'N/A')"
            echo "Error:     $(docker inspect ${CONT_NAME} --format '{{.State.Error}}' 2>/dev/null || echo 'N/A')"
            echo ""
            echo "=== 容器日志(最后 50 行) ==="
            docker logs ${CONT_NAME} 2>&1 | tail -50 || true
            echo "=== 日志结束 ==="
            echo ""
            echo "请检查容器状态: docker logs ${CONT_NAME}"
            rm -f "${ENTRYPOINT_WRAPPER}" 2>/dev/null || true
            exit 1
        fi

        # 清理宿主机临时 entrypoint wrapper(容器已启动,不再需要)
        rm -f "${ENTRYPOINT_WRAPPER}" 2>/dev/null || true

        # 输出已启用的 server 列表
        echo "MCP-Atlas agent-environment 部署成功,已启用的 MCP servers:"
        curl -s --noproxy localhost http://localhost:1984/enabled-servers | python3 -m json.tool 2>/dev/null || echo "(解析失败,但服务可用)"
        echo "预检通过"
    else
        echo "MCP-Atlas agent-environment 服务不可达(HTTP ${HTTP_CODE}),且 MCP_ATLAS_AUTO_DEPLOY=false。"
        echo "请手动部署: docker pull ${MCP_ATLAS_IMAGE} && docker run -d -p 1984:1984 --env UV_NO_SYNC=1 --env UV_OFFLINE=1 --env UV_PYTHON=3.12 --env npm_config_offline=true ${MCP_ATLAS_IMAGE}"
        echo "或设置 MCP_ATLAS_AUTO_DEPLOY=true 让 Jenkins 自动部署。"
        echo "mcp_atlas 任务将继续保留在任务列表中,但预期会失败。"
    fi
else
    echo "TASK_MCP_ATLAS=false,跳过 mcp_atlas 服务检查"
fi
