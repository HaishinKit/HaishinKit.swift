"""Publish SwiftPM results as GitHub Actions annotations and a job summary."""

import argparse
from collections import Counter, defaultdict
from html import escape
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET


ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ISSUE = re.compile(r"✘ Test (.*?) recorded an issue at (.*?):(\d+):(\d+): (.*)")


def workflow_escape(value, property=False):
    value = value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    return value.replace(":", "%3A").replace(",", "%2C") if property else value


def annotation(title, message, **location):
    properties = {"title": title, **location}
    return "::error " + ",".join(
        f"{key}={workflow_escape(str(value), property=True)}" for key, value in properties.items()
    ) + "::" + workflow_escape(message)


def annotations(cases, log, sources, repository):
    commands, reported, seen = [], set(), set()
    # Swift Testing's XML omits source locations; its console diagnostics include them.
    for match in ISSUE.finditer(ANSI.sub("", log)):
        name, filename, line, column, message = match.groups()
        if match.groups() in seen:
            continue  # fastlane can repeat the command output when it fails.
        seen.add(match.groups())
        reported.add(name)
        path = Path(filename)
        if path.is_absolute():
            try:
                path = path.relative_to(repository)
            except ValueError:
                path = None
        candidates = [] if path is None else [
            source for source in sources if source == path.as_posix() or source.endswith("/" + path.as_posix())
        ]
        location = {}
        if len(candidates) == 1:
            location = {"file": candidates[0], "line": line, "col": column}
        # Keep the original location in the message even if its path is ambiguous.
        commands.append(annotation(name, f"{filename}:{line}:{column}: {message}", **location))
    for case in cases:
        if case["status"] == "Failed" and case["name"] not in reported:
            commands.append(annotation(f'{case["suite"]}.{case["name"]}', case["details"]))
    return commands


def load_results(directory):
    cases, problems = [], []
    # SwiftPM adds '-swift-testing' to the requested filename for Swift Testing.
    for path in sorted(directory.glob("*.xml")):
        try:
            root = ET.parse(path).getroot()
        except (ET.ParseError, OSError) as error:
            problems.append(f"Cannot read {path.name}: {error}")
            continue
        for case in root.iter("testcase"):
            issues = case.findall("failure") + case.findall("error")
            status = "Failed" if issues else "Skipped" if case.find("skipped") is not None else "Passed"
            details = "\n".join(
                "\n".join(filter(None, [issue.get("message", ""), issue.text or ""]))
                for issue in issues
            )
            cases.append({
                "suite": case.get("classname", path.stem),
                "name": case.get("name", "Unnamed test"),
                "status": status,
                "details": details,
            })
    if not cases:
        problems.append("No test cases were reported. The build or test runner may have failed before producing results. See review.log.")
    return cases, problems


def render(cases, problems, outcome, has_errors=False):
    counts = Counter(case["status"] for case in cases)
    failed = outcome != "success" or counts["Failed"] > 0 or bool(problems) or has_errors
    status = "Failed / incomplete" if failed else "Passed"
    totals = f'{len(cases)} tests · {counts["Passed"]} passed · {counts["Failed"]} failed · {counts["Skipped"]} skipped'
    notices = list(problems)
    if outcome != "success":
        notices.append("The review command did not succeed. These results may be incomplete; see review.log for build or runner errors.")

    summary = ["## Test results", "", f"**{status}** — {totals}", ""]
    for notice in notices:
        summary.extend([escape(notice), ""])

    failures = [case for case in cases if case["status"] == "Failed"]
    if failures:
        summary.extend(["### Failures", ""])
        for index, case in enumerate(failures):
            name = escape(f'{case["suite"]}.{case["name"]}')
            # Bound the job summary; the XML artifact retains the complete details.
            if index < 20:
                summary.extend([f"<details><summary>{name}</summary>", "", f"<pre>{escape(case['details'][:2000])}</pre>", "", "</details>", ""])
        if len(failures) > 20:
            summary.extend(["More failures are listed in the test-logs artifact.", ""])

    suites = defaultdict(list)
    for case in cases:
        suites[case["suite"]].append(case)
    summary.extend(["| Suite | Passed | Failed | Skipped |", "| --- | ---: | ---: | ---: |"])
    for suite, tests in sorted(suites.items()):
        suite_counts = Counter(case["status"] for case in tests)
        name = escape(suite)
        summary.append(f"| {name.replace('|', '&#124;').replace(chr(10), ' ')} | {suite_counts['Passed']} | {suite_counts['Failed']} | {suite_counts['Skipped']} |")
    return "\n".join(summary) + "\n", failed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--outcome", choices=["success", "failure", "cancelled"], required=True)
    parser.add_argument("--summary", type=Path)
    args = parser.parse_args()
    cases, problems = load_results(args.directory)
    repository = Path(__file__).resolve().parents[2]
    sources = subprocess.check_output(
        ["git", "ls-files", "-z", "--", "*.swift"], cwd=repository, text=True,
    ).split("\0")
    log_path = args.directory / "review.log"
    log = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""
    commands = annotations(cases, log, sources, repository)
    commands.extend(annotation("Test results unavailable", problem) for problem in problems)
    if args.outcome != "success" and not commands:
        commands.append(annotation("Review failed", "See review.log for build or runner errors; test results may be incomplete."))
    summary, failed = render(cases, problems, args.outcome, has_errors=bool(commands))
    # Actions accepts at most 10 error annotations per step.
    if len(commands) > 10:
        summary += "\nOnly the first 10 errors are annotated. See test-logs for all failure details.\n"
    for command in commands[:10]:
        print(command)
    if args.summary:
        with args.summary.open("a", encoding="utf-8") as output:
            output.write(summary)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
