#!/usr/bin/env python3
"""evalscope 测试编排脚本。

由 Jenkinsfile 远程调用,负责:
1. 解析 Jenkins 传入的参数
2. 创建结果目录(结构对齐 sgl-eval-test):
       output/<tester>/<build_number>/<chip>/<model>/<timestamp>/
3. 设置环境变量并通过 bash 调用 evalscope_main.sh
4. 透传退出码

与 sgl-eval-test/run_sgleval.py 的差异:
   - 本仓库编排脚本命名为 run_evalscope.py(避免与其他测试框架的 run_eval.py 混淆,
     Jenkinsfile 清理残留进程时按全字符串 run_evalscope.py 匹配,不会误杀其他框架)
   - evalscope 的 generation-config 是单个 JSON 字符串,拆分为 max_tokens /
     top_p / top_k / enable_thinking 等独立参数后注入;采样温度改为
     按任务通过 TASK_TEMPERATURE_JSON 指定(无全局 TEMPERATURE)。仅保留
     Jenkinsfile 暴露的参数,min_p / seed / timeout / use_cache 等未暴露
     的 knob 不再透传(用 evalscope 自身默认值)
   - 多任务由 --tasks 逗号分隔,在一次 bash 调用里串行执行
   - evalscope 的 --limit 等价于 sgl-eval 的 --num-examples
   - evalscope 的 --repeats 等价于 sgl-eval 的 --n-repeats
"""

import argparse
import os
import subprocess
import sys
from datetime import datetime


