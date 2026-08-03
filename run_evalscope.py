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
     temperature / top_p / top_k / min_p / enable_thinking 等独立参数后注入
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
        help="任务列表,逗号分隔(默认 mmlu_pro)。可选: mmlu_pro, gpqa_diamond",
    )
    parser.add_argument("--examples", default="", help="样本数限制(空 = 不限制)")
    parser.add_argument(
        "--eval-batch-size",
        default="1",
        help="并发批大小(对应 evalscope --eval-batch-size,默认 1)",
    )
    parser.add_argument("--temperature", default="0.6", help="采样温度(默认 0.6)")
    parser.add_argument(
        "--max-tokens",
        default="30000",
        help="生成最大 token 数(默认 30000;空 = 不指定)",
    )
    parser.add_argument("--top-p", default="0.95", help="nucleus top_p(默认 0.95)")
    parser.add_argument("--top-k", default="20", help="top-k 采样(默认 20)")
    parser.add_argument("--min-p", default="0", help="min-p 采样(默认 0)")
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
    parser.add_argument("--timeout", default="", help="请求超时秒数(空 = 不指定)")
    parser.add_argument("--seed", default="42", help="随机种子(默认 42)")
    parser.add_argument(
        "--judge-strategy",
        default="auto",
        choices=["auto", "rule", "llm", "llm_recall"],
        help="评分策略(默认 auto)",
    )
    parser.add_argument("--use-cache", default="", help="复用缓存路径(空 = 不复用)")
    parser.add_argument(
        "--dataset-args", default="", help="数据集参数 JSON 字符串(空 = 不指定)"
    )
    parser.add_argument(
        "--task-max-tokens-json",
        default="",
        help='按任务覆盖 max_tokens 的 JSON,例: {"mmlu_pro":32768,"gpqa_diamond":32768}',
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
    env["TEMPERATURE"] = args.temperature
    if args.max_tokens:
        env["MAX_TOKENS"] = args.max_tokens
    env["TOP_P"] = args.top_p
    env["TOP_K"] = args.top_k
    env["MIN_P"] = args.min_p
    env["ENABLE_THINKING"] = args.enable_thinking
    if args.repeats:
        env["REPEATS"] = args.repeats
    if args.timeout:
        env["TIMEOUT"] = args.timeout
    env["SEED"] = args.seed
    env["JUDGE_STRATEGY"] = args.judge_strategy
    if args.use_cache:
        env["USE_CACHE"] = args.use_cache
    if args.dataset_args:
        env["DATASET_ARGS"] = args.dataset_args
    if args.task_max_tokens_json:
        env["TASK_MAX_TOKENS_JSON"] = args.task_max_tokens_json

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
        "TEMPERATURE",
        "MAX_TOKENS",
        "TOP_P",
        "TOP_K",
        "MIN_P",
        "ENABLE_THINKING",
        "REPEATS",
        "TIMEOUT",
        "SEED",
        "JUDGE_STRATEGY",
        "USE_CACHE",
        "DATASET_ARGS",
        "TASK_MAX_TOKENS_JSON",
    ]:
        if k in env:
            print(f"  {k}={env[k]}")
    print("=" * 60)

    result = subprocess.run(cmd, env=env)

    print(f"Test completed. Output directory: {output_dir}")
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
