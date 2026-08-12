#!/usr/bin/env python3
"""Patch Pier's mini_swe_agent.py for proxy-compatible installation.

Two categories of patches:

1. **apt step** (root_run):
   - Inject ``sed`` to switch Debian apt sources from HTTP→HTTPS (proxy CONNECT
     tunnel works for HTTPS but not HTTP).
   - Add ``python3-pip`` to the apt install list (needed by the pip-based
     agent install below).

2. **agent step** (agent_run + install_extra_packages):
   - Replace ``curl https://astral.sh/uv/...install.sh | sh`` with
     ``python3 -m pip install --user --index-url=aliyun mini-swe-agent``.
     The Astral CDN (astral.sh) is RST'd by enterprise proxies; aliyun mirror
     reliably serves packages through HTTP-CONNECT tunnels.
   - Remove ``source "$HOME/.local/bin/env"`` (uv-specific, not needed).
   - Remove ``uv tool install mini-swe-agent`` (done by pip above).
   - Replace ``uv pip install --python "$python_bin" {packages}`` with
     ``"$python_bin" -m pip install --index-url=aliyun {packages}``.

Usage::

    python3 scripts/patch_pier_apt.py           # auto-detect & patch
    python3 scripts/patch_pier_apt.py /path/to/mini_swe_agent.py
    python3 scripts/patch_pier_apt.py --check   # exit 0 if already patched

Idempotent: re-running on an already-patched file is a no-op.
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path

MARKER = "PATCHED_FOR_PROXY"

ALIYUN = "https://mirrors.aliyun.com/pypi/simple/"

# (old_substring, new_substring, description)
REPLACEMENTS: list[tuple[str, str, str]] = []

# 1. apt: inject sed (HTTP->HTTPS) before apt-get (do NOT add python3-pip;
#    swe-bench images already have pip, and apt-get update may fail through proxy)
REPLACEMENTS.append(
    (
        '"  apt-get update && apt-get install -y curl build-essential git;"',
        (
            '"  sed -i '
            "'s|http://deb.debian.org|https://deb.debian.org|g; "
            "s|http://security.debian.org|https://security.debian.org|g; "
            "s|http://deb.nodesource.com|https://deb.nodesource.com|g' "
            "/etc/apt/sources.list /etc/apt/sources.list.d/*.list "
            '/etc/apt/sources.list.d/*.sources 2>/dev/null || true;"'
            "\n"
            '            "  apt-get update && apt-get install -y curl build-essential git;"'
        ),
        "apt: inject sed HTTP->HTTPS before apt-get",
    )
)

# 2. uv install -> ensurepip bootstrap + pip install with aliyun mirror
#    ensurepip bootstraps pip if missing (no network needed);
#    aliyun mirror reliably serves through proxy CONNECT tunnel.
REPLACEMENTS.append(
    (
        "curl -LsSf https://astral.sh/uv/0.7.13/install.sh | sh",
        f"python3 -m ensurepip --user 2>/dev/null || true\\n"
        f'python3 -m pip install --user --index-url={ALIYUN} --trusted-host mirrors.aliyun.com "mini-swe-agent{{version_spec}}"',
        "uv install -> ensurepip + pip install (aliyun mirror)",
    )
)

# 3. Replace source env with export PATH (needed for pip --user binaries)
REPLACEMENTS.append(
    (
        'source "$HOME/.local/bin/env"',
        f'export PATH="$HOME/.local/bin:$PATH"  # {MARKER}: replaced uv env with export',
        "replace uv env source with export PATH",
    )
)

# 4. Remove uv tool install (done by pip above)
REPLACEMENTS.append(
    (
        "uv tool install mini-swe-agent{version_spec}",
        f"# uv tool install mini-swe-agent{{version_spec}}  # {MARKER}: done via pip above",
        "remove uv tool install",
    )
)

# 5. uv pip -> pip in install_extra_packages
REPLACEMENTS.append(
    (
        "f'uv pip install --python \"$python_bin\" {packages}\\n'",
        f"f'\"$python_bin\" -m pip install --index-url={ALIYUN} --trusted-host mirrors.aliyun.com {{packages}}\\n'",
        "uv pip -> pip in extra packages",
    )
)


def find_module() -> Path | None:
    """Locate the installed pier mini_swe_agent module."""
    try:
        import pier.agents.installed.mini_swe_agent as mod  # type: ignore

        return Path(mod.__file__)
    except Exception:
        return None


def patch_file(path: Path) -> bool:
    """Patch *path* in-place.  Returns True on success."""
    content = path.read_text(encoding="utf-8")

    if MARKER in content:
        print(f"Already patched: {path}")
        return True

    applied = 0
    for old, new, desc in REPLACEMENTS:
        if old in content:
            content = content.replace(old, new)
            applied += 1
            print(f"  Applied: {desc}")
        else:
            print(f"  SKIP (not found): {desc}")

    if applied == 0:
        print(f"ERROR: no replacements applied to {path}")
        return False

    # Inject marker as a comment near the top of install_spec
    marker_comment = f"        # {MARKER}\n"
    # Insert after the install_spec method def line
    marker_target = "    def install_spec(self) -> AgentInstallSpec:"
    if marker_target in content:
        content = content.replace(
            marker_target,
            marker_target + "\n" + marker_comment,
        )

    try:
        ast.parse(content)
    except SyntaxError as exc:
        print(f"ERROR: patched file would have a syntax error: {exc}")
        return False

    path.write_text(content, encoding="utf-8")
    print(f"Patched: {path} ({applied} replacements)")
    return True


def main() -> int:
    check_only = "--check" in sys.argv or "--check-only" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]

    if args:
        path = Path(args[0])
    else:
        path = find_module()
        if path is None:
            print("ERROR: cannot locate pier/agents/installed/mini_swe_agent.py")
            print("  Make sure pier is installed (pip install evalscope[deep_swe])")
            return 1

    print(f"Pier agent module: {path}")

    if check_only:
        already = MARKER in path.read_text(encoding="utf-8")
        print(f"Already patched: {already}")
        return 0 if already else 1

    return 0 if patch_file(path) else 1


if __name__ == "__main__":
    sys.exit(main())
