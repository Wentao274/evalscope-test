# evalscope-test 本地 CI/CD 使用说明

本文件补足 [`README_TEST.md`](README_TEST.md) 中**未覆盖**的本地脚本编排、
Jenkins 流水线与远程执行约定。evalscope 上游 README 讲的是单机一条命令跑评测;
本文件讲的是 **如何在 Jenkins 上参数化触发、远程 ssh 到 GPU 主机跑、把结果/mail
发回**。

设计参照 `sgl-eval-test` 仓库(其
`Jenkinsfile` / `sgl_eval_main.sh` / `run_sgleval.py` 三件套),命名、目录层级、
邮件渲染逻辑保持一致,仅按 evalscope 的参数面和 report 结构做适配。

---

## 1. 文件清单

| 文件 | 角色 | 对应 sgl-eval-test |
|------|------|---------------------|
| `evalscope_main.sh` | shell 主入口,定义 `run_task` 函数 | `sgl_eval_main.sh` |
| `run_evalscope.py` | Python 编排器,Jenkins → shell 的桥 | `run_sgleval.py` |
| `Jenkinsfile` | Jenkins 声明式流水线 | `Jenkinsfile` |

`evalscope_main.sh` 不会自己读 Jenkins 参数;它通过环境变量接收所有配置,
由 `run_evalscope.py` 统一注入——与 sgl-eval-test 完全相同的分层。

---

## 2. 目录与日志层级(对齐 sgl-eval-test)

```
<WORK_DIR>/output/<tester>/<build_number>/<chip>/<model>/<timestamp>/
├── evalscope-<tasks>.log                      # 全程 tee 出来的总日志(邮件附件)
└── <evalscope_internal_timestamp>/            # evalscope 自动加的时间戳子目录
    ├── configs/                               # TaskConfig 快照(yaml)
    ├── logs/                                  # evalscope 内部日志
    ├── predictions/                           # 每样本预测流(jsonl)
    ├── reviews/                               # 每样本评分(jsonl)
    └── reports/                               # 最终报告
        └── <model_name>/
            └── <dataset_name>.json            # report JSON(邮件解析该文件)
```

`<tester>` / `<build_number>` / `<chip>` / `<model>` / `<timestamp>` 五层
与 sgl-eval-test 完全一致,便于跨框架横向比对。`reports/<model>/<dataset>.json`
由 `evalscope/report/report.py:Report.to_json` 写入,邮件 stage 通过
`readJSON` 直接读取,不再解析 stdout 表格——比 sgl-eval-test 的正则表格提取
更稳健。

### 与 sgl-eval-test 目录差异

| 项 | sgl-eval-test | evalscope-test |
|----|---------------|----------------|
| 运行目录名 | `sgl_eval_<name>_<stamp>/` | `<evalscope_internal_timestamp>/` |
| 得分文件 | `metrics.json` | `reports/<model>/<dataset>.json` |
| 预测文件 | `output-rs*.jsonl` | `predictions/*.jsonl` |
| 评分文件 | (无单独) | `reviews/*.jsonl` |

---

## 3. 三种使用方式

### 3.1 直接调 shell(本地 smoke)

```bash
# 默认 mmlu_pro / 无样本限制 / localhost
bash evalscope_main.sh

# 通过环境变量覆盖
MODEL_NAME=glm-5.2 \
DATASETS=mmlu_pro \
LLM_ADDR=http://10.201.149.34:8000/v1 \
EXAMPLES=50 \
OUTPUT_BASE=./output/smoke \
bash evalscope_main.sh
```

### 3.2 通过 run_evalscope.py 编排(本地复现 Jenkins 行为)

```bash
python3 run_evalscope.py \
    --tester liwt \
    --build-number manual001 \
    --chip nvidia-h100 \
    --model glm-5.2 \
    --base-url http://10.201.149.34:8000/v1 \
    --tasks mmlu_pro,gpqa_diamond \
    --examples 50 \
    --task-temperature-json '{"mmlu_pro":0.0,"gpqa_diamond":0.0}' \
    --max-tokens 32768 \
    --enable-thinking false
```

