#!/usr/bin/env python3
"""Patch Pier for proxy-compatible installation.

Three categories of patches:

1. **apt step** (root_run in mini_swe_agent.py):
   - Inject ``sed`` to switch Debian apt sources from HTTP→HTTPS (proxy CONNECT
     tunnel works for HTTPS but not HTTP).
   - Add ``python3-pip`` to the apt install list (needed by the pip-based
     agent install below).

2. **agent step** (agent_run + install_extra_packages in mini_swe_agent.py):
   - Replace ``curl https://astral.sh/uv/...install.sh | sh`` with
     ``python3 -m pip install --user --index-url=pypi.org mini-swe-agent``.
     The Astral CDN (astral.sh) is RST'd by enterprise proxies; official PyPI
     reliably serves packages through HTTP-CONNECT tunnels.
   - Remove ``source "$HOME/.local/bin/env"`` (uv-specific, not needed).
   - Remove ``uv tool install mini-swe-agent`` (done by pip above).
   - Replace ``uv pip install --python "$python_bin" {packages}`` with
     ``"$python_bin" -m pip install --index-url=pypi.org {packages}``.

3. **docker-compose-build.yaml** (in pier/environments/docker/):
   - Add ``network: host`` under the ``build:`` section so that
     ``docker compose build`` uses the host network instead of the default
     bridge network.  The enterprise proxy at 100.64.1.68:1080 is unreachable
     from the bridge network (TLS handshake timeout), but works from the host
     network.  This is equivalent to ``docker build --network=host`` which
     already works for the egress-proxy pre-build.

Usage::

    python3 scripts/patch_pier_apt.py           # auto-detect & patch both files
    python3 scripts/patch_pier_apt.py /path/to/mini_swe_agent.py
    python3 scripts/patch_pier_apt.py --check   # exit 0 if already patched

Idempotent: re-running on already-patched files is a no-op.
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path

MARKER = "PATCHED_FOR_PROXY"

PYPI = "https://pypi.org/simple/"

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

# 2. uv install -> ensurepip bootstrap + pip install with official PyPI
#    ensurepip bootstraps pip if missing (no network needed);
#    official PyPI reliably serves through proxy CONNECT tunnel.
REPLACEMENTS.append(
    (
        "curl -LsSf https://astral.sh/uv/0.7.13/install.sh | sh",
        f"python3 -m ensurepip --user 2>/dev/null || true\\n"
        f'python3 -m pip install --user --index-url={PYPI} "mini-swe-agent{{version_spec}}"',
        "uv install -> ensurepip + pip install (official PyPI)",
    )
)

# 3. Replace . "$HOME/.local/bin/env" with export PATH (needed for pip --user binaries)
#    The original code uses `.` (POSIX source), not `source`.
REPLACEMENTS.append(
    (
        '. "$HOME/.local/bin/env"',
        f'export PATH="$HOME/.local/bin:$PATH"  # {MARKER}: replaced uv env with export',
        "replace . env with export PATH",
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
        f"f'\"$python_bin\" -m pip install --index-url={PYPI} {{packages}}\\n'",
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


def find_compose_file(module_path: Path | None = None) -> Path | None:
    """Locate docker-compose-build.yaml in the installed pier package.

    Derives the path from *module_path* (mini_swe_agent.py) by walking up to
    the pier package root, then descending into environments/docker/.
    Falls back to importing the pier package directly.
    """
    if module_path is not None:
        # module_path = .../pier/agents/installed/mini_swe_agent.py
        # pier root  = .../pier/
        pier_root = module_path.parent.parent.parent  # remove agents/installed/
        compose = pier_root / "environments" / "docker" / "docker-compose-build.yaml"
        if compose.exists():
            return compose

    try:
        import pier  # type: ignore

        return (
            Path(pier.__file__).parent
            / "environments"
            / "docker"
            / "docker-compose-build.yaml"
        )
    except Exception:
        return None


COMPOSE_MARKER = "# PATCHED_FOR_PROXY: host network"

# The compose file patch: add `network: host` under `build:` section.
# Current content:
#   services:
#     main:
#       build:
#         context: ${CONTEXT_DIR}
#       pull_policy: build
#       command: [ "sh", "-c", "sleep infinity" ]
#
# Patched content:
#   services:
#     main:
#       build:
#         context: ${CONTEXT_DIR}
#         network: host  # PATCHED_FOR_PROXY: host network
#       pull_policy: build
#       command: [ "sh", "-c", "sleep infinity" ]
COMPOSE_OLD = "      context: ${CONTEXT_DIR}\n    pull_policy: build"
COMPOSE_NEW = (
    f"      context: ${{CONTEXT_DIR}}\n"
    f"      network: host  {COMPOSE_MARKER}\n"
    f"    pull_policy: build"
)


def patch_compose_file(path: Path) -> bool:
    """Patch docker-compose-build.yaml to use host network for builds.  Returns True on success."""
    content = path.read_text(encoding="utf-8")

    if COMPOSE_MARKER in content:
        print(f"Already patched: {path}")
        return True

    if COMPOSE_OLD not in content:
        if "network: host" in content:
            print(f"Already patched (network: host present): {path}")
            return True
        print(f"SKIP (compose pattern not found): {path}")
        print("  The compose file may have been updated -- manual review needed")
        return False

    content = content.replace(COMPOSE_OLD, COMPOSE_NEW)
    path.write_text(content, encoding="utf-8")
    print(f"Patched compose: {path} (added network: host to build section)")
    return True

    if COMPOSE_OLD not in content:
        print(f"SKIP (compose pattern not found): {path}")
        print("  The compose file may have been updated — manual review needed")
        return False

    content = content.replace(COMPOSE_OLD, COMPOSE_NEW)
    path.write_text(content, encoding="utf-8")
    print(f"Patched compose: {path} (added network: host to build section)")
    return True


def patch_file(path: Path) -> bool:
    """Patch *path* in-place.  Returns True on success.

    Each replacement is checked individually so partially-patched files
    (e.g. from a previous run with a different search string) are handled
    correctly: already-applied replacements are skipped, missing ones are applied.
    """
    content = path.read_text(encoding="utf-8")

    applied = 0
    already = 0
    for old, new, desc in REPLACEMENTS:
        if new in content:
            already += 1
            print(f"  Already applied: {desc}")
        elif old in content:
            content = content.replace(old, new)
            applied += 1
            print(f"  Applied: {desc}")
        else:
            print(f"  SKIP (not found): {desc}")

    if applied == 0 and already > 0:
        print(f"Already fully patched: {path} ({already} replacements)")
        return True

    if applied == 0:
        print(f"ERROR: no replacements applied to {path}")
        return False

    # Inject marker as a comment near the top of install_spec (if not present)
    if MARKER not in content:
        marker_target = "    def install_spec(self) -> AgentInstallSpec:"
        if marker_target in content:
            marker_comment = f"        # {MARKER}\n"
            content = content.replace(
                marker_target, marker_target + "\n" + marker_comment
            )

    try:
        ast.parse(content)
    except SyntaxError as exc:
        print(f"ERROR: patched file would have a syntax error: {exc}")
        return False

    path.write_text(content, encoding="utf-8")
    print(f"Patched: {path} ({applied} new, {already} already applied)")
    return True


def main() -> int:
    check_only = "--check" in sys.argv or "--check-only" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]

    if args:
        module_path = Path(args[0])
    else:
        module_path = find_module()
        if module_path is None:
            print("ERROR: cannot locate pier/agents/installed/mini_swe_agent.py")
            print("  Make sure pier is installed (pip install evalscope[deep_swe])")
            return 1

    print(f"Pier agent module: {module_path}")

    compose_path = find_compose_file(module_path)

    if check_only:
        agent_ok = MARKER in module_path.read_text(encoding="utf-8")
        compose_ok = (
            COMPOSE_MARKER in compose_path.read_text(encoding="utf-8")
            if compose_path and compose_path.exists()
            else False
        )
        print(f"Agent patched: {agent_ok}")
        print(f"Compose patched: {compose_ok}")
        return 0 if (agent_ok and compose_ok) else 1

    # Patch both files; compose failure is non-fatal (agent patch is the critical one)
    agent_ok = patch_file(module_path)
    compose_ok = True
    if compose_path is not None and compose_path.exists():
        compose_ok = patch_compose_file(compose_path)
    else:
        print("WARN: docker-compose-build.yaml not found, skipping compose patch")

    return 0 if agent_ok else 1


if __name__ == "__main__":
    sys.exit(main())
