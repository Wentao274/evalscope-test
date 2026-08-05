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

        // 各基准一个 boolean(按需勾选;默认全开)
        booleanParam(name: 'TASK_MMLU_PRO',     defaultValue: true,  description: '运行 mmlu_pro (10 选项多学科多选,5-shot,accuracy)')
        booleanParam(name: 'TASK_GPQA_DIAMOND', defaultValue: true,  description: '运行 gpqa_diamond (博士级 4 选择,0-shot,accuracy)')
        booleanParam(name: 'TASK_CEVAL',        defaultValue: true,  description: '运行 ceval (中文多学科多选,52 学科,5-shot,accuracy)')
        booleanParam(name: 'TASK_CMMLU',        defaultValue: true,  description: '运行 cmmlu (中文多学科多选,67 学科,0-shot,accuracy)')
        booleanParam(name: 'TASK_MATH_500',     defaultValue: true,  description: '运行 math_500 (数学推理,500 题,0-shot,accuracy)')

        string(name: 'EXAMPLES',        defaultValue: '',      description: '样本数限制(空 = 不限制;传给 evalscope --limit。int=数量,float=比例)')
        string(name: 'REPEATS',         defaultValue: '',      description: '重复次数(k-metrics,传给 evalscope --repeats。空 = 默认 1)')
        string(name: 'EVAL_BATCH_SIZE', defaultValue: '32',    description: '并发批大小(对应 evalscope --eval-batch-size,默认 32)')
        string(name: 'TEMPERATURE',     defaultValue: '0.0',   description: '采样温度(默认 0.0 = greedy,保证精度评测可复现)')
        string(name: 'MAX_TOKENS',      defaultValue: '32768', description: '生成最大 token 数(默认 32768;清空 = 不指定)')
        string(name: 'TOP_P',           defaultValue: '0.95',  description: 'nucleus top_p(默认 0.95)')
        string(name: 'TOP_K',           defaultValue: '20',    description: 'top-k 采样(默认 20)')
        choice(name: 'ENABLE_THINKING', choices: ['false', 'true'], description: '启用 thinking 模式(默认 false)')
        choice(name: 'JUDGE_STRATEGY',  choices: ['auto', 'rule', 'llm', 'llm_recall'], description: '评分策略(默认 auto;多选题用 rule,主观题用 llm)')
        text(name: 'TASK_MAX_TOKENS_JSON', defaultValue: '', description: '按任务覆盖 max_tokens 的 JSON,例: {"mmlu_pro":4096,"gpqa_diamond":4096}')
        text(name: 'DATASET_ARGS',      defaultValue: '',      description: '数据集参数 JSON,例: {"mmlu_pro":{"subset_list":["math","physics"]}}')

        string(name: 'DESCRIPTION', defaultValue: '', description: '模型服务描述信息(仅用于邮件展示)')
        text(name: 'RECIPIENTS',    defaultValue: 'liwt@zetyun.com', description: '报告邮件接收者(逗号分隔)')
        string(name: 'WORK_DIR',    defaultValue: '/dingofs/data2/userdata/liwt/maas-image/evalscope-test', description: '远程仓库目录,请不要改动')
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
                    println("样本限制:        ${params.EXAMPLES ?: '无限制'}")
                    println("repeats:         ${params.REPEATS ?: 'default 1'}")
                    println("eval-batch-size: ${params.EVAL_BATCH_SIZE}")
                    println("温度:            ${params.TEMPERATURE}")
                    println("max_tokens:      ${params.MAX_TOKENS ?: 'unlimited'}")
                    println("top_p / top_k:   ${params.TOP_P} / ${params.TOP_K}")
                    println("enable_thinking: ${params.ENABLE_THINKING}")
                    println("judge_strategy:  ${params.JUDGE_STRATEGY}")
                    println("per-task max_tokens JSON: ${params.TASK_MAX_TOKENS_JSON ?: 'N/A'}")
                    println("dataset_args:    ${params.DATASET_ARGS ?: 'N/A'}")
                    println("模型描述:        ${params.DESCRIPTION}")
                    println("邮件接收者:      ${params.RECIPIENTS}")
                    println("工作目录:        ${params.WORK_DIR}")
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
if [ ! -d "${params.WORK_DIR}/.venv" ]; then
    export https_proxy=http://100.64.1.68:1080
    export http_proxy=http://100.64.1.68:1080
    echo "创建虚拟环境..."
    cd ${params.WORK_DIR}
    uv venv
    source .venv/bin/activate
    uv pip install -e .
    deactivate
    unset https_proxy
    unset http_proxy
fi

cd ${params.WORK_DIR}
echo "=== 虚拟环境准备完成 ==="
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
                    if (taskList.isEmpty()) {
                        error '至少需要选择一个测试任务'
                    }
                    env.TASKS = taskList.join(',')

                    def modelDir = params.MODEL.contains("/") ? params.MODEL.split("/").last() : params.MODEL
                    env.MODEL_DIR = modelDir

                    env.API_KEY_STR = params.API_KEY?.toString() ?: ''

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
    --temperature "${params.TEMPERATURE}" \\
    --max-tokens "${params.MAX_TOKENS}" \\
    --top-p "${params.TOP_P}" \\
    --top-k "${params.TOP_K}" \\
    --enable-thinking "${params.ENABLE_THINKING?.toString()?.toLowerCase()}" \\
    --repeats "${params.REPEATS}" \\
    --judge-strategy "${params.JUDGE_STRATEGY}" \\
    --task-max-tokens-json '${params.TASK_MAX_TOKENS_JSON}' \\
    --dataset-args '${params.DATASET_ARGS}' \\
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
                <tr><th>温度</th><td>${params.TEMPERATURE}</td></tr>
                <tr><th>max_tokens</th><td>${params.MAX_TOKENS ?: 'unlimited'}</td></tr>
                <tr><th>top_p / top_k</th><td>${params.TOP_P} / ${params.TOP_K}</td></tr>
                <tr><th>enable_thinking</th><td>${params.ENABLE_THINKING}</td></tr>
                <tr><th>judge_strategy</th><td>${params.JUDGE_STRATEGY}</td></tr>
                <tr><th>per-task max_tokens JSON</th><td>${params.TASK_MAX_TOKENS_JSON ?: 'N/A'}</td></tr>
                <tr><th>dataset_args</th><td>${params.DATASET_ARGS ?: 'N/A'}</td></tr>
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