`run_evalscope.py` 会:
1. 创建 `./output/liwt/manual001/nvidia-h100/glm-5.2/<timestamp>/`
2. 设置环境变量(`MODEL_NAME` / `DATASETS` / `LLM_ADDR` / `OUTPUT_BASE` / ...)
3. 调 `bash evalscope_main.sh`,透传退出码

### 3.3 通过 Jenkins 触发(生产路径)

打开 Jenkins job → Build with Parameters → 勾选任务、填端点 → 构建。
Jenkins 通过 ssh 远程到 `REMOTE_HOST`(默认 `10.201.132.50`)在 `WORK_DIR` 下
跑 `run_evalscope.py`,完成后 scp 拉回结果、归档、发邮件。

---

## 4. Jenkins 参数清单(对应需求 #7 的「更多 evalscope 参数」)

| Jenkins 参数 | 对应 evalscope flag | 默认 | 说明 |
|--------------|---------------------|------|------|
| `TESTER` | — | `liwt` | 测试人员(目录分层用) |
| `CHIP` | — | `nvidia-h100` | 芯片平台(目录分层用) |
| `ENGINE` / `PD` | — | `vllm` / `agg` | 仅邮件展示,不传 evalscope |
| `MODEL` | `--model` | `glm-5.2` | 模型服务名 |
| `BASE_URL` | `--api-url` | `http://10.201.149.34:8000/v1` | 端点(自动拼 /v1) |
| `API_KEY` | `--api-key` | 空 → `EMPTY` | 鉴权 |
| `TASK_MMLU_PRO` | `--datasets mmlu_pro` | true | 勾选后逗号拼接 |
| `TASK_GPQA_DIAMOND` | `--datasets gpqa_diamond` | true | 勾选后逗号拼接 |
| `TASK_CEVAL` | `--datasets ceval` | true | 勾选后逗号拼接 |
| `TASK_CMMLU` | `--datasets cmmlu` | true | 勾选后逗号拼接 |
| `TASK_MATH_500` | `--datasets math_500` | true | 勾选后逗号拼接 |
| `TASK_HELLASWAG` | `--datasets hellaswag` | true | 勾选后逗号拼接 |
| `EXAMPLES` | `--limit` | 空 | 空 = 跑全集;int=数量,float=比例 |
| `REPEATS` | `--repeats` | 空 | 空 = 默认 1 |
| `EVAL_BATCH_SIZE` | `--eval-batch-size` | `32` | 并发批大小 |
| `TEMPERATURE_FALLBACK` | (shell 内温度兜底) | `0.0` | `TASK_TEMPERATURE_JSON` 未命中任务时用此值 |
| `TASK_TEMPERATURE_JSON` | (shell 内 per-task 覆盖) | 见默认值 | 例 `{"mmlu_pro":0.0,"math_500":0.6}` |
| `MAX_TOKENS` | `--generation-config max_tokens` | `32768` | 注入 generation-config |
| `TOP_P` | `--generation-config top_p` | `0.95` | 注入 generation-config |
| `TOP_K` | `--generation-config top_k` | `20` | 注入 generation-config |
| `ENABLE_THINKING` | `--generation-config chat_template_kwargs.enable_thinking` | `false` | 注入 generation-config |
| `JUDGE_STRATEGY` | `--judge-strategy` | `auto` | auto/rule/llm/llm_recall |
| `TASK_MAX_TOKENS_JSON` | (shell 内 per-task 覆盖) | 空 | 例 `{"mmlu_pro":32768}` |
| `DATASET_ARGS` | `--dataset-args` | 空 | 数据集参数 JSON |
| `DESCRIPTION` / `RECIPIENTS` / `WORK_DIR` | — | — | 元信息/邮件收件人/远程目录 |

**为什么有 `TASK_MAX_TOKENS_JSON` / `TASK_TEMPERATURE_JSON`:** evalscope 的
`max_tokens` 与 `temperature` 都是全局的,但不同基准对生成长度需求差异极大
(mmlu_pro 推理长、gpqa 短),且不同任务对采样温度偏好不同(多选题用
`temperature=0.0` greedy 保证可复现,数学推理 `math_500` 用 `0.6` 略带随机
有助思考模型发散)。`evalscope_main.sh:_resolve_max_tokens` /
`_resolve_temperature` 在循环每个任务时按 JSON 覆盖,比多次 Jenkins 构建省事。

