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
        booleanParam(name: 'TASK_AIME26',      defaultValue: true,  description: '运行 aime26 (AIME 2026 美国数学邀请赛,30 题,0-shot,numeric accuracy;数学推理题,答案需 \\boxed{} 格式)')
        booleanParam(name: 'TASK_GPQA_DIAMOND', defaultValue: true,  description: '运行 gpqa_diamond (博士级 4 选择,0-shot,accuracy)')
        booleanParam(name: 'TASK_CEVAL',        defaultValue: true,  description: '运行 ceval (中文多学科多选,52 学科,5-shot,accuracy)')
        booleanParam(name: 'TASK_CMMLU',        defaultValue: false, description: '运行 cmmlu (中文多学科多选,67 学科,0-shot,accuracy)')
        booleanParam(name: 'TASK_MATH_500',     defaultValue: true,  description: '运行 math_500 (数学推理,500 题,0-shot,accuracy)')
        booleanParam(name: 'TASK_HELLASWAG',   defaultValue: false, description: '运行 hellaswag (常识推理,4 选择,0-shot,accuracy)')
        booleanParam(name: 'TASK_HUMANEVAL',    defaultValue: false, description: '运行 humaneval (Python 代码生成,164 题,0-shot,pass@1;需执行模型生成的代码,启用 sandbox 见 evalscope 文档)')
        booleanParam(name: 'TASK_HUMANEVAL_PLUS', defaultValue: true,  description: '运行 humaneval_plus (HumanEval 增强版,164 题,测试用例数万级,0-shot,pass@1;review_timeout=300s,需 sandbox 且使用内置 numpy 的自定义 docker 镜像)')
        booleanParam(name: 'TASK_HMMT25',        defaultValue: false, description: '运行 hmmt25 (HMMT 2025年2月数学竞赛,30 题,0-shot,numeric accuracy;数学推理题,答案需 \\boxed{} 格式)')
        booleanParam(name: 'TASK_HMMT26',        defaultValue: true,  description: '运行 hmmt26 (HMMT 2026年2月数学竞赛,33 题,0-shot,numeric accuracy;数学推理题,答案需 \\boxed{} 格式)')
        booleanParam(name: 'TASK_IMO_ANSWERBENCH', defaultValue: false, description: '运行 imo_answerbench (IMO 短名单奥数题,400 题,0-shot,numeric accuracy;llm_judge_default=True,有裁判模型时自动走 LLM judge,无裁判模型时回退 rule(numeric math_equal);答案含区间/集合/分数等复杂 LaTeX 形式,部分比对可能不如纯数字精确)')
        booleanParam(name: 'TASK_MCP_ATLAS',          defaultValue: false, description: '运行 mcp_atlas (Scale AI MCP 工具使用智能体,89 题,multi-turn function-calling,LLM judge coverage_score/pass_rate;MCP-Atlas agent-environment Docker 服务支持自动部署,见 MCP_ATLAS_AUTO_DEPLOY 参数;20 个无需 API key 的 MCP server 默认启用,约 40-50 个任务可评测,配置 MCP_ATLAS_API_KEYS 可启用更多 server;被测模型驱动 AgentLoop,裁判模型逐 claim 评判;依赖 JUDGE_MODEL_ID/JUDGE_API_URL/JUDGE_API_KEY 参数)')

        booleanParam(name: 'TASK_DEEP_SWE',           defaultValue: false, description: '运行 deep_swe (仓库级软件工程编码智能体,113 题,multi-turn agent,verifier 二值奖励 acc;通过 Pier Python API 运行,需 Docker + pip install evalscope[deep_swe] + Python>=3.12;Pier 内置 mini-swe-agent 驱动,默认 litellm model_class 兼容 OpenAI chat/completions 端点;默认 temperature=1.0 top_p=1.0 timeout=48h max_tokens=400k(官方 GLM-5.2 为 2h,低性能机器调大到 48h 兜底,可在 TASK_TIMEOUT_JSON 进一步调整);每个任务在隔离容器中运行,2 CPU/8GB RAM/无网络,串行执行耗时较长)')

        string(name: 'EXAMPLES',        defaultValue: '',      description: '样本数限制(空 = 不限制;传给 evalscope --limit。int=数量,float=比例)')
        string(name: 'REPEATS',         defaultValue: '',      description: '重复次数(k-metrics,传给 evalscope --repeats。空 = 默认 1)')
        string(name: 'EVAL_BATCH_SIZE', defaultValue: '8',     description: '并发批大小(对应 evalscope --eval-batch-size,默认 8)')
        string(name: 'TEMPERATURE_FALLBACK', defaultValue: '1.0', description: '采样温度兜底值(仅当 TASK_TEMPERATURE_JSON 未命中某任务时使用;默认 1.0,适配 thinking 模式推理模型)')
        string(name: 'MAX_TOKENS',      defaultValue: '32768', description: '生成最大 token 数(默认 32768;清空 = 不指定)')
        string(name: 'TOP_P',           defaultValue: '0.95',  description: 'nucleus top_p(默认 0.95)')
        string(name: 'TOP_K',           defaultValue: '20',    description: 'top-k 采样(默认 20)')
        choice(name: 'ENABLE_THINKING', choices: ['true', 'false'], description: '启用 thinking 模式(默认 true)')
        choice(name: 'JUDGE_STRATEGY',  choices: ['auto', 'rule', 'llm', 'llm_recall'], description: '评分策略(默认 auto;多选题用 rule,主观题用 llm)')
        text(name: 'TASK_JUDGE_STRATEGY_JSON', defaultValue: '', description: '按任务覆盖 judge_strategy 的 JSON。默认为空:imo_answerbench 在有裁判模型(JUDGE_MODEL_ID 非空)时走 auto 自动启用 LLM judge,无裁判模型时自动回退 rule(numeric math_equal);如需手动指定可追加,例: {"imo_answerbench":"rule","simple_qa":"llm"}(需配套 judge_model_args)')
        choice(name: 'ENABLE_SANDBOX', choices: ['true', 'false'], description: '启用 sandbox 执行(默认 true)。true 时给所有任务拼 --sandbox {"enabled": true},仅对 humaneval 等 CodeExecutionSandboxMixin 任务生效。启用前环境检查 stage 会预装 evalscope[sandbox] 并校验 Docker 可用')
        text(name: 'TASK_MAX_TOKENS_JSON', defaultValue: '{"gpqa_diamond":131072,"aime26":131072,"mcp_atlas":4096,"deep_swe":409600}', description: '按任务覆盖 max_tokens 的 JSON,默认 gpqa_diamond=131072,aime26=131072(数学推理需大输出窗口),mcp_atlas=4096(多轮 AgentLoop,单步工具调用 args/短回复够用,过大会触发长思考导致超时),deep_swe=409600(400k,编码 agent 需大输出窗口),其余任务用 MAX_TOKENS 默认值;可按需追加,例: {"mmlu_pro":4096,"gpqa_diamond":131072}')
        text(name: 'TASK_TIMEOUT_JSON', defaultValue: '{"mcp_atlas":7200,"deep_swe":172800}', description: '按任务覆盖模型调用超时(秒)的 JSON,默认 mcp_atlas=7200(2 小时,多轮 AgentLoop 配合 max_tokens=4096 + thinking 仍可能耗时长),deep_swe=172800(48 小时,仓库级编码 agent 串行构建+验证,低性能机器或大仓库需更长 agent_timeout),其余任务用内置默认 3600;可按需追加,例: {"mcp_atlas":7200,"humaneval":1800}')
        text(name: 'TASK_TOP_P_JSON', defaultValue: '{"deep_swe":1.0}', description: '按任务覆盖 top_p 的 JSON,默认 deep_swe=1.0(编码 agent 高随机性探索,全局默认 0.95);可按需追加,例: {"deep_swe":1.0,"humaneval":0.95}')
        choice(name: 'TASK_TEMPERATURE_JSON', choices: ['{"mmlu_pro":1.0,"aime26":1.0,"gpqa_diamond":1.0,"ceval":1.0,"cmmlu":1.0,"math_500":1.0,"hellaswag":1.0,"humaneval":1.0,"humaneval_plus":1.0,"hmmt25":1.0,"hmmt26":1.0,"imo_answerbench":1.0,"mcp_atlas":1.0,"deep_swe":1.0}', '{"mmlu_pro":0.0,"aime26":0.6,"gpqa_diamond":0.0,"ceval":0.0,"cmmlu":0.0,"math_500":0.6,"hellaswag":0.0,"humaneval":0.2,"humaneval_plus":0.2,"hmmt25":0.6,"hmmt26":0.6,"imo_answerbench":0.6,"mcp_atlas":0.0,"deep_swe":1.0}'], description: '按任务指定采样温度的 JSON。选项1(thinking 模式,默认):全部任务 1.0,适配 GLM-5.2/DeepSeek-V4/Kimi-K3 推理模型(官方均推荐 1.0;Kimi-K3 强制 1.0)。选项2(R1/instruct 模式):多选题 0.0,数学推理 0.6,代码 0.2,工具调用 0.0,编码 agent 1.0;适配 DeepSeek-R1 系(推荐 0.5-0.7)或非 thinking instruct 模型(greedy)。如需更细粒度控制可手动输入 JSON')
        text(name: 'TASK_REPEATS_JSON', defaultValue: '', description: '按任务覆盖 repeats 的 JSON,例: {"humaneval":5,"humaneval_plus":5}。命中任务使用对应值,未命中任务用全局 REPEATS;为空则全部用全局 REPEATS。推荐:humaneval/humaneval_plus 设 5 算 pass@1..pass@5,其余 greedy 基准(mmlu_pro/aime26/gpqa_diamond/ceval/cmmlu/hellaswag/math_500/hmmt25/hmmt26/imo_answerbench)保持 1 避免 N 倍空跑')
        text(name: 'DATASET_ARGS',      defaultValue: '',      description: '数据集参数 JSON,例: {"mmlu_pro":{"subset_list":["math","physics"]}}')

        string(name: 'USE_CACHE',     defaultValue: '', description: '[断点续跑] 上次运行的输出目录(相对 WORK_DIR 或绝对路径),非空时启用续跑:已完成的题目直接复用缓存,只跑未完成的题目。典型填法: output/<tester>/<build_number>/<chip>/<model>/<timestamp>')
        booleanParam(name: 'RERUN_REVIEW', defaultValue: false, description: '仅 USE_CACHE 启用时生效。开启时强制重算评分(删除 reviews 缓存),predictions 缓存仍复用;适合仅换了评分逻辑 / judge 模型的场景')

        string(name: 'DESCRIPTION', defaultValue: '', description: '模型服务描述信息(仅用于邮件展示)')
        text(name: 'RECIPIENTS',    defaultValue: 'liwt@zetyun.com', description: '报告邮件接收者(逗号分隔)')
        string(name: 'WORK_DIR',    defaultValue: '/dingofs/data2/userdata/liwt/maas-image/evalscope-test', description: '远程仓库目录,请不要改动')

        // MCP-Atlas agent-environment 自动部署
        string(name: 'MCP_ATLAS_IMAGE', defaultValue: 'ghcr.io/scaleapi/mcp-atlas:1.2.7', description: 'MCP-Atlas agent-environment Docker 镜像(Scale AI 官方预构建)。当 TASK_MCP_ATLAS=true 且服务未运行时,Jenkins 自动拉取并启动此镜像,监听 localhost:1984。20 个无需 API key 的 MCP server 默认启用')
        choice(name: 'MCP_ATLAS_AUTO_DEPLOY', choices: ['true', 'false'], description: '自动部署 MCP-Atlas agent-environment(默认 true)。服务未运行时自动 pull + docker run;false 则仅检查不自动启动,需手动准备')
        string(name: 'MCP_ATLAS_API_KEYS', defaultValue: 'MONGODB_URI=mongodb://admin:abc123@host.docker.internal:27017/?authSource=admin,GITHUB_TOKEN=ghp_REPLACE_WITH_YOUR_TOKEN', description: 'MCP server API keys,逗号分隔 KEY=VALUE 对。默认值含:1) MongoDB(宿主机已部署,使用 host.docker.internal:27017,容器内经 --add-host 映射到宿主机;authSource=admin);2) GitHub PAT 占位符(替换 ghp_REPLACE_WITH_YOUR_TOKEN 为真实 token 即可启用 github server)。格式: KEY1=VALUE1,KEY2=VALUE2。其他可选 key:BRAVE_API_KEY=xxx — Brave Search(https://brave.com/search/api/)。删除某项则对应 server 不启用')
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
                    println("任务 AIME26:       ${params.TASK_AIME26}")
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
                    println("use_cache:        ${params.USE_CACHE ?: 'N/A (全新跑)'}")
                    println("rerun_review:     ${params.RERUN_REVIEW}")
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
    export https_proxy=http://10.201.136.68:1080
    export http_proxy=http://10.201.136.68:1080
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
    echo "从官方源 https://pypi.org/simple/ 安装 evalscope(extras: \${EXTRAS:-none})..."
    if [ -n "\${EXTRAS}" ]; then
        if UV_INDEX_URL="https://pypi.org/simple/" uv pip install -e ".[\${EXTRAS}]" 2>&1; then
            EXTRAS_OK=true
        fi
    else
        if UV_INDEX_URL="https://pypi.org/simple/" uv pip install -e . 2>&1; then
            EXTRAS_OK=true
        fi
    fi
    unset https_proxy
    unset http_proxy
    deactivate
    if [ "\${EXTRAS_OK}" != "true" ]; then
        echo "ERROR: evalscope 安装失败(官方源 pypi.org 不可用)。"
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
            export https_proxy=http://10.201.136.68:1080
            export http_proxy=http://10.201.136.68:1080
            SANDBOX_OK=false
            echo "从官方源 https://pypi.org/simple/ 补装 sandbox 依赖..."
            if UV_INDEX_URL="https://pypi.org/simple/" uv pip install -r requirements/sandbox.txt 2>&1; then
                SANDBOX_OK=true
            fi
            unset https_proxy
            unset http_proxy
            if [ "\${SANDBOX_OK}" != "true" ]; then
                echo "ERROR: sandbox 依赖补装失败(官方源 pypi.org 不可用)。"
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
            export https_proxy=http://10.201.136.68:1080
            export http_proxy=http://10.201.136.68:1080
            DEEP_SWE_OK=false
            echo "从官方源 https://pypi.org/simple/ 补装 deep_swe 依赖..."
            if UV_INDEX_URL="https://pypi.org/simple/" uv pip install -r evalscope/benchmarks/deep_swe/requirements.txt 2>&1; then
                DEEP_SWE_OK=true
            fi
            unset https_proxy
            unset http_proxy
            if [ "\${DEEP_SWE_OK}" != "true" ]; then
                echo "ERROR: deep_swe 依赖补装失败(官方源 pypi.org 不可用)。"
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
                export https_proxy=http://10.201.136.68:1080
                export http_proxy=http://10.201.136.68:1080
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

    # === 检测宿主机 apt mirror(用于 egress-proxy 预构建 + noProxy 配置)===
    # 宿主机 apt 能正常工作的 mirror,Docker 容器经默认 bridge NAT 也能访问。
    # 关键:必须将 mirror hostname 加入 noProxy — Docker 的 noProxy CIDR(如 10.0.0.0/8)
    # 只对 IP-address 目标生效,不对 hostname 生效。若不加入,Pier 的 egress-proxy 构建中
    # apt-get update 会经代理(10.201.136.68:1080)访问内网 mirror,代理返回 502 Bad Gateway。
    HOST_MIRROR=""
    if [ -f /etc/apt/sources.list ]; then
        HOST_MIRROR=\$(grep -E '^deb ' /etc/apt/sources.list | head -1 | awk '{print \$2}' | sed 's|/ubuntu.*||' | sed 's|/\$||')
    fi
    if [ -z "\${HOST_MIRROR}" ] && [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
        HOST_MIRROR=\$(awk -F': ' '/^URIs:/ {print \$2}' /etc/apt/sources.list.d/ubuntu.sources | head -1 | sed 's|/ubuntu.*||' | sed 's|/\$||')
    fi
    echo "宿主机 apt mirror: \${HOST_MIRROR:-<未检测到>}"
    # 从 mirror URL 提取 hostname(例 http://nexus.hd-04.zetyun.cn:8081/repository → nexus.hd-04.zetyun.cn)
    MIRROR_HOST=""
    if [ -n "\${HOST_MIRROR}" ]; then
        MIRROR_HOST=\$(echo "\${HOST_MIRROR}" | sed -E 's|^[a-zA-Z]+://||; s|:[0-9]+.*||; s|/.*||')
    fi
    echo "Mirror hostname for noProxy: \${MIRROR_HOST:-<none>}"
    # 构建 noProxy 列表:基础 + mirror hostname(让 egress-proxy 构建中的 apt 绕过代理直连 mirror)
    NO_PROXY_LIST="localhost,127.0.0.1,10.0.0.0/8"
    if [ -n "\${MIRROR_HOST}" ]; then
        NO_PROXY_LIST="\${NO_PROXY_LIST},\${MIRROR_HOST}"
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
c['proxies'] = {'default': {'httpProxy': 'http://10.201.136.68:1080', 'httpsProxy': 'http://10.201.136.68:1080', 'noProxy': '\${NO_PROXY_LIST}'}}
with open(p, 'w') as f:
    json.dump(c, f, indent=2)
print('Docker 构建代理已配置: http://10.201.136.68:1080 (noProxy: \${NO_PROXY_LIST})')
"

    # 配置 Docker daemon 代理(systemd drop-in)
    # ~/.docker/config.json 只影响 docker run 的容器环境变量和 docker build 的 build-arg,
    # 但 docker build / docker pull 拉取 base image 时用的是 dockerd 自身的环境变量(来自 systemd drop-in)。
    # 如果 dockerd 的代理地址过期(如 100.64.1.68:1080),buildkit 拉取 base image 会超时。
    # 这里检测并更新 systemd drop-in,如果代理地址已变更则重启 Docker daemon。
    echo "=== 检查 Docker daemon 代理(systemd drop-in) ==="
    DROPIN_DIR=/etc/systemd/system/docker.service.d
    DROPIN_FILE=\${DROPIN_DIR}/http-proxy.conf
    NEEDS_DAEMON_PROXY_UPDATE=false

    # 检查当前 daemon 的代理环境变量
    CURRENT_DAEMON_PROXY=\$(systemctl show docker --property=Environment 2>/dev/null | grep -o 'HTTPS_PROXY=[^ ]*' | cut -d= -f2 || echo "")
    echo "当前 Docker daemon 代理: \${CURRENT_DAEMON_PROXY:-<无>}"
    if [ "\${CURRENT_DAEMON_PROXY}" != "http://10.201.136.68:1080" ]; then
        NEEDS_DAEMON_PROXY_UPDATE=true
    fi

    if [ "\${NEEDS_DAEMON_PROXY_UPDATE}" = "true" ]; then
        echo "Docker daemon 代理需要更新 → 写入 systemd drop-in"
        mkdir -p \${DROPIN_DIR}
        cat > "\${DROPIN_FILE}" << 'PROXY_EOF'
[Service]
Environment="HTTP_PROXY=http://10.201.136.68:1080"
Environment="HTTPS_PROXY=http://10.201.136.68:1080"
Environment="NO_PROXY=localhost,127.0.0.1,10.0.0.0/8"
PROXY_EOF
        systemctl daemon-reload
        echo "正在重启 Docker daemon(应用新代理地址)..."
        systemctl restart docker
        # 等待 Docker 恢复
        for i in \$(seq 1 12); do
            if docker info >/dev/null 2>&1; then
                echo "Docker daemon 已恢复(\${i} 秒)"
                break
            fi
            sleep 1
        done
        if ! docker info >/dev/null 2>&1; then
            echo "ERROR: Docker daemon 在重启后 12 秒内未恢复"
            exit 1
        fi
        echo "Docker daemon 代理已更新为 http://10.201.136.68:1080"
    else
        echo "Docker daemon 代理已是最新,无需更新"
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
    if [ "\${NEED_DEEP_SWE}" = "true" ]; then
        echo "=== Pre-building ubuntu:24.04 with host apt mirror + egress-proxy packages ==="
        NEEDS_REBUILD=false
        if ! docker image inspect ubuntu:24.04 >/dev/null 2>&1; then
            NEEDS_REBUILD=true
        elif ! docker inspect ubuntu:24.04 --format '{{json .Config.Labels}}' 2>/dev/null | grep -q "egress-proxy-prebuilt"; then
            NEEDS_REBUILD=true
        fi
        if [ "\${NEEDS_REBUILD}" = "true" ]; then
            # HOST_MIRROR 已在前面检测(同时用于 noProxy 配置)

            # Pull base image (Docker Hub via proxy — HTTPS works for Docker pulls)
            export https_proxy=http://10.201.136.68:1080
            export http_proxy=http://10.201.136.68:1080
            docker pull ubuntu:24.04
            unset https_proxy http_proxy

            if [ -n "\${HOST_MIRROR}" ]; then
                # 用宿主机的 apt mirror 替换 ubuntu:24.04 的 apt 源
                # 宿主机网络可直接访问该 mirror(内网镜像),Docker build 用 --network=host 共享宿主机网络
                echo "使用宿主机 mirror 构建: \${HOST_MIRROR}"
                docker build --network=host \
                    --build-arg http_proxy= --build-arg https_proxy= --build-arg HTTP_PROXY= --build-arg HTTPS_PROXY= --build-arg no_proxy=* \
                    -t ubuntu:24.04 --label egress-proxy-prebuilt=true - <<DOCKERFILE
FROM ubuntu:24.04
RUN echo "deb \${HOST_MIRROR}/ubuntu noble main restricted universe multiverse" > /etc/apt/sources.list && \
    echo "deb \${HOST_MIRROR}/ubuntu noble-updates main restricted universe multiverse" >> /etc/apt/sources.list
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
                echo "ERROR: Pre-installed packages verification failed."
                echo "The host apt mirror may not support Ubuntu 24.04 (noble) packages."
                echo "Host mirror: \${HOST_MIRROR:-<none>}"
                echo "Manual fix: build a custom ubuntu:24.04 image with squid pre-installed."
                exit 1
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
    if [ "\${NEED_DEEP_SWE}" = "true" ]; then
        echo "=== Patching Pier for proxy compatibility (agent + compose + docker) ==="
        source ${params.WORK_DIR}/.venv/bin/activate
        python3 ${params.WORK_DIR}/scripts/patch_pier_apt.py 2>&1
        PATCH_EXIT=\$?
        deactivate
        if [ "\${PATCH_EXIT}" -ne 0 ]; then
            echo "WARN: Pier patch failed (exit \${PATCH_EXIT}), deep_swe may fail"
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
    # 仅 HTTP 200 不够:旧容器可能因 uvx Python 版本问题导致部分 server offline,
    # 仍在 1984 响应但可用 server 不足。同时校验 online server 数量。
    HTTP_CODE=\$(curl -s --noproxy localhost --connect-timeout 5 -o /dev/null -w "%{http_code}" http://localhost:1984/enabled-servers 2>/dev/null) || true
    ONLINE_COUNT=0
    if [ "\${HTTP_CODE}" = "200" ]; then
        ONLINE_COUNT=\$(curl -s --noproxy localhost http://localhost:1984/enabled-servers 2>/dev/null | \
            python3 -c "import sys,json; d=json.load(sys.stdin); s=d.get('servers',d); print(sum(1 for v in (s.values() if isinstance(s,dict) else [x[1] for x in s if isinstance(x,list)]) if v=='OK'))" 2>/dev/null || echo 0)
    fi
    # 期望至少 15 个 online(镜像预装 20 个无需 key 的 server,容忍 5 个偶发失败:
    # npm servers 如 context7 可能因代理 TLS 问题 ECONNRESET,部分 uvx servers 可能因
    # 依赖解析或网络瞬断离线,不影响 eval 核心功能)
    if [ "\${HTTP_CODE}" = "200" ] && [ "\${ONLINE_COUNT}" -ge 15 ]; then
        echo "MCP-Atlas agent-environment 服务已运行(HTTP 200, \${ONLINE_COUNT} servers online),预检通过"
        # 输出已启用的 server 列表
        echo "已启用的 MCP servers:"
        curl -s --noproxy localhost http://localhost:1984/enabled-servers | python3 -m json.tool 2>/dev/null || echo "(解析失败,但服务可用)"
    elif [ "${params.MCP_ATLAS_AUTO_DEPLOY}" = "true" ]; then
        if [ "\${HTTP_CODE}" = "200" ]; then
            echo "MCP-Atlas agent-environment 服务在运行但仅 \${ONLINE_COUNT} servers online(< 15),部分 server 可能因网络/代理问题离线,重新部署..."
        else
            echo "MCP-Atlas agent-environment 服务未运行(HTTP \${HTTP_CODE}),开始自动部署..."
        fi
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

        # 拉取镜像:优先复用本地镜像,避免每次构建都强连外网校验 digest
        if docker image inspect ${params.MCP_ATLAS_IMAGE} >/dev/null 2>&1; then
            echo "本地已有镜像 ${params.MCP_ATLAS_IMAGE},跳过 pull"
            echo "镜像 ID: \$(docker image inspect ${params.MCP_ATLAS_IMAGE} --format '{{.Id}}' 2>/dev/null)"
        else
            echo "本地无镜像,准备拉取 ${params.MCP_ATLAS_IMAGE}(可能需要几分钟)..."
            # 注意:Docker CLI 的 export http_proxy/https_proxy 不会传给 daemon,
            # daemon 拉镜像用的是自身进程环境;Jenkins 本身跑在容器内,
            # 不能在此重启 docker 服务(会停掉 Jenkins 容器)。
            # 新机器需事先手动配置 docker daemon 代理,或人工 docker load 镜像。
            if ! docker pull ${params.MCP_ATLAS_IMAGE} 2>&1; then
                echo "ERROR: 拉取 MCP-Atlas 镜像失败。"
                echo "请手动拉取: docker pull ${params.MCP_ATLAS_IMAGE}"
                echo "或在新机器上手动配置 docker daemon 代理(systemd drop-in / /etc/docker/daemon.json)"
                echo "或用 docker save/load 离线导入镜像。"
                exit 1
            fi
        fi

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
        ENTRYPOINT_WRAPPER=\$(mktemp /tmp/mcp-entrypoint-XXXXXX.sh)
        cat > "\${ENTRYPOINT_WRAPPER}" << 'ENTRYPOINT_EOF'
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
exec "\$@"
ENTRYPOINT_EOF
        chmod +x "\${ENTRYPOINT_WRAPPER}"

        echo "启动 MCP-Atlas agent-environment 容器(名称: \${CONT_NAME})..."
        docker run -d \
            --name \${CONT_NAME} \
            --add-host=host.docker.internal:host-gateway \
            -p 1984:1984 \
            \${DOCKER_ENV_ARGS} \
            --env UV_NO_SYNC=1 \
            --env UV_OFFLINE=1 \
            --env UV_PYTHON=3.12 \
            --env npm_config_offline=true \
            --env HTTPS_PROXY=http://10.201.136.68:1080 \
            --env HTTP_PROXY=http://10.201.136.68:1080 \
            --env NO_PROXY=localhost,127.0.0.1,10.0.0.0/8,host.docker.internal \
            -v "\${ENTRYPOINT_WRAPPER}:/agent-environment/entrypoint_wrapper.sh:ro" \
            --entrypoint /agent-environment/entrypoint_wrapper.sh \
            --restart on-failure:3 \
            ${params.MCP_ATLAS_IMAGE} \
            uv run python -m uvicorn agent_environment.main:app --host 0.0.0.0 --port 1984 2>&1 || {
                echo "ERROR: 启动 MCP-Atlas 容器失败。"
                docker logs \${CONT_NAME} 2>&1 | tail -20 || true
                rm -f "\${ENTRYPOINT_WRAPPER}" 2>/dev/null || true
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

        # 等待服务就绪(官方文档说启动需要 1+ 分钟,最长等 5 分钟)
        echo "等待 MCP-Atlas agent-environment 启动(最长 300 秒)..."
        READY=false
        for i in \$(seq 1 60); do
            sleep 5
            HTTP_CODE=\$(curl -s --noproxy localhost --connect-timeout 3 -o /dev/null -w "%{http_code}" http://localhost:1984/enabled-servers 2>/dev/null) || true
            if [ "\${HTTP_CODE}" = "200" ]; then
                READY=true
                echo "MCP-Atlas agent-environment 启动完成(等待 \$((i * 5)) 秒)"
                break
            fi
            echo "  等待中... (\$((i * 5))s, HTTP \${HTTP_CODE})"
        done

        if [ "\${READY}" != "true" ]; then
            echo "ERROR: MCP-Atlas agent-environment 在 300 秒内未就绪。"
            echo ""
            echo "=== 容器状态 ==="
            docker ps -a --filter "name=mcp-atlas-agent-env" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
            echo ""
            echo "=== 容器详细信息 ==="
            echo "Status:    \$(docker inspect \${CONT_NAME} --format '{{.State.Status}}' 2>/dev/null || echo 'N/A')"
            echo "ExitCode:  \$(docker inspect \${CONT_NAME} --format '{{.State.ExitCode}}' 2>/dev/null || echo 'N/A')"
            echo "RestartCount: \$(docker inspect \${CONT_NAME} --format '{{.State.RestartCount}}' 2>/dev/null || echo 'N/A')"
            echo "Error:     \$(docker inspect \${CONT_NAME} --format '{{.State.Error}}' 2>/dev/null || echo 'N/A')"
            echo ""
            echo "=== 容器日志(最后 50 行) ==="
            docker logs \${CONT_NAME} 2>&1 | tail -50 || true
            echo "=== 日志结束 ==="
            echo ""
            echo "请检查容器状态: docker logs \${CONT_NAME}"
            rm -f "\${ENTRYPOINT_WRAPPER}" 2>/dev/null || true
            exit 1
        fi

        # 清理宿主机临时 entrypoint wrapper(容器已启动,不再需要)
        rm -f "\${ENTRYPOINT_WRAPPER}" 2>/dev/null || true

        # 输出已启用的 server 列表
        echo "MCP-Atlas agent-environment 部署成功,已启用的 MCP servers:"
        curl -s --noproxy localhost http://localhost:1984/enabled-servers | python3 -m json.tool 2>/dev/null || echo "(解析失败,但服务可用)"
        echo "预检通过"
    else
        echo "MCP-Atlas agent-environment 服务不可达(HTTP \${HTTP_CODE}),且 MCP_ATLAS_AUTO_DEPLOY=false。"
        echo "请手动部署: docker pull ${params.MCP_ATLAS_IMAGE} && docker run -d -p 1984:1984 --env UV_NO_SYNC=1 --env UV_OFFLINE=1 --env UV_PYTHON=3.12 --env npm_config_offline=true ${params.MCP_ATLAS_IMAGE}"
        echo "或设置 MCP_ATLAS_AUTO_DEPLOY=true 让 Jenkins 自动部署。"
        echo "mcp_atlas 任务将继续保留在任务列表中,但预期会失败。"
    fi
else
    echo "TASK_MCP_ATLAS=false,跳过 mcp_atlas 服务检查"
fi

# === 记录当前容器快照(用于构建后精准清理) ===
# 在 eval 开始前,记录所有已存在的容器 ID。
# 构建结束后,对比快照找出本次新增的容器(deep_swe Pier 等),只清理这些,不影响其他构建。
docker ps -aq > /tmp/eval_containers_before_${BUILD_NUMBER}
echo "容器快照已保存: \$(wc -l < /tmp/eval_containers_before_${BUILD_NUMBER}) 个容器(用于构建后精准清理)"
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
                    if (params.TASK_AIME26)      taskList.add('aime26')
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
    --use-cache "${params.USE_CACHE}" \\
    ${params.RERUN_REVIEW ? '--rerun-review' : ''} \\
    --description "${params.DESCRIPTION}"
echo "=== 测试脚本执行结束 ==="
echo "=== 输出目录 ==="
find output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${env.MODEL_DIR}/ -type f
if [ -n "${params.USE_CACHE}" ]; then
    echo "=== USE_CACHE 模式: evalscope 实际结果目录(报告/预测/评分落在此处) ==="
    USE_CACHE_ABS="${params.USE_CACHE}"
    # 相对路径转 WORK_DIR 绝对路径,与 run_evalscope.py 中 abspath 处理一致
    if [ -n "\${USE_CACHE_ABS##/*}" ]; then
        USE_CACHE_ABS="${params.WORK_DIR}/\${USE_CACHE_ABS}"
    fi
    find "\${USE_CACHE_ABS}" -type f 2>/dev/null || echo "WARN: USE_CACHE 目录不存在或为空"
fi
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

                            // USE_CACHE 模式下 evalscope 实际把结果写到 USE_CACHE 目录
                            // (run.py 把 work_dir 改写为 use_cache 路径),日志也被
                            // evalscope_main.sh 重定向到 USE_CACHE/evalscope-*.log。
                            // 因此拉取目标切换为 USE_CACHE(转绝对路径),本地布局保持
                            // reports/<tester>/<build_number>/<chip>/<MODEL_DIR>/ 不变,
                            // 让邮件阶段的 glob **/reports/**/*.json 继续匹配。
                            def useCacheRemote = ''
                            if (params.USE_CACHE?.trim()) {
                                useCacheRemote = params.USE_CACHE.trim()
                                if (!useCacheRemote.startsWith('/')) {
                                    useCacheRemote = "${params.WORK_DIR}/${useCacheRemote}"
                                }
                            }

                            echo "拉取测试结果目录: ${useCacheRemote ?: remoteDir}"

                            if (env.CONNECTIVITY_FAILED == 'true') {
                                echo "=== 连通性检查未通过,跳过测试结果目录拉取,仅拉取连通性预检日志 ==="
                            } else if (useCacheRemote) {
                                // USE_CACHE 模式:把 USE_CACHE 整个目录 scp 到临时目录,
                                // 再用 cp -r src/. dst 合并到 localDir/<MODEL_DIR>/,
                                // 让下面的 DeepSWE 诊断 find 和邮件 glob 继续匹配原布局。
                                env.RESULT_DIR = useCacheRemote.replaceAll("^${params.WORK_DIR}/", '')
                                sh """
set -e
mkdir -p ${localDir}/${env.MODEL_DIR}
echo "=== USE_CACHE 模式:从 ${useCacheRemote} 拉取 evalscope 实际结果 ==="
scp -r -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST}:${useCacheRemote} ${localDir}/${env.MODEL_DIR}_use_cache_tmp
# 合并内容(包括隐藏文件),避免额外嵌套一层 timestamp basename 导致邮件 glob 错位
cp -r ${localDir}/${env.MODEL_DIR}_use_cache_tmp/. ${localDir}/${env.MODEL_DIR}/
rm -rf ${localDir}/${env.MODEL_DIR}_use_cache_tmp
echo "=== 拉取结果 ==="
find ${localDir}/ -type f

echo ""
echo "=== DeepSWE 诊断: exception.txt ==="
for f in \$(find ${localDir}/ -name "exception.txt" -type f); do
    echo "--- \$f ---"
    cat "\$f" 2>/dev/null || echo "(unable to read)"
    echo ""
done

echo ""
echo "=== DeepSWE 诊断: mini-swe-agent.txt (最后50行) ==="
for f in \$(find ${localDir}/ -name "mini-swe-agent.txt" -type f); do
    echo "--- \$f ---"
    tail -50 "\$f" 2>/dev/null || echo "(unable to read)"
    echo ""
done

echo ""
echo "=== DeepSWE 诊断: reward.txt ==="
for f in \$(find ${localDir}/ -name "reward.txt" -type f); do
    echo "--- \$f ---"
    cat "\$f" 2>/dev/null || echo "(unable to read)"
    echo ""
done

echo ""
echo "=== DeepSWE 诊断: trial.log (最后30行) ==="
for f in \$(find ${localDir}/ -name "trial.log" -type f); do
    echo "--- \$f ---"
    tail -30 "\$f" 2>/dev/null || echo "(unable to read)"
    echo ""
done
"""
                            } else {
                                sh """
mkdir -p ${localDir}
scp -o StrictHostKeyChecking=no \
    -r ${REMOTE_USER}@${REMOTE_HOST}:${remoteDir} \
    ${localDir}/
echo "=== 拉取结果 ==="
find ${localDir}/ -type f

echo ""
echo "=== DeepSWE 诊断: exception.txt ==="
for f in \$(find ${localDir}/ -name "exception.txt" -type f); do
    echo "--- \$f ---"
    cat "\$f" 2>/dev/null || echo "(unable to read)"
    echo ""
done

echo ""
echo "=== DeepSWE 诊断: mini-swe-agent.txt (最后50行) ==="
for f in \$(find ${localDir}/ -name "mini-swe-agent.txt" -type f); do
    echo "--- \$f ---"
    tail -50 "\$f" 2>/dev/null || echo "(unable to read)"
    echo ""
done

echo ""
echo "=== DeepSWE 诊断: reward.txt ==="
for f in \$(find ${localDir}/ -name "reward.txt" -type f); do
    echo "--- \$f ---"
    cat "\$f" 2>/dev/null || echo "(unable to read)"
    echo ""
done

echo ""
echo "=== DeepSWE 诊断: trial.log (最后30行) ==="
for f in \$(find ${localDir}/ -name "trial.log" -type f); do
    echo "--- \$f ---"
    tail -30 "\$f" 2>/dev/null || echo "(unable to read)"
    echo ""
done
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

                        // 统计被 --ignore-errors 跳过的失败样本数
                        // evalscope 在 ignore_errors=True 时,每个被跳过的样本会输出一条
                        // WARNING: Error ignored, continuing with next sample. (evaluator.py on_error)
                        def ignoredCount = 0
                        if (logContent) {
                            ignoredCount = logContent.count("Error ignored, continuing with next sample.")
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
                            // readJSON returns net.sf.json.JSONNull for JSON null values, which is truthy
                            // in Groovy and throws MissingPropertyException when accessing fields on it.
                            def norm = { v -> v == null || v instanceof net.sf.json.JSONNull ? null : v }
                            for (def rf : reportFiles) {
                                def json = readJSON(file: rf.path)
                                def taskName = norm(json.dataset_name) ?: norm(json.name) ?: "unknown"
                                def score = norm(json.score)
                                def scoreStr = "N/A"
                                if (score != null) {
                                    scoreStr = String.format("%.2f%%", (score as Double) * 100)
                                }
                                taskScores[taskName] = scoreStr
                                taskSummaryRows += "<tr><td>${taskName}</td><td>${scoreStr}</td></tr>"

                                // 单任务详情行(包含 metric / category / subset 明细)
                                def detailRows = ""
                                def metrics = norm(json.metrics) ?: []
                                for (def m : metrics) {
                                    def metricName = norm(m.name) ?: "score"
                                    def metricScore = norm(m.score)
                                    def metricScoreStr = metricScore != null ? String.format("%.2f%%", (metricScore as Double) * 100) : "N/A"
                                    detailRows += "<tr class=\"score-highlight\"><td>${taskName}</td><td>${metricName} (overall)</td><td>${metricScoreStr}</td></tr>"
                                    def categories = norm(m.categories) ?: []
                                    for (def c : categories) {
                                        def catName = norm(c.name)
                                        if (catName instanceof List) {
                                            catName = catName.collect { it.toString() }.join(' / ')
                                        }
                                        def catScore = norm(c.score)
                                        def catScoreStr = catScore != null ? String.format("%.2f%%", (catScore as Double) * 100) : "N/A"
                                        def catNum = norm(c.num) ?: 0
                                        detailRows += "<tr><td>${taskName}</td><td>${catName} (n=${catNum})</td><td>${catScoreStr}</td></tr>"
                                        def subsets = norm(c.subsets) ?: []
                                        for (def s : subsets) {
                                            def subName = norm(s.name)
                                            def subScore = norm(s.score)
                                            def subScoreStr = subScore != null ? String.format("%.4f", (subScore as Double) * 100) + "%" : "N/A"
                                            def subNum = norm(s.num) ?: 0
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
                                def perf = norm(json.perf_metrics)
                                if (perf != null && norm(perf.summary) != null) {
                                    def sum = perf.summary
                                    def latency = norm(sum.latency)
                                    def throughput = norm(sum.throughput)
                                    def usage = norm(sum.usage)
                                    def ttft = norm(sum.ttft)
                                    def nSamples = norm(sum.n_samples) ?: 'N/A'
                                    def perfLines = "samples: ${nSamples}"
                                    if (latency != null && norm(latency.avg) != null) {
                                        perfLines += " | latency avg: ${latency.avg}s"
                                    }
                                    if (throughput != null && norm(throughput.avg_output_tps) != null) {
                                        perfLines += " | output tps: ${throughput.avg_output_tps}"
                                    }
                                    if (ttft != null && norm(ttft.avg) != null) {
                                        perfLines += " | TTFT avg: ${ttft.avg}s"
                                    }
                                    if (usage != null && norm(usage.total_tokens_count) != null) {
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

                        // 已忽略失败样本 HTML 块(--ignore-errors 跳过的样本,不影响其余样本出分)
                        def ignoredSamplesHtml = ""
                        if (ignoredCount > 0) {
                            ignoredSamplesHtml = """
            <div style="background-color: #fff3e0; color: #000000; border-left: 4px solid #ff9800; padding: 12px 15px; margin-top: 15px; border-radius: 3px;">
                <h3 style="color: #ef6c00; margin-top: 0; margin-bottom: 8px;">⚠️ 已忽略 ${ignoredCount} 个失败样本</h3>
                <p style="margin-top: 0; margin-bottom: 8px; color: #000000;">本次测试启用了 <code>--ignore-errors</code>,有 ${ignoredCount} 个样本在推理/评分阶段失败被跳过,未计入得分;其余样本继续评估并产出报告。失败详情见日志中的 <code>Error ignored, continuing with next sample.</code> 及对应 ERROR 堆栈。</p>
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
                <tr><th>use_cache</th><td>${params.USE_CACHE ?: 'N/A (全新跑)'}</td></tr>
                <tr><th>rerun_review</th><td>${params.RERUN_REVIEW}</td></tr>
                <tr><th>MCP-Atlas 镜像</th><td>${params.MCP_ATLAS_IMAGE}</td></tr>
                <tr><th>MCP-Atlas 自动部署</th><td>${params.MCP_ATLAS_AUTO_DEPLOY}</td></tr>
                <tr><th>MCP-Atlas API Keys</th><td>${params.MCP_ATLAS_API_KEYS ?: 'N/A(仅启用 20 个无 key server)'}</td></tr>
                <tr><th>执行时间</th><td>${currentBuild.durationString}</td></tr>
                <tr><th>测试状态</th><td>${resultStatus}</td></tr>
                <tr><th>已忽略失败样本</th><td>${ignoredCount > 0 ? "${ignoredCount} (已跳过,未计入得分)" : '0'}</td></tr>
                <tr><th>构建状态</th><td>${currentBuild.currentResult}</td></tr>
            </table>

            ${connectivityFailureHtml}

            ${ignoredSamplesHtml}

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
            // 容器清理放在 post.always 中,无论前面任意 stage 成功或失败都会执行,
            // 避免"环境检查"失败时已启动的 MCP-Atlas / deep_swe 容器残留。
            sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                catchError(buildResult: 'SUCCESS', stageResult: 'SUCCESS') {
                    sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << 'ENDSSH'
echo "=== 清理本次构建启动的容器(BUILD #${BUILD_NUMBER}) ==="

# 1. MCP-Atlas 容器:按名称精准清理(名称含构建编号,不会误删其他构建的容器)
CONT_NAME="mcp-atlas-agent-env-${BUILD_NUMBER}"
MCP_ID=\$(docker ps -a --filter "name=\${CONT_NAME}" --format '{{.ID}}' 2>/dev/null | head -1)
if [ -n "\${MCP_ID}" ]; then
    echo "清理 MCP-Atlas 容器: \${CONT_NAME} (\${MCP_ID})"
    docker rm -f \${MCP_ID} 2>/dev/null || true
else
    echo "MCP-Atlas 容器 \${CONT_NAME} 不存在,跳过"
fi

# 2. eval 期间新增的容器(deep_swe Pier 容器等):对比快照,只清理新增的
#    Pier 容器名含随机 UUID,无法按构建编号匹配,用快照 diff 精准识别
SNAPSHOT_FILE="/tmp/eval_containers_before_${BUILD_NUMBER}"
if [ ! -f "\${SNAPSHOT_FILE}" ]; then
    echo "快照文件不存在(环境检查阶段可能被跳过),跳过 diff 清理"
    echo "=== 清理完成 ==="
    exit 0
fi

docker ps -aq > /tmp/eval_containers_after_${BUILD_NUMBER}
sort "\${SNAPSHOT_FILE}" > /tmp/eval_before_sorted
sort /tmp/eval_containers_after_${BUILD_NUMBER} > /tmp/eval_after_sorted

# comm -13: 只显示 after 中有但 before 中没有的行(即新增容器)
NEW_CONTAINERS=\$(comm -13 /tmp/eval_before_sorted /tmp/eval_after_sorted)

if [ -n "\${NEW_CONTAINERS}" ]; then
    NEW_COUNT=\$(echo "\${NEW_CONTAINERS}" | grep -c . )
    echo "发现 \${NEW_COUNT} 个本次构建新增的容器,清理中:"
    echo "\${NEW_CONTAINERS}" | while read -r cid; do
        if [ -n "\$cid" ]; then
            IMG=\$(docker inspect "\$cid" --format '{{.Config.Image}}' 2>/dev/null || echo "?")
            docker rm -f "\$cid" 2>/dev/null && echo "  已清理: \$cid (\${IMG})" || echo "  清理失败: \$cid"
        fi
    done
    echo "新增容器清理完成"
else
    echo "无新增容器需要清理"
fi

# 清理临时文件
rm -f "\${SNAPSHOT_FILE}" /tmp/eval_containers_after_${BUILD_NUMBER} /tmp/eval_before_sorted /tmp/eval_after_sorted
echo "=== 容器清理完成 ==="
ENDSSH
"""
                }
            }
        }
        cleanup {
            cleanWs()
        }
    }
}
