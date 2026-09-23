#!/usr/bin/env python3
"""Generate the evalscope test report email HTML body.

Reads report JSON files, log files, and build parameters from environment
variables, then writes the complete HTML email body to stdout or a file.

Usage::

    python3 scripts/generate_report.py --report-base reports/.../ --output email_body.html

Environment variables (all passed from Jenkins):
  BUILD_NUMBER, BUILD_URL, TESTER, CHIP, ENGINE, PD, MODEL, BASE_URL,
  DESCRIPTION, TASKS, EXAMPLES, REPEATS, EVAL_BATCH_SIZE, TEMPERATURE_FALLBACK,
  TASK_TEMPERATURE_JSON, TASK_REPEATS_JSON, MAX_TOKENS, TOP_P, TOP_K,
  ENABLE_THINKING, JUDGE_STRATEGY, TASK_JUDGE_STRATEGY_JSON, JUDGE_MODEL_ID,
  JUDGE_API_URL, USER_MODEL_ID, USER_MODEL_API_URL, TASK_MAX_TOKENS_JSON,
  TASK_TIMEOUT_JSON, TASK_TOP_P_JSON, DATASET_ARGS, USE_CACHE, RERUN_REVIEW,
  MCP_ATLAS_IMAGE, MCP_ATLAS_AUTO_DEPLOY, MCP_ATLAS_API_KEYS,
  CONNECTIVITY_FAILED, RESULT_DIR, BUILD_RESULT, DURATION_STRING
"""

import argparse
import glob
import html
import json
import os
import sys
from pathlib import Path


def env(key: str, default: str = '') -> str:
    return os.environ.get(key, default) or default


def norm(v):
    """Normalize JSON null values (net.sf.json.JSONNull equivalent)."""
    if v is None:
        return None
    return v


def find_log_file(log_file_base: str) -> tuple:
    """Find evalscope log file and return (path, content)."""
    pattern = os.path.join(log_file_base, '**', 'evalscope-*.log')
    logs = glob.glob(pattern, recursive=True)
    if logs:
        path = logs[0]
        try:
            with open(path, encoding='utf-8') as f:
                return path, f.read()
        except Exception:
            return path, ''
    return '', ''


def check_connectivity_failure(build_number: str) -> tuple:
    """Check for connectivity failure in the connectivity log.

    Returns (failure_reason, connectivity_failure_reason).
    """
    log_path = f'builds/{build_number}/evalscope_connectivity_{build_number}.log'
    failure_reason = ''
    connectivity_failure_reason = ''

    if os.path.isfile(log_path):
        try:
            with open(log_path, encoding='utf-8') as f:
                content = f.read()
        except Exception:
            content = ''
        if 'API 连通性检查失败' in content or 'Chat Completions 接口检查失败' in content:
            failure_reason = '连通性检查未通过'
            lines = content.split('\n')
            collected = []
            in_section = False
            for line in lines:
                if '检查 API 连通性' in line or 'Chat Completions 接口检查' in line:
                    in_section = True
                if in_section:
                    if (collected and line.strip().startswith('===')
                            and '检查 API 连通性' not in line
                            and 'Chat Completions 接口检查' not in line):
                        break
                    collected.append(line)
            connectivity_failure_reason = '\n'.join(collected).strip()

    if not failure_reason and env('CONNECTIVITY_FAILED') == 'true':
        failure_reason = '连通性检查未通过'
        connectivity_failure_reason = (
            'API 连通性或 Chat Completions 接口检查失败,具体日志未拉到,详见 Jenkins 控制台输出。'
        )

    return failure_reason, connectivity_failure_reason


def count_ignored_samples(log_content: str) -> int:
    """Count samples skipped by --ignore-errors."""
    if not log_content:
        return 0
    return log_content.count('Error ignored, continuing with next sample.')


