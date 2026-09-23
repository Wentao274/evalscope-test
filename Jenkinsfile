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

        // 用户模拟模型(tau_bench / tau2_bench 必填;这两个任务用 LLM 模拟客户与被测模型多轮对话,评分靠 task reward 规则判定,不需要裁判模型)
        string(name: 'USER_MODEL_ID', defaultValue: '', description: '用户模拟模型名称(tau_bench/tau2_bench 必填,对应 extra_params.user_model;留空则复用被测模型 MODEL,推荐用 qwen-plus 等能力较强的模型以获得真实用户模拟)')
        string(name: 'USER_MODEL_API_URL', defaultValue: '', description: '用户模拟模型 OpenAI 兼容端点 URL(含 /v1 后缀;留空则复用 BASE_URL_V1)')
        password(name: 'USER_MODEL_API_KEY', defaultValue: '', description: '用户模拟模型 API Key(留空则复用 API_KEY;无需认证时填 EMPTY)')

        // 各基准一个 boolean(按需勾选;默认仅开 mmlu_pro / aime25 / aime26 / gpqa_diamond)
        booleanParam(name: 'TASK_MMLU_PRO',     defaultValue: true,  description: '运行 mmlu_pro (10 选项多学科多选,5-shot,accuracy)')
        booleanParam(name: 'TASK_AIME25',      defaultValue: true,  description: '运行 aime25 (AIME 2025 美国数学邀请赛,30 题,0-shot,numeric accuracy;数学推理题,答案需 \\boxed{} 格式)')
        booleanParam(name: 'TASK_AIME26',      defaultValue: true,  description: '运行 aime26 (AIME 2026 美国数学邀请赛,30 题,0-shot,numeric accuracy;数学推理题,答案需 \\boxed{} 格式)')
        booleanParam(name: 'TASK_GPQA_DIAMOND', defaultValue: true,  description: '运行 gpqa_diamond (博士级 4 选择,0-shot,accuracy)')
        booleanParam(name: 'TASK_CEVAL',        defaultValue: false, description: '运行 ceval (中文多学科多选,52 学科,5-shot,accuracy)')
        booleanParam(name: 'TASK_CMMLU',        defaultValue: false, description: '运行 cmmlu (中文多学科多选,67 学科,0-shot,accuracy)')
        booleanParam(name: 'TASK_MATH_500',     defaultValue: false, description: '运行 math_500 (数学推理,500 题,0-shot,accuracy)')
        booleanParam(name: 'TASK_HELLASWAG',   defaultValue: false, description: '运行 hellaswag (常识推理,4 选择,0-shot,accuracy)')
        booleanParam(name: 'TASK_HUMANEVAL',    defaultValue: false, description: '运行 humaneval (Python 代码生成,164 题,0-shot,pass@1;需执行模型生成的代码,启用 sandbox 见 evalscope 文档)')
        booleanParam(name: 'TASK_HUMANEVAL_PLUS', defaultValue: false, description: '运行 humaneval_plus (HumanEval 增强版,164 题,测试用例数万级,0-shot,pass@1;review_timeout=300s,需 sandbox 且使用内置 numpy 的自定义 docker 镜像)')
        booleanParam(name: 'TASK_HMMT25',        defaultValue: false, description: '运行 hmmt25 (HMMT 2025年2月数学竞赛,30 题,0-shot,numeric accuracy;数学推理题,答案需 \\boxed{} 格式)')
        booleanParam(name: 'TASK_HMMT26',        defaultValue: false, description: '运行 hmmt26 (HMMT 2026年2月数学竞赛,33 题,0-shot,numeric accuracy;数学推理题,答案需 \\boxed{} 格式)')
        booleanParam(name: 'TASK_IMO_ANSWERBENCH', defaultValue: false, description: '运行 imo_answerbench (IMO 短名单奥数题,400 题,0-shot,numeric accuracy;llm_judge_default=True,有裁判模型时自动走 LLM judge,无裁判模型时回退 rule(numeric math_equal);答案含区间/集合/分数等复杂 LaTeX 形式,部分比对可能不如纯数字精确)')
        booleanParam(name: 'TASK_MCP_ATLAS',          defaultValue: false, description: '运行 mcp_atlas (Scale AI MCP 工具使用智能体,89 题,multi-turn function-calling,LLM judge coverage_score/pass_rate;MCP-Atlas agent-environment Docker 服务支持自动部署,见 MCP_ATLAS_AUTO_DEPLOY 参数;20 个无需 API key 的 MCP server 默认启用,约 40-50 个任务可评测,配置 MCP_ATLAS_API_KEYS 可启用更多 server;被测模型驱动 AgentLoop,裁判模型逐 claim 评判;依赖 JUDGE_MODEL_ID/JUDGE_API_URL/JUDGE_API_KEY 参数)')
        booleanParam(name: 'TASK_DEEP_SWE',           defaultValue: false, description: '运行 deep_swe (仓库级软件工程编码智能体,113 题,multi-turn agent,verifier 二值奖励 acc;通过 Pier Python API 运行,需 Docker + pip install evalscope[deep_swe] + Python>=3.12;Pier 内置 mini-swe-agent 驱动,默认 litellm model_class 兼容 OpenAI chat/completions 端点;默认 temperature=1.0 top_p=1.0 timeout=48h max_tokens=400k(官方 GLM-5.2 为 2h,低性能机器调大到 48h 兜底,可在 TASK_TIMEOUT_JSON 进一步调整);每个任务在隔离容器中运行,2 CPU/8GB RAM/无网络,串行执行耗时较长)')
        booleanParam(name: 'TASK_MBPP',    defaultValue: false, description: '运行 mbpp (Mostly Basic Python Problems,500 题,3-shot,pass@1;代码生成后沙箱执行测试用例判定 pass/fail;需启用 ENABLE_SANDBOX=true + Docker;与 HumanEval 测试环境相同,不需要裁判模型;默认 review_timeout=20s)')
        booleanParam(name: 'TASK_FRAMES',  defaultValue: false, description: '运行 frames (RAG 长上下文多跳推理,824 题,0-shot,accuracy;输入含维基百科上下文文档,prompt 平均 68K 字符,最大 557K 字符,被测模型需支持超长上下文(>=128K);支持精确匹配(rule)和 LLM judge 两种评分,有裁判模型时自动走 LLM judge,无裁判模型时回退 rule(exact match);裁判模型无需长上下文)')
        booleanParam(name: 'TASK_MM_BENCH', defaultValue: false, description: '运行 mm_bench (MMBench 视觉多选问答,8658 题(中英各 4329),0-shot,CoT,accuracy;被测模型必须支持多模态输入(图像+文本),如 qwen-vl-plus/gpt-4o 等;纯文本模型不可用;多选题规则评分,不需要裁判模型)')
        booleanParam(name: 'TASK_HLE', defaultValue: false, description: "运行 hle (Humanity's Last Exam,2500 专家级跨学科题,14% 含图像;本流水线默认只跑文本子集 include_multi_modal=false,约 2150 题;llm_judge_default=True,有裁判模型走 LLM judge(GRADE C/I),无裁判模型回退 rule 精确匹配;76% 简答题对格式 \\boxed{}/单位/区间 敏感,rule 准确率偏低,建议配裁判模型)")
        booleanParam(name: 'TASK_TAU_BENCH',  defaultValue: false, description: '运行 tau_bench (τ-bench 多轮对话 agent,航空/零售客服场景,被测模型通过 API 工具调用完成任务;LLM 模拟用户对话,需配 USER_MODEL_ID 等用户模拟模型参数;规则评分 task reward,不需要裁判模型;pass^k 聚合,设 REPEATS=k 启用;git-only 依赖,环境检查阶段自动从 github 安装)')
        booleanParam(name: 'TASK_TAU2_BENCH', defaultValue: false, description: '运行 tau2_bench (τ²-bench,τ-bench 增强版,新增 telecom 域;被测模型通过 API 工具调用完成任务;LLM 模拟用户对话,需配 USER_MODEL_ID 等用户模拟模型参数;规则评分 task reward,不需要裁判模型;pass^k 聚合,设 REPEATS=k 启用;git-only 依赖,环境检查阶段自动从 github 安装;注意:与 tau3_bench 共用 tau2 包名不可共存,本流水线不含 tau3_bench)')

        string(name: 'EXAMPLES',        defaultValue: '',      description: '样本数限制(空 = 不限制;传给 evalscope --limit。int=数量,float=比例)')
        string(name: 'REPEATS',         defaultValue: '',      description: '重复次数(k-metrics,传给 evalscope --repeats。空 = 默认 1)')
        string(name: 'EVAL_BATCH_SIZE', defaultValue: '1',     description: '并发批大小(对应 evalscope --eval-batch-size,默认 1)')
        string(name: 'TEMPERATURE_FALLBACK', defaultValue: '1.0', description: '采样温度兜底值(仅当 TASK_TEMPERATURE_JSON 未命中某任务时使用;默认 1.0,适配 thinking 模式推理模型)')
        string(name: 'MAX_TOKENS',      defaultValue: '32768', description: '生成最大 token 数(默认 32768;清空 = 不指定)')
        string(name: 'TOP_P',           defaultValue: '0.95',  description: 'nucleus top_p(默认 0.95)')
        string(name: 'TOP_K',           defaultValue: '20',    description: 'top-k 采样(默认 20)')
        choice(name: 'ENABLE_THINKING', choices: ['true', 'false'], description: '启用 thinking 模式(默认 true)')
        choice(name: 'JUDGE_STRATEGY',  choices: ['auto', 'rule', 'llm', 'llm_recall'], description: '评分策略(默认 auto;多选题用 rule,主观题用 llm)')
        text(name: 'TASK_JUDGE_STRATEGY_JSON', defaultValue: '', description: '按任务覆盖 judge_strategy 的 JSON。默认为空:imo_answerbench 在有裁判模型(JUDGE_MODEL_ID 非空)时走 auto 自动启用 LLM judge,无裁判模型时自动回退 rule(numeric math_equal);如需手动指定可追加,例: {"imo_answerbench":"rule","simple_qa":"llm"}(需配套 judge_model_args)')
        choice(name: 'ENABLE_SANDBOX', choices: ['true', 'false'], description: '启用 sandbox 执行(默认 true)。true 时给所有任务拼 --sandbox {"enabled": true},仅对 humaneval 等 CodeExecutionSandboxMixin 任务生效。启用前环境检查 stage 会预装 evalscope[sandbox] 并校验 Docker 可用')
        text(name: 'TASK_MAX_TOKENS_JSON', defaultValue: '{"gpqa_diamond":131072,"aime25":131072,"aime26":131072,"imo_answerbench":131072,"hmmt25":65536,"hmmt26":65536,"mcp_atlas":8192,"deep_swe":409600,"hellaswag":8192,"humaneval":16384,"humaneval_plus":16384,"mbpp":16384,"frames":16384,"hle":131072}', description: '按任务覆盖 max_tokens 的 JSON。未列出的任务用 MAX_TOKENS 默认值(32768)。各项依据: gpqa_diamond=131072(PhD级科学MCQ+CoT,thinking推理极长),aime25=131072(AIME数学竞赛,thinking推理链最长),aime26=131072(同aime25),imo_answerbench=131072(IMO奥数最高难度,400题,解答篇幅≥AIME,32768会截断\\boxed{}前推导导致答案提取失败),hmmt25=65536(HMMT数学竞赛,难度接近AIME),hmmt26=65536(同hmmt25),mcp_atlas=8192(多轮AgentLoop,单步工具调用args/短回复够用,过大会触发长思考导致超时),deep_swe=409600(400k,编码agent需大输出窗口),hellaswag=8192(常识单选,输出仅1字母),humaneval=16384(Python代码生成),humaneval_plus=16384(同humaneval,更多测试用例),mbpp=16384(基础Python代码生成,3-shot),frames=16384(RAG短答案,target_mean=31字符)。ceval 未列出,使用全局默认 32768(中文通识多选,5-shot,thinking模式下部分题目推理链较长,16384易截断导致答案丢失)。可按需追加,例: {"mmlu_pro":4096}')
        text(name: 'TASK_TIMEOUT_JSON', defaultValue: '{"aime25":7200,"aime26":7200,"gpqa_diamond":7200,"mcp_atlas":7200,"deep_swe":172800,"hle":7200}', description: '按任务覆盖模型调用超时(秒)的 JSON,默认 aime25/aime26=7200(2 小时,AIME数学竞赛 thinking 推理链长),mcp_atlas=7200(2 小时,多轮 AgentLoop 配合 max_tokens=4096 + thinking 仍可能耗时长),deep_swe=172800(48 小时,仓库级编码 agent 串行构建+验证,低性能机器或大仓库需更长 agent_timeout),其余任务用内置默认 3600;可按需追加,例: {"mcp_atlas":7200,"humaneval":1800}')
        text(name: 'TASK_TOP_P_JSON', defaultValue: '{"deep_swe":1.0}', description: '按任务覆盖 top_p 的 JSON,默认 deep_swe=1.0(编码 agent 高随机性探索,全局默认 0.95);可按需追加,例: {"deep_swe":1.0,"humaneval":0.95}')
        text(name: 'TASK_STOP_SEQS_JSON', defaultValue: '{"mmlu_pro":["Question:"]}', description: '按任务指定 stop_seqs(停止序列)的 JSON。命中的任务会将对应字符串列表注入 generation_config 的 stop_seqs 字段,服务端生成时遇到任一序列立即截断,避免模型在 few-shot 模式下答完题后继续生成多余内容。默认 mmlu_pro=["Question:"] 与 lm-evaluation-harness 的 until=["Question:"] 对齐;其他任务不在此 JSON 中则不加 stop_seqs。可按需追加,例: {"mmlu_pro":["Question:"],"ceval":["Question:"]}')
        choice(name: 'TASK_TEMPERATURE_JSON', choices: ['{"mmlu_pro":1.0,"aime25":1.0,"aime26":1.0,"gpqa_diamond":1.0,"ceval":1.0,"cmmlu":1.0,"math_500":1.0,"hellaswag":1.0,"humaneval":1.0,"humaneval_plus":1.0,"hmmt25":1.0,"hmmt26":1.0,"imo_answerbench":1.0,"mcp_atlas":1.0,"deep_swe":1.0,"mbpp":1.0,"frames":1.0,"mm_bench":1.0,"hle":1.0,"tau_bench":1.0,"tau2_bench":1.0}', '{"mmlu_pro":0.0,"aime25":0.6,"aime26":0.6,"gpqa_diamond":0.0,"ceval":0.0,"cmmlu":0.0,"math_500":0.6,"hellaswag":0.0,"humaneval":0.2,"humaneval_plus":0.2,"hmmt25":0.6,"hmmt26":0.6,"imo_answerbench":0.6,"mcp_atlas":0.0,"deep_swe":1.0,"mbpp":0.2,"frames":0.0,"mm_bench":0.0,"hle":0.6,"tau_bench":0.0,"tau2_bench":0.0}'], description: '按任务指定采样温度的 JSON。选项1(thinking 模式,默认):全部任务 1.0,适配 GLM-5.2/DeepSeek-V4/Kimi-K3 推理模型(官方均推荐 1.0;Kimi-K3 强制 1.0)。选项2(R1/instruct 模式):多选题 0.0,数学推理 0.6,代码 0.2,工具调用 0.0,编码 agent 1.0;适配 DeepSeek-R1 系(推荐 0.5-0.7)或非 thinking instruct 模型(greedy)。如需更细粒度控制可手动输入 JSON')
        text(name: 'TASK_REPEATS_JSON', defaultValue: '', description: '按任务覆盖 repeats 的 JSON,例: {"humaneval":5,"humaneval_plus":5}。命中任务使用对应值,未命中任务用全局 REPEATS;为空则全部用全局 REPEATS。推荐:humaneval/humaneval_plus 设 5 算 pass@1..pass@5,其余 greedy 基准(mmlu_pro/aime25/aime26/gpqa_diamond/ceval/cmmlu/hellaswag/math_500/hmmt25/hmmt26/imo_answerbench)保持 1 避免 N 倍空跑')
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
                    println("任务 AIME25:       ${params.TASK_AIME25}")
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
                    println("任务 MBPP:         ${params.TASK_MBPP}")
                    println("任务 FRAMES:       ${params.TASK_FRAMES}")
                    println("任务 MM_BENCH:     ${params.TASK_MM_BENCH}")
                    println("任务 HLE:         ${params.TASK_HLE}")
                    println("任务 TAU_BENCH:   ${params.TASK_TAU_BENCH}")
                    println("任务 TAU2_BENCH:  ${params.TASK_TAU2_BENCH}")
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
                    println("用户模拟模型:    ${params.USER_MODEL_ID ?: '<复用被测模型 ' + params.MODEL + '>'}")
                    println("用户模拟模型API: ${params.USER_MODEL_API_URL ?: '<复用 ' + env.BASE_URL_V1 + '>'}")
                    println("enable_sandbox:  ${params.ENABLE_SANDBOX}")
                    println("per-task max_tokens JSON: ${params.TASK_MAX_TOKENS_JSON ?: 'N/A'}")
                    println("per-task timeout JSON: ${params.TASK_TIMEOUT_JSON ?: 'N/A'}")
                    println("per-task top_p JSON: ${params.TASK_TOP_P_JSON ?: 'N/A'}")
                    println("per-task stop_seqs JSON: ${params.TASK_STOP_SEQS_JSON ?: 'N/A'}")
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
# 连通性检查目标是内网IP,不走代理(宿主机系统环境可能设置了 HTTP_PROXY)
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
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
export WORK_DIR=${params.WORK_DIR}
export TASK_DEEP_SWE=${params.TASK_DEEP_SWE}
export ENABLE_SANDBOX=${params.ENABLE_SANDBOX}
export TASK_HUMANEVAL=${params.TASK_HUMANEVAL}
export TASK_HUMANEVAL_PLUS=${params.TASK_HUMANEVAL_PLUS}
export TASK_MBPP=${params.TASK_MBPP}
export TASK_TAU_BENCH=${params.TASK_TAU_BENCH}
export TASK_TAU2_BENCH=${params.TASK_TAU2_BENCH}
bash \$WORK_DIR/scripts/setup_venv.sh
ENDSSH
"""
                    sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << 'ENDSSH'
set -e
export WORK_DIR=${params.WORK_DIR}
export TASK_DEEP_SWE=${params.TASK_DEEP_SWE}
export ENABLE_SANDBOX=${params.ENABLE_SANDBOX}
export TASK_HUMANEVAL=${params.TASK_HUMANEVAL}
export TASK_HUMANEVAL_PLUS=${params.TASK_HUMANEVAL_PLUS}
export TASK_MBPP=${params.TASK_MBPP}
bash \$WORK_DIR/scripts/setup_docker.sh
ENDSSH
"""
                    sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << 'ENDSSH'
