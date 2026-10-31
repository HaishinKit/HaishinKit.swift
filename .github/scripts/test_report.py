"""Render SwiftPM's XCTest/Swift Testing XML as standalone HTML and a job summary."""

import argparse
from collections import Counter, defaultdict
from html import escape
from pathlib import Path
import xml.etree.ElementTree as ET


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
                "time": case.get("time", ""),
                "details": details,
            })
    if not cases:
        problems.append("No test cases were reported. The build or test runner may have failed before producing results. See review.log.")
    return cases, problems


def render(cases, problems, outcome):
    counts = Counter(case["status"] for case in cases)
    failed = outcome != "success" or counts["Failed"] > 0 or bool(problems)
    status = "Failed / incomplete" if failed else "Passed"
    totals = f'{len(cases)} tests · {counts["Passed"]} passed · {counts["Failed"]} failed · {counts["Skipped"]} skipped'
    notices = list(problems)
    if outcome != "success":
        notices.append("The review command did not succeed. These results may be incomplete; see review.log for build or runner errors.")

    body = [f"<h1>Test results</h1><p class='{('failed' if failed else 'passed')}'><strong>{status}</strong></p><p>{totals}</p>"]
    summary = ["## Test results", "", f"**{status}** — {totals}", ""]
    for notice in notices:
        body.append(f"<p class='notice'>{escape(notice)}</p>")
        summary.extend([escape(notice), ""])

    failures = [case for case in cases if case["status"] == "Failed"]
    if failures:
        body.append("<h2>Failures</h2>")
        summary.extend(["### Failures", ""])
        for index, case in enumerate(failures):
            name = escape(f'{case["suite"]}.{case["name"]}')
            details = escape(case["details"] or "No failure details were provided.")
            body.append(f"<section><h3>{name}</h3><pre>{details}</pre></section>")
            # Bound the job summary; the HTML retains the complete details.
            if index < 20:
                summary.extend([f"<details><summary>{name}</summary>", "", f"<pre>{escape(case['details'][:2000])}</pre>", "", "</details>", ""])
        if len(failures) > 20:
            summary.extend(["More failures are listed in the HTML report.", ""])

    suites = defaultdict(list)
    for case in cases:
        suites[case["suite"]].append(case)
    body.append("<h2>All tests</h2>")
    summary.extend(["| Suite | Passed | Failed | Skipped |", "| --- | ---: | ---: | ---: |"])
    for suite, tests in sorted(suites.items()):
        suite_counts = Counter(case["status"] for case in tests)
        name = escape(suite)
        summary.append(f"| {name.replace('|', '&#124;').replace(chr(10), ' ')} | {suite_counts['Passed']} | {suite_counts['Failed']} | {suite_counts['Skipped']} |")
        opened = " open" if suite_counts["Failed"] else ""
        body.append(f"<details{opened}><summary>{name} — {len(tests)} tests, {suite_counts['Failed']} failed</summary><table><thead><tr><th>Test</th><th>Result</th><th>Seconds</th></tr></thead><tbody>")
        for case in sorted(tests, key=lambda case: case["name"]):
            body.append(f"<tr><td>{escape(case['name'])}</td><td class='{case['status'].lower()}'>{case['status']}</td><td>{escape(case['time'])}</td></tr>")
        body.append("</tbody></table></details>")

    html = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>HaishinKit test results</title><style>
body { font: 16px/1.5 system-ui, sans-serif; color: #1f2328; background: #f6f8fa; margin: 2rem auto; max-width: 1100px; padding: 0 1rem; }
section, details { background: white; border: 1px solid #d1d9e0; border-radius: 8px; padding: 1rem; margin: 1rem 0; }
summary { cursor: pointer; font-weight: 600; overflow-wrap: anywhere; }
table { width: 100%; border-collapse: collapse; margin-top: 1rem; }
th, td { text-align: left; border-bottom: 1px solid #d1d9e0; padding: .5rem; overflow-wrap: anywhere; }
pre { white-space: pre-wrap; overflow-wrap: anywhere; }
.passed { color: #116329; } .failed { color: #a40e26; } .skipped { color: #59636e; }
.notice { border-left: 4px solid #a40e26; padding: .5rem 1rem; background: #fff1f3; }
</style></head><body>""" + "\n".join(body) + "</body></html>\n"
    return html, "\n".join(summary) + "\n", failed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--outcome", choices=["success", "failure", "cancelled"], required=True)
    parser.add_argument("--summary", type=Path)
    args = parser.parse_args()
    cases, problems = load_results(args.directory)
    html, summary, failed = render(cases, problems, args.outcome)
    args.directory.mkdir(parents=True, exist_ok=True)
    (args.directory / "test-results.html").write_text(html, encoding="utf-8")
    if args.summary:
        with args.summary.open("a", encoding="utf-8") as output:
            output.write(summary)
    print(summary)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
