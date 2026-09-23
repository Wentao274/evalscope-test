#!/bin/bash
set -e

# Setup Docker: daemon proxy config, image pre-pull, compose install,
# ubuntu:24.04 pre-build with egress-proxy packages, Pier patch.
#
# Env vars (must be set by caller):
#   WORK_DIR, TASK_DEEP_SWE, ENABLE_SANDBOX, TASK_HUMANEVAL,
#   TASK_HUMANEVAL_PLUS, TASK_MBPP

echo "=== 虚拟环境准备完成 ==="

echo "=== 校验 Docker(sandbox / deep_swe 共用)==="
# 判断是否需要 Docker:仅当勾选了实际需要 Docker 的任务时才校验
#   - sandbox 任务(humaneval/humaneval_plus/mbpp 等 CodeExecutionSandboxMixin)+ ENABLE_SANDBOX=true
#   - deep_swe(通过 Pier 运行,独立 Docker 环境)
# 按勾选任务构建需要预拉取的镜像列表(每个任务只添加自身需要的镜像,最后去重拉取):
#   humaneval      → python:3.11-slim(标准沙箱镜像)
#   mbpp           → python:3.11-slim(标准沙箱镜像)
#   humaneval_plus → 自定义镜像 python3.11-numpy(evalscope 运行时 docker build 本地构建,无需预拉取)
NEED_DOCKER=false
SANDBOX_IMAGES=""
if [ "${ENABLE_SANDBOX}" = "true" ]; then
    if [ "${TASK_HUMANEVAL}" = "true" ]; then
        NEED_DOCKER=true
        SANDBOX_IMAGES="${SANDBOX_IMAGES} python:3.11-slim"
    fi
    if [ "${TASK_HUMANEVAL_PLUS}" = "true" ]; then
        NEED_DOCKER=true
    fi
    if [ "${TASK_MBPP}" = "true" ]; then
        NEED_DOCKER=true
        SANDBOX_IMAGES="${SANDBOX_IMAGES} python:3.11-slim"
    fi
fi
if [ "${TASK_DEEP_SWE}" = "true" ]; then
    NEED_DOCKER=true
