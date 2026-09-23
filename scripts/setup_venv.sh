#!/bin/bash
set -e

# Setup venv: clean residual processes, create/repair Python 3.12 virtual environment,
# install/repair evalscope with task-specific extras and git-only dependencies.
#
# Env vars (must be set by caller):
#   WORK_DIR, TASK_DEEP_SWE, ENABLE_SANDBOX, TASK_HUMANEVAL,
#   TASK_HUMANEVAL_PLUS, TASK_MBPP, TASK_TAU_BENCH, TASK_TAU2_BENCH

cd "$WORK_DIR"
echo "工作目录: $(pwd)"
ls -la

echo "=== 清理残留进程 (evalscope / run_evalscope) ==="
# 用更精确的"全字符串"匹配避免误杀其他测试框架同名脚本与 Jenkins 内部进程:
#   - "evalscope eval"       :真正的 evalscope 运行命令
#   - "run_evalscope.py"     :我们的编排脚本(改用全字符串,避免命中其他框架的 run_eval.py / run_eval_xxx.py)
#   - 排除含 "jenkins" / "durable" / "@tmp" 的 Jenkins 内部进程
# pgrep -f 的 pattern 默认做正则匹配,转义为普通字符串以确保整串相等而非子串正则。
RESIDUAL=$(pgrep -af "evalscope eval|run_evalscope\.py" 2>/dev/null | grep -vE "jenkins|durable|@tmp" || true)
if [ -n "${RESIDUAL}" ]; then
    echo "发现残留进程:"
    echo "${RESIDUAL}"
    echo "发送 SIGTERM..."
    echo "${RESIDUAL}" | awk '{print $1}' | xargs -r kill -TERM 2>/dev/null || true
    sleep 3
    REMAINING=$(pgrep -af "evalscope eval|run_evalscope\.py" 2>/dev/null | grep -vE "jenkins|durable|@tmp" || true)
    if [ -n "${REMAINING}" ]; then
        echo "残留进程未响应 SIGTERM,发送 SIGKILL..."
        echo "${REMAINING}" | awk '{print $1}' | xargs -r kill -KILL 2>/dev/null || true
        sleep 1
    fi
    FINAL=$(pgrep -af "evalscope eval|run_evalscope\.py" 2>/dev/null | grep -vE "jenkins|durable|@tmp" || true)
    if [ -n "${FINAL}" ]; then
        echo "WARN: 以下残留进程仍存在,需人工介入:"
        echo "${FINAL}"
    else
        echo "残留进程清理完成"
    fi
else
    echo "未发现残留进程"
fi

echo "=== 检查并创建虚拟环境 ==="
# 统一使用 Python 3.12 创建虚拟环境:
# - deep_swe 需要 Python >= 3.12(datacurve-pier 的硬约束)
# - Python 3.12 向后兼容 3.10/3.11 代码,EvalScope 支持的所有任务均可正常运行
# - uv 会在系统无 3.12 时自动下载
REQUIRED_PY="3.12"

# 检查现有 venv 的 Python 版本,不满足则重建
if [ -d "${WORK_DIR}/.venv" ]; then
    VENV_PY=$(${WORK_DIR}/.venv/bin/python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "")
    if [ -n "${VENV_PY}" ]; then
        VENV_MAJOR=$(echo "${VENV_PY}" | cut -d. -f1)
        VENV_MINOR=$(echo "${VENV_PY}" | cut -d. -f2)
        REQUIRED_MAJOR=$(echo "${REQUIRED_PY}" | cut -d. -f1)
        REQUIRED_MINOR=$(echo "${REQUIRED_PY}" | cut -d. -f2)
        if [ "${VENV_MAJOR}" -lt "${REQUIRED_MAJOR}" ] || ([ "${VENV_MAJOR}" -eq "${REQUIRED_MAJOR}" ] && [ "${VENV_MINOR}" -lt "${REQUIRED_MINOR}" ]); then
            echo "当前 venv Python ${VENV_PY} < ${REQUIRED_PY}(deep_swe 需要),重建虚拟环境..."
            rm -rf ${WORK_DIR}/.venv
        else
            echo "现有 venv Python ${VENV_PY} 满足要求(>= ${REQUIRED_PY})"
        fi
    else
        echo "无法检测 venv Python 版本,重建虚拟环境..."
        rm -rf ${WORK_DIR}/.venv
    fi
