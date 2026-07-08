#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import tempfile
import tomllib
from pathlib import Path


VALID_TRUST_LEVELS = {"trusted", "untrusted"}


def usage() -> str:
    return "usage: merge-config.py <base-config.toml> <target-config.toml>"


def toml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def load_project_trust(config_path: Path) -> dict[str, str]:
    if not config_path.exists():
        return {}

    data = tomllib.loads(config_path.read_text())
    projects = data.get("projects", {})
    if not isinstance(projects, dict):
        return {}

    trusted_projects: dict[str, str] = {}
    for project_path, project_config in projects.items():
        if not isinstance(project_config, dict):
            continue
        trust_level = project_config.get("trust_level")
        if trust_level in VALID_TRUST_LEVELS:
            trusted_projects[str(project_path)] = str(trust_level)

    return trusted_projects


def render_project_trust(projects: dict[str, str]) -> str:
    if not projects:
        return ""

    lines = [
        "",
        "# Local project trust state.",
        "# Generated from the previous ~/.codex/config.toml; do not copy this block",
        "# into codex/config.base.toml.",
        "",
    ]
    for project_path, trust_level in projects.items():
        lines.append(f"[projects.{toml_string(project_path)}]")
        lines.append(f"trust_level = {toml_string(trust_level)}")
        lines.append("")

    return "\n".join(lines)


def write_atomic(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent,
        text=True,
    )
    try:
        with os.fdopen(fd, "w") as tmp:
            tmp.write(content)
        os.chmod(tmp_name, 0o600)
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(usage(), file=sys.stderr)
        return 2

    base_path = Path(argv[1]).expanduser()
    target_path = Path(argv[2]).expanduser()

    if target_path.is_symlink():
        print(
            f"refusing to update symlinked Codex config: {target_path}",
            file=sys.stderr,
        )
        return 1

    base_text = base_path.read_text()
    # Parse the base too, so Home Manager fails early on invalid tracked TOML.
    tomllib.loads(base_text)

    projects = load_project_trust(target_path)
    merged_text = base_text.rstrip() + "\n" + render_project_trust(projects)
    if not merged_text.endswith("\n"):
        merged_text += "\n"

    write_atomic(target_path, merged_text)
    print(f"Updated {target_path} ({len(projects)} project trust entries preserved)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
