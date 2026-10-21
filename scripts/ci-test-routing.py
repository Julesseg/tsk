#!/usr/bin/env python3
import json
import os
import re
import subprocess
from pathlib import Path, PurePosixPath


def documentation_path(path):
    value = PurePosixPath(path)
    if path in {"LICENSE", "LICENSE.txt"}:
        return True
    if value.suffix == ".md" and (len(value.parts) == 1 or value.name == "README.md"):
        return True
    return path.startswith("docs/") and value.suffix.lower() in {
        ".md", ".txt", ".rst", ".adoc", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".pdf"
    }


def git(*arguments, repository):
    return subprocess.check_output(["git", *arguments], cwd=repository, stderr=subprocess.PIPE)


def route(event_name, event, repository="."):
    if event_name not in {"pull_request", "push"}:
        return True, "This event always runs tests."
    try:
        if event_name == "pull_request":
            before = event["pull_request"]["base"]["sha"]
            after = event["pull_request"]["head"]["sha"]
        else:
            before, after = event["before"], event["after"]
        if not all(isinstance(sha, str) and re.fullmatch(r"[0-9a-fA-F]{40}", sha) and int(sha, 16) for sha in (before, after)):
            return True, "Missing or invalid comparison commits; running tests."
        if event_name == "pull_request":
            before = git("merge-base", before, after, repository=repository).decode().strip()
        changed = git("diff", "--no-renames", "--name-only", "-z", before, after, "--", repository=repository)
        paths = [os.fsdecode(path) for path in changed.split(b"\0") if path]
        if paths and all(documentation_path(path) for path in paths):
            return False, f"All {len(paths)} changed paths are documentation; skipping Core, Native and UI tests."
        return True, "Non-documentation changes or an empty comparison; running tests."
    except (KeyError, TypeError, ValueError, OSError, subprocess.CalledProcessError):
        return True, "Unable to classify the comparison; running tests."


def main():
    try:
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        run_tests, reason = route(os.environ.get("GITHUB_EVENT_NAME", ""), event)
    except (KeyError, OSError, ValueError):
        run_tests, reason = True, "Unable to read the event; running tests."
    print(reason)
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"run_tests={str(run_tests).lower()}\n")
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary, "a") as output:
            output.write(f"## Test routing\n\n{reason}\n")


if __name__ == "__main__":
    main()
