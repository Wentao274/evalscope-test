pipeline {
    agent {
        label 'slave-2'
    }
    parameters {
        string(name: 'TESTER', defaultValue: 'liwt', description: '测试人员名称(必填)')
        string(name: 'CHIP', defaultValue: 'nvidia-h100', description: '芯片平台名称(必填)')
        choice(name: 'ENGINE', choices: ['vllm', 'sglang'], description: '推理框架(必填,仅用于邮件展示)')
        choice(name: 'PD', choices: ['agg', 'disagg'], description: 'PD分离模式(agg=非PD分离,disagg=PD分离,仅用于邮件展示)')
        string(name: 'MODEL', defaultValue: 'deepseek-v4-flash', description: '模型服务名称(必填,对应 evalscope eval --model)')
        string(name: 'BASE_URL', defaultValue: 'http://10.201.149.37:8080', description: 'OpenAI 兼容端点根 URL(必填,不带 /v1 后缀,流水线会自动拼接)')
        password(name: 'API_KEY', defaultValue: '', description: 'API Key(可选,无需认证时留空)')

        // 裁判模型(mcp_atlas 等 LLM judge 任务必填)
        string(name: 'JUDGE_MODEL_ID', defaultValue: 'deepseek-v4-flash', description: '裁判模型名称(mcp_atlas 等 LLM judge 任务必填,对应 judge_model_args.model_id)')
        string(name: 'JUDGE_API_URL', defaultValue: 'http://10.201.149.41:8080/v1', description: '裁判模型 OpenAI 兼容端点 URL(mcp_atlas 等 LLM judge 任务必填,含 /v1 后缀)')
        password(name: 'JUDGE_API_KEY', defaultValue: 'EMPTY', description: '裁判模型 API Key(无需认证时填 EMPTY)')

        // 各基准一个 boolean(按需勾选;默认全开)
        booleanParam(name: 'TASK_MMLU_PRO',     defaultValue: true,  description: '运行 mmlu_pro (10 选项多学科多选,5-shot,accuracy)')
        booleanParam(name: 'TASK_GPQA_DIAMOND', defaultValue: true,  description: '运行 gpqa_diamond (博士级 4 选择,0-shot,accuracy)')
        booleanParam(name: 'TASK_CEVAL',        defaultValue: true,  description: '运行 ceval (中文多学科多选,52 学科,5-shot,accuracy)')
        booleanParam(name: 'TASK_CMMLU',        defaultValue: true,  description: '运行 cmmlu (中文多学科多选,67 学科,0-shot,accuracy)')
        booleanParam(name: 'TASK_MATH_500',     defaultValue: true,  description: '运行 math_500 (数学推理,500 题,0-shot,accuracy)')
        booleanParam(name: 'TASK_HELLASWAG',   defaultValue: true,  description: '运行 hellaswag (常识推理,4 选择,0-shot,accuracy)')
        booleanParam(name: 'TASK_HUMANEVAL',    defaultValue: true,  description: '运行 humaneval (Python 代码生成,164 题,0-shot,pass@1;需执行模型生成的代码,启用 sandbox 见 evalscope 文档)')
        booleanParam(name: 'TASK_HUMANEVAL_PLUS', defaultValue: true,  description: '运行 humaneval_plus (HumanEval 增强版,164 题,测试用例数万级,0-shot,pass@1;review_timeout=300s,需 sandbox 且使用内置 numpy 的自定义 docker 镜像)')
        booleanParam(name: 'TASK_HMMT25',        defaultValue: true,  description: '运行 hmmt25 (HMMT 2025年2月数学竞赛,30 题,0-shot,numeric accuracy;数学推理题,答案需 \\boxed{} 格式)')
        booleanParam(name: 'TASK_HMMT26',        defaultValue: true,  description: '运行 hmmt26 (HMMT 2026年2月数学竞赛,33 题,0-shot,numeric accuracy;数学推理题,答案需 \\boxed{} 格式)')
        booleanParam(name: 'TASK_IMO_ANSWERBENCH', defaultValue: true,  description: '运行 imo_answerbench (IMO 短名单奥数题,400 题,0-shot,numeric accuracy;llm_judge_default=True,有裁判模型时自动走 LLM judge,无裁判模型时回退 rule(numeric math_equal);答案含区间/集合/分数等复杂 LaTeX 形式,部分比对可能不如纯数字精确)')
        booleanParam(name: 'TASK_MCP_ATLAS',          defaultValue: true,  description: '运行 mcp_atlas (Scale AI MCP 工具使用智能体,89 题,multi-turn function-calling,LLM judge coverage_score/pass_rate;MCP-Atlas agent-environment Docker 服务支持自动部署,见 MCP_ATLAS_AUTO_DEPLOY 参数;20 个无需 API key 的 MCP server 默认启用,约 40-50 个任务可评测,配置 MCP_ATLAS_API_KEYS 可启用更多 server;被测模型驱动 AgentLoop,裁判模型逐 claim 评判;依赖 JUDGE_MODEL_ID/JUDGE_API_URL/JUDGE_API_KEY 参数)')

        booleanParam(name: 'TASK_DEEP_SWE',           defaultValue: true,  description: '运行 deep_swe (仓库级软件工程编码智能体,113 题,multi-turn agent,verifier 二值奖励 acc;通过 Pier Python API 运行,需 Docker + pip install evalscope[deep_swe] + Python>=3.12;Pier 内置 mini-swe-agent 驱动,默认 litellm model_class 兼容 OpenAI chat/completions 端点;默认 temperature=1.0 top_p=1.0 timeout=24h max_tokens=400k(官方 GLM-5.2 为 2h,低性能机器可调大);每个任务在隔离容器中运行,2 CPU/8GB RAM/无网络,串行执行耗时较长)')

        string(name: 'EXAMPLES',        defaultValue: '',      description: '样本数限制(空 = 不限制;传给 evalscope --limit。int=数量,float=比例)')
        string(name: 'REPEATS',         defaultValue: '',      description: '重复次数(k-metrics,传给 evalscope --repeats。空 = 默认 1)')
        string(name: 'EVAL_BATCH_SIZE', defaultValue: '32',    description: '并发批大小(对应 evalscope --eval-batch-size,默认 32)')
        string(name: 'TEMPERATURE_FALLBACK', defaultValue: '0.0', description: '采样温度兜底值(仅当 TASK_TEMPERATURE_JSON 未命中某任务时使用;默认 0.0 = greedy)')
        string(name: 'MAX_TOKENS',      defaultValue: '32768', description: '生成最大 token 数(默认 32768;清空 = 不指定)')
        string(name: 'TOP_P',           defaultValue: '0.95',  description: 'nucleus top_p(默认 0.95)')
        string(name: 'TOP_K',           defaultValue: '20',    description: 'top-k 采样(默认 20)')
        choice(name: 'ENABLE_THINKING', choices: ['false', 'true'], description: '启用 thinking 模式(默认 false)')
        choice(name: 'JUDGE_STRATEGY',  choices: ['auto', 'rule', 'llm', 'llm_recall'], description: '评分策略(默认 auto;多选题用 rule,主观题用 llm)')
        text(name: 'TASK_JUDGE_STRATEGY_JSON', defaultValue: '', description: '按任务覆盖 judge_strategy 的 JSON。默认为空:imo_answerbench 在有裁判模型(JUDGE_MODEL_ID 非空)时走 auto 自动启用 LLM judge,无裁判模型时自动回退 rule(numeric math_equal);如需手动指定可追加,例: {"imo_answerbench":"rule","simple_qa":"llm"}(需配套 judge_model_args)')
        choice(name: 'ENABLE_SANDBOX', choices: ['true', 'false'], description: '启用 sandbox 执行(默认 true)。true 时给所有任务拼 --sandbox {"enabled": true},仅对 humaneval 等 CodeExecutionSandboxMixin 任务生效。启用前环境检查 stage 会预装 evalscope[sandbox] 并校验 Docker 可用')
        text(name: 'TASK_MAX_TOKENS_JSON', defaultValue: '{"gpqa_diamond":131072,"deep_swe":409600}', description: '按任务覆盖 max_tokens 的 JSON,默认 gpqa_diamond=131072,deep_swe=409600(400k,编码 agent 需大输出窗口),其余任务用 MAX_TOKENS 默认值;可按需追加,例: {"mmlu_pro":4096,"gpqa_diamond":131072}')
        text(name: 'TASK_TIMEOUT_JSON', defaultValue: '{"mcp_atlas":3600,"deep_swe":86400}', description: '按任务覆盖模型调用超时(秒)的 JSON,默认 mcp_atlas=3600(1 小时,多轮 AgentLoop),deep_swe=86400(24 小时,仓库级编码 agent 串行构建+验证),其余任务用内置默认 3600;可按需追加,例: {"mcp_atlas":3600,"humaneval":1800}')
        text(name: 'TASK_TOP_P_JSON', defaultValue: '{"deep_swe":1.0}', description: '按任务覆盖 top_p 的 JSON,默认 deep_swe=1.0(编码 agent 高随机性探索,全局默认 0.95);可按需追加,例: {"deep_swe":1.0,"humaneval":0.95}')
        text(name: 'TASK_TEMPERATURE_JSON', defaultValue: '{"mmlu_pro":0.0,"gpqa_diamond":0.0,"ceval":0.0,"cmmlu":0.0,"math_500":0.6,"hellaswag":0.0,"humaneval":0.2,"humaneval_plus":0.2,"hmmt25":0.6,"hmmt26":0.6,"imo_answerbench":0.6,"mcp_atlas":0.0,"deep_swe":1.0}', description: '按任务指定采样温度的 JSON。默认值=各基准推荐温度:多选题/常识题 0.0(greedy 可复现),math_500/hmmt25/hmmt26/imo_answerbench 0.6(数学推理略带随机有助思考),humaneval/humaneval_plus 0.2(代码生成略带随机有助 pass@1 多样性),mcp_atlas 0.0(工具调用 greedy 可复现),deep_swe 1.0(编码 agent 高随机性探索)。可按模型调整,如 DSv4 reasoning 提高到 1.0、R1 系 0.6、instruct 0.0')
        text(name: 'TASK_REPEATS_JSON', defaultValue: '', description: '按任务覆盖 repeats 的 JSON,例: {"humaneval":5,"humaneval_plus":5}。命中任务使用对应值,未命中任务用全局 REPEATS;为空则全部用全局 REPEATS。推荐:humaneval/humaneval_plus 设 5 算 pass@1..pass@5,其余 greedy 基准(mmlu_pro/gpqa_diamond/ceval/cmmlu/hellaswag/math_500/hmmt25/hmmt26/imo_answerbench)保持 1 避免 N 倍空跑')
        text(name: 'DATASET_ARGS',      defaultValue: '',      description: '数据集参数 JSON,例: {"mmlu_pro":{"subset_list":["math","physics"]}}')

        string(name: 'DESCRIPTION', defaultValue: '', description: '模型服务描述信息(仅用于邮件展示)')
        text(name: 'RECIPIENTS',    defaultValue: 'liwt@zetyun.com', description: '报告邮件接收者(逗号分隔)')
        string(name: 'WORK_DIR',    defaultValue: '/dingofs/data2/userdata/liwt/maas-image/evalscope-test', description: '远程仓库目录,请不要改动')

        // MCP-Atlas agent-environment 自动部署
        string(name: 'MCP_ATLAS_IMAGE', defaultValue: 'ghcr.io/scaleapi/mcp-atlas:1.2.7', description: 'MCP-Atlas agent-environment Docker 镜像(Scale AI 官方预构建)。当 TASK_MCP_ATLAS=true 且服务未运行时,Jenkins 自动拉取并启动此镜像,监听 localhost:1984。20 个无需 API key 的 MCP server 默认启用')
        choice(name: 'MCP_ATLAS_AUTO_DEPLOY', choices: ['true', 'false'], description: '自动部署 MCP-Atlas agent-environment(默认 true)。服务未运行时自动 pull + docker run;false 则仅检查不自动启动,需手动准备')
        string(name: 'MCP_ATLAS_API_KEYS', defaultValue: '', description: '可选:MCP server API keys 环境变量,逗号分隔 KEY=VALUE 对。例: BRAVE_API_KEY=xxx,GITHUB_TOKEN=yyy。留空则仅启用 20 个无需 key 的 server(约 40-50 个任务可评测)')
    }
    environment {
        SSH_CREDENTIALS = 'HOST_SSH_KEY'
        REMOTE_HOST = '10.201.132.50'
        REMOTE_USER = 'root'
        // 用户在 BASE_URL 填根地址(可不带或带 /v1,可带或不带尾斜杠)。
        // 这里 idempotent 拼接出唯一的 OpenAI 兼容端点:
        //   先剥尾斜杠 → 再剥结尾 /v1(若有)→ 统一补 /v1
        BASE_URL_V1 = "${params.BASE_URL.replaceAll('/+\$', '').replaceAll('/?v1\$', '')}/v1"
    }

    stages {
        stage('打印测试参数') {
            steps {
                script {
                    println("========================================")
                    println("=== 测试参数信息 ===")
                    println("========================================")
                    println("测试人员:        ${params.TESTER}")
                    println("芯片平台:        ${params.CHIP}")
                    println("推理框架:        ${params.ENGINE}")
                    println("PD分离模式:      ${params.PD}")
                    println("模型名称:        ${params.MODEL}")
                    println("BASE_URL:        ${params.BASE_URL}  (→ ${env.BASE_URL_V1})")
                    println("任务 MMLU_PRO:     ${params.TASK_MMLU_PRO}")
                    println("任务 GPQA_DIAMOND: ${params.TASK_GPQA_DIAMOND}")
                    println("任务 CEVAL:        ${params.TASK_CEVAL}")
                    println("任务 CMMLU:        ${params.TASK_CMMLU}")
                    println("任务 MATH_500:     ${params.TASK_MATH_500}")
                    println("任务 HELLASWAG:   ${params.TASK_HELLASWAG}")
                    println("任务 HUMANEVAL:   ${params.TASK_HUMANEVAL}")
                    println("任务 HUMANEVAL_PLUS: ${params.TASK_HUMANEVAL_PLUS}")
                    println("任务 HMMT25:       ${params.TASK_HMMT25}")
                    println("任务 HMMT26:       ${params.TASK_HMMT26}")
                    println("任务 IMO_ANSWERBENCH: ${params.TASK_IMO_ANSWERBENCH}")
                    println("任务 MCP_ATLAS:      ${params.TASK_MCP_ATLAS}")
                    println("任务 DEEP_SWE:       ${params.TASK_DEEP_SWE}")
                    println("样本限制:        ${params.EXAMPLES ?: '无限制'}")
                    println("repeats:         ${params.REPEATS ?: 'default 1'}")
                    println("eval-batch-size: ${params.EVAL_BATCH_SIZE}")
                    println("温度(兜底):     ${params.TEMPERATURE_FALLBACK}")
                    println("max_tokens:      ${params.MAX_TOKENS ?: 'unlimited'}")
                    println("top_p / top_k:   ${params.TOP_P} / ${params.TOP_K}")
                    println("enable_thinking: ${params.ENABLE_THINKING}")
                    println("judge_strategy:  ${params.JUDGE_STRATEGY}")
                    println("per-task judge_strategy JSON: ${params.TASK_JUDGE_STRATEGY_JSON ?: 'N/A'}")
                    println("裁判模型:        ${params.JUDGE_MODEL_ID}")
                    println("裁判模型API:     ${params.JUDGE_API_URL}")
                    println("enable_sandbox:  ${params.ENABLE_SANDBOX}")
                    println("per-task max_tokens JSON: ${params.TASK_MAX_TOKENS_JSON ?: 'N/A'}")
                    println("per-task timeout JSON: ${params.TASK_TIMEOUT_JSON ?: 'N/A'}")
                    println("per-task top_p JSON: ${params.TASK_TOP_P_JSON ?: 'N/A'}")
                    println("per-task temperature JSON: ${params.TASK_TEMPERATURE_JSON ?: 'N/A'}")
                    println("per-task repeats JSON:   ${params.TASK_REPEATS_JSON ?: 'N/A'}")
                    println("dataset_args:    ${params.DATASET_ARGS ?: 'N/A'}")
                    println("模型描述:        ${params.DESCRIPTION}")
                    println("邮件接收者:      ${params.RECIPIENTS}")
                    println("工作目录:        ${params.WORK_DIR}")
                    println("MCP-Atlas 镜像:  ${params.MCP_ATLAS_IMAGE}")
                    println("MCP-Atlas 自动部署: ${params.MCP_ATLAS_AUTO_DEPLOY}")
                    println("MCP-Atlas API Keys: ${params.MCP_ATLAS_API_KEYS ?: 'N/A(仅启用 20 个无 key server)'}")
                    println("构建编号:        #${BUILD_NUMBER}")
                    println("========================================")
                }
            }
        }

        stage('API 连通性预检') {
            steps {
                sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                    script {
                        try {
                            sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << 'ENDSSH'
set -o pipefail
{
    echo "=== 检查 API 连通性 (/v1/models) ==="
    HTTP_CODE=\$(curl -s --connect-timeout 10 -m 30 -o /dev/null -w "%{http_code}" ${env.BASE_URL_V1}/models)
    if [ "\${HTTP_CODE}" != "200" ]; then
        echo "ERROR: API 连通性检查失败, HTTP状态码: \${HTTP_CODE}, URL: ${env.BASE_URL_V1}/models"
        exit 1
    fi
    echo "API /models 连通性检查通过, HTTP状态码: \${HTTP_CODE}"

    echo "=== 检查 Chat Completions 接口 ==="
    CHAT_RESP=\$(curl -s --connect-timeout 10 -m 60 -w "\\n%{http_code}" ${env.BASE_URL_V1}/chat/completions \\
        -H "Content-Type: application/json" \\
        -d '{"model":"${params.MODEL}","messages":[{"role":"user","content":"hello"}],"max_tokens":10}')
    CHAT_HTTP_CODE=\$(echo "\${CHAT_RESP}" | tail -1)
    if [ "\${CHAT_HTTP_CODE}" != "200" ]; then
        echo "ERROR: Chat Completions 接口检查失败, HTTP状态码: \${CHAT_HTTP_CODE}"
        echo "响应内容: \$(echo "\${CHAT_RESP}" | head -n -1)"
        exit 1
    fi
    echo "Chat Completions 接口检查通过, HTTP状态码: \${CHAT_HTTP_CODE}"
} 2>&1 | tee /tmp/evalscope_connectivity_${BUILD_NUMBER}.log
ENDSSH
"""
                        } catch (Exception e) {
                            env.CONNECTIVITY_FAILED = 'true'
                            currentBuild.result = 'UNSTABLE'
                            println("=== API 连通性预检失败,后续阶段(环境检查、运行evalscope测试)将跳过 ===")
                        }
                    }
                }
            }
        }

        stage('环境检查') {
            when {
                expression { env.CONNECTIVITY_FAILED != 'true' }
            }
            steps {
                sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                    sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << 'ENDSSH'
set -e
cd ${params.WORK_DIR}
echo "工作目录: \$(pwd)"
ls -la

echo "=== 清理残留进程 (evalscope / run_evalscope) ==="
# 用更精确的"全字符串"匹配避免误杀其他测试框架同名脚本与 Jenkins 内部进程:
#   - "evalscope eval"       :真正的 evalscope 运行命令
#   - "run_evalscope.py"     :我们的编排脚本(改用全字符串,避免命中其他框架的 run_eval.py / run_eval_xxx.py)
#   - 排除含 "jenkins" / "durable" / "@tmp" 的 Jenkins 内部进程
# pgrep -f 的 pattern 默认做正则匹配,转义为普通字符串以确保整串相等而非子串正则。
RESIDUAL=\$(pgrep -af "evalscope eval|run_evalscope\\.py" 2>/dev/null | grep -vE "jenkins|durable|@tmp" || true)
if [ -n "\${RESIDUAL}" ]; then
    echo "发现残留进程:"
    echo "\${RESIDUAL}"
    echo "发送 SIGTERM..."
    echo "\${RESIDUAL}" | awk '{print \$1}' | xargs -r kill -TERM 2>/dev/null || true
    sleep 3
    REMAINING=\$(pgrep -af "evalscope eval|run_evalscope\\.py" 2>/dev/null | grep -vE "jenkins|durable|@tmp" || true)
    if [ -n "\${REMAINING}" ]; then
        echo "残留进程未响应 SIGTERM,发送 SIGKILL..."
        echo "\${REMAINING}" | awk '{print \$1}' | xargs -r kill -KILL 2>/dev/null || true
        sleep 1
    fi
    FINAL=\$(pgrep -af "evalscope eval|run_evalscope\\.py" 2>/dev/null | grep -vE "jenkins|durable|@tmp" || true)
    if [ -n "\${FINAL}" ]; then
        echo "WARN: 以下残留进程仍存在,需人工介入:"
        echo "\${FINAL}"
    else
        echo "残留进程清理完成"
    fi
else
    echo "未发现残留进程"
fi

echo "=== 设置权限 ==="
chmod +x evalscope_main.sh
chmod +x run_evalscope.py

echo "=== 检查并创建虚拟环境 ==="
# 统一使用 Python 3.12 创建虚拟环境:
# - deep_swe 需要 Python >= 3.12(datacurve-pier 的硬约束)
# - Python 3.12 向后兼容 3.10/3.11 代码,EvalScope 支持的所有任务均可正常运行
# - uv 会在系统无 3.12 时自动下载
REQUIRED_PY="3.12"

# 判断需要哪些 extras
NEED_DEEP_SWE="${params.TASK_DEEP_SWE}"
NEED_SANDBOX="${params.ENABLE_SANDBOX}"

# 检查现有 venv 的 Python 版本,不满足则重建
if [ -d "${params.WORK_DIR}/.venv" ]; then
    VENV_PY=\$(${params.WORK_DIR}/.venv/bin/python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "")
    if [ -n "\${VENV_PY}" ]; then
        VENV_MAJOR=\$(echo "\${VENV_PY}" | cut -d. -f1)
        VENV_MINOR=\$(echo "\${VENV_PY}" | cut -d. -f2)
        REQUIRED_MAJOR=\$(echo "\${REQUIRED_PY}" | cut -d. -f1)
        REQUIRED_MINOR=\$(echo "\${REQUIRED_PY}" | cut -d. -f2)
        if [ "\${VENV_MAJOR}" -lt "\${REQUIRED_MAJOR}" ] || ([ "\${VENV_MAJOR}" -eq "\${REQUIRED_MAJOR}" ] && [ "\${VENV_MINOR}" -lt "\${REQUIRED_MINOR}" ]); then
            echo "当前 venv Python \${VENV_PY} < \${REQUIRED_PY}(deep_swe 需要),重建虚拟环境..."
            rm -rf ${params.WORK_DIR}/.venv
        else
            echo "现有 venv Python \${VENV_PY} 满足要求(>= \${REQUIRED_PY})"
        fi
    else
        echo "无法检测 venv Python 版本,重建虚拟环境..."
        rm -rf ${params.WORK_DIR}/.venv
    fi
fi

if [ ! -d "${params.WORK_DIR}/.venv" ]; then
    export https_proxy=http://100.64.1.68:1080
    export http_proxy=http://100.64.1.68:1080
    echo "创建虚拟环境 (Python \${REQUIRED_PY})..."
    cd ${params.WORK_DIR}
    uv venv --python \${REQUIRED_PY}
    source .venv/bin/activate
    # 构建动态 extras 列表,一次性安装所有需要的 extras 与基础包
    EXTRAS=""
    if [ "\${NEED_SANDBOX}" = "true" ]; then
        EXTRAS="sandbox"
    fi
    if [ "\${NEED_DEEP_SWE}" = "true" ]; then
        if [ -n "\${EXTRAS}" ]; then
            EXTRAS="\${EXTRAS},deep_swe"
        else
            EXTRAS="deep_swe"
        fi
    fi
    EXTRAS_OK=false
    for INDEX_URL in "https://mirrors.aliyun.com/pypi/simple/" "https://pypi.tuna.tsinghua.edu.cn/simple/" "https://pypi.org/simple/"; do
        echo "尝试从 \${INDEX_URL} 安装 evalscope(extras: \${EXTRAS:-none})..."
        if [ -n "\${EXTRAS}" ]; then
            if UV_INDEX_URL="\${INDEX_URL}" uv pip install -e ".[\${EXTRAS}]" 2>&1; then
                EXTRAS_OK=true
                break
            fi
        else
            if UV_INDEX_URL="\${INDEX_URL}" uv pip install -e . 2>&1; then
                EXTRAS_OK=true
                break
            fi
        fi
        echo "从 \${INDEX_URL} 安装失败,尝试下一个源..."
    done
    unset https_proxy
    unset http_proxy
    deactivate
    if [ "\${EXTRAS_OK}" != "true" ]; then
        echo "ERROR: evalscope 安装失败,所有 PyPI 源均不可用。"
        echo "请检查网络/代理配置。"
        exit 1
    fi
    echo "虚拟环境创建完成(Python \${REQUIRED_PY}, extras: \${EXTRAS:-none})"
else
    echo "虚拟环境已存在,检查并补装缺失 extras..."

    cd ${params.WORK_DIR}
    source .venv/bin/activate

    # sandbox:检查是否已安装
    if [ "\${NEED_SANDBOX}" = "true" ]; then
        if ! python3 -c "import evalscope.api.sandbox" 2>/dev/null && ! pip show evalscope 2>/dev/null | grep -q "sandbox"; then
            echo "补装 sandbox 依赖..."
            export https_proxy=http://100.64.1.68:1080
            export http_proxy=http://100.64.1.68:1080
            SANDBOX_OK=false
            for INDEX_URL in "https://mirrors.aliyun.com/pypi/simple/" "https://pypi.tuna.tsinghua.edu.cn/simple/" "https://pypi.org/simple/"; do
                if UV_INDEX_URL="\${INDEX_URL}" uv pip install -r requirements/sandbox.txt 2>&1; then
                    SANDBOX_OK=true
                    break
                fi
            done
            unset https_proxy
            unset http_proxy
            if [ "\${SANDBOX_OK}" != "true" ]; then
                echo "ERROR: sandbox 依赖补装失败,所有 PyPI 源均不可用。"
                exit 1
            fi
            echo "sandbox 依赖补装完成"
        else
            echo "sandbox 依赖已安装"
        fi
    fi

    # deep_swe:检查 pier 是否已安装
    if [ "\${NEED_DEEP_SWE}" = "true" ]; then
        if ! python3 -c "import pier" 2>/dev/null; then
            echo "补装 deep_swe 依赖(datacurve-pier)..."
            export https_proxy=http://100.64.1.68:1080
            export http_proxy=http://100.64.1.68:1080
            DEEP_SWE_OK=false
            for INDEX_URL in "https://mirrors.aliyun.com/pypi/simple/" "https://pypi.tuna.tsinghua.edu.cn/simple/" "https://pypi.org/simple/"; do
                if UV_INDEX_URL="\${INDEX_URL}" uv pip install -r evalscope/benchmarks/deep_swe/requirements.txt 2>&1; then
                    DEEP_SWE_OK=true
                    break
                fi
            done
            unset https_proxy
            unset http_proxy
            if [ "\${DEEP_SWE_OK}" != "true" ]; then
                echo "ERROR: deep_swe 依赖补装失败,所有 PyPI 源均不可用。"
                exit 1
            fi
            if ! python3 -c "import pier" 2>/dev/null; then
                echo "ERROR: deep_swe 依赖安装后仍无法 import pier。"
                echo "当前 Python 版本: \$(python3 --version)"
                echo "请删除 venv 重建: rm -rf .venv(下次 Jenkins 构建会自动用 Python \${REQUIRED_PY} 重建)"
                exit 1
            fi
            echo "deep_swe 依赖补装完成"
        else
            echo "deep_swe 依赖(pier)已安装"
        fi
    fi

    deactivate
fi

cd ${params.WORK_DIR}
echo "=== 虚拟环境准备完成 ==="

echo "=== 校验 Docker(sandbox / deep_swe 共用)==="
NEED_DOCKER=false
if [ "\${NEED_SANDBOX}" = "true" ]; then
    NEED_DOCKER=true
fi
if [ "\${NEED_DEEP_SWE}" = "true" ]; then
    NEED_DOCKER=true
fi
if [ "\${NEED_DOCKER}" = "true" ]; then
    if ! docker info >/dev/null 2>&1; then
        echo "ERROR: Docker daemon 不可用(ENABLE_SANDBOX 或 TASK_DEEP_SWE 需要 Docker)。"
        echo "请确认 runner 上 Docker 已安装且 daemon 运行。"
        exit 1
    fi
    echo "Docker daemon 可用"

    # deep_swe 需要 Docker Compose v2 插件(Pier 用 "docker compose" 语法管理环境)
    if [ "\${NEED_DEEP_SWE}" = "true" ]; then
        if docker compose version >/dev/null 2>&1; then
            echo "Docker Compose v2 可用: \$(docker compose version --short 2>/dev/null)"
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
            if [ "\${COMPOSE_INSTALL_OK}" != "true" ]; then
                echo "apt 安装失败,尝试直接下载 docker-compose 二进制..."
                export https_proxy=http://100.64.1.68:1080
                export http_proxy=http://100.64.1.68:1080
                COMPOSE_VERSION="v2.29.7"
                COMPOSE_URL="https://github.com/docker/compose/releases/download/\${COMPOSE_VERSION}/docker-compose-linux-x86_64"
                mkdir -p /usr/local/lib/docker/cli-plugins
                if curl -fsSL "\${COMPOSE_URL}" -o /usr/local/lib/docker/cli-plugins/docker-compose && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose; then
                    COMPOSE_INSTALL_OK=true
                fi
                unset https_proxy
                unset http_proxy
            fi
            if [ "\${COMPOSE_INSTALL_OK}" = "true" ] && docker compose version >/dev/null 2>&1; then
                echo "Docker Compose v2 安装成功: \$(docker compose version --short 2>/dev/null)"
            else
                echo "ERROR: Docker Compose v2 自动安装失败。"
                echo "请手动安装: apt-get install docker-compose-plugin"
                echo "  或: mkdir -p /usr/local/lib/docker/cli-plugins && curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose"
                exit 1
            fi
        fi
    fi

    # 配置 Docker 构建代理(Pier 的 docker build 需要通过代理访问 Docker Hub/pypi 等)
    # 关键:在 noProxy 中加入 mirrors.aliyun.com — 代理无法处理 apt 流量(HTTP 502 / HTTPS 超时),
    # 但 runner 在中国,可直接访问阿里云镜像站(无需代理)。这样 docker build 中的 apt-get 会直连 mirrors.aliyun.com。
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
c['proxies'] = {'default': {'httpProxy': 'http://100.64.1.68:1080', 'httpsProxy': 'http://100.64.1.68:1080', 'noProxy': 'localhost,127.0.0.1,10.0.0.0/8,mirrors.aliyun.com'}}
with open(p, 'w') as f:
    json.dump(c, f, indent=2)
print('Docker 构建代理已配置: http://100.64.1.68:1080 (noProxy: localhost,127.0.0.1,10.0.0.0/8,mirrors.aliyun.com)')
"

    # === Pre-build ubuntu:24.04 with aliyun mirror + pre-installed egress-proxy packages ===
    # Pier 的 egress-proxy Dockerfile 生成时会:
    #   FROM ubuntu:24.04
    #   RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends apache2-utils ca-certificates squid
    # 问题:
    #   1) 默认 ubuntu:24.04 用 HTTP 到 archive.ubuntu.com → 代理返回 502
    #   2) 改成 HTTPS 到 mirrors.aliyun.com → base 镜像无 ca-certificates,SSL 握手失败
    #   3) 代理对 apt 流量(HTTP/HTTPS)均不可靠
    # 修复:
    #   - noProxy 加入 mirrors.aliyun.com → docker build 中 apt 直连阿里云(不走代理)
    #   - apt 源改成 http://mirrors.aliyun.com(HTTP,不需要 ca-certificates)
    #   - 预装 squid/apache2-utils/ca-certificates → Pier 的 apt-get install 变成 no-op
    #   - 用 label "egress-proxy-prebuilt" 标记已预装的镜像,避免重复构建
    if [ "\${NEED_DEEP_SWE}" = "true" ]; then
        echo "=== Pre-building ubuntu:24.04 with aliyun mirror + egress-proxy packages ==="
        NEEDS_REBUILD=false
        if ! docker image inspect ubuntu:24.04 >/dev/null 2>&1; then
            NEEDS_REBUILD=true
        elif ! docker inspect ubuntu:24.04 --format '{{json .Config.Labels}}' 2>/dev/null | grep -q "egress-proxy-prebuilt"; then
            NEEDS_REBUILD=true
        fi
        if [ "\${NEEDS_REBUILD}" = "true" ]; then
            # Pull base image (Docker Hub via proxy — HTTPS works for Docker pulls)
            export https_proxy=http://100.64.1.68:1080
            export http_proxy=http://100.64.1.68:1080
            docker pull ubuntu:24.04
            unset https_proxy http_proxy

            # Build custom ubuntu:24.04:
            #   1. Change apt sources to http://mirrors.aliyun.com (HTTP, no SSL needed)
            #   2. Pre-install the three egress-proxy packages so Pier's apt-get install is a no-op
            #   3. Label it so we skip rebuild on subsequent runs
            # noProxy in ~/.docker/config.json ensures apt goes directly to mirrors.aliyun.com
            docker build -t ubuntu:24.04 --label egress-proxy-prebuilt=true - <<'DOCKERFILE'
FROM ubuntu:24.04
RUN sed -i 's|http://archive.ubuntu.com|http://mirrors.aliyun.com|g; s|http://security.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list 2>/dev/null || true
RUN if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
        sed -i 's|http://archive.ubuntu.com|http://mirrors.aliyun.com|g; s|http://security.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list.d/ubuntu.sources; \
    fi
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends apache2-utils ca-certificates squid && rm -rf /var/lib/apt/lists/*
DOCKERFILE
            echo "ubuntu:24.04 customized: aliyun HTTP mirror + squid/apache2-utils/ca-certificates pre-installed"

            # Verify: try apt-get install (should be instant no-op since packages are pre-installed)
            echo "Verifying pre-installed packages..."
            if docker run --rm ubuntu:24.04 dpkg -s squid apache2-utils ca-certificates >/dev/null 2>&1; then
                echo "Verification passed: squid, apache2-utils, ca-certificates all installed"
            else
                echo "ERROR: Pre-installed packages verification failed."
                echo "The runner may not have direct access to mirrors.aliyun.com."
                echo "Check: docker run --rm ubuntu:24.04 apt-get update"
                exit 1
            fi
        else
            echo "ubuntu:24.04 already pre-built with egress-proxy packages, skipping"
        fi
    fi
else
    echo "无需 Docker,跳过"
fi

echo "=== 检查 MCP-Atlas agent-environment 服务 ==="
if [ "${params.TASK_MCP_ATLAS}" = "true" ]; then
    echo "TASK_MCP_ATLAS=true,检查 MCP-Atlas agent-environment 服务..."
    CONT_NAME="mcp-atlas-agent-env-${BUILD_NUMBER}"

    # 先检查服务是否已在运行(检查端口,而非容器名,因为容器名每次构建不同)
    HTTP_CODE=\$(curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" http://localhost:1984/enabled-servers 2>/dev/null) || true
    if [ "\${HTTP_CODE}" = "200" ]; then
        echo "MCP-Atlas agent-environment 服务已运行(HTTP 200),预检通过"
        # 输出已启用的 server 列表
        echo "已启用的 MCP servers:"
        curl -s http://localhost:1984/enabled-servers | python3 -m json.tool 2>/dev/null || echo "(解析失败,但服务可用)"
    elif [ "${params.MCP_ATLAS_AUTO_DEPLOY}" = "true" ]; then
        echo "MCP-Atlas agent-environment 服务未运行(HTTP \${HTTP_CODE}),开始自动部署..."
        echo "镜像: ${params.MCP_ATLAS_IMAGE}"

        # 检查 Docker
        if ! docker info >/dev/null 2>&1; then
            echo "ERROR: Docker daemon 不可用,无法自动部署 MCP-Atlas agent-environment。"
            echo "请确认 Docker 已安装且 daemon 运行,或设置 MCP_ATLAS_AUTO_DEPLOY=false 手动准备。"
            exit 1
        fi

        # 清理所有旧的 MCP-Atlas 容器(按名称前缀匹配,覆盖所有历史构建)
        echo "清理旧的 MCP-Atlas 容器(前缀 mcp-atlas-agent-env*)..."
        OLD_CONTAINERS=\$(docker ps -a --filter "name=mcp-atlas-agent-env" --format "{{.ID}} {{.Names}}" 2>/dev/null || echo "")
        if [ -n "\${OLD_CONTAINERS}" ]; then
            echo "发现旧容器:"
            echo "\${OLD_CONTAINERS}"
            OLD_IDS=\$(echo "\${OLD_CONTAINERS}" | awk '{print \$1}')
            docker rm -f \${OLD_IDS} 2>/dev/null || true
            echo "旧容器已清理"
        else
            # 兜底:按端口匹配(可能有不同名称的旧容器占用 1984)
            OLD_IDS=\$(docker ps -a --filter "publish=1984" --format "{{.ID}}" 2>/dev/null || echo "")
            if [ -n "\${OLD_IDS}" ]; then
                echo "清理占用端口 1984 的旧容器: \${OLD_IDS}"
                docker rm -f \${OLD_IDS} 2>/dev/null || true
            else
                echo "无旧容器需要清理"
            fi
        fi

        # 拉取镜像(代理)
        echo "拉取 MCP-Atlas 镜像(可能需要几分钟)..."
        export https_proxy=http://100.64.1.68:1080
        export http_proxy=http://100.64.1.68:1080
        if ! docker pull ${params.MCP_ATLAS_IMAGE} 2>&1; then
            unset https_proxy http_proxy
            echo "ERROR: 拉取 MCP-Atlas 镜像失败。"
            echo "请检查网络/代理配置,或手动拉取: docker pull ${params.MCP_ATLAS_IMAGE}"
            exit 1
        fi
        unset https_proxy
        unset http_proxy

        # 构建 docker run 的环境变量参数
        DOCKER_ENV_ARGS=""
        if [ -n "${params.MCP_ATLAS_API_KEYS}" ]; then
            # 解析逗号分隔的 KEY=VALUE 对,生成 --env 参数
            IFS=',' read -ra KEY_PAIRS <<< "${params.MCP_ATLAS_API_KEYS}"
            for pair in "\${KEY_PAIRS[@]}"; do
                pair=\$(echo "\$pair" | xargs)  # trim whitespace
                if [ -n "\$pair" ]; then
                    DOCKER_ENV_ARGS="\${DOCKER_ENV_ARGS} --env \$pair"
                fi
            done
            echo "注入 MCP server API keys: \$(echo \${DOCKER_ENV_ARGS} | tr ' ' '\n' | grep -- '--env' | wc -l) 个"
        fi

        # 启动容器(限制重启次数避免无限 crash-loop 掩盖错误)
        # UV_NO_SYNC=1: 预构建镜像已含全部依赖,跳过 uv run 的项目级 re-sync
        # UV_OFFLINE=1: 强制 uvx 使用预装缓存(install_mcp_packages.sh 已在镜像构建时装好),不尝试访问 pypi.org
        # npm_config_offline=true: 强制 npx 使用预装缓存,不尝试访问 npm registry
        # HTTPS_PROXY/HTTP_PROXY: MCP server 运行时访问外部 API(wikipedia/arxiv 等)用
        # NO_PROXY: 内网地址(10.0.0.0/8)不走代理
        echo "启动 MCP-Atlas agent-environment 容器(名称: \${CONT_NAME})..."
        docker run -d \
            --name \${CONT_NAME} \
            -p 1984:1984 \
            \${DOCKER_ENV_ARGS} \
            --env UV_NO_SYNC=1 \
            --env UV_OFFLINE=1 \
            --env npm_config_offline=true \
            --env HTTPS_PROXY=http://100.64.1.68:1080 \
            --env HTTP_PROXY=http://100.64.1.68:1080 \
            --env NO_PROXY=localhost,127.0.0.1,10.0.0.0/8 \
            --restart on-failure:3 \
            ${params.MCP_ATLAS_IMAGE} 2>&1 || {
                echo "ERROR: 启动 MCP-Atlas 容器失败。"
                docker logs \${CONT_NAME} 2>&1 | tail -20 || true
                exit 1
            }

        # 快速检查容器是否立即退出(crash-loop 第一轮)
        sleep 3
        CONT_STATUS=\$(docker inspect \${CONT_NAME} --format '{{.State.Status}}' 2>/dev/null || echo "inspect_failed")
        if [ "\${CONT_STATUS}" = "exited" ]; then
            echo "ERROR: 容器在启动后 3 秒内即退出。"
            echo "退出码: \$(docker inspect \${CONT_NAME} --format '{{.State.ExitCode}}' 2>/dev/null)"
            echo "错误信息: \$(docker inspect \${CONT_NAME} --format '{{.State.Error}}' 2>/dev/null)"
            echo "容器日志(最后 50 行):"
            docker logs \${CONT_NAME} 2>&1 | tail -50 || true
            exit 1
        fi
        echo "容器状态: \${CONT_STATUS},开始等待服务就绪..."

        # 等待服务就绪(官方文档说启动需要 1+ 分钟,最长等 3 分钟)
        echo "等待 MCP-Atlas agent-environment 启动(最长 180 秒)..."
        READY=false
        for i in \$(seq 1 36); do
            sleep 5
            HTTP_CODE=\$(curl -s --connect-timeout 3 -o /dev/null -w "%{http_code}" http://localhost:1984/enabled-servers 2>/dev/null) || true
            if [ "\${HTTP_CODE}" = "200" ]; then
                READY=true
                echo "MCP-Atlas agent-environment 启动完成(等待 \$((i * 5)) 秒)"
                break
            fi
            echo "  等待中... (\$((i * 5))s, HTTP \${HTTP_CODE})"
        done

        if [ "\${READY}" != "true" ]; then
            echo "ERROR: MCP-Atlas agent-environment 在 180 秒内未就绪。"
            echo ""
            echo "=== 容器状态 ==="
            docker ps -a --filter "name=mcp-atlas-agent-env" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
            echo ""
            echo "=== 容器详细信息 ==="
            echo "Status:    \$(docker inspect \${CONT_NAME} --format '{{.State.Status}}' 2>/dev/null || echo 'N/A')"
            echo "ExitCode:  \$(docker inspect \${CONT_NAME} --format '{{.State.ExitCode}}' 2>/dev/null || echo 'N/A')"
            echo "RestartCount: \$(docker inspect \${CONT_NAME} --format '{{.RestartCount}}' 2>/dev/null || echo 'N/A')"
            echo "Error:     \$(docker inspect \${CONT_NAME} --format '{{.State.Error}}' 2>/dev/null || echo 'N/A')"
            echo ""
            echo "=== 容器日志(最后 50 行) ==="
            docker logs \${CONT_NAME} 2>&1 | tail -50 || true
            echo "=== 日志结束 ==="
            echo ""
            echo "请检查容器状态: docker logs \${CONT_NAME}"
            exit 1
        fi

        # 输出已启用的 server 列表
        echo "MCP-Atlas agent-environment 部署成功,已启用的 MCP servers:"
        curl -s http://localhost:1984/enabled-servers | python3 -m json.tool 2>/dev/null || echo "(解析失败,但服务可用)"
        echo "预检通过"
    else
        echo "MCP-Atlas agent-environment 服务不可达(HTTP \${HTTP_CODE}),且 MCP_ATLAS_AUTO_DEPLOY=false。"
        echo "请手动部署: docker pull ${params.MCP_ATLAS_IMAGE} && docker run -d -p 1984:1984 --env UV_NO_SYNC=1 --env UV_OFFLINE=1 --env npm_config_offline=true ${params.MCP_ATLAS_IMAGE}"
        echo "或设置 MCP_ATLAS_AUTO_DEPLOY=true 让 Jenkins 自动部署。"
        echo "mcp_atlas 任务将继续保留在任务列表中,但预期会失败。"
    fi
else
    echo "TASK_MCP_ATLAS=false,跳过 mcp_atlas 服务检查"
fi
ENDSSH
"""
                }
            }
        }

        stage('运行evalscope测试') {
            when {
                expression { env.CONNECTIVITY_FAILED != 'true' }
            }
            steps {
                script {
                    def taskList = []
                    if (params.TASK_MMLU_PRO)     taskList.add('mmlu_pro')
                    if (params.TASK_GPQA_DIAMOND) taskList.add('gpqa_diamond')
                    if (params.TASK_CEVAL)        taskList.add('ceval')
                    if (params.TASK_CMMLU)        taskList.add('cmmlu')
                    if (params.TASK_MATH_500)     taskList.add('math_500')
                    if (params.TASK_HELLASWAG)   taskList.add('hellaswag')
                    if (params.TASK_HUMANEVAL)    taskList.add('humaneval')
                    if (params.TASK_HUMANEVAL_PLUS) taskList.add('humaneval_plus')
                    if (params.TASK_HMMT25)        taskList.add('hmmt25')
                    if (params.TASK_HMMT26)        taskList.add('hmmt26')
                    if (params.TASK_IMO_ANSWERBENCH) taskList.add('imo_answerbench')
                    if (params.TASK_MCP_ATLAS)        taskList.add('mcp_atlas')
                    if (params.TASK_DEEP_SWE)         taskList.add('deep_swe')
                    if (taskList.isEmpty()) {
                        error '至少需要选择一个测试任务'
                    }
                    env.TASKS = taskList.join(',')

                    def modelDir = params.MODEL.contains("/") ? params.MODEL.split("/").last() : params.MODEL
                    env.MODEL_DIR = modelDir

                    env.API_KEY_STR = params.API_KEY?.toString() ?: ''
                    env.JUDGE_API_KEY_STR = params.JUDGE_API_KEY?.toString() ?: ''

                    sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                        catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                            sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << ENDSSH
set -e
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
cd ${params.WORK_DIR}
source .venv/bin/activate
echo "=== 执行Python测试脚本 ==="
python3 run_evalscope.py \\
    --tester ${params.TESTER} \\
    --build-number ${BUILD_NUMBER} \\
    --chip ${params.CHIP} \\
    --model ${params.MODEL} \\
    --base-url ${env.BASE_URL_V1} \\
    --api-key "${env.API_KEY_STR ?: 'EMPTY'}" \\
    --tasks ${env.TASKS} \\
    --examples "${params.EXAMPLES}" \\
    --eval-batch-size "${params.EVAL_BATCH_SIZE}" \\
    --temperature-fallback "${params.TEMPERATURE_FALLBACK}" \\
    --task-temperature-json '${params.TASK_TEMPERATURE_JSON}' \\
    --max-tokens "${params.MAX_TOKENS}" \\
    --top-p "${params.TOP_P}" \\
    --top-k "${params.TOP_K}" \\
    --enable-thinking "${params.ENABLE_THINKING?.toString()?.toLowerCase()}" \\
    --repeats "${params.REPEATS}" \\
    --task-repeats-json '${params.TASK_REPEATS_JSON}' \\
    --judge-strategy "${params.JUDGE_STRATEGY}" \\
    --task-judge-strategy-json '${params.TASK_JUDGE_STRATEGY_JSON}' \\
    --enable-sandbox "${params.ENABLE_SANDBOX?.toString()?.toLowerCase()}" \\
    --task-max-tokens-json '${params.TASK_MAX_TOKENS_JSON}' \\
    --task-timeout-json '${params.TASK_TIMEOUT_JSON}' \\
    --task-top-p-json '${params.TASK_TOP_P_JSON}' \\
    --dataset-args '${params.DATASET_ARGS}' \\
    --judge-model-id "${params.JUDGE_MODEL_ID}" \\
    --judge-api-url "${params.JUDGE_API_URL}" \\
    --judge-api-key "${env.JUDGE_API_KEY_STR ?: 'EMPTY'}" \\
    --description "${params.DESCRIPTION}"
echo "=== 测试脚本执行结束 ==="
echo "=== 输出目录 ==="
find output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${env.MODEL_DIR}/ -type f
ENDSSH
"""
                        }
                    }
                }
            }
        }

        stage('拉取测试结果') {
            steps {
                sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                    catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                        script {
                            def remoteDir = "${params.WORK_DIR}/output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${env.MODEL_DIR}"
                            def localDir = "reports/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}"
                            def localBuildsDir = "builds/${BUILD_NUMBER}"
                            env.RESULT_DIR = "output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${env.MODEL_DIR}"
                            echo "拉取测试结果目录: ${remoteDir}"

                            if (env.CONNECTIVITY_FAILED == 'true') {
                                echo "=== 连通性检查未通过,跳过测试结果目录拉取,仅拉取连通性预检日志 ==="
                            } else {
                                sh """
mkdir -p ${localDir}
scp -o StrictHostKeyChecking=no \
    -r ${REMOTE_USER}@${REMOTE_HOST}:${remoteDir} \
    ${localDir}/
echo "=== 拉取结果 ==="
find ${localDir}/ -type f
"""
                            }

                            sh """
mkdir -p ${localBuildsDir}
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ${REMOTE_USER}@${REMOTE_HOST}:/tmp/evalscope_connectivity_${BUILD_NUMBER}.log \
    ./${localBuildsDir}/evalscope_connectivity_${BUILD_NUMBER}.log 2>/dev/null \
    && echo "连通性预检日志已拉取: ${localBuildsDir}/evalscope_connectivity_${BUILD_NUMBER}.log" \
    || echo "WARN: 连通性预检日志拉取失败"
"""
                        }
                    }
                }
            }
        }

        stage('发送邮件') {
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                    script {
                        def logFileBase = "reports/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${env.MODEL_DIR}"

                        // 找到 evalscope-<tasks>.log
                        def logFiles = findFiles(glob: "${logFileBase}/**/evalscope-*.log")
                        def logFile = ""
                        def logContent = ""
                        if (logFiles.length > 0) {
                            logFile = logFiles[0].path
                            logContent = readFile(logFile)
                        }

                        // 连通性预检失败检测
                        def connectivityLogPath = "builds/${BUILD_NUMBER}/evalscope_connectivity_${BUILD_NUMBER}.log"
                        def connectivityLogContent = ""
                        def failureReason = ""
                        def connectivityFailureReason = ""
                        if (fileExists(connectivityLogPath)) {
                            connectivityLogContent = readFile(connectivityLogPath)
                            if (connectivityLogContent.contains("API 连通性检查失败") ||
                                connectivityLogContent.contains("Chat Completions 接口检查失败")) {
                                failureReason = "连通性检查未通过"
                                def logLines = connectivityLogContent.split('\n')
                                def collected = []
                                def inFailureSection = false
                                for (def ll : logLines) {
                                    if (ll.contains("检查 API 连通性") || ll.contains("Chat Completions 接口检查")) {
                                        inFailureSection = true
                                    }
                                    if (inFailureSection) {
                                        if (!collected.isEmpty() && ll.trim().startsWith("===") &&
                                            !ll.contains("检查 API 连通性") && !ll.contains("Chat Completions 接口检查")) {
                                            break
                                        }
                                        collected.add(ll)
                                    }
                                }
                                connectivityFailureReason = collected.join('\n').trim()
                            }
                        }
                        if (!failureReason && env.CONNECTIVITY_FAILED == 'true') {
                            failureReason = "连通性检查未通过"
                            connectivityFailureReason = "API 连通性或 Chat Completions 接口检查失败,具体日志未拉到,详见 Jenkins 控制台输出。"
                        }

                        // 从 evalscope report JSON 提取每个任务的得分
                        // report 路径: <logFileBase>/<timestamp>/<evalscope-internal-timestamp>/reports/<model>/<dataset>.json
                        def taskScores = [:]
                        def taskMetricsHtml = ""
                        def taskSummaryRows = ""
                        if (!failureReason) {
                            // evalscope 的 report 文件名为 <dataset_name>.json,位于 reports/<model_name>/ 下
                            // glob 递归匹配 reports/**/<dataset>.json
                            def reportFiles = findFiles(glob: "${logFileBase}/**/reports/**/*.json")
                            for (def rf : reportFiles) {
                                def json = readJSON(file: rf.path)
                                def taskName = json.dataset_name ?: json.name ?: "unknown"
                                def score = json.score
                                def scoreStr = "N/A"
                                if (score != null) {
                                    scoreStr = String.format("%.2f%%", (score as Double) * 100)
                                }
                                taskScores[taskName] = scoreStr
                                taskSummaryRows += "<tr><td>${taskName}</td><td>${scoreStr}</td></tr>"

                                // 单任务详情行(包含 metric / category / subset 明细)
                                def detailRows = ""
                                def metrics = json.metrics ?: []
                                for (def m : metrics) {
                                    def metricName = m.name ?: "score"
                                    def metricScore = m.score
                                    def metricScoreStr = metricScore != null ? String.format("%.2f%%", (metricScore as Double) * 100) : "N/A"
                                    detailRows += "<tr class=\"score-highlight\"><td>${taskName}</td><td>${metricName} (overall)</td><td>${metricScoreStr}</td></tr>"
                                    def categories = m.categories ?: []
                                    for (def c : categories) {
                                        def catName = c.name
                                        if (catName instanceof List) {
                                            catName = catName.collect { it.toString() }.join(' / ')
                                        }
                                        def catScore = c.score
                                        def catScoreStr = catScore != null ? String.format("%.2f%%", (catScore as Double) * 100) : "N/A"
                                        def catNum = c.num ?: 0
                                        detailRows += "<tr><td>${taskName}</td><td>${catName} (n=${catNum})</td><td>${catScoreStr}</td></tr>"
                                        def subsets = c.subsets ?: []
                                        for (def s : subsets) {
                                            def subName = s.name
                                            def subScore = s.score
                                            def subScoreStr = subScore != null ? String.format("%.4f", (subScore as Double) * 100) + "%" : "N/A"
                                            def subNum = s.num ?: 0
                                            if (subName != null) {
                                                detailRows += "<tr><td>${taskName}</td><td>&nbsp;&nbsp;&nbsp;${subName} (n=${subNum})</td><td>${subScoreStr}</td></tr>"
                                            }
                                        }
                                    }
                                }

                                taskMetricsHtml += """
            <div class="section-title">${taskName} 任务测试结果</div>
            <table>
                <tr style="background-color: #e3f2fd;"><th>任务</th><th>指标 / 子集</th><th>值</th></tr>
                ${detailRows}
            </table>
            <p style="font-size: 12px; color: #666;">report: ${rf.path}</p>
"""
                                // 性能指标
                                def perf = json.perf_metrics
                                if (perf != null && perf.summary != null) {
                                    def sum = perf.summary
                                    def latency = sum.latency
                                    def throughput = sum.throughput
                                    def usage = sum.usage
                                    def ttft = sum.ttft
                                    def nSamples = sum.n_samples ?: 'N/A'
                                    def perfLines = "samples: ${nSamples}"
                                    if (latency != null && latency.avg != null) {
                                        perfLines += " | latency avg: ${latency.avg}s"
                                    }
                                    if (throughput != null && throughput.avg_output_tps != null) {
                                        perfLines += " | output tps: ${throughput.avg_output_tps}"
                                    }
                                    if (ttft != null && ttft.avg != null) {
                                        perfLines += " | TTFT avg: ${ttft.avg}s"
                                    }
                                    if (usage != null && usage.total_tokens_count != null) {
                                        perfLines += " | total tokens: ${usage.total_tokens_count}"
                                    }
                                    taskMetricsHtml += """
            <p style="font-size: 12px; color: #666;">${perfLines}</p>
"""
                                }
                            }
                        }
                        if (failureReason) {
                            taskSummaryRows = "<tr><td colspan='2'>连通性检查未通过,任务未执行</td></tr>"
                        } else if (taskSummaryRows.isEmpty()) {
                            taskSummaryRows = "<tr><td colspan='2'>无任务执行或未找到 report JSON</td></tr>"
                        }

                        def hasResult = !taskScores.isEmpty()
                        def resultStatus = hasResult ? "完成" : "失败/无结果"
                        if (failureReason) {
                            resultStatus = "失败/${failureReason}"
                        }

                        // 连通性失败 HTML 块
                        def connectivityFailureHtml = ""
                        if (failureReason) {
                            def escapedReason = (connectivityFailureReason ?: '')
                                .replace('&', '&amp;')
                                .replace('<', '&lt;')
                                .replace('>', '&gt;')
                            connectivityFailureHtml = """
            <div style="background-color: #ffebee; color: #000000; border-left: 4px solid #d32f2f; padding: 12px 15px; margin-top: 15px; border-radius: 3px;">
                <h3 style="color: #d32f2f; margin-top: 0; margin-bottom: 8px;">⚠️ 连通性检查未通过</h3>
                <p style="margin-top: 0; margin-bottom: 8px; color: #000000;">本次测试未能正常执行用例,原因是 API 连通性检查失败:</p>
                <pre style="background-color: #ffffff; color: #000000; padding: 10px; border-radius: 3px; overflow-x: auto; white-space: pre-wrap; margin: 0; font-family: Menlo, Consolas, monospace; font-size: 12px;">${escapedReason}</pre>
            </div>"""
                        }

                        def emailBody = """
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: #fff; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .header { background-color: ${hasResult ? '#4CAF50' : '#f44336'}; color: white; padding: 20px; border-radius: 5px 5px 0 0; }
        .content { padding: 20px; }
        table { border-collapse: collapse; width: 100%; margin-top: 15px; font-size: 13px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .footer { margin-top: 20px; padding: 15px; background-color: #f9f9f9; border-radius: 0 0 5px 5px; color: #666; font-size: 12px; }
        .section-title { background-color: #e3f2fd; padding: 10px; margin-top: 20px; border-radius: 3px; font-weight: bold; }
        .score-highlight { background-color: #c8e6c9; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2 style="margin: 0;">evalscope 精度测试报告 - 构建 #${BUILD_NUMBER}</h2>
        </div>
        <div class="content">
            <h3>测试概要</h3>
            <table>
                <tr><th>项目</th><td>值</td></tr>
                <tr><th>构建编号</th><td>#${BUILD_NUMBER}</td></tr>
                <tr><th>模型服务描述</th><td>${params.DESCRIPTION}</td></tr>
                <tr><th>测试人员</th><td>${params.TESTER}</td></tr>
                <tr><th>芯片平台</th><td>${params.CHIP}</td></tr>
                <tr><th>推理框架</th><td>${params.ENGINE}</td></tr>
                <tr><th>PD分离模式</th><td>${params.PD}</td></tr>
                <tr><th>模型名称</th><td>${params.MODEL}</td></tr>
                <tr><th>API地址</th><td>${params.BASE_URL}</td></tr>
                <tr><th>测试任务</th><td>${env.TASKS ?: (failureReason ? '未执行(连通性检查未通过)' : 'N/A')}</td></tr>
                <tr><th>样本限制</th><td>${params.EXAMPLES ?: '无限制'}</td></tr>
                <tr><th>repeats</th><td>${params.REPEATS ?: 'default 1'}</td></tr>
                <tr><th>eval-batch-size</th><td>${params.EVAL_BATCH_SIZE}</td></tr>
                <tr><th>温度(兜底)</th><td>${params.TEMPERATURE_FALLBACK}</td></tr>
                <tr><th>per-task temperature JSON</th><td>${params.TASK_TEMPERATURE_JSON ?: 'N/A'}</td></tr>
                <tr><th>per-task repeats JSON</th><td>${params.TASK_REPEATS_JSON ?: 'N/A'}</td></tr>
                <tr><th>max_tokens</th><td>${params.MAX_TOKENS ?: 'unlimited'}</td></tr>
                <tr><th>top_p / top_k</th><td>${params.TOP_P} / ${params.TOP_K}</td></tr>
                <tr><th>enable_thinking</th><td>${params.ENABLE_THINKING}</td></tr>
                <tr><th>judge_strategy</th><td>${params.JUDGE_STRATEGY}</td></tr>
                <tr><th>per-task judge_strategy JSON</th><td>${params.TASK_JUDGE_STRATEGY_JSON ?: 'N/A'}</td></tr>
                <tr><th>裁判模型</th><td>${params.JUDGE_MODEL_ID}</td></tr>
                <tr><th>裁判模型API</th><td>${params.JUDGE_API_URL}</td></tr>
                <tr><th>per-task max_tokens JSON</th><td>${params.TASK_MAX_TOKENS_JSON ?: 'N/A'}</td></tr>
                <tr><th>per-task timeout JSON</th><td>${params.TASK_TIMEOUT_JSON ?: 'N/A'}</td></tr>
                <tr><th>per-task top_p JSON</th><td>${params.TASK_TOP_P_JSON ?: 'N/A'}</td></tr>
                <tr><th>dataset_args</th><td>${params.DATASET_ARGS ?: 'N/A'}</td></tr>
                <tr><th>MCP-Atlas 镜像</th><td>${params.MCP_ATLAS_IMAGE}</td></tr>
                <tr><th>MCP-Atlas 自动部署</th><td>${params.MCP_ATLAS_AUTO_DEPLOY}</td></tr>
                <tr><th>MCP-Atlas API Keys</th><td>${params.MCP_ATLAS_API_KEYS ?: 'N/A(仅启用 20 个无 key server)'}</td></tr>
                <tr><th>执行时间</th><td>${currentBuild.durationString}</td></tr>
                <tr><th>测试状态</th><td>${resultStatus}</td></tr>
                <tr><th>构建状态</th><td>${currentBuild.currentResult}</td></tr>
            </table>

            ${connectivityFailureHtml}

            <h3>任务汇总得分</h3>
            <table>
                <tr style="background-color: #e3f2fd;"><th>任务名称</th><th>得分</th></tr>
                ${taskSummaryRows}
            </table>

            ${taskMetricsHtml}

            <h3>输出目录</h3>
            <p>${failureReason ? 'N/A (连通性检查未通过)' : (env.RESULT_DIR ?: 'N/A')}</p>

            <p style="margin-top: 20px;">详细日志请查看附件。</p>
            <p>Jenkins 构建地址: <a href="${env.BUILD_URL}">${env.BUILD_URL}</a></p>
        </div>
        <div class="footer">
            此邮件由 Jenkins 自动发送，请勿回复。
        </div>
    </div>
</body>
</html>"""

                        echo "=== evalscope 测试结果 ==="
                        echo "Build Number: ${BUILD_NUMBER}"
                        echo "结果目录: ${env.RESULT_DIR ?: 'N/A'}"
                        echo "测试状态: ${resultStatus}"
                        taskScores.each { k, v -> println("  ${k} 得分: ${v}") }

                        def attachPattern = ""
                        def attachPatterns = []
                        if (logFile) {
                            attachPatterns.add(logFile)
                        }
                        if (fileExists("builds/${BUILD_NUMBER}/evalscope_connectivity_${BUILD_NUMBER}.log")) {
                            attachPatterns.add("builds/${BUILD_NUMBER}/evalscope_connectivity_${BUILD_NUMBER}.log")
                        }
                        attachPattern = attachPatterns.join(',')
                        emailext(
                            subject: "[模型推理 - evalscope精度测试报告] #${BUILD_NUMBER} ${params.CHIP} - ${params.MODEL}",
                            body: emailBody,
                            to: "${params.RECIPIENTS}",
                            mimeType: 'text/html',
                            attachmentsPattern: attachPattern
                        )
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                archiveArtifacts artifacts: "reports/${params.TESTER}/${BUILD_NUMBER}/**,builds/${BUILD_NUMBER}/**", allowEmptyArchive: true, fingerprint: true
                echo "构建完成: ${currentBuild.currentResult}"
            }
        }
        cleanup {
            cleanWs()
        }
    }
}
