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
            html, summary, failed = test_report.render(cases, problems, "success")
            self.assertFalse(failed)
            self.assertIn("3 tests · 2 passed · 0 failed · 1 skipped", summary)
            self.assertIn("XCTest", html)
            self.assertIn("SwiftTests", html)

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
            html, summary, failed = test_report.render(cases, problems, "failure")
            self.assertTrue(failed)
            self.assertIn("2 failed", summary)
            self.assertIn("Invalid socket ID &lt;script&gt;", html)
            self.assertIn("&lt;b&gt;details&lt;/b&gt;", html)
            self.assertNotIn("<script>", html)
            self.assertIn("Invalid socket ID", summary)

    def test_missing_results_are_not_success(self):
        with tempfile.TemporaryDirectory() as directory:
            cases, problems = test_report.load_results(Path(directory))
            html, _, failed = test_report.render(cases, problems, "success")
            self.assertTrue(failed)
            self.assertIn("No test cases were reported", html)

    def test_failed_command_with_partial_results_is_not_success(self):
        case = {"suite": "Tests", "name": "one", "time": "1", "status": "Passed", "details": ""}
        html, _, failed = test_report.render([case], [], "failure")
        self.assertTrue(failed)
        self.assertIn("results may be incomplete", html)

    def test_malformed_xml_still_produces_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tests.xml").write_text("<testsuites>")
            summary = root / "summary.md"
            result = subprocess.run([
                sys.executable, str(Path(test_report.__file__)), str(root),
                "--outcome", "failure", "--summary", str(summary),
            ], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("Cannot read tests.xml", (root / "test-results.html").read_text())
            self.assertIn("Failed / incomplete", summary.read_text())


if __name__ == "__main__":
    unittest.main()
