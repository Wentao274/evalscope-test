#!/usr/bin/env python3
"""Pre-download evalscope benchmark datasets with proxy support.

Used by the Jenkinsfile "环境检查" stage to cache datasets while the proxy is
available, so that the subsequent eval stage (proxy unset) can load from cache
without network access.

Cache mechanisms handled:
  1. RemoteDataLoader: datasets.save_to_disk() -> dataset_info.json in evalscope cache
  2. ModelScope snapshot: modelscope.dataset_snapshot_download() -> files in MS cache

Usage::

    PRELOAD_TASKS="mmlu_pro ceval ..." PROXY_URL="http://..." python3 scripts/predownload_datasets.py

Environment variables:
  PRELOAD_TASKS: space-separated benchmark names to pre-download
  PROXY_URL: HTTP proxy URL to use during download (empty = no proxy)
"""

import glob
import os
import shutil

from evalscope.api.registry import get_benchmark
from evalscope.config import TaskConfig
from evalscope.constants import DEFAULT_EVALSCOPE_CACHE_DIR
from evalscope.utils.io_utils import safe_filename


def check_cache(adapter):
    """Check if the dataset is fully cached.

    Handles two cache mechanisms:
    1. RemoteDataLoader: datasets.save_to_disk() -> dataset_info.json in evalscope cache
    2. ModelScope snapshot: modelscope.dataset_snapshot_download() -> files in MS cache

    Returns (is_cached: bool, valid_count: int, expected_count: int, stale_dirs: list)
    """
    stale_dirs = []
    n_subsets = len(adapter.subset_list) if not adapter.reformat_subset else 1

    # --- Mechanism 1: evalscope datasets cache (RemoteDataLoader) ---
    safe_name = safe_filename(adapter.dataset_id)
    cache_bases = [
        os.path.join(adapter.dataset_dir, 'datasets'),
        os.path.join(DEFAULT_EVALSCOPE_CACHE_DIR, 'datasets'),
    ]
    valid = 0
    for base in cache_bases:
        if os.path.isdir(base):
            for d in glob.glob(os.path.join(base, f'{safe_name}-*')):
                if os.path.isdir(d):
                    if os.path.isfile(os.path.join(d, 'dataset_info.json')):
                        valid += 1
                    else:
                        stale_dirs.append(d)
    if valid >= n_subsets:
        return True, valid, n_subsets, stale_dirs

    # --- Mechanism 2: ModelScope snapshot cache (tau2_bench etc.) ---
    # modelscope.dataset_snapshot_download caches at cache_dir/dataset_id/
    ms_snapshot = os.path.join(adapter.dataset_dir, adapter.dataset_id)
    if os.path.isdir(ms_snapshot) and os.listdir(ms_snapshot):
        return True, 1, 1, stale_dirs

    return False, valid, n_subsets, stale_dirs


def build_task_config(name: str) -> TaskConfig:
    """Build a TaskConfig for preloading, with per-task overrides.

    videomme_v2: force video_source='archive' so the load path downloads the official
    MP4 archives via proxy (default 'url' mode passes public links to the model and
    downloads nothing). The download is idempotent: cached ModelScope snapshots are
    resolved offline and already-extracted videos are skipped, so repeated builds only
    pay an in-memory dataset rebuild.
    """
    if name == 'videomme_v2':
        return TaskConfig(dataset_args={'videomme_v2': {'extra_params': {'video_source': 'archive'}}})
    return TaskConfig()


def main():
    tasks = [t.strip() for t in os.environ.get('PRELOAD_TASKS', '').split() if t.strip()]
    proxy_url = os.environ.get('PROXY_URL', '')

    for name in tasks:
        try:
            config = build_task_config(name)
            adapter = get_benchmark(name, config=config)

            # videomme_v2: custom load path, no save_to_disk cache; its real cache is
            # the extracted video files + the ModelScope snapshot, both idempotent.
            # Always run the load: cached snapshots resolve offline (local_files_only)
            # and already-extracted videos are skipped, so repeat builds are cheap.
            if name == 'videomme_v2':
                video_dir = getattr(adapter, 'video_cache_dir', '')
                n_videos = len(glob.glob(os.path.join(video_dir, '*.mp4'))) if video_dir else 0
                state = 'verify' if n_videos else 'download (first run is multi-GB)'
                print(f'[{"CACHED" if n_videos else "MISS"}] {name}: {n_videos} video(s) cached, running idempotent {state}...')
                os.environ['http_proxy'] = proxy_url
                os.environ['https_proxy'] = proxy_url
                adapter.load_dataset()
                del os.environ['http_proxy']
                del os.environ['https_proxy']
                print(f'[OK] {name}: dataset verified/downloaded')
                continue

            # Phase 1: check cache via filesystem (no network, no proxy)
            is_cached, valid_count, expected_count, stale_dirs = check_cache(adapter)

            if is_cached:
                print(f'[CACHED] {name}: {valid_count}/{expected_count} subset(s) cached, skipping')
                continue

            # Clean up incomplete/stale cache directories
            for d in stale_dirs:
                print(f'[STALE] {name}: removing incomplete cache: {d}')
                shutil.rmtree(d, ignore_errors=True)

            # Phase 2: download with proxy (set env for requests/httpx used by SDK)
            print(f'[MISS] {name}: cache incomplete ({valid_count}/{expected_count}), downloading...')
            os.environ['http_proxy'] = proxy_url
            os.environ['https_proxy'] = proxy_url
            adapter = get_benchmark(name, config=config)
            adapter.load_dataset()
            del os.environ['http_proxy']
            del os.environ['https_proxy']
            print(f'[OK] {name}: dataset downloaded and cached')
        except Exception as e:
            os.environ.pop('http_proxy', None)
            os.environ.pop('https_proxy', None)
            print(f'[WARN] {name}: {e}')


if __name__ == '__main__':
    main()