def parse_reports(log_file_base: str) -> tuple:
    """Parse report JSON files and return (task_scores, task_summary_rows, task_metrics_html)."""
    task_scores = {}
    task_summary_rows = ''
    task_metrics_html = ''

    pattern = os.path.join(log_file_base, '**', 'reports', '**', '*.json')
    report_files = glob.glob(pattern, recursive=True)

    for rf in report_files:
        try:
            with open(rf, encoding='utf-8') as f:
                json_data = json.load(f)
        except Exception:
            continue

        task_name = norm(json_data.get('dataset_name')) or norm(json_data.get('name')) or 'unknown'
        score = norm(json_data.get('score'))
        score_str = 'N/A'
        if score is not None:
            try:
                score_str = f'{float(score) * 100:.2f}%'
            except (ValueError, TypeError):
                score_str = 'N/A'
        task_scores[task_name] = score_str
        task_summary_rows += f'<tr><td>{html.escape(task_name)}</td><td>{score_str}</td></tr>'

        # Detail rows (metric / category / subset)
        detail_rows = ''
        metrics = norm(json_data.get('metrics')) or []
        for m in metrics:
            metric_name = norm(m.get('name')) or 'score'
            metric_score = norm(m.get('score'))
            metric_score_str = (
                f'{float(metric_score) * 100:.2f}%' if metric_score is not None else 'N/A'
            )
            detail_rows += (
                f'<tr class="score-highlight"><td>{html.escape(task_name)}</td>'
                f'<td>{html.escape(metric_name)} (overall)</td><td>{metric_score_str}</td></tr>'
            )
            categories = norm(m.get('categories')) or []
            for c in categories:
                cat_name = norm(c.get('name'))
                if isinstance(cat_name, list):
                    cat_name = ' / '.join(str(x) for x in cat_name)
                cat_score = norm(c.get('score'))
                cat_score_str = f'{float(cat_score) * 100:.2f}%' if cat_score is not None else 'N/A'
                cat_num = norm(c.get('num')) or 0
                detail_rows += (
                    f'<tr><td>{html.escape(task_name)}</td>'
                    f'<td>{html.escape(str(cat_name))} (n={cat_num})</td><td>{cat_score_str}</td></tr>'
                )
                subsets = norm(c.get('subsets')) or []
                for s in subsets:
                    sub_name = norm(s.get('name'))
                    sub_score = norm(s.get('score'))
                    sub_score_str = (
                        f'{float(sub_score) * 100:.4f}%' if sub_score is not None else 'N/A'
                    )
                    sub_num = norm(s.get('num')) or 0
                    if sub_name is not None:
                        detail_rows += (
                            f'<tr><td>{html.escape(task_name)}</td>'
                            f'<td>&nbsp;&nbsp;&nbsp;{html.escape(str(sub_name))} (n={sub_num})</td>'
                            f'<td>{sub_score_str}</td></tr>'
                        )

        task_metrics_html += f"""
            <div class="section-title">{html.escape(task_name)} 任务测试结果</div>
            <table>
                <tr style="background-color: #e3f2fd;"><th>任务</th><th>指标 / 子集</th><th>值</th></tr>
                {detail_rows}
            </table>
            <p style="font-size: 12px; color: #666;">report: {html.escape(rf)}</p>
"""
        # Performance metrics
        perf = norm(json_data.get('perf_metrics'))
        if perf is not None and norm(perf.get('summary')) is not None:
            sum_data = perf['summary']
            latency = norm(sum_data.get('latency'))
            throughput = norm(sum_data.get('throughput'))
            usage = norm(sum_data.get('usage'))
            ttft = norm(sum_data.get('ttft'))
            n_samples = norm(sum_data.get('n_samples')) or 'N/A'
            perf_lines = f'samples: {n_samples}'
            if latency is not None and norm(latency.get('avg')) is not None:
                perf_lines += f' | latency avg: {latency["avg"]}s'
            if throughput is not None and norm(throughput.get('avg_output_tps')) is not None:
                perf_lines += f' | output tps: {throughput["avg_output_tps"]}'
            if ttft is not None and norm(ttft.get('avg')) is not None:
                perf_lines += f' | TTFT avg: {ttft["avg"]}s'
            if usage is not None and norm(usage.get('total_tokens_count')) is not None:
                perf_lines += f' | total tokens: {usage["total_tokens_count"]}'
            task_metrics_html += f"""
            <p style="font-size: 12px; color: #666;">{html.escape(perf_lines)}</p>
"""

    return task_scores, task_summary_rows, task_metrics_html


