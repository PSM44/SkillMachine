import json
import sys
import tempfile
import unittest
from pathlib import Path


PILOT_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = PILOT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

import task_runner


class TaskRunnerTests(unittest.TestCase):
    def test_parse_tasks_classifies_expected_states(self) -> None:
        text = "\n".join(
            [
                "# Demo",
                "- [ ] draft parser",
                "- [x] ship parser",
                "- [!] waiting on approval",
                "- [ ] BLOCKED: upstream dependency",
            ]
        )

        items = task_runner.parse_tasks(text)

        self.assertEqual([item.state for item in items], ["pending", "done", "blocked", "blocked"])
        self.assertEqual(items[0].text, "draft parser")
        self.assertEqual(items[3].text, "BLOCKED: upstream dependency")

    def test_render_report_is_deterministic(self) -> None:
        source = "C:/lab/TASKS.sample.md"
        items = task_runner.parse_tasks("- [ ] one\n- [X] two\n")

        first = task_runner.render_report(task_runner.build_report(source, items))
        second = task_runner.render_report(task_runner.build_report(source, items))

        self.assertEqual(first, second)
        data = json.loads(first)
        self.assertEqual(data["summary"]["pending"], 1)
        self.assertEqual(data["summary"]["done"], 1)

    def test_write_report_writes_normalized_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            input_path = Path(tmp_dir) / "tasks.md"
            output_path = Path(tmp_dir) / "report.json"
            input_path.write_text("- [ ] one\n- [!] two\n", encoding="utf-8", newline="\n")

            report = task_runner.write_report(input_path, output_path)

            self.assertTrue(output_path.exists())
            self.assertEqual(report["summary"]["blocked"], 1)
            self.assertEqual(report["summary"]["pending"], 1)
            self.assertIn('"state": "blocked"', output_path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
