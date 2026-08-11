#!/bin/bash
# evalscope 测试脚本主入口
#
# 设计参照 sgl-eval-test/sgl_eval_main.sh 与 lm-evaluation-harness/lm_eval_test.sh:
#   - 顶层定义 run_task 函数,每个任务调用一次
#   - 通过环境变量接收运行期参数(由 run_evalscope.py 设置)
#   - 所有输出 tee 到统一日志文件,便于 Jenkins 邮件解析
#
# run_task 函数签名(需求 #1):
#   run_task MODEL DATASET BASE_URL EXAMPLES [MAX_TOKENS]
#       MODEL       : 模型名称(传给 evalscope eval --model)
#       DATASET     : 单个数据集名(传给 evalscope eval --datasets)
#       BASE_URL    : OpenAI 兼容端点 URL
#       EXAMPLES    : 样本数(--limit);为空则不指定该参数
#       MAX_TOKENS  : 生成最大 token 数(可选,覆盖环境变量)
#
# 采样温度不再有全局参数,改由 TASK_TEMPERATURE_JSON 按任务指定(见下)。
#
# 其余 evalscope 参数通过环境变量传入(需求 #7):
#   API_KEY          OpenAI 风格 api key,默认 EMPTY
#   EVAL_TYPE        评估类型,默认 openai_api
#   EVAL_BATCH_SIZE  并发批大小,默认 1
#   TOP_P            nucleus 概率,默认 0.95
#   TOP_K            top-k 采样,默认 20
#   ENABLE_THINKING  true / false,默认 false
#   TEMPERATURE_FALLBACK  按任务温度未配置时的兜底值,默认 0.0
#   REPEATS          重复次数(k-metrics),空 = 不指定
#   TASK_REPEATS_JSON     可选 JSON,形如 {"humaneval":5},按任务覆盖 REPEATS
#   DATASETS         逗号分隔的多任务列表(本次运行的全部任务)
#   OUTPUT_BASE      结果根目录,传给 evalscope --work-dir
#   TASK_MAX_TOKENS_JSON   可选 JSON,形如 {"mmlu_pro":32768,"gpqa_diamond":32768},
#                          按任务覆盖 MAX_TOKENS(若设置则覆盖全局 MAX_TOKENS)
#   TASK_TIMEOUT_JSON  可选 JSON,形如 {"mcp_atlas":3600},按任务覆盖 timeout(秒)
#   TASK_TOP_P_JSON    可选 JSON,形如 {"deep_swe":1.0},按任务覆盖 top_p
#   TASK_TEMPERATURE_JSON  可选 JSON,形如 {"mmlu_pro":0.0,"math_500":0.6},
#                          按任务指定采样温度(若未命中则用 TEMPERATURE_FALLBACK)
#   DATASET_ARGS     数据集参数 JSON 字符串
#   JUDGE_STRATEGY   评分策略,默认 auto
#   ENABLE_SANDBOX   true / false,默认 false。true 时给所有任务拼
#                    --sandbox {"enabled": true}(仅对 CodeExecutionSandboxMixin
#                    任务如 humaneval 生效,其他任务被 evalscope 忽略)。
#                    启用前需确保 runner 上 Docker 可用且装了 evalscope[sandbox]。
#   JUDGE_MODEL_ID   裁判模型名称(非空时给所有任务拼 --judge-model-args
#                    JSON,含 model_id/api_url/api_key;仅对 LLM judge 任务
#                    如 mcp_atlas 生效,rule-only 任务忽略)
#   JUDGE_API_URL    裁判模型 OpenAI 兼容端点 URL(含 /v1 后缀)
#   JUDGE_API_KEY    裁判模型 API Key,默认 EMPTY
# 注(deep_swe):deep_swe 绕过 EvalScope generation_config,仅将 model.name 传给
#   Pier。temperature/top_p/max_tokens/timeout/base_url/api_key 通过
#   pier_agent_kwargs.config_yaml 注入(因 AgentConfig.env={} 不继承父进程环境,
#   litellm 在 Docker 容器内需从 config_yaml 读取端点信息)。
#
# 注:Jenkinsfile 未暴露的 evalscope knob(min_p / seed / timeout / use_cache)
#   不再透传,统一用 evalscope 自身默认值。

set -o pipefail

ROOT_PATH=$(cd "$(dirname "$0")"; pwd)
cd "${ROOT_PATH}"

