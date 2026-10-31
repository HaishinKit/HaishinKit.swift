import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import test_report


class TestReportTests(unittest.TestCase):
    def test_combines_xctest_and_swift_testing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tests.xml").write_text('<testsuite><testcase classname="XCTest" name="one" /></testsuite>')
            (root / "tests-swift-testing.xml").write_text('''<testsuites><testsuite>
              <testcase classname="SwiftTests" name="two" time="0.5" />
              <testcase classname="SwiftTests" name="three"><skipped /></testcase>
            </testsuite></testsuites>''')
            cases, problems = test_report.load_results(root)
            summary, failed = test_report.render(cases, problems, "success")
            self.assertFalse(failed)
            self.assertIn("3 tests · 2 passed · 0 failed · 1 skipped", summary)
            self.assertIn("XCTest", summary)
            self.assertIn("SwiftTests", summary)
            self.assertEqual(test_report.annotations(cases, "", [], root), [])

    def test_failure_messages_are_visible_and_escaped(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tests-swift-testing.xml").write_text('''<testsuites><testsuite>
              <testcase classname="SRTTests" name="int64()">
                <failure message="Invalid socket ID &lt;script&gt;">&lt;b&gt;details&lt;/b&gt;</failure>
              </testcase>
              <testcase classname="SRTTests" name="other"><error message="runner error" /></testcase>
            </testsuite></testsuites>''')
            cases, problems = test_report.load_results(root)
            summary, failed = test_report.render(cases, problems, "failure")
            self.assertTrue(failed)
            self.assertIn("2 failed", summary)
            self.assertIn("Invalid socket ID &lt;script&gt;", summary)
            self.assertIn("&lt;b&gt;details&lt;/b&gt;", summary)
            self.assertNotIn("<script>", summary)
            commands = test_report.annotations(cases, "", [], root)
            self.assertEqual(len(commands), 2)
            self.assertIn("::error title=SRTTests.int64()::Invalid socket ID", commands[0])
            self.assertIn("%0A<b>details</b>", commands[0])

    def test_swift_testing_failure_resolves_source_and_deduplicates_fastlane_output(self):
        log = '[05:12:10]: ▸ \x1b[35m✘ Test int64() recorded an issue at SRTSocketOptionTests.swift:45:6: Caught error: .invalidOption("Invalid socket ID")\x1b[0m\n'
        case = {"suite": "SRTTests", "name": "int64()", "status": "Failed", "details": "Invalid socket ID"}
        commands = test_report.annotations(
            [case], log + log, ["SRTHaishinKit/Tests/SRT/SRTSocketOptionTests.swift"], Path("/repo"),
        )
        self.assertEqual(commands, [
            '::error title=int64(),file=SRTHaishinKit/Tests/SRT/SRTSocketOptionTests.swift,line=45,col=6::SRTSocketOptionTests.swift:45:6: Caught error: .invalidOption("Invalid socket ID")'
        ])

    def test_source_resolution_does_not_guess_ambiguous_or_external_paths(self):
        sources = ["One/Tests.swift", "Two/Tests.swift"]
        for filename, expected in [
            ("Tests.swift", None),
            ("Missing.swift", None),
            ("/other/One/Tests.swift", None),
            ("One/Tests.swift", "One/Tests.swift"),
            ("/repo/One/Tests.swift", "One/Tests.swift"),
        ]:
            with self.subTest(filename=filename):
                log = f"✘ Test example() recorded an issue at {filename}:2:3: failed"
                command, = test_report.annotations([], log, sources, Path("/repo"))
                if expected:
                    self.assertIn(f",file={expected},line=2,col=3::", command)
                else:
                    self.assertNotIn(",file=", command)
                self.assertIn(f"{filename}:2:3: failed", command)

    def test_known_issues_and_passing_tests_are_not_errors(self):
        log = """✘ Test expectedFailure() recorded a known issue at Tests.swift:3:4: expected
✔ Test success() passed after 0.001 seconds.
"""
        self.assertEqual(test_report.annotations([], log, ["Tests.swift"], Path("/repo")), [])

    def test_annotation_values_cannot_inject_workflow_commands_or_properties(self):
        command = test_report.annotation(
            "test(x:,y:)\n100%", "failure\r\n::warning::injected%0A", file="Tests,x:.swift",
        )
        self.assertEqual(command, "::error title=test(x%3A%2Cy%3A)%0A100%25,file=Tests%2Cx%3A.swift::failure%0D%0A::warning::injected%250A")

    def test_missing_results_are_not_success(self):
        with tempfile.TemporaryDirectory() as directory:
            cases, problems = test_report.load_results(Path(directory))
            summary, failed = test_report.render(cases, problems, "success")
            self.assertTrue(failed)
            self.assertIn("No test cases were reported", summary)

    def test_failed_command_with_partial_results_is_not_success(self):
        case = {"suite": "Tests", "name": "one", "time": "1", "status": "Passed", "details": ""}
        summary, failed = test_report.render([case], [], "failure")
        self.assertTrue(failed)
        self.assertIn("results may be incomplete", summary)

    def test_log_errors_with_incomplete_xml_are_not_success(self):
        case = {"suite": "Tests", "name": "one", "status": "Passed", "details": ""}
        summary, failed = test_report.render([case], [], "success", has_errors=True)
        self.assertTrue(failed)
        self.assertIn("Failed / incomplete", summary)

    def test_malformed_xml_still_produces_summary_and_annotations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tests.xml").write_text("<testsuites>")
            summary = root / "summary.md"
            result = subprocess.run([
                sys.executable, str(Path(test_report.__file__)), str(root),
                "--outcome", "failure", "--summary", str(summary),
            ], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("::error title=Test results unavailable::Cannot read tests.xml", result.stdout)
            self.assertIn("Failed / incomplete", summary.read_text())

    def test_cli_limits_annotations_and_retains_failure_details_in_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cases = ''.join(f'<testcase name="test{i}"><failure message="failure{i}" /></testcase>' for i in range(11))
            (root / "tests-swift-testing.xml").write_text(f"<testsuite>{cases}</testsuite>")
            summary = root / "summary.md"
            result = subprocess.run([
                sys.executable, str(Path(test_report.__file__)), str(root),
                "--outcome", "failure", "--summary", str(summary),
            ], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout.count("::error "), 10)
            self.assertIn("Only the first 10 errors", summary.read_text())
            self.assertIn("failure10", summary.read_text())


if __name__ == "__main__":
    unittest.main()