def parse_args():
    parser = argparse.ArgumentParser(description="Run evalscope test via shell script")
    parser.add_argument("--tester", required=True, help="测试人员名称")
    parser.add_argument("--build-number", required=True, help="Jenkins 构建编号")
    parser.add_argument("--chip", required=True, help="芯片平台名称")
    parser.add_argument(
        "--model", required=True, help="模型服务名称(对应 evalscope eval --model)"
    )
    parser.add_argument(
        "--base-url",
        required=True,
        help="OpenAI 兼容端点 URL(如 http://10.201.149.34:8000/v1)",
    )
    parser.add_argument("--api-key", default="EMPTY", help="API Key(无需认证时留空)")
    parser.add_argument(
        "--tasks",
        default="mmlu_pro",
        help="任务列表,逗号分隔(默认 mmlu_pro)。可选: mmlu_pro, aime26, gpqa_diamond, ceval, cmmlu, math_500, hellaswag, humaneval, humaneval_plus, hmmt25, hmmt26, imo_answerbench, mcp_atlas, deep_swe",
    )
    parser.add_argument("--examples", default="", help="样本数限制(空 = 不限制)")
    parser.add_argument(
        "--eval-batch-size",
        default="8",
        help="并发批大小(对应 evalscope --eval-batch-size,默认 8)",
    )
    parser.add_argument(
        "--task-temperature-json",
        default="",
        help='按任务指定采样温度的 JSON,例: {"mmlu_pro":0.0,"math_500":0.6}',
    )
    parser.add_argument(
        "--temperature-fallback",
        default="1.0",
        help="TASK_TEMPERATURE_JSON 未命中任务时的兜底采样温度(默认 1.0,适配 thinking 模式推理模型)",
    )
    parser.add_argument(
        "--max-tokens",
        default="32768",
        help="生成最大 token 数(默认 32768;空 = 不指定)",
    )
    parser.add_argument("--top-p", default="0.95", help="nucleus top_p(默认 0.95)")
    parser.add_argument("--top-k", default="20", help="top-k 采样(默认 20)")
    parser.add_argument(
        "--enable-thinking",
        default="false",
        choices=["true", "false"],
        help="启用 thinking 模式(默认 false)",
    )
    parser.add_argument(
        "--repeats",
        default="",
        help="重复次数(对应 evalscope --repeats,空 = 默认 1)",
    )
    parser.add_argument(
        "--task-repeats-json",
        default="",
        help='按任务覆盖 repeats 的 JSON,例: {"humaneval":5};命中任务覆盖全局 --repeats',
    )
    parser.add_argument(
        "--judge-strategy",
        default="auto",
        choices=["auto", "rule", "llm", "llm_recall"],
        help="评分策略(默认 auto)",
    )
    parser.add_argument(
        "--task-judge-strategy-json",
        default="",
        help='按任务覆盖 judge_strategy 的 JSON,例: {"imo_answerbench":"rule"}。'
        "命中任务使用对应值,未命中任务用全局 judge-strategy;为空则全部用全局。"
        "用途:让 llm_judge_default=True 的任务(如 imo_answerbench)改走 rule,"
        "避免未配置裁判模型时报错",
    )
    parser.add_argument(
        "--enable-sandbox",
        default="false",
        choices=["true", "false"],
        help="启用 sandbox 执行(默认 false)。true 时给所有任务拼 --sandbox "
        '{"enabled": true},仅对 CodeExecutionSandboxMixin 任务(如 humaneval)'
        "生效;需 runner 上 Docker 可用且装了 evalscope[sandbox]",
    )
    parser.add_argument(
        "--dataset-args", default="", help="数据集参数 JSON 字符串(空 = 不指定)"
    )
    parser.add_argument(
        "--judge-model-id",
        default="",
        help="裁判模型名称(用于 mcp_atlas 等 LLM judge 任务,对应 judge_model_args.model_id)",
    )
    parser.add_argument(
        "--judge-api-url",
        default="",
        help="裁判模型 OpenAI 兼容端点 URL(含 /v1 后缀,如 http://10.201.149.41:8080/v1)",
    )
    parser.add_argument(
        "--judge-api-key",
        default="EMPTY",
        help="裁判模型 API Key(无需认证时填 EMPTY)",
    )
    parser.add_argument(
        "--task-max-tokens-json",
        default="",
        help='按任务覆盖 max_tokens 的 JSON,例: {"mmlu_pro":32768,"gpqa_diamond":32768}',
    )
    parser.add_argument(
        "--task-timeout-json",
        default="",
        help='按任务覆盖 timeout(秒)的 JSON,例: {"mcp_atlas":3600}。命中任务使用对应值,未命中任务用默认 3600(1 小时)',
    )
    parser.add_argument(
        "--task-top-p-json",
        default="",
        help='按任务覆盖 top_p 的 JSON,例: {"deep_swe":1.0}。命中任务使用对应值,未命中任务用全局 TOP_P',
    )
    parser.add_argument(
        "--description",
        default="",
        help="模型服务描述信息(仅用于邮件展示,不影响执行)",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    model_dir = args.model.split("/")[-1]
    output_dir = os.path.abspath(
        f"./output/{args.tester}/{args.build_number}/{args.chip}/{model_dir}/{timestamp}"
    )
    os.makedirs(output_dir, exist_ok=True)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    shell_script = os.path.join(script_dir, "evalscope_main.sh")

    if not os.path.exists(shell_script):
        print(f"Error: Shell script not found at {shell_script}")
        sys.exit(1)

    env = os.environ.copy()
    env["MODEL_NAME"] = args.model
    env["DATASETS"] = args.tasks
    env["LLM_ADDR"] = args.base_url
    env["API_KEY"] = args.api_key or "EMPTY"
    env["OUTPUT_BASE"] = output_dir
    if args.examples:
        env["EXAMPLES"] = args.examples
    env["EVAL_BATCH_SIZE"] = args.eval_batch_size
    if args.task_temperature_json:
        env["TASK_TEMPERATURE_JSON"] = args.task_temperature_json
    env["TEMPERATURE_FALLBACK"] = args.temperature_fallback
    if args.max_tokens:
        env["MAX_TOKENS"] = args.max_tokens
    env["TOP_P"] = args.top_p
    env["TOP_K"] = args.top_k
    env["ENABLE_THINKING"] = args.enable_thinking
    if args.repeats:
        env["REPEATS"] = args.repeats
    if args.task_repeats_json:
        env["TASK_REPEATS_JSON"] = args.task_repeats_json
    env["JUDGE_STRATEGY"] = args.judge_strategy
    if args.task_judge_strategy_json:
        env["TASK_JUDGE_STRATEGY_JSON"] = args.task_judge_strategy_json
    env["ENABLE_SANDBOX"] = args.enable_sandbox
    if args.dataset_args:
        env["DATASET_ARGS"] = args.dataset_args
    if args.task_max_tokens_json:
        env["TASK_MAX_TOKENS_JSON"] = args.task_max_tokens_json
    if args.task_timeout_json:
        env["TASK_TIMEOUT_JSON"] = args.task_timeout_json
    if args.task_top_p_json:
        env["TASK_TOP_P_JSON"] = args.task_top_p_json
    if args.judge_model_id:
        env["JUDGE_MODEL_ID"] = args.judge_model_id
    if args.judge_api_url:
        env["JUDGE_API_URL"] = args.judge_api_url
    env["JUDGE_API_KEY"] = args.judge_api_key or "EMPTY"

    cmd = ["bash", shell_script]

    print(f"Output directory: {output_dir}")
    print(f"Command: {' '.join(cmd)}")
    print("Environment overrides:")
    for k in [
        "MODEL_NAME",
        "DATASETS",
        "LLM_ADDR",
        "API_KEY",
        "OUTPUT_BASE",
        "EXAMPLES",
        "EVAL_BATCH_SIZE",
        "TEMPERATURE_FALLBACK",
        "TASK_TEMPERATURE_JSON",
        "MAX_TOKENS",
        "TOP_P",
        "TOP_K",
        "ENABLE_THINKING",
        "REPEATS",
        "TASK_REPEATS_JSON",
        "JUDGE_STRATEGY",
        "TASK_JUDGE_STRATEGY_JSON",
        "ENABLE_SANDBOX",
        "DATASET_ARGS",
        "TASK_MAX_TOKENS_JSON",
        "TASK_TIMEOUT_JSON",
        "TASK_TOP_P_JSON",
        "JUDGE_MODEL_ID",
        "JUDGE_API_URL",
        "JUDGE_API_KEY",
    ]:
        if k in env:
            print(f"  {k}={env[k]}")
    print("=" * 60)

    result = subprocess.run(cmd, env=env)

    print(f"Test completed. Output directory: {output_dir}")
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
