#!/bin/bash
# evalscope 测试脚本主入口
#
# 设计参照 sgl-eval-test/sgl_eval_main.sh 与 lm-evaluation-harness/lm_eval_test.sh:
#   - 顶层定义 run_task 函数,每个任务调用一次
#   - 通过环境变量接收运行期参数(由 run_evalscope.py 设置)
#   - 所有输出 tee 到统一日志文件,便于 Jenkins 邮件解析
#
# run_task 函数签名(需求 #1):
#   run_task MODEL DATASET BASE_URL EXAMPLES [MAX_TOKENS] [TEMPERATURE]
#       MODEL       : 模型名称(传给 evalscope eval --model)
#       DATASET     : 单个数据集名(传给 evalscope eval --datasets)
#       BASE_URL    : OpenAI 兼容端点 URL
#       EXAMPLES    : 样本数(--limit);为空则不指定该参数
#       MAX_TOKENS  : 生成最大 token 数(可选,覆盖环境变量)
#       TEMPERATURE : 采样温度(可选,覆盖环境变量)
#
# 其余 evalscope 参数通过环境变量传入(需求 #7):
#   API_KEY          OpenAI 风格 api key,默认 EMPTY
#   EVAL_TYPE        评估类型,默认 openai_api
#   TIMEOUT          请求超时(秒),空 = 不指定
#   EVAL_BATCH_SIZE  并发批大小,默认 1
#   TOP_P            nucleus 概率,默认 0.95
#   TOP_K            top-k 采样,默认 20
#   MIN_P            min-p 采样,默认 0
#   ENABLE_THINKING  true / false,默认 false
#   REPEATS          重复次数(k-metrics),空 = 不指定
#   SEED             随机种子,默认 42
#   DATASETS         逗号分隔的多任务列表(本次运行的全部任务)
#   OUTPUT_BASE      结果根目录,传给 evalscope --work-dir
#   TASK_MAX_TOKENS_JSON   可选 JSON,形如 {"mmlu_pro":32768,"gpqa_diamond":32768},
#                          按任务覆盖 MAX_TOKENS(若设置则覆盖全局 MAX_TOKENS)
#   DATASET_ARGS     数据集参数 JSON 字符串
#   JUDGE_STRATEGY   评分策略,默认 auto
#   USE_CACHE        复用缓存路径,空 = 不复用

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
TIMEOUT=${TIMEOUT:-}
EVAL_BATCH_SIZE=${EVAL_BATCH_SIZE:-1}
TEMPERATURE=${TEMPERATURE:-0.6}
TOP_P=${TOP_P:-0.95}
TOP_K=${TOP_K:-20}
MIN_P=${MIN_P:-0}
MAX_TOKENS=${MAX_TOKENS:-32768}
ENABLE_THINKING=${ENABLE_THINKING:-false}
REPEATS=${REPEATS:-}
SEED=${SEED:-42}
DATASET_ARGS=${DATASET_ARGS:-}
JUDGE_STRATEGY=${JUDGE_STRATEGY:-auto}
USE_CACHE=${USE_CACHE:-}
TASK_MAX_TOKENS_JSON=${TASK_MAX_TOKENS_JSON:-}

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

# ---------- 组装 generation-config JSON ----------
_build_generation_config() {
    local max_tokens="$1"
    local temperature="$2"

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
    'temperature': ${temperature:-0.6},
    'top_p': ${TOP_P},
    'top_k': ${TOP_K},
    'MinP': ${MIN_P},
    'timeout': 3600,
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
    local TEMPERATURE_ARG="${6:-$TEMPERATURE}"

    # 按任务覆盖 max_tokens
    local task_max_tokens
    task_max_tokens=$(_resolve_max_tokens "$DATASET")
    [ -n "$task_max_tokens" ] && MAX_TOKENS_ARG="$task_max_tokens"

    # 组装 generation-config JSON
    local gen_config
    gen_config=$(_build_generation_config "$MAX_TOKENS_ARG" "$TEMPERATURE_ARG")

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
        --seed "$SEED"
        --judge-strategy "$JUDGE_STRATEGY"
    )

    # ---- 需求 #2:样本数为空则不指定 --limit ----
    [ -n "$EXAMPLES" ] && cmd_args+=(--limit "$EXAMPLES")

    # ---- 扩展参数:repeats / use-cache ----
    if [ -n "$REPEATS" ]; then
        cmd_args+=(--repeats "$REPEATS")
    fi

    if [ -n "$USE_CACHE" ]; then
        cmd_args+=(--use-cache "$USE_CACHE")
    fi

    if [ -n "$DATASET_ARGS" ]; then
        cmd_args+=(--dataset-args "$DATASET_ARGS")
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
    echo "  TOP_P            : $TOP_P"               | tee -a "$LOG_FILE"
    echo "  TOP_K            : $TOP_K"               | tee -a "$LOG_FILE"
    echo "  MIN_P            : $MIN_P"               | tee -a "$LOG_FILE"
    echo "  ENABLE_THINKING  : $ENABLE_THINKING"     | tee -a "$LOG_FILE"
    echo "  REPEATS          : ${REPEATS:-<default 1>}"   | tee -a "$LOG_FILE"
    echo "  TIMEOUT          : ${TIMEOUT:-<unset>}"  | tee -a "$LOG_FILE"
    echo "  SEED             : $SEED"                | tee -a "$LOG_FILE"
    echo "  JUDGE_STRATEGY   : $JUDGE_STRATEGY"      | tee -a "$LOG_FILE"
    echo "  USE_CACHE        : ${USE_CACHE:-<no>}"   | tee -a "$LOG_FILE"
    echo "  DATASET_ARGS     : ${DATASET_ARGS:-<none>}"  | tee -a "$LOG_FILE"
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
    echo "  TEMPERATURE       : $TEMPERATURE"
    echo "  MAX_TOKENS        : ${MAX_TOKENS:-<unlimited>}"
    echo "  TOP_P             : $TOP_P"
    echo "  TOP_K             : $TOP_K"
    echo "  MIN_P             : $MIN_P"
    echo "  ENABLE_THINKING   : $ENABLE_THINKING"
    echo "  REPEATS           : ${REPEATS:-<default 1>}"
    echo "  TIMEOUT           : ${TIMEOUT:-<unset>}"
    echo "  SEED              : $SEED"
    echo "  JUDGE_STRATEGY    : $JUDGE_STRATEGY"
    echo "  USE_CACHE         : ${USE_CACHE:-<no>}"
    echo "  DATASET_ARGS      : ${DATASET_ARGS:-<none>}"
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