**默认推荐温度**(已预填在 `TASK_TEMPERATURE_JSON`):

| 任务 | 推荐温度 | 理由 |
|------|----------|------|
| `mmlu_pro` / `gpqa_diamond` / `ceval` / `cmmlu` / `hellaswag` | `0.0` | 多选题/常识题,greedy 解码保证可复现、最大化准确率 |
| `math_500` | `0.6` | 数学推理,带 thinking 时略带随机有助模型发散推理路径 |

按模型族微调:DSv3.2/V4 reasoning 系可整体提高到 `1.0`,R1 系用 `0.6`,
通用 instruct(非 thinking)用 `0.0`。

### 4.1 各基准的默认配置(来自 adapter)

| 基准 | dataset_id | 默认 few-shot | metric | 说明 |
|------|------------|----------------|--------|------|
| `mmlu_pro` | `TIGER-Lab/MMLU-Pro` | 5-shot | `acc` | 10 选项多学科多选,要求 step-by-step 推理 |
| `gpqa_diamond` | `AI-ModelScope/gpqa_diamond` | 0-shot | `acc` | 博士级 4 选择,198 题,答案随机打乱 |
| `ceval` | `evalscope/ceval` | 5-shot | `acc` | 中文多学科多选,52 学科 |
| `cmmlu` | `evalscope/cmmlu` | 0-shot | `acc` | 中文多学科多选,67 学科 |
| `math_500` | `AI-ModelScope/MATH-500` | 0-shot | `acc` | 数学推理,500 题,5 个难度等级 |
| `hellaswag` | `evalscope/hellaswag` | 0-shot | `acc` | 常识推理,4 选择句补全 |

这些默认值不传任何 flag 时生效;Jenkins 任一对应参数填了非空值就覆盖默认。

---

## 5. evalscope 完整命令行参数参考(需求 #7)

来源:`evalscope/arguments.py:add_argument`(`evalscope eval --help`)。
下面列出当前流水线 **未在 Jenkins 暴露**但 evalscope 本身支持的参数,留作扩展:

| flag | 类型 | 说明 | 是否在 Jenkins 中暴露 |
|------|------|------|-----------------------|
| `--model-id` | str | 报告中显示的模型名 | 否(默认用 `--model`) |
| `--model-args` | str | 模型额外参数 | 否 |
| `--model-task` | str | 模型任务类型 | 否(默认 text-generation) |
| `--chat-template` | str | 自定义 jinja 模板 | 否 |
| `--dataset-dir` | str | 数据集缓存目录 | 否(默认 `~/.cache/modelscope/hub/datasets`) |
| `--dataset-hub` | str | 数据源(modelscope/huggingface/local) | 否(默认 modelscope) |
| `--eval-type` | str | 评估类型 | 否(流水线固定 `openai_api`) |
| `--eval-backend` | str | 评估后端 | 否(默认 native) |
| `--eval-config` | str | 后端任务配置文件 | 否 |
| `--no-timestamp` | flag | 不加时间戳子目录 | 否(默认加) |
| `--rerun-review` | flag | 配合 `--use-cache`,强制重算评分 | 否 |
| `--enable-progress-tracker` | flag | 写 progress.json | 否 |
| `--ignore-errors` | flag | 出错继续 | 否 |
| `--debug` | flag | 调试模式 | 否 |
| `--analysis-report` | flag | 用 judge 模型生成分析报告 | 否 |
| `--collect-perf` / `--no-collect-perf` | flag | 收集性能指标 | 否(默认开) |
| `--judge-model-args` | json | judge 模型参数 | 否 |
| `--judge-worker-num` | int | judge 并发数 | 否 |
| `--agent-config` | json | Agent 配置 | 否 |
| `--sandbox` | json | 沙箱配置 | 否 |

其余子命令(`evalscope perf` / `evalscope service` / `evalscope app`)未接入
流水线,本地直接用即可。

---

## 6. 数据集下载位置

evalscope 默认使用 **ModelScope** 作为数据源,缓存到:

```
~/.cache/modelscope/hub/datasets/                              # 原始下载
~/.cache/modelscope/hub/datasets/datasets/<name>-<hash>/       # 处理后缓存
```