def generate_email_body(log_file_base: str) -> tuple:
    """Generate the complete HTML email body and return (html, task_scores, result_status, log_file, attach_pattern)."""
    log_file, log_content = find_log_file(log_file_base)
    failure_reason, connectivity_failure_reason = check_connectivity_failure(env('BUILD_NUMBER'))
    ignored_count = count_ignored_samples(log_content)

    task_scores, task_summary_rows, task_metrics_html = parse_reports(log_file_base)

    if failure_reason:
        task_summary_rows = "<tr><td colspan='2'>连通性检查未通过,任务未执行</td></tr>"
    elif not task_summary_rows:
        task_summary_rows = "<tr><td colspan='2'>无任务执行或未找到 report JSON</td></tr>"

    has_result = bool(task_scores)
    result_status = '完成' if has_result else '失败/无结果'
    if failure_reason:
        result_status = f'失败/{failure_reason}'

    # Connectivity failure HTML block
    connectivity_failure_html = ''
    if failure_reason:
        escaped_reason = html.escape(connectivity_failure_reason or '')
        connectivity_failure_html = f"""
            <div style="background-color: #ffebee; color: #000000; border-left: 4px solid #d32f2f; padding: 12px 15px; margin-top: 15px; border-radius: 3px;">
                <h3 style="color: #d32f2f; margin-top: 0; margin-bottom: 8px;">⚠️ 连通性检查未通过</h3>
                <p style="margin-top: 0; margin-bottom: 8px; color: #000000;">本次测试未能正常执行用例,原因是 API 连通性检查失败:</p>
                <pre style="background-color: #ffffff; color: #000000; padding: 10px; border-radius: 3px; overflow-x: auto; white-space: pre-wrap; margin: 0; font-family: Menlo, Consolas, monospace; font-size: 12px;">{escaped_reason}</pre>
            </div>"""

    # Ignored samples HTML block
    ignored_samples_html = ''
    if ignored_count > 0:
        ignored_samples_html = f"""
            <div style="background-color: #fff3e0; color: #000000; border-left: 4px solid #ff9800; padding: 12px 15px; margin-top: 15px; border-radius: 3px;">
                <h3 style="color: #ef6c00; margin-top: 0; margin-bottom: 8px;">⚠️ 已忽略 {ignored_count} 个失败样本</h3>
                <p style="margin-top: 0; margin-bottom: 8px; color: #000000;">本次测试启用了 <code>--ignore-errors</code>,有 {ignored_count} 个样本在推理/评分阶段失败被跳过,未计入得分;其余样本继续评估并产出报告。失败详情见日志中的 <code>Error ignored, continuing with next sample.</code> 及对应 ERROR 堆栈。</p>
            </div>"""

    tasks_display = env('TASKS') or ('未执行(连通性检查未通过)' if failure_reason else 'N/A')
    result_dir_display = 'N/A (连通性检查未通过)' if failure_reason else (env('RESULT_DIR') or 'N/A')
    ignored_display = (
        f'{ignored_count} (已跳过,未计入得分)' if ignored_count > 0 else '0'
    )
    header_color = '#4CAF50' if has_result else '#f44336'

    email_body = f"""
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }}
        .container {{ max-width: 1200px; margin: 0 auto; background-color: #fff; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }}
        .header {{ background-color: {header_color}; color: white; padding: 20px; border-radius: 5px 5px 0 0; }}
        .content {{ padding: 20px; }}
        table {{ border-collapse: collapse; width: 100%; margin-top: 15px; font-size: 13px; }}
        th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
        th {{ background-color: #f2f2f2; }}
        .footer {{ margin-top: 20px; padding: 15px; background-color: #f9f9f9; border-radius: 0 0 5px 5px; color: #666; font-size: 12px; }}
        .section-title {{ background-color: #e3f2fd; padding: 10px; margin-top: 20px; border-radius: 3px; font-weight: bold; }}
        .score-highlight {{ background-color: #c8e6c9; font-weight: bold; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2 style="margin: 0;">evalscope 精度测试报告 - 构建 #{env('BUILD_NUMBER')}</h2>
        </div>
        <div class="content">
            <h3>测试概要</h3>
            <table>
                <tr><th>项目</th><td>值</td></tr>
                <tr><th>构建编号</th><td>#{env('BUILD_NUMBER')}</td></tr>
                <tr><th>模型服务描述</th><td>{html.escape(env('DESCRIPTION'))}</td></tr>
                <tr><th>测试人员</th><td>{html.escape(env('TESTER'))}</td></tr>
                <tr><th>芯片平台</th><td>{html.escape(env('CHIP'))}</td></tr>
                <tr><th>推理框架</th><td>{html.escape(env('ENGINE'))}</td></tr>
                <tr><th>PD分离模式</th><td>{html.escape(env('PD'))}</td></tr>
                <tr><th>模型名称</th><td>{html.escape(env('MODEL'))}</td></tr>
                <tr><th>API地址</th><td>{html.escape(env('BASE_URL'))}</td></tr>
                <tr><th>测试任务</th><td>{html.escape(tasks_display)}</td></tr>
                <tr><th>样本限制</th><td>{html.escape(env('EXAMPLES') or '无限制')}</td></tr>
                <tr><th>repeats</th><td>{html.escape(env('REPEATS') or 'default 1')}</td></tr>
                <tr><th>eval-batch-size</th><td>{html.escape(env('EVAL_BATCH_SIZE'))}</td></tr>
                <tr><th>温度(兜底)</th><td>{html.escape(env('TEMPERATURE_FALLBACK'))}</td></tr>
                <tr><th>per-task temperature JSON</th><td>{html.escape(env('TASK_TEMPERATURE_JSON') or 'N/A')}</td></tr>
                <tr><th>per-task repeats JSON</th><td>{html.escape(env('TASK_REPEATS_JSON') or 'N/A')}</td></tr>
                <tr><th>max_tokens</th><td>{html.escape(env('MAX_TOKENS') or 'unlimited')}</td></tr>
                <tr><th>top_p / top_k</th><td>{html.escape(env('TOP_P'))} / {html.escape(env('TOP_K'))}</td></tr>
                <tr><th>enable_thinking</th><td>{html.escape(env('ENABLE_THINKING'))}</td></tr>
                <tr><th>judge_strategy</th><td>{html.escape(env('JUDGE_STRATEGY'))}</td></tr>
                <tr><th>per-task judge_strategy JSON</th><td>{html.escape(env('TASK_JUDGE_STRATEGY_JSON') or 'N/A')}</td></tr>
                <tr><th>裁判模型</th><td>{html.escape(env('JUDGE_MODEL_ID'))}</td></tr>
                <tr><th>裁判模型API</th><td>{html.escape(env('JUDGE_API_URL'))}</td></tr>
                <tr><th>用户模拟模型</th><td>{html.escape(env('USER_MODEL_ID') or '<复用被测模型>')}</td></tr>
                <tr><th>用户模拟模型API</th><td>{html.escape(env('USER_MODEL_API_URL') or '<复用被测模型API>')}</td></tr>
                <tr><th>per-task max_tokens JSON</th><td>{html.escape(env('TASK_MAX_TOKENS_JSON') or 'N/A')}</td></tr>
                <tr><th>per-task timeout JSON</th><td>{html.escape(env('TASK_TIMEOUT_JSON') or 'N/A')}</td></tr>
                <tr><th>per-task top_p JSON</th><td>{html.escape(env('TASK_TOP_P_JSON') or 'N/A')}</td></tr>
                <tr><th>dataset_args</th><td>{html.escape(env('DATASET_ARGS') or 'N/A')}</td></tr>
                <tr><th>use_cache</th><td>{html.escape(env('USE_CACHE') or 'N/A (全新跑)')}</td></tr>
                <tr><th>rerun_review</th><td>{html.escape(env('RERUN_REVIEW'))}</td></tr>
                <tr><th>MCP-Atlas 镜像</th><td>{html.escape(env('MCP_ATLAS_IMAGE'))}</td></tr>
                <tr><th>MCP-Atlas 自动部署</th><td>{html.escape(env('MCP_ATLAS_AUTO_DEPLOY'))}</td></tr>
                <tr><th>MCP-Atlas API Keys</th><td>{html.escape(env('MCP_ATLAS_API_KEYS') or 'N/A(仅启用 20 个无 key server)')}</td></tr>
                <tr><th>执行时间</th><td>{html.escape(env('DURATION_STRING'))}</td></tr>
                <tr><th>测试状态</th><td>{html.escape(result_status)}</td></tr>
                <tr><th>已忽略失败样本</th><td>{html.escape(ignored_display)}</td></tr>
                <tr><th>构建状态</th><td>{html.escape(env('BUILD_RESULT'))}</td></tr>
            </table>

            {connectivity_failure_html}

            {ignored_samples_html}

            <h3>任务汇总得分</h3>
            <table>
                <tr style="background-color: #e3f2fd;"><th>任务名称</th><th>得分</th></tr>
                {task_summary_rows}
            </table>

            {task_metrics_html}

            <h3>输出目录</h3>
            <p>{html.escape(result_dir_display)}</p>

            <p style="margin-top: 20px;">详细日志请查看附件。</p>
            <p>Jenkins 构建地址: <a href="{html.escape(env('BUILD_URL'))}">{html.escape(env('BUILD_URL'))}</a></p>
        </div>
        <div class="footer">
            此邮件由 Jenkins 自动发送，请勿回复。
        </div>
    </div>
</body>
</html>"""

    # Build attachment pattern
    attach_patterns = []
    if log_file:
        attach_patterns.append(log_file)
    conn_log = f'builds/{env("BUILD_NUMBER")}/evalscope_connectivity_{env("BUILD_NUMBER")}.log'
    if os.path.isfile(conn_log):
        attach_patterns.append(conn_log)
    attach_pattern = ','.join(attach_patterns)

    return email_body, task_scores, result_status, log_file, attach_pattern


