# evalscope-test

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Python](https://img.shields.io/badge/python-3.10%20%7C%203.11%20%7C%203.12-blue.svg)](https://www.python.org/)

基于 [EvalScope](https://github.com/modelscope/evalscope) 的精度评测封装,面向
OpenAI 兼容推理服务,提供 Jenkins 流水线 + 远程执行 + 自动邮件报告的一键式测试。

---

## 概述

本仓库在 EvalScope 之上增加了一层 **CI/CD 编排**,核心是三个文件:

| 文件 | 角色 |
|------|------|
| `evalscope_main.sh` | shell 主入口,定义 `run_task` 函数,串行跑多个数据集 |
| `run_eval.py` | Python 编排器,Jenkins → shell 的桥 |
| `Jenkinsfile` | Jenkins 声明式流水线:远程 ssh 执行、拉取结果、发邮件 |

设计参照 [sgl-eval-test](https://github.com/maas/sgl-eval-test) 仓库的
`sgl_eval_main.sh` / `run_eval.py` / `Jenkinsfile` 三件套,命名、目录层级、
邮件渲染逻辑保持一致,仅按 evalscope 的参数面和 report 结构做适配。

---

## Quick start

### 1. 安装

```bash
git clone <repo-url> evalscope-test
cd evalscope-test
pip install -e .          # 安装 evalscope 及依赖
```

### 2. 本地 smoke 测试

```bash
# 直接调 shell(默认 mmlu_pro / 无样本限制 / localhost)
bash evalscope_main.sh

# 通过环境变量覆盖
MODEL_NAME=glm-5.2 \
DATASETS=mmlu_pro \
LLM_ADDR=http://10.201.149.34:8000/v1 \
EXAMPLES=50 \
OUTPUT_BASE=./output/smoke \
bash evalscope_main.sh
```

### 3. 通过 run_eval.py 编排(复现 Jenkins 行为)

```bash
python3 run_eval.py \
    --tester liwt \
    --build-number manual001 \
    --chip nvidia-h100 \
    --model glm-5.2 \
    --base-url http://10.201.149.34:8000/v1 \
    --tasks mmlu_pro,gpqa_diamond \
    --examples 50 \
    --temperature 0.6 \
    --max-tokens 30000
```

`run_eval.py` 会:
1. 创建 `./output/liwt/manual001/nvidia-h100/glm-5.2/<timestamp>/`
2. 设置环境变量(`MODEL_NAME` / `DATASETS` / `LLM_ADDR` / `OUTPUT_BASE` / ...)
3. 调 `bash evalscope_main.sh`,透传退出码

### 4. 通过 Jenkins 触发(生产路径)

打开 Jenkins job → Build with Parameters → 勾选任务、填端点 → 构建。
Jenkins 通过 ssh 远程到 `REMOTE_HOST`(默认 `10.201.132.50`)在 `WORK_DIR` 下
跑 `run_eval.py`,完成后 scp 拉回结果、归档、发邮件。

---

## 支持的数据集(需求 #9)

当前流水线 **默认暴露** 两个基准,均为多选题(accuracy):

| 数据集 | dataset_id | 默认 few-shot | 子集数 | 说明 |
|--------|------------|----------------|--------|------|
| `mmlu_pro` | `TIGER-Lab/MMLU-Pro` | 5-shot | 14 | 10 选项多学科多选,要求 step-by-step 推理,答案格式 `ANSWER: [LETTER]` |
| `gpqa_diamond` | `AI-ModelScope/gpqa_diamond` | 0-shot | 1 | 博士级 4 选择(biology/physics/chemistry),198 题,答案随机打乱 |

> EvalScope 本身支持更多基准(如 gsm8k、aime、arc、ceval 等),可按需在
> `Jenkinsfile` 的 `parameters` 块添加 `booleanParam` 并在 `运行evalscope测试`
> stage 拼接到 `env.TASKS`。

---

## 核心命令(base command)

`evalscope_main.sh:run_task` 组装并执行以下命令(需求 #1):

```bash
evalscope eval \
    --model "${model}" \
    --api-url "${BASE_URL}" \
    --api-key "${API_KEY}" \
    --eval-type openai_api \
    --datasets "${dataset}" \
    --generation-config '{"max_tokens":30000,"temperature":0.6,"top_p":0.95,"top_k":20,"MinP":0,"chat_template_kwargs":{"enable_thinking":false}}' \
    --timeout ${TIMEOUT} \
    --eval-batch-size ${BS} \
    --work-dir "${OUTPUT_DIR}"
```

其中 `max_tokens` / `temperature` 等通过环境变量参数化注入 `generation-config`
JSON(需求 #1、#2)。`run_eval.py` 负责把 Jenkins 参数翻译为环境变量,
`evalscope_main.sh` 负责把环境变量组装成最终命令。

---

## 输出目录与日志层级(需求 #4)

```
<WORK_DIR>/output/<tester>/<build_number>/<chip>/<model>/<timestamp>/
├── evalscope-<tasks>.log                 # 全程 tee 出来的总日志(邮件附件)
└── <evalscope_internal_timestamp>/       # evalscope 自动加的时间戳子目录
    ├── configs/                          # TaskConfig 快照(yaml)
    ├── logs/                             # evalscope 内部日志
    ├── predictions/                      # 每样本预测(jsonl)
    ├── reviews/                          # 每样本评分(jsonl)
    └── reports/                          # 最终报告
        └── <model_name>/
            └── <dataset_name>.json       # report JSON(邮件解析该文件)
```

`<tester>` / `<build_number>` / `<chip>` / `<model>` / `<timestamp>` 五层
与 sgl-eval-test 完全一致,便于跨框架横向比对。`reports/<model>/<dataset>.json`
由 `evalscope/report/report.py:Report.to_json` 写入,邮件 stage 通过
`readJSON` 直接读取,不解析 stdout 表格。

---

## 更多 evalscope 参数(需求 #7)

`Jenkinsfile` 已暴露以下 evalscope `eval` 子命令参数:

| Jenkins 参数 | evalscope flag | 默认 | 说明 |
|--------------|----------------|------|------|
| `MODEL` | `--model` | `glm-5.2` | 模型服务名 |
| `BASE_URL` | `--api-url` | `http://10.201.149.34:8000/v1` | 端点(自动拼 /v1) |
| `API_KEY` | `--api-key` | 空 → `EMPTY` | 鉴权 |
| `TASK_MMLU_PRO` / `TASK_GPQA_DIAMOND` | `--datasets` | 见 checkbox | 勾选后逗号拼接 |
| `EXAMPLES` | `--limit` | 空 | 空 = 跑全集;int=数量,float=比例 |
| `REPEATS` | `--repeats` | 空 | 重复次数(k-metrics),空 = 默认 1 |
| `EVAL_BATCH_SIZE` | `--eval-batch-size` | `1` | 并发批大小 |
| `TEMPERATURE` | `--generation-config temperature` | `0.6` | 注入 generation-config |
| `MAX_TOKENS` | `--generation-config max_tokens` | `30000` | 注入 generation-config |
| `TOP_P` | `--generation-config top_p` | `0.95` | 注入 generation-config |
| `TOP_K` | `--generation-config top_k` | `20` | 注入 generation-config |
| `MIN_P` | `--generation-config MinP` | `0` | 注入 generation-config |
| `ENABLE_THINKING` | `--generation-config chat_template_kwargs.enable_thinking` | `false` | 注入 generation-config |
| `TIMEOUT` | `--timeout` | 空 | deprecated,建议用 generation-config.timeout |
| `SEED` | `--seed` | `42` | 随机种子 |
| `JUDGE_STRATEGY` | `--judge-strategy` | `auto` | auto/rule/llm/llm_recall |
| `USE_CACHE` | `--use-cache` | 空 | 断点续跑,填 outputs/<timestamp> 路径 |
| `TASK_MAX_TOKENS_JSON` | (shell 内 per-task 覆盖) | 空 | 例 `{"mmlu_pro":32768}` |
| `DATASET_ARGS` | `--dataset-args` | 空 | 数据集参数 JSON |

evalscope 还支持但未在 Jenkins 暴露的参数(留作扩展):

| flag | 类型 | 说明 |
|------|------|------|
| `--eval-type` | str | 评估类型,流水线固定 `openai_api` |
| `--dataset-dir` | str | 数据集缓存目录(默认 `~/.cache/modelscope/hub/datasets`) |
| `--dataset-hub` | str | 数据源(modelscope / huggingface / local) |
| `--no-timestamp` | flag | 不加时间戳子目录 |
| `--rerun-review` | flag | 配合 `--use-cache`,强制重算评分 |
| `--debug` | flag | 调试模式 |
| `--ignore-errors` | flag | 出错继续 |
| `--analysis-report` | flag | 用 judge 模型生成分析报告 |
| `--collect-perf` / `--no-collect-perf` | flag | 收集性能指标(默认开) |

> **为什么有 `TASK_MAX_TOKENS_JSON`:** evalscope 的 `max_tokens` 是全局的,但
> 不同基准对生成长度需求差异大(mmlu_pro 推理长、gpqa 短)。`evalscope_main.sh:
> _resolve_max_tokens` 在循环每个任务时按 JSON 覆盖,比多次 Jenkins 构建省事。

---

## 邮件通知(需求 #3)

- **触发条件**:`发送邮件` stage 永远执行(`catchError` 包裹,失败不阻塞 build)
- **数据源**:`reports/<model>/<dataset>.json`(由 `Report.to_json` 写入),
  用 `readJSON` 步骤直接解析,不靠正则提 stdout 表格
- **每任务展示**:
  - headline 得分(`score`,百分比)
  - 按 metric / category / subset 展开明细
  - 性能侧指标(latency / throughput / TTFT / token 统计)
- **连通性失败**:单独红色告警框,内嵌失败 curl 响应片段
- **附件**:`evalscope-<tasks>.log` + 连通性预检日志

---

## 设计分层

```
Jenkinsfile (Jenkins master, ssh 触发)
    │
    │  ssh → python3 run_eval.py <params>
    ▼
run_eval.py (远程 GPU 主机,参数 → 环境变量)
    │
    │  bash evalscope_main.sh
    ▼
evalscope_main.sh (定义 run_task,按逗号分发,tee 日志)
    │
    │  evalscope eval --model ... --datasets <task>
    ▼
evalscope (Python 库,下载数据集 → 推理 → 评分 → 写 report.json)
```

`evalscope_main.sh` 不读 Jenkins 参数;它通过环境变量接收所有配置,由
`run_eval.py` 统一注入——与 sgl-eval-test 完全相同的分层。

---

## 故障排查

| 现象 | 排查路径 |
|------|----------|
| 首次跑 mmlu_pro 很慢 | 正常,需从 ModelScope 下载完整数据集到 `~/.cache/modelscope/hub/datasets/`;后续走缓存 |
| 邮件 metrics 全 N/A | `find reports/<tester>/<build> -name '*.json' -path '*/reports/*'` 看是否拉到 report JSON |
| `no_answer` 比例高 | `max_tokens` 太小被截断,加大 `MAX_TOKENS` 或用 `TASK_MAX_TOKENS_JSON` 按任务调 |
| reasoning 模型温度选不对 | DSv3.2/V4 用 `1.0`,R1 系用 `0.6`,通用 instruct 用 `0.0` |
| 远程 venv 缺包 | 删 `.venv` 重跑环境检查 stage,Jenkins 会自动 `uv pip install -e .` |
| 数据集下载失败 | 设置 `MODELSCOPE_CACHE` 或 `HF_HOME` 换数据源;或用 `DATASET_ARGS` 指定 `local_path` |

---

## License

Apache-2.0。本仓库的封装代码与 EvalScope 上游许可证一致。