重定向下载位置:
- `MODELSCOPE_CACHE=/your/path` — 移动 ModelScope 原始下载和默认 `dataset_dir`
- `EVALSCOPE_CACHE=/your/path` — 移动 evalscope 处理后缓存
- `TaskConfig(dataset_hub='huggingface')` — 切换到 HuggingFace,受 `HF_HOME` 控制

详见 `evalscope/constants.py:9-20`、`evalscope/api/dataset/hub.py:69-125`。

---

## 7. 邮件通知

- **触发条件**:`发送邮件` stage 永远执行(`catchError` 包裹,失败不阻塞 build)
- **数据源**:`reports/<model>/<dataset>.json`(由 `Report.to_json` 写入),用
  `readJSON` 步骤直接解析,不靠正则提 stdout 表格
- **每任务展示**:
  - headline 得分(`score`,百分比)
  - 按 metric / category / subset 展开明细
  - 性能侧指标(latency / throughput / TTFT / token 统计)
- **连通性失败**:单独红色告警框,内嵌失败 curl 响应片段
- **附件**:`evalscope-<tasks>.log` + 连通性预检日志

### report JSON 结构(邮件解析依据)

```json
{
  "name": "mmlu_pro",
  "dataset_name": "mmlu_pro",
  "model_name": "glm-5.2",
  "score": 0.4567,
  "metrics": [
    {
      "name": "acc",
      "score": 0.4567,
      "num": 12032,
      "categories": [
        {
          "name": ["default"],
          "num": 12032,
          "score": 0.4567,
          "subsets": [
            {"name": "mmlu_pro/math", "score": 0.5234, "num": 856}
          ]
        }
      ]
    }
  ],
  "perf_metrics": {
    "summary": {
      "n_samples": 12032,
      "latency": {"avg": 1.23, "min": 0.5, "max": 5.6},
      "throughput": {"avg_output_tps": 45.6},
      "usage": {"total_tokens_count": 1234567}
    }
  }
}
```

---

## 8. 故障排查

| 现象 | 排查路径 |
|------|----------|
| 首次跑 mmlu_pro 很慢 | 正常,需从 ModelScope 下载完整数据集到 `~/.cache/modelscope/hub/datasets/`;后续走缓存 |
| 数据集下载失败 | 设置 `MODELSCOPE_CACHE` 换路径;或 `DATASET_ARGS` 指定 `local_path`;或切 `dataset_hub=huggingface` |
| 邮件 metrics 全 N/A | `find reports/<tester>/<build> -name '*.json' -path '*/reports/*'` 看是否拉到 report JSON;若拉到但 N/A,检查 `dataset_name` 字段名 |
| `no_answer` 比例高 | `max_tokens` 太小被截断,加大 `MAX_TOKENS` 或用 `TASK_MAX_TOKENS_JSON` 按任务调 |
| reasoning 模型温度选不对 | 改 `TASK_TEMPERATURE_JSON` 按模型族调:DSv3.2/V4 reasoning 用 `1.0`,R1 系用 `0.6`,通用 instruct 用 `0.0` |
| 远程 venv 缺包 | 删 `.venv` 重跑环境检查 stage,Jenkins 会自动 `uv pip install -e .` |
| evalscope 命令找不到 | 确认 `source .venv/bin/activate` 后 `which evalscope` 有输出;否则重装 |
| 连通性预检失败 | 检查 `BASE_URL` 是否可达、`MODEL` 参数是否匹配服务端模型名 |

---

## 9. 与 sgl-eval-test 的对应关系

| 概念 | sgl-eval-test | evalscope-test |
|------|---------------|----------------|
| 样本数限制 | `--num-examples` | `--limit` |
| 重复次数 | `--n-repeats` | `--repeats` |
| 并发 | `--num-threads` | `--eval-batch-size` |
| 生成配置 | `--max-tokens` / `--temperature` / `--top-p` 独立 flag | 统一 `--generation-config` JSON |
| thinking | `--thinking` / `--no-thinking` | `--generation-config chat_template_kwargs.enable_thinking` |
| 得分文件 | `metrics.json` | `reports/<model>/<dataset>.json` |
| 得分指标 | `pass@1` / `score` / `majority@k` | `score` / `metrics[].score` |
| 数据集 | vendored 内置 | ModelScope/HF 在线下载 + 缓存 |