# ---------- 从环境变量读取配置(带默认值)----------
MODEL_NAME=${MODEL_NAME:-}
DATASETS=${DATASETS:-mmlu_pro}
LLM_ADDR=${LLM_ADDR:-http://127.0.0.1:8080/v1}
API_KEY=${API_KEY:-EMPTY}
EVAL_TYPE=${EVAL_TYPE:-openai_api}
OUTPUT_BASE=${OUTPUT_BASE:-./output}
EXAMPLES=${EXAMPLES:-}
EVAL_BATCH_SIZE=${EVAL_BATCH_SIZE:-32}
TOP_P=${TOP_P:-0.95}
TOP_K=${TOP_K:-20}
MAX_TOKENS=${MAX_TOKENS:-32768}
ENABLE_THINKING=${ENABLE_THINKING:-false}
REPEATS=${REPEATS:-}
DATASET_ARGS=${DATASET_ARGS:-}
JUDGE_STRATEGY=${JUDGE_STRATEGY:-auto}
ENABLE_SANDBOX=${ENABLE_SANDBOX:-false}
TASK_MAX_TOKENS_JSON=${TASK_MAX_TOKENS_JSON:-}
TASK_TEMPERATURE_JSON=${TASK_TEMPERATURE_JSON:-}
TASK_REPEATS_JSON=${TASK_REPEATS_JSON:-}
TASK_JUDGE_STRATEGY_JSON=${TASK_JUDGE_STRATEGY_JSON:-}
TEMPERATURE_FALLBACK=${TEMPERATURE_FALLBACK:-0.0}
JUDGE_MODEL_ID=${JUDGE_MODEL_ID:-}
JUDGE_API_URL=${JUDGE_API_URL:-}
JUDGE_API_KEY=${JUDGE_API_KEY:-EMPTY}
TASK_TIMEOUT_JSON=${TASK_TIMEOUT_JSON:-}
TASK_TOP_P_JSON=${TASK_TOP_P_JSON:-}

# ---------- 日志文件 ----------
TASKS_UNDERSCORE=$(echo "$DATASETS" | tr ',' '-')
LOG_FILE="${OUTPUT_BASE}/evalscope-${TASKS_UNDERSCORE}.log"
mkdir -p "${OUTPUT_BASE}"

# ---------- 按任务覆盖的 max_tokens ----------
_resolve_max_tokens() {
    local dataset="$1"
    local global_max_tokens="$MAX_TOKENS"
    if [ -n "$TASK_MAX_TOKENS_JSON" ]; then
        local per_task
        per_task=$(python3 -c "
import json, sys
try:
    m = json.loads('''${TASK_MAX_TOKENS_JSON}''')
except Exception:
    m = {}
v = m.get('${dataset}')
print(v if v is not None else '')
" 2>/dev/null || echo "")
        if [ -n "$per_task" ]; then
            echo "$per_task"
            return
        fi
    fi
    echo "$global_max_tokens"
}

# ---------- 按任务指定采样温度 ----------
# 与 _resolve_max_tokens 同构:命中 TASK_TEMPERATURE_JSON 即返回对应值,
# 否则返回 TEMPERATURE_FALLBACK(默认 0.0 = greedy,保证精度评测可复现)。
_resolve_temperature() {
    local dataset="$1"
    local fallback="${TEMPERATURE_FALLBACK:-0.0}"
    if [ -n "$TASK_TEMPERATURE_JSON" ]; then
        local per_task
        per_task=$(python3 -c "
import json, sys
try:
    m = json.loads('''${TASK_TEMPERATURE_JSON}''')
except Exception:
    m = {}
v = m.get('${dataset}')
print(v if v is not None else '')
" 2>/dev/null || echo "")
        if [ -n "$per_task" ]; then
            echo "$per_task"
            return
        fi
    fi
    echo "$fallback"
}

# ---------- 按任务覆盖 repeats ----------
# 命中 TASK_REPEATS_JSON 即返回对应值,否则返回全局 REPEATS(可能为空)。
_resolve_repeats() {
    local dataset="$1"
    if [ -n "$TASK_REPEATS_JSON" ]; then
        local per_task
        per_task=$(python3 -c "
import json, sys
try:
    m = json.loads('''${TASK_REPEATS_JSON}''')
except Exception:
    m = {}
v = m.get('${dataset}')
print(v if v is not None else '')
" 2>/dev/null || echo "")
        if [ -n "$per_task" ]; then
            echo "$per_task"
            return
        fi
    fi
    echo "${REPEATS:-}"
}

# ---------- 按任务覆盖 judge_strategy ----------
# 命中 TASK_JUDGE_STRATEGY_JSON 即返回对应值,否则返回全局 JUDGE_STRATEGY。
# 用途:让 llm_judge_default=True 的任务(如 imo_answerbench)在 auto 下改走 rule,
# 避免未配置裁判模型时报错;其余任务不受影响。
_resolve_judge_strategy() {
    local dataset="$1"
    local fallback="${JUDGE_STRATEGY:-auto}"
    if [ -n "$TASK_JUDGE_STRATEGY_JSON" ]; then
        local per_task
        per_task=$(python3 -c "
import json, sys
try:
    m = json.loads('''${TASK_JUDGE_STRATEGY_JSON}''')
except Exception:
    m = {}
v = m.get('${dataset}')
print(v if v is not None else '')
" 2>/dev/null || echo "")
        if [ -n "$per_task" ]; then
            echo "$per_task"
            return
        fi
    fi
    echo "$fallback"
}

# ---------- 按任务覆盖 timeout ----------
# 命中 TASK_TIMEOUT_JSON 即返回对应值,否则返回全局默认 3600(秒 = 1 小时)。
# 用途:mcp_atlas 多轮 AgentLoop 需更长单次模型调用超时,其余任务用默认值。
_resolve_timeout() {
    local dataset="$1"
    local fallback="${TIMEOUT:-3600}"
    if [ -n "$TASK_TIMEOUT_JSON" ]; then
        local per_task
        per_task=$(python3 -c "
import json, sys
try:
    m = json.loads('''${TASK_TIMEOUT_JSON}''')
except Exception:
    m = {}
v = m.get('${dataset}')
print(v if v is not None else '')
" 2>/dev/null || echo "")
        if [ -n "$per_task" ]; then
            echo "$per_task"
            return
        fi
    fi
    echo "$fallback"
}

# ---------- 按任务覆盖 top_p ----------
# 命中 TASK_TOP_P_JSON 即返回对应值,否则返回全局 TOP_P。
# 用途:deep_swe 等编码 agent 任务需 top_p=1.0,而全局默认 0.95。
_resolve_top_p() {
    local dataset="$1"
    local fallback="${TOP_P:-0.95}"
    if [ -n "$TASK_TOP_P_JSON" ]; then
        local per_task
        per_task=$(python3 -c "
import json, sys
try:
    m = json.loads('''${TASK_TOP_P_JSON}''')
except Exception:
    m = {}
v = m.get('${dataset}')
print(v if v is not None else '')
" 2>/dev/null || echo "")
        if [ -n "$per_task" ]; then
            echo "$per_task"
            return
        fi
    fi
    echo "$fallback"
}

# ---------- 组装 generation-config JSON ----------
_build_generation_config() {
    local max_tokens="$1"
    local temperature="$2"
    local timeout="${3:-3600}"
    local top_p="${4:-${TOP_P}}"

    # shell 使用小写 true/false,Python 需要 True/False,在此转换避免 NameError。
    local enable_thinking_py
    if [ "${ENABLE_THINKING}" = 'true' ]; then
        enable_thinking_py=True
    else
        enable_thinking_py=False
    fi

    python3 -c "
import json
cfg = {
    'max_tokens': ${max_tokens:-32768},
    'temperature': ${temperature:-0.0},
    'top_p': ${top_p},
    'top_k': ${TOP_K},
    'timeout': ${timeout},
    'chat_template_kwargs': {'enable_thinking': ${enable_thinking_py}}
}
print(json.dumps(cfg, ensure_ascii=False))
"
}

# ---------- run_task:接受位置参数 + 通过 env 读取扩展参数 ----------
run_task() {
    local MODEL="$1"            # 必填:模型名
    local DATASET="$2"          # 必填:数据集名
    local BASE_URL="$3"         # 必填:端点 URL
    local EXAMPLES="$4"         # 可空:样本数,空则不指定 --limit
    local MAX_TOKENS_ARG="${5:-$MAX_TOKENS}"

    # 按任务覆盖 max_tokens / temperature
    local task_max_tokens
    task_max_tokens=$(_resolve_max_tokens "$DATASET")
    [ -n "$task_max_tokens" ] && MAX_TOKENS_ARG="$task_max_tokens"

    local TEMPERATURE_ARG
    TEMPERATURE_ARG=$(_resolve_temperature "$DATASET")

    # 按任务覆盖 repeats(命中 TASK_REPEATS_JSON 则覆盖全局 REPEATS)
    local REPEATS_ARG
    REPEATS_ARG=$(_resolve_repeats "$DATASET")

    # 按任务覆盖 judge_strategy(命中 TASK_JUDGE_STRATEGY_JSON 则覆盖全局 JUDGE_STRATEGY)
    local JUDGE_STRATEGY_ARG
    JUDGE_STRATEGY_ARG=$(_resolve_judge_strategy "$DATASET")

    # imo_answerbench 特殊处理:
    #   llm_judge_default=True,在 auto 下会尝试调用裁判模型。
    #   有裁判模型(JUDGE_MODEL_ID 非空)→ 保留 auto,自动启用 LLM judge;
    #   无裁判模型(JUDGE_MODEL_ID 为空)→ 强制 rule,回退到 numeric math_equal 规则评分。
    if [ "$DATASET" = "imo_answerbench" ] && [ -z "$JUDGE_MODEL_ID" ]; then
        JUDGE_STRATEGY_ARG="rule"
    fi

    # 按任务覆盖 timeout(命中 TASK_TIMEOUT_JSON 则覆盖全局默认 3600)
    local TIMEOUT_ARG
    TIMEOUT_ARG=$(_resolve_timeout "$DATASET")

    # 按任务覆盖 top_p(命中 TASK_TOP_P_JSON 则覆盖全局 TOP_P)
    local TOP_P_ARG
    TOP_P_ARG=$(_resolve_top_p "$DATASET")

    # 组装 generation-config JSON
    local gen_config
    gen_config=$(_build_generation_config "$MAX_TOKENS_ARG" "$TEMPERATURE_ARG" "$TIMEOUT_ARG" "$TOP_P_ARG")

    # 组装 evalscope eval 命令的参数数组
    local cmd_args=(
        eval
        --model "$MODEL"
        --api-url "$BASE_URL"
        --api-key "$API_KEY"
        --eval-type "$EVAL_TYPE"
        --datasets "$DATASET"
        --generation-config "$gen_config"
        --eval-batch-size "$EVAL_BATCH_SIZE"
        --work-dir "$OUTPUT_BASE"
        --judge-strategy "$JUDGE_STRATEGY_ARG"
    )

    # ---- 需求 #2:样本数为空则不指定 --limit ----
    [ -n "$EXAMPLES" ] && cmd_args+=(--limit "$EXAMPLES")

    # ---- sandbox:全局开关,仅对 CodeExecutionSandboxMixin 任务生效 ----
    if [ "${ENABLE_SANDBOX}" = 'true' ]; then
        cmd_args+=(--sandbox '{"enabled": true}')
    fi

    # ---- 扩展参数:repeats(支持按任务覆盖)----
    if [ -n "$REPEATS_ARG" ]; then
        cmd_args+=(--repeats "$REPEATS_ARG")
    fi

    if [ -n "$DATASET_ARGS" ]; then
        cmd_args+=(--dataset-args "$DATASET_ARGS")
    fi

    # ---- deep_swe 专属:注入 pier_agent_kwargs + 环境变量(若用户未通过 DATASET_ARGS 指定)----
    # deep_swe 绕过 EvalScope generation_config,仅将 model.name 传给 Pier,因此
    # temperature/top_p/max_tokens/timeout 需通过 pier_agent_kwargs.config_yaml 传递。
    # 对齐官方 GLM-5.2 配置:temperature=1.0, top_p=1.0, 400K context, 24h timeout(低性能机器可调大)。
    # litellm 在 Docker 容器内运行,AgentConfig.env={} 不继承父进程环境变量,
    # 因此 base_url/api_key 需写入 config_yaml 供 litellm 读取。
    if [ "$DATASET" = "deep_swe" ] && [ -z "$DATASET_ARGS" ]; then
        local deep_swe_args
        deep_swe_args=$(TEMPERATURE="$TEMPERATURE_ARG" \
                        TOP_P="$TOP_P_ARG" \
                        MAX_TOKENS="$MAX_TOKENS_ARG" \
                        TIMEOUT="$TIMEOUT_ARG" \
                        BASE_URL="$BASE_URL" \
                        API_KEY="${API_KEY}" \
                        MODEL_NAME="$MODEL" \
                        python3 -c "
import json, os
config_yaml = (
    f'agent:\n'
    f'  model:\n'
    f'    temperature: {os.environ.get(\"TEMPERATURE\", \"1.0\")}\n'
    f'    top_p: {os.environ.get(\"TOP_P\", \"1.0\")}\n'
    f'    max_tokens: {os.environ.get(\"MAX_TOKENS\", \"409600\")}\n'
    f'    timeout: {os.environ.get(\"TIMEOUT\", \"86400\")}\n'
    f'    base_url: \"{os.environ.get(\"BASE_URL\", \"\")}\"\n'
    f'    api_key: \"{os.environ.get(\"API_KEY\", \"EMPTY\")}\"\n'
)
args = {
    'deep_swe': {
        'extra_params': {
            'pier_agent_kwargs': {
                'model_class': 'litellm',
                'config_yaml': config_yaml,
            }
        }
    }
}
print(json.dumps(args, ensure_ascii=False))
")
        cmd_args+=(--dataset-args "$deep_swe_args")
    fi

    # ---- judge-model-args:全局,仅当配置了裁判模型时传入 ----
    # 任何需要 LLM judge 的任务(mcp_atlas/imo_answerbench 等)都会使用此配置;
    # rule-only 任务(mmlu_pro/gpqa_diamond 等)忽略此参数。
    local judge_args_json=""
    if [ -n "$JUDGE_MODEL_ID" ]; then
        judge_args_json=$(JUDGE_MODEL_ID="$JUDGE_MODEL_ID" \
                          JUDGE_API_URL="$JUDGE_API_URL" \
                          JUDGE_API_KEY="$JUDGE_API_KEY" \
                          python3 -c "
import json, os
args = {'model_id': os.environ['JUDGE_MODEL_ID']}
api_url = os.environ.get('JUDGE_API_URL', '')
if api_url:
    args['api_url'] = api_url
api_key = os.environ.get('JUDGE_API_KEY', 'EMPTY')
args['api_key'] = api_key if api_key else 'EMPTY'
print(json.dumps(args, ensure_ascii=False))
")
        cmd_args+=(--judge-model-args "$judge_args_json")
    fi

    # ---- mcp_atlas 专属:agent-config(native AgentLoop + function_calling)----
    if [ "$DATASET" = "mcp_atlas" ]; then
        cmd_args+=(--agent-config '{"mode":"native","strategy":"function_calling","max_steps":100}')
    fi

    echo ""                                          | tee -a "$LOG_FILE"
    echo "========================================"   | tee -a "$LOG_FILE"
    echo "Running Task: $DATASET"                    | tee -a "$LOG_FILE"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"        | tee -a "$LOG_FILE"
    echo "========================================"   | tee -a "$LOG_FILE"
    echo "Config:"                                   | tee -a "$LOG_FILE"
    echo "  MODEL            : $MODEL"               | tee -a "$LOG_FILE"
    echo "  DATASET          : $DATASET"             | tee -a "$LOG_FILE"
    echo "  BASE_URL         : $BASE_URL"            | tee -a "$LOG_FILE"
    echo "  EVAL_TYPE        : $EVAL_TYPE"           | tee -a "$LOG_FILE"
    echo "  EXAMPLES         : ${EXAMPLES:-<unlimited>}"  | tee -a "$LOG_FILE"
    echo "  EVAL_BATCH_SIZE  : $EVAL_BATCH_SIZE"     | tee -a "$LOG_FILE"
    echo "  TEMPERATURE      : $TEMPERATURE_ARG"     | tee -a "$LOG_FILE"
    echo "  MAX_TOKENS       : ${MAX_TOKENS_ARG:-<unlimited>}" | tee -a "$LOG_FILE"
    echo "  TIMEOUT          : ${TIMEOUT_ARG}s"             | tee -a "$LOG_FILE"
    echo "  TOP_P            : $TOP_P_ARG"               | tee -a "$LOG_FILE"
    echo "  TOP_K            : $TOP_K"               | tee -a "$LOG_FILE"
    echo "  ENABLE_THINKING  : $ENABLE_THINKING"     | tee -a "$LOG_FILE"
    echo "  REPEATS          : ${REPEATS_ARG:-<default 1>}"  | tee -a "$LOG_FILE"
    echo "  JUDGE_STRATEGY   : $JUDGE_STRATEGY_ARG"      | tee -a "$LOG_FILE"
    echo "  ENABLE_SANDBOX   : $ENABLE_SANDBOX"      | tee -a "$LOG_FILE"
    echo "  DATASET_ARGS     : ${DATASET_ARGS:-<none>}"  | tee -a "$LOG_FILE"
    echo "  JUDGE_MODEL_ID   : ${JUDGE_MODEL_ID:-<none>}" | tee -a "$LOG_FILE"
    echo "  JUDGE_API_URL    : ${JUDGE_API_URL:-<none>}"  | tee -a "$LOG_FILE"
    echo "  judge-model-args : ${judge_args_json:-<none>}" | tee -a "$LOG_FILE"
    if [ "$DATASET" = "deep_swe" ] && [ -z "$DATASET_ARGS" ]; then
        echo "  deep_swe_args    : ${deep_swe_args}"          | tee -a "$LOG_FILE"
    fi
    echo "  WORK_DIR         : ${OUTPUT_BASE}"       | tee -a "$LOG_FILE"
    echo "  generation-config: $gen_config"          | tee -a "$LOG_FILE"
    echo "========================================"   | tee -a "$LOG_FILE"
    echo "Command: evalscope ${cmd_args[*]}"         | tee -a "$LOG_FILE"
    echo ""                                          | tee -a "$LOG_FILE"

    # ---- 失败不中断后续任务(catchError 风格)----
    if ! evalscope "${cmd_args[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        echo "[WARN] task $DATASET failed (exit $?), continuing..." | tee -a "$LOG_FILE"
    fi
}

# ---------- 主流程:打印总体配置 + 按逗号分发到 run_task ----------
{
    echo "========================================"
    echo "evalscope Test Start"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================"
    echo "Config:"
    echo "  LLM_ADDR          : $LLM_ADDR"
    echo "  MODEL_NAME        : $MODEL_NAME"
    echo "  DATASETS          : $DATASETS"
    echo "  EVAL_TYPE         : $EVAL_TYPE"
    echo "  EXAMPLES          : ${EXAMPLES:-<unlimited>}"
    echo "  EVAL_BATCH_SIZE   : $EVAL_BATCH_SIZE"
    echo "  TEMPERATURE       : <per-task; fallback=$TEMPERATURE_FALLBACK>"
    echo "  TASK_TEMPERATURE_JSON : ${TASK_TEMPERATURE_JSON:-<none>}"
    echo "  MAX_TOKENS        : ${MAX_TOKENS:-<unlimited>}"
    echo "  TASK_TIMEOUT_JSON : ${TASK_TIMEOUT_JSON:-<none>}"
    echo "  TOP_P             : $TOP_P"
    echo "  TASK_TOP_P_JSON   : ${TASK_TOP_P_JSON:-<none>}"
    echo "  TOP_K             : $TOP_K"
    echo "  ENABLE_THINKING   : $ENABLE_THINKING"
    echo "  REPEATS           : ${REPEATS:-<default 1>}"
    echo "  TASK_REPEATS_JSON : ${TASK_REPEATS_JSON:-<none>}"
    echo "  JUDGE_STRATEGY    : $JUDGE_STRATEGY"
    echo "  TASK_JUDGE_STRATEGY_JSON : ${TASK_JUDGE_STRATEGY_JSON:-<none>}"
    echo "  ENABLE_SANDBOX    : $ENABLE_SANDBOX"
    echo "  DATASET_ARGS      : ${DATASET_ARGS:-<none>}"
    echo "  JUDGE_MODEL_ID    : ${JUDGE_MODEL_ID:-<none>}"
    echo "  JUDGE_API_URL     : ${JUDGE_API_URL:-<none>}"
    echo "  JUDGE_API_KEY     : ${JUDGE_API_KEY:-<none>}"
    echo "  OUTPUT_BASE       : $OUTPUT_BASE"
    echo "  LOG_FILE          : $LOG_FILE"
    echo "========================================"
} | tee "$LOG_FILE"

IFS=',' read -ra TASK_LIST <<< "$DATASETS"
for task in "${TASK_LIST[@]}"; do
    task=$(echo "$task" | xargs)   # 去除前后空白
    [ -z "$task" ] && continue
    run_task "$MODEL_NAME" "$task" "$LLM_ADDR" "$EXAMPLES"
done

echo ""                                          | tee -a "$LOG_FILE"
echo "========================================"   | tee -a "$LOG_FILE"
echo "evalscope Test Complete"                    | tee -a "$LOG_FILE"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"        | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE"                        | tee -a "$LOG_FILE"
echo "Output dir: $OUTPUT_BASE"                   | tee -a "$LOG_FILE"
echo "========================================"   | tee -a "$LOG_FILE"