fi

if [ ! -d "${WORK_DIR}/.venv" ]; then
    export https_proxy=http://10.201.136.68:1080
    export http_proxy=http://10.201.136.68:1080
    echo "创建虚拟环境 (Python ${REQUIRED_PY})..."
    cd ${WORK_DIR}
    uv venv --python ${REQUIRED_PY}
    source .venv/bin/activate
    # 构建动态 extras 列表,一次性安装所有需要的 extras 与基础包
    EXTRAS=""
    if [ "${ENABLE_SANDBOX}" = "true" ]; then
        EXTRAS="sandbox"
    fi
    if [ "${TASK_DEEP_SWE}" = "true" ]; then
        if [ -n "${EXTRAS}" ]; then
            EXTRAS="${EXTRAS},deep_swe"
        else
            EXTRAS="deep_swe"
        fi
    fi
    EXTRAS_OK=false
    echo "从官方源 https://pypi.org/simple/ 安装 evalscope(extras: ${EXTRAS:-none})..."
    if [ -n "${EXTRAS}" ]; then
        if UV_INDEX_URL="https://pypi.org/simple/" uv pip install -e ".[${EXTRAS}]" 2>&1; then
            EXTRAS_OK=true
        fi
    else
        if UV_INDEX_URL="https://pypi.org/simple/" uv pip install -e . 2>&1; then
            EXTRAS_OK=true
        fi
    fi
    # tau_bench / tau2_bench: git-only 依赖,需在 evalscope 安装后单独安装(代理仍在生效)
    if [ "${TASK_TAU_BENCH}" = "true" ]; then
        echo "安装 tau_bench 依赖(git+https://github.com/sierra-research/tau-bench)..."
        uv pip install "git+https://github.com/sierra-research/tau-bench" 2>&1 || echo "WARN: tau_bench git 依赖安装失败,稍后在补装阶段会重试"
    fi
    if [ "${TASK_TAU2_BENCH}" = "true" ]; then
        echo "安装 tau2_bench 依赖(git+https://github.com/sierra-research/tau2-bench@v0.2.0)..."
        uv pip install "git+https://github.com/sierra-research/tau2-bench@v0.2.0" 2>&1 || echo "WARN: tau2_bench git 依赖安装失败,稍后在补装阶段会重试"
    fi
    unset https_proxy
    unset http_proxy
    deactivate
    if [ "${EXTRAS_OK}" != "true" ]; then
        echo "ERROR: evalscope 安装失败(官方源 pypi.org 不可用)。"
        echo "请检查网络/代理配置。"
        exit 1
    fi
    echo "虚拟环境创建完成(Python ${REQUIRED_PY}, extras: ${EXTRAS:-none})"