def main():
    parser = argparse.ArgumentParser(description='Generate evalscope test report email HTML.')
    parser.add_argument('--report-base', required=True, help='Base directory for reports (e.g. reports/tester/build/chip/model)')
    parser.add_argument('--output', default='-', help='Output file path (default: stdout)')
    args = parser.parse_args()

    email_body, task_scores, result_status, log_file, attach_pattern = generate_email_body(args.report_base)

    # Print summary to stderr (visible in Jenkins console)
    print('=== evalscope 测试结果 ===', file=sys.stderr)
    print(f'结果目录: {os.environ.get("RESULT_DIR") or "N/A"}', file=sys.stderr)
    print(f'测试状态: {result_status}', file=sys.stderr)
    for k, v in task_scores.items():
        print(f'  {k} 得分: {v}', file=sys.stderr)

    # Write email body
    if args.output == '-':
        print(email_body)
    else:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(email_body)
        print(f'Email HTML written to {args.output}', file=sys.stderr)

    # Write attachment pattern to a sidecar file
    if args.output != '-':
        ap_path = args.output + '.attach'
        with open(ap_path, 'w', encoding='utf-8') as f:
            f.write(attach_pattern)
        print(f'Attachment pattern written to {ap_path}', file=sys.stderr)


if __name__ == '__main__':
    main()
