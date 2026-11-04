#!/usr/bin/env python3
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def start(env):
    issue = env.get("ISSUE", "")
    if not re.fullmatch(r"[1-9][0-9]*", issue):
        raise ValueError("ISSUE must be a positive issue number")
    required = ("T3_PROJECT_DIR",)
    missing = [key for key in required if not env.get(key, "").strip()]
    if missing:
        raise ValueError("Set repository Actions variables: " + ", ".join(missing))
    project = Path(env["T3_PROJECT_DIR"]).expanduser()
    if not project.is_absolute() or not project.is_dir():
        raise ValueError("T3_PROJECT_DIR must be an existing absolute checkout path")
    cli = env.get("T3_CLI") or shutil.which("t3") or str(Path.home() / ".t3/bin/t3")
    base_arguments = ["--base-dir", env["T3_BASE_DIR"]] if env.get("T3_BASE_DIR") else []
    subprocess.run(
        [cli, "thread", "list", "--project", str(project), "--json", *base_arguments],
        check=True, capture_output=True, text=True,
    )
    subprocess.run(["git", "-C", str(project), "fetch", "--prune", "origin"], check=True)
    subprocess.run(
        [
            cli, "thread", "start", str(project),
            f"Use the label-and-implement-with-pr skill to implement issue #{issue}. "
            "Read AGENTS.md and docs/agents/t3-code.md before starting. "
            "Schedules and heartbeats remain in Paseo.",
            "--title", f"Implement issue #{issue}",
            "--worktree", env.get("T3_BASE") or "origin/main",
            "--branch", f"agent/issue-{issue}", "--json", *base_arguments,
        ],
        check=True,
    )


if __name__ == "__main__":
    try:
        start(os.environ)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"::error::Cannot start T3 thread: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        sys.exit(1)
