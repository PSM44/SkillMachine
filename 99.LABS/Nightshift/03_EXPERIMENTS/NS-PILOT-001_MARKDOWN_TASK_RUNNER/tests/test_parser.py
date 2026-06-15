import unittest
from src.parser import classify_line, parse


SAMPLE = """# TASKS.sample.md

## Pending
- [ ] Draft parser interface
- [ ] Implement report writer
- [ ] Add CLI entrypoint

## Done
- [x] Define pilot scope
- [X] Create scaffold

## Blocked
- [!] Agent execution not started
- [ ] BLOCKED: comparison cannot run until both agent runs exist
"""


class TestClassifyLine(unittest.TestCase):
    def test_pending(self):
        self.assertEqual(classify_line("- [ ] Do something"), "pending")

    def test_done_lower(self):
        self.assertEqual(classify_line("- [x] Done thing"), "done")

    def test_done_upper(self):
        self.assertEqual(classify_line("- [X] Done thing"), "done")

    def test_blocked_bang(self):
        self.assertEqual(classify_line("- [!] Blocked thing"), "blocked")

    def test_blocked_keyword(self):
        self.assertEqual(classify_line("- [ ] BLOCKED: some reason"), "blocked")

    def test_non_checklist(self):
        self.assertIsNone(classify_line("## Heading"))

    def test_non_checklist_text(self):
        self.assertIsNone(classify_line("Plain text"))


class TestParse(unittest.TestCase):
    def setUp(self):
        self.result = parse(SAMPLE)

    def test_pending_count(self):
        self.assertEqual(len(self.result["pending"]), 3)

    def test_done_count(self):
        self.assertEqual(len(self.result["done"]), 2)

    def test_blocked_count(self):
        self.assertEqual(len(self.result["blocked"]), 2)

    def test_pending_items(self):
        self.assertIn("- [ ] Draft parser interface", self.result["pending"])

    def test_done_items(self):
        self.assertIn("- [x] Define pilot scope", self.result["done"])
        self.assertIn("- [X] Create scaffold", self.result["done"])

    def test_blocked_bang_item(self):
        self.assertIn("- [!] Agent execution not started", self.result["blocked"])

    def test_blocked_keyword_item(self):
        self.assertIn(
            "- [ ] BLOCKED: comparison cannot run until both agent runs exist",
            self.result["blocked"],
        )


if __name__ == "__main__":
    unittest.main()