else
    echo "虚拟环境已存在,检查并补装缺失 extras..."

    cd ${WORK_DIR}
    source .venv/bin/activate

    # sandbox:检查是否已安装
    if [ "${ENABLE_SANDBOX}" = "true" ]; then
        if ! python3 -c "import evalscope.api.sandbox" 2>/dev/null && ! pip show evalscope 2>/dev/null | grep -q "sandbox"; then
            echo "补装 sandbox 依赖..."
            export https_proxy=http://10.201.136.68:1080
            export http_proxy=http://10.201.136.68:1080
            SANDBOX_OK=false
            echo "从官方源 https://pypi.org/simple/ 补装 sandbox 依赖..."
            if UV_INDEX_URL="https://pypi.org/simple/" uv pip install -r requirements/sandbox.txt 2>&1; then
                SANDBOX_OK=true
            fi
            unset https_proxy
            unset http_proxy
            if [ "${SANDBOX_OK}" != "true" ]; then
                echo "ERROR: sandbox 依赖补装失败(官方源 pypi.org 不可用)。"
                exit 1
            fi
            echo "sandbox 依赖补装完成"
        else
            echo "sandbox 依赖已安装"
        fi
    fi

    # deep_swe:检查 pier 是否已安装
    if [ "${TASK_DEEP_SWE}" = "true" ]; then
        if ! python3 -c "import pier" 2>/dev/null; then
            echo "补装 deep_swe 依赖(datacurve-pier)..."
            export https_proxy=http://10.201.136.68:1080
            export http_proxy=http://10.201.136.68:1080
            DEEP_SWE_OK=false
            echo "从官方源 https://pypi.org/simple/ 补装 deep_swe 依赖..."
            if UV_INDEX_URL="https://pypi.org/simple/" uv pip install -r evalscope/benchmarks/deep_swe/requirements.txt 2>&1; then
                DEEP_SWE_OK=true
            fi
            unset https_proxy
            unset http_proxy
            if [ "${DEEP_SWE_OK}" != "true" ]; then
                echo "ERROR: deep_swe 依赖补装失败(官方源 pypi.org 不可用)。"
                exit 1
            fi
            if ! python3 -c "import pier" 2>/dev/null; then
                echo "ERROR: deep_swe 依赖安装后仍无法 import pier。"
                echo "当前 Python 版本: $(python3 --version)"
                echo "请删除 venv 重建: rm -rf .venv(下次 Jenkins 构建会自动用 Python ${REQUIRED_PY} 重建)"
                exit 1
            fi
            echo "deep_swe 依赖补装完成"
        else
            echo "deep_swe 依赖(pier)已安装"
        fi
    fi

    # tau_bench:检查 tau_bench 包是否已安装(git-only 依赖,无法通过 pip extras 安装)
    if [ "${TASK_TAU_BENCH}" = "true" ]; then
        if ! python3 -c "import tau_bench" 2>/dev/null; then
            echo "补装 tau_bench 依赖(git+https://github.com/sierra-research/tau-bench)..."
            export https_proxy=http://10.201.136.68:1080
            export http_proxy=http://10.201.136.68:1080
            TAU_BENCH_OK=false
            if uv pip install "git+https://github.com/sierra-research/tau-bench" 2>&1; then
                TAU_BENCH_OK=true
            fi
            unset https_proxy
            unset http_proxy
            if [ "${TAU_BENCH_OK}" != "true" ]; then
                echo "ERROR: tau_bench 依赖补装失败(github 不可达或代理超时)。"
                echo "请手动安装: pip install git+https://github.com/sierra-research/tau-bench"
                exit 1
            fi
            echo "tau_bench 依赖补装完成"
        else
            echo "tau_bench 依赖已安装"
        fi
    fi

    # tau2_bench:检查 tau2 包是否已安装(git-only 依赖,无法通过 pip extras 安装)
    # 注意:tau2_bench 与 tau3_bench 共用 tau2 包名(不同版本),不可共存;本流水线不含 tau3_bench
    if [ "${TASK_TAU2_BENCH}" = "true" ]; then
        if ! python3 -c "import tau2" 2>/dev/null; then
            echo "补装 tau2_bench 依赖(git+https://github.com/sierra-research/tau2-bench@v0.2.0)..."
            export https_proxy=http://10.201.136.68:1080
            export http_proxy=http://10.201.136.68:1080
            TAU2_BENCH_OK=false
            if uv pip install "git+https://github.com/sierra-research/tau2-bench@v0.2.0" 2>&1; then
                TAU2_BENCH_OK=true
            fi
            unset https_proxy
            unset http_proxy
            if [ "${TAU2_BENCH_OK}" != "true" ]; then
                echo "ERROR: tau2_bench 依赖补装失败(github 不可达或代理超时)。"
                echo "请手动安装: pip install git+https://github.com/sierra-research/tau2-bench@v0.2.0"
                exit 1
            fi
            echo "tau2_bench 依赖补装完成"
        else
            echo "tau2_bench 依赖(tau2)已安装"
        fi
    fi

    deactivate
fi