set -e
export WORK_DIR=${params.WORK_DIR}
export BUILD_NUMBER=${BUILD_NUMBER}
export TASK_MCP_ATLAS=${params.TASK_MCP_ATLAS}
export MCP_ATLAS_AUTO_DEPLOY=${params.MCP_ATLAS_AUTO_DEPLOY}
export MCP_ATLAS_IMAGE=${params.MCP_ATLAS_IMAGE}
export MCP_ATLAS_API_KEYS=${params.MCP_ATLAS_API_KEYS}
bash \$WORK_DIR/scripts/setup_mcp_atlas.sh
ENDSSH
"""
                    sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << 'ENDSSH'
set -e
cd ${params.WORK_DIR}

# === 预下载数据集(经代理)===
# 评测阶段会 unset 代理直连内网,若数据集未缓存会导致下载失败。
# 在此阶段(有代理)预下载所有勾选的、需要从远端拉取的数据集任务,
# 评测时 load_dataset() 命中缓存,无需网络,直连内网推理。
#
# 数据加载方式分类:
#   - 标准任务(mmlu_pro/hle/ceval 等):RemoteDataLoader → ModelScope/HF → datasets.save_to_disk()
#     缓存于 ~/.cache/evalscope/datasets/<safe_name>-<hash>/,完整性标志:dataset_info.json
#   - tau2_bench:resolve_snapshot_or_local_path() → modelscope.dataset_snapshot_download()
#     缓存于 ~/.cache/modelscope/hub/datasets/evalscope/tau2-bench-data/,完整性标志:目录非空
#   - tau_bench:数据随 pip 包捆绑(tau_bench/envs/*/data/*.json),无需下载,排除
#   - mcp_atlas/deep_swe:使用自有基础设施(Docker/Pier),不走标准数据集下载,排除
echo "=== 预下载数据集 ==="
PRELOAD_TASKS=""
[ "${params.TASK_MMLU_PRO}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS mmlu_pro"
[ "${params.TASK_AIME25}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS aime25"
[ "${params.TASK_AIME26}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS aime26"
[ "${params.TASK_GPQA_DIAMOND}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS gpqa_diamond"
[ "${params.TASK_CEVAL}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS ceval"
[ "${params.TASK_CMMLU}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS cmmlu"
[ "${params.TASK_MATH_500}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS math_500"
[ "${params.TASK_HELLASWAG}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS hellaswag"
[ "${params.TASK_HUMANEVAL}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS humaneval"
[ "${params.TASK_HUMANEVAL_PLUS}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS humaneval_plus"
[ "${params.TASK_HMMT25}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS hmmt25"
[ "${params.TASK_HMMT26}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS hmmt26"
[ "${params.TASK_IMO_ANSWERBENCH}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS imo_answerbench"
[ "${params.TASK_MBPP}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS mbpp"
[ "${params.TASK_FRAMES}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS frames"
[ "${params.TASK_MM_BENCH}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS mm_bench"
[ "${params.TASK_HLE}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS hle"
# tau2_bench:从 ModelScope 下载 evalscope/tau2-bench-data 快照,需要代理
[ "${params.TASK_TAU2_BENCH}" = "true" ] && PRELOAD_TASKS="\$PRELOAD_TASKS tau2_bench"
# tau_bench:数据随 pip 包捆绑,无需下载,不加入预下载列表

if [ -n "\$PRELOAD_TASKS" ]; then
    source ${params.WORK_DIR}/.venv/bin/activate
    # 先检查缓存(无代理,纯文件系统检查),再按需下载(有代理)
    # 脚本独立为 scripts/predownload_datasets.py 避免 Jenkinsfile CPS 方法过大
    PRELOAD_TASKS="\$PRELOAD_TASKS" PROXY_URL="http://10.201.136.68:1080" python3 ${params.WORK_DIR}/scripts/predownload_datasets.py 2>&1
    deactivate
    echo "数据集预下载阶段完成"
else
    echo "无标准数据集任务,跳过预下载"
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
                    if (params.TASK_AIME25)      taskList.add('aime25')
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
                    if (params.TASK_MBPP)            taskList.add('mbpp')
                    if (params.TASK_FRAMES)          taskList.add('frames')
                    if (params.TASK_MM_BENCH)        taskList.add('mm_bench')
                    if (params.TASK_HLE)             taskList.add('hle')
                    if (params.TASK_TAU_BENCH)       taskList.add('tau_bench')
                    if (params.TASK_TAU2_BENCH)      taskList.add('tau2_bench')
                    if (taskList.isEmpty()) {
                        error '至少需要选择一个测试任务'
                    }
                    env.TASKS = taskList.join(',')

                    def modelDir = params.MODEL.contains("/") ? params.MODEL.split("/").last() : params.MODEL
                    env.MODEL_DIR = modelDir

                    env.API_KEY_STR = params.API_KEY?.toString() ?: ''
                    env.JUDGE_API_KEY_STR = params.JUDGE_API_KEY?.toString() ?: ''
                    env.USER_MODEL_API_KEY_STR = params.USER_MODEL_API_KEY?.toString() ?: ''

                    sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                        catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                            sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << ENDSSH
set -e
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# === 取消代理 ===
# runner 宿主机系统环境中有 HTTP_PROXY/HTTPS_PROXY(见环境检查阶段注释),
# 评测时模型推理请求(10.11.x.x 内网IP)若走代理会间歇性 Connection error。
# 数据集已在环境检查阶段经代理预下载并缓存,评测阶段无需网络,直连内网推理。
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
echo "=== Proxy unset for eval ==="

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
    --task-stop-seqs-json '${params.TASK_STOP_SEQS_JSON}' \\
    --dataset-args '${params.DATASET_ARGS}' \\
    --judge-model-id "${params.JUDGE_MODEL_ID}" \\
    --judge-api-url "${params.JUDGE_API_URL}" \\
    --judge-api-key "${env.JUDGE_API_KEY_STR ?: 'EMPTY'}" \\
    --user-model-id "${params.USER_MODEL_ID}" \\
    --user-model-api-url "${params.USER_MODEL_API_URL}" \\
    --user-model-api-key "${env.USER_MODEL_API_KEY_STR}" \\
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
                <tr><th>用户模拟模型</th><td>${params.USER_MODEL_ID ?: '<复用被测模型>'}</td></tr>
                <tr><th>用户模拟模型API</th><td>${params.USER_MODEL_API_URL ?: '<复用被测模型API>'}</td></tr>
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