fi
if [ "${NEED_DOCKER}" = "true" ]; then
    if ! docker info >/dev/null 2>&1; then
        echo "WARN: Docker daemon 不可用(ENABLE_SANDBOX 或 TASK_DEEP_SWE 需要 Docker)。"
        echo "勾选的 Docker 任务(humaneval/mbpp/deep_swe 等)将在 eval 时失败,"
        echo "但非 Docker 任务(mmlu_pro/aime26 等)不受影响,继续运行。"
        echo "请确认 runner 上 Docker 已安装且 daemon 运行。"
    else
        echo "Docker daemon 可用"

    # === 配置 Docker daemon 代理(必须在 docker pull 之前)===
    # docker pull / docker build 拉取镜像时用的是 dockerd 自身的环境变量(来自 systemd drop-in),
    # 而非 shell 的 http_proxy/https_proxy。若 daemon 代理未配置或已过期,docker pull 会直连
    # Docker Hub 导致超时失败。因此先配置 daemon 代理,再拉取镜像。
    # === 检测宿主机 apt mirror(用于 egress-proxy 预构建 + noProxy 配置)===
    # 宿主机 apt 能正常工作的 mirror,Docker 容器经默认 bridge NAT 也能访问。
    # 关键:必须将 mirror hostname 加入 noProxy — Docker 的 noProxy CIDR(如 10.0.0.0/8)
    # 只对 IP-address 目标生效,不对 hostname 生效。若不加入,Pier 的 egress-proxy 构建中
    # apt-get update 会经代理(10.201.136.68:1080)访问内网 mirror,代理返回 502 Bad Gateway。
    HOST_MIRROR=""
    if [ -f /etc/apt/sources.list ]; then
        HOST_MIRROR=$(grep -E '^deb ' /etc/apt/sources.list | head -1 | awk '{print $2}' | sed 's|/ubuntu.*||' | sed 's|/$||')
    fi
    if [ -z "${HOST_MIRROR}" ] && [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
        HOST_MIRROR=$(awk -F': ' '/^URIs:/ {print $2}' /etc/apt/sources.list.d/ubuntu.sources | head -1 | sed 's|/ubuntu.*||' | sed 's|/$||')
    fi
    echo "宿主机 apt mirror: ${HOST_MIRROR:-<未检测到>}"
    # 从 mirror URL 提取 hostname(例 http://nexus.hd-04.zetyun.cn:8081/repository → nexus.hd-04.zetyun.cn)
    MIRROR_HOST=""
    if [ -n "${HOST_MIRROR}" ]; then
        MIRROR_HOST=$(echo "${HOST_MIRROR}" | sed -E 's|^[a-zA-Z]+://||; s|:[0-9]+.*||; s|/.*||')
    fi
    echo "Mirror hostname for noProxy: ${MIRROR_HOST:-<none>}"
    # 构建 noProxy 列表:基础 + mirror hostname(让 egress-proxy 构建中的 apt 绕过代理直连 mirror)
    NO_PROXY_LIST="localhost,127.0.0.1,10.0.0.0/8"
    if [ -n "${MIRROR_HOST}" ]; then
        NO_PROXY_LIST="${NO_PROXY_LIST},${MIRROR_HOST}"
    fi

    # 配置 Docker 构建代理(Pier 的 docker build 需要通过代理访问 Docker Hub/pypi 等)
    # ~/.docker/config.json 的 proxies 配置会自动注入 HTTP_PROXY/HTTPS_PROXY 到 docker build 和 docker run
    echo "=== 配置 Docker 构建代理 ==="
    mkdir -p ~/.docker
    python3 -c "
import json, os
p = os.path.expanduser('~/.docker/config.json')
c = {}
if os.path.exists(p):
    try:
        c = json.load(open(p))
    except Exception:
        c = {}
c['proxies'] = {'default': {'httpProxy': 'http://10.201.136.68:1080', 'httpsProxy': 'http://10.201.136.68:1080', 'noProxy': '${NO_PROXY_LIST}'}}
with open(p, 'w') as f:
    json.dump(c, f, indent=2)
print('Docker 构建代理已配置: http://10.201.136.68:1080 (noProxy: ${NO_PROXY_LIST})')
"

    # 配置 Docker daemon 代理(systemd drop-in)
    # ~/.docker/config.json 只影响 docker run 的容器环境变量和 docker build 的 build-arg,
    # 但 docker build / docker pull 拉取 base image 时用的是 dockerd 自身的环境变量(来自 systemd drop-in)。
    # 如果 dockerd 的代理地址过期(如 100.64.1.68:1080),buildkit 拉取 base image 会超时。
    # 这里检测并更新 systemd drop-in,如果代理地址已变更则重启 Docker daemon。
    echo "=== 检查 Docker daemon 代理(systemd drop-in) ==="
    DROPIN_DIR=/etc/systemd/system/docker.service.d
    DROPIN_FILE=${DROPIN_DIR}/http-proxy.conf
    NEEDS_DAEMON_PROXY_UPDATE=false

    # 检查当前 daemon 的代理环境变量
    CURRENT_DAEMON_PROXY=$(systemctl show docker --property=Environment 2>/dev/null | grep -o 'HTTPS_PROXY=[^ ]*' | cut -d= -f2 || echo "")
    echo "当前 Docker daemon 代理: ${CURRENT_DAEMON_PROXY:-<无>}"
    if [ "${CURRENT_DAEMON_PROXY}" != "http://10.201.136.68:1080" ]; then
        NEEDS_DAEMON_PROXY_UPDATE=true
    fi

    if [ "${NEEDS_DAEMON_PROXY_UPDATE}" = "true" ]; then
        echo "Docker daemon 代理需要更新 → 写入 systemd drop-in"
        mkdir -p ${DROPIN_DIR}
        cat > "${DROPIN_FILE}" << 'PROXY_EOF'
[Service]
Environment="HTTP_PROXY=http://10.201.136.68:1080"
Environment="HTTPS_PROXY=http://10.201.136.68:1080"
Environment="NO_PROXY=localhost,127.0.0.1,10.0.0.0/8"
PROXY_EOF
        systemctl daemon-reload
        echo "正在重启 Docker daemon(应用新代理地址)..."
        systemctl restart docker
        # 等待 Docker 恢复
        for i in $(seq 1 12); do
            if docker info >/dev/null 2>&1; then
                echo "Docker daemon 已恢复(${i} 秒)"
                break
            fi
            sleep 1
        done
        if ! docker info >/dev/null 2>&1; then
            echo "WARN: Docker daemon 在重启后 12 秒内未恢复,deep_swe/sandbox 任务可能失败"
            echo "  非 Docker 任务(mmlu_pro 等)不受影响,继续运行"
        else
            echo "Docker daemon 代理已更新为 http://10.201.136.68:1080"
        fi
    else
        echo "Docker daemon 代理已是最新,无需更新"
    fi

    # 按勾选任务预拉取对应的 sandbox 镜像(去重后逐个拉取)
    # ms_enclave 运行时首次 create_sandbox 会自动 pull,但经代理可能超时,
    # 在环境检查阶段预拉取并缓存,避免 eval 运行时阻塞和代理超时风险。
    # 注意:docker pull 使用 Docker daemon 的代理(systemd drop-in),已在上方配置完成;
    #       同时设置 shell 级代理作为兜底,拉取完成后立即 unset,避免泄漏到后续阶段。
    if [ -n "${SANDBOX_IMAGES}" ]; then
        export https_proxy=http://10.201.136.68:1080
        export http_proxy=http://10.201.136.68:1080
        for IMAGE in $(echo "${SANDBOX_IMAGES}" | tr ' ' '\n' | sort -u); do
            [ -z "${IMAGE}" ] && continue
            if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
                echo "预拉取镜像 ${IMAGE}(经 Docker daemon 代理)..."
                if docker pull "${IMAGE}" 2>&1; then
                    echo "镜像 ${IMAGE} 预拉取完成"
                else
                    echo "WARN: 镜像 ${IMAGE} 预拉取失败,eval 运行时会再次尝试自动 pull"
                    echo "  若 eval 也失败,请检查 Docker daemon 代理配置(systemd drop-in)"
                fi
            else
                echo "镜像 ${IMAGE} 已存在,跳过预拉取"
            fi
        done
        unset https_proxy
        unset http_proxy
    else
        echo "未勾选需要标准沙箱镜像的任务(humaneval/mbpp),跳过镜像预拉取"
    fi
    # humaneval_plus 使用自定义镜像 python3.11-numpy(FROM python:3.11 + numpy),
    # 由 evalscope 运行时通过 prepare_docker_image 本地 build,无需在此预拉取。

    # deep_swe 需要 Docker Compose v2 插件(Pier 用 "docker compose" 语法管理环境)
    if [ "${TASK_DEEP_SWE}" = "true" ]; then
        if docker compose version >/dev/null 2>&1; then
            echo "Docker Compose v2 可用: $(docker compose version --short 2>/dev/null)"
        else
            echo "Docker Compose v2 插件未安装(deep_swe 需要),尝试自动安装..."
            COMPOSE_INSTALL_OK=false
            # 优先用 apt 安装(需要访问 Docker 官方 apt 仓库)
            if apt-get update -qq >/dev/null 2>&1; then
                if apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1; then
                    COMPOSE_INSTALL_OK=true
                fi
            fi
            # apt 失败,尝试直接下载二进制
            if [ "${COMPOSE_INSTALL_OK}" != "true" ]; then
                echo "apt 安装失败,尝试直接下载 docker-compose 二进制..."
                export https_proxy=http://10.201.136.68:1080
                export http_proxy=http://10.201.136.68:1080
                COMPOSE_VERSION="v2.29.7"
                COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"
                mkdir -p /usr/local/lib/docker/cli-plugins
                if curl -fsSL "${COMPOSE_URL}" -o /usr/local/lib/docker/cli-plugins/docker-compose && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose; then
                    COMPOSE_INSTALL_OK=true
                fi
                unset https_proxy
                unset http_proxy
            fi
            if [ "${COMPOSE_INSTALL_OK}" = "true" ] && docker compose version >/dev/null 2>&1; then
                echo "Docker Compose v2 安装成功: $(docker compose version --short 2>/dev/null)"
            else
                echo "WARN: Docker Compose v2 自动安装失败,deep_swe 任务将失败"
                echo "  非 Docker 任务(mmlu_pro 等)不受影响,继续运行"
                echo "  手动安装: apt-get install docker-compose-plugin"
                echo "  或: mkdir -p /usr/local/lib/docker/cli-plugins && curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose"
            fi
        fi
    fi

    # === Pre-build ubuntu:24.04 with host apt mirror + pre-installed egress-proxy packages ===
    # Pier 的 egress-proxy Dockerfile 生成时会:
    #   FROM ubuntu:24.04
    #   RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends apache2-utils ca-certificates squid
    # 问题(官方源 + 代理对 apt 不可用):
    #   1) 默认 ubuntu:24.04 用 HTTP 到 archive.ubuntu.com → 代理返回 502 Bad Gateway
    #   2) 改 HTTPS → base 镜像无 ca-certificates,SSL 握手失败
    #   3) 代理对 apt 流量(HTTP/HTTPS)均不可靠
    # 修复:检测宿主机自己的 apt mirror(内网 Nexus,直连无需代理),用同一个 mirror
    #   替换 ubuntu:24.04 的 apt 源,然后在 Docker build(--network=host)中预装
    #   squid/apache2-utils/ca-certificates。
    # 注意:这是唯一使用内网 mirror 而非官方源+代理的环节,因为代理对 apt 不可靠。
    #   所有 PyPI 依赖(pip install)均走官方源 pypi.org + 代理。
    if [ "${TASK_DEEP_SWE}" = "true" ]; then
        echo "=== Pre-building ubuntu:24.04 with host apt mirror + egress-proxy packages ==="
        NEEDS_REBUILD=false
        if ! docker image inspect ubuntu:24.04 >/dev/null 2>&1; then
            NEEDS_REBUILD=true
        elif ! docker inspect ubuntu:24.04 --format '{{json .Config.Labels}}' 2>/dev/null | grep -q "egress-proxy-prebuilt"; then
            NEEDS_REBUILD=true
        fi
        if [ "${NEEDS_REBUILD}" = "true" ]; then
            # HOST_MIRROR 已在前面检测(同时用于 noProxy 配置)

            # Pull base image (Docker Hub via proxy — HTTPS works for Docker pulls)
            export https_proxy=http://10.201.136.68:1080
            export http_proxy=http://10.201.136.68:1080
            docker pull ubuntu:24.04
            unset https_proxy http_proxy

            if [ -n "${HOST_MIRROR}" ]; then
                # 用宿主机的 apt mirror 替换 ubuntu:24.04 的 apt 源
                # 宿主机网络可直接访问该 mirror(内网镜像),Docker build 用 --network=host 共享宿主机网络
                echo "使用宿主机 mirror 构建: ${HOST_MIRROR}"
                docker build --network=host \
                    --build-arg http_proxy= --build-arg https_proxy= --build-arg HTTP_PROXY= --build-arg HTTPS_PROXY= --build-arg no_proxy=* \
                    -t ubuntu:24.04 --label egress-proxy-prebuilt=true - <<DOCKERFILE
FROM ubuntu:24.04
RUN echo "deb ${HOST_MIRROR}/ubuntu noble main restricted universe multiverse" > /etc/apt/sources.list && \
    echo "deb ${HOST_MIRROR}/ubuntu noble-updates main restricted universe multiverse" >> /etc/apt/sources.list
RUN rm -f /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
RUN http_proxy= https_proxy= HTTP_PROXY= HTTPS_PROXY= apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends apache2-utils ca-certificates squid && rm -rf /var/lib/apt/lists/*
DOCKERFILE
            else
                echo "WARN: 未检测到宿主机 apt mirror,尝试使用 --network=host + 默认源"
                # --network=host 共享宿主机网络,可能可以访问宿主机能访问的 apt mirror
                docker build --network=host \
                    --build-arg http_proxy= --build-arg https_proxy= --build-arg HTTP_PROXY= --build-arg HTTPS_PROXY= --build-arg no_proxy=* \
                    -t ubuntu:24.04 --label egress-proxy-prebuilt=true - <<'DOCKERFILE'
FROM ubuntu:24.04
RUN http_proxy= https_proxy= HTTP_PROXY= HTTPS_PROXY= apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends apache2-utils ca-certificates squid && rm -rf /var/lib/apt/lists/*
DOCKERFILE
            fi

            echo "ubuntu:24.04 customized: host apt mirror + squid/apache2-utils/ca-certificates pre-installed"

            # Verify packages are installed
            echo "Verifying pre-installed packages..."
            if docker run --rm ubuntu:24.04 dpkg -s squid apache2-utils ca-certificates >/dev/null 2>&1; then
                echo "Verification passed: squid, apache2-utils, ca-certificates all installed"
            else
                echo "WARN: Pre-installed packages verification failed,deep_swe 任务可能失败"
                echo "  The host apt mirror may not support Ubuntu 24.04 (noble) packages."
                echo "  Host mirror: ${HOST_MIRROR:-<none>}"
                echo "  非 Docker 任务(mmlu_pro 等)不受影响,继续运行"
                echo "  Manual fix: build a custom ubuntu:24.04 image with squid pre-installed."
            fi
        else
            echo "ubuntu:24.04 already pre-built with egress-proxy packages, skipping"
        fi
    fi

    # === Patch Pier for proxy compatibility ===
    # Patch four issues:
    #   1. apt step: inject sed to switch Debian apt sources HTTP->HTTPS
    #   2. agent step: replace uv/curl install with pip install (official PyPI)
    #      astral.sh (uv CDN) is RST'd by enterprise proxy; official PyPI works through proxy CONNECT tunnel.
    #   3. docker-compose-build.yaml: add `network: host` under `build:` so that
    #      `docker compose build` uses host network (proxy unreachable from bridge).
    #   4. docker.py: force allow_internet=True in _prepare_egress_proxy_compose so that
    #      DeepSWE tasks (which set network_mode=no-network) can reach the LLM API endpoint.
    # Script is idempotent: already-patched files are skipped.
    if [ "${TASK_DEEP_SWE}" = "true" ]; then
        echo "=== Patching Pier for proxy compatibility (agent + compose + docker) ==="
        source ${WORK_DIR}/.venv/bin/activate
        python3 ${WORK_DIR}/scripts/patch_pier_apt.py 2>&1
        PATCH_EXIT=$?
        deactivate
        if [ "${PATCH_EXIT}" -ne 0 ]; then
            echo "WARN: Pier patch failed (exit ${PATCH_EXIT}), deep_swe may fail"
        fi
    fi
    fi
else
    echo "无需 Docker,跳过"
fi
