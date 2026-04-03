import os
import tempfile
import unittest
from unittest.mock import patch


class TestWriteStatus(unittest.TestCase):
    """_write_status — writes last sync event to a file for observability."""

    def _with_temp_status_file(self, fn):
        with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".txt") as f:
            tmp = f.name
        try:
            from sync_agent import git_handler
            original = git_handler.STATUS_FILE
            git_handler.STATUS_FILE = tmp
            fn(git_handler)
            git_handler.STATUS_FILE = original
            return tmp
        except Exception:
            git_handler.STATUS_FILE = original
            raise

    def test_writes_event_and_utc_timestamp(self):
        def check(gh):
            gh._write_status("push:ok")
            with open(gh.STATUS_FILE) as f:
                content = f.read()
            self.assertIn("push:ok", content)
            self.assertIn("UTC", content)

        tmp = self._with_temp_status_file(check)
        os.unlink(tmp)

    def test_writes_optional_detail(self):
        def check(gh):
            gh._write_status("pull:failed", "network timeout")
            with open(gh.STATUS_FILE) as f:
                content = f.read()
            self.assertIn("pull:failed", content)
            self.assertIn("network timeout", content)

        tmp = self._with_temp_status_file(check)
        os.unlink(tmp)

    def test_silently_ignores_write_errors(self):
        """Agent must never crash if the status file cannot be written."""
        from sync_agent.git_handler import _write_status
        with patch("builtins.open", side_effect=PermissionError("read-only")):
            _write_status("push:ok")  # must not raise


class TestRunCommand(unittest.TestCase):
    """run_command — thin subprocess wrapper."""

    def test_raises_on_nonzero_exit(self):
        from sync_agent.git_handler import run_command
        with self.assertRaises(Exception):
            run_command("python -c \"import sys; sys.exit(1)\"")

    def test_returns_stripped_stdout_on_success(self):
        from sync_agent.git_handler import run_command
        result = run_command("python -c \"print('hello')\"")
        self.assertEqual(result, "hello")


if __name__ == "__main__":
    unittest.main()
