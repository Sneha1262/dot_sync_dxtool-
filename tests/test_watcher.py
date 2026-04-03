import time
import unittest
from unittest.mock import patch


class TestShouldSync(unittest.TestCase):
    """ChangeHandler._should_sync — pure filtering logic, no I/O."""

    def setUp(self):
        from sync_agent.watcher import ChangeHandler
        self.handler = ChangeHandler("/repo")

    def test_ignores_git_internals(self):
        self.assertFalse(self.handler._should_sync("/repo/.git/COMMIT_EDITMSG"))

    def test_ignores_lock_files(self):
        self.assertFalse(self.handler._should_sync("/repo/file.lock"))

    def test_ignores_swp_files(self):
        self.assertFalse(self.handler._should_sync("/repo/.bashrc.swp"))

    def test_ignores_tilde_backup_files(self):
        self.assertFalse(self.handler._should_sync("/repo/.bashrc~"))

    def test_ignores_tmp_files(self):
        self.assertFalse(self.handler._should_sync("/repo/scratch.tmp"))

    def test_syncs_dotfiles(self):
        self.assertTrue(self.handler._should_sync("/repo/.bashrc"))

    def test_syncs_regular_files_in_all_mode(self):
        self.assertTrue(self.handler._should_sync("/repo/config.txt"))


class TestIsPullingGuard(unittest.TestCase):
    """The is_pulling flag must block pushes while a pull is in progress."""

    def tearDown(self):
        from sync_agent.git_handler import is_pulling
        is_pulling.clear()

    def test_skips_push_when_pull_in_progress(self):
        from sync_agent.git_handler import is_pulling
        from sync_agent.watcher import ChangeHandler

        handler = ChangeHandler("/repo")
        is_pulling.set()

        with patch("sync_agent.watcher.push_changes") as mock_push:
            handler._trigger_push("MODIFIED", "/repo/.bashrc")
            mock_push.assert_not_called()

    def test_triggers_push_when_not_pulling(self):
        from sync_agent.git_handler import is_pulling
        from sync_agent.watcher import ChangeHandler

        handler = ChangeHandler("/repo")
        handler.last_push_time = 0  # bypass debounce
        is_pulling.clear()

        with patch("sync_agent.watcher.push_changes") as mock_push:
            handler._trigger_push("MODIFIED", "/repo/.bashrc")
            mock_push.assert_called_once_with("/repo")

    def test_debounce_suppresses_rapid_pushes(self):
        from sync_agent.git_handler import is_pulling
        from sync_agent.watcher import ChangeHandler

        handler = ChangeHandler("/repo")
        handler.last_push_time = time.time()  # simulate a very recent push
        is_pulling.clear()

        with patch("sync_agent.watcher.push_changes") as mock_push:
            handler._trigger_push("MODIFIED", "/repo/.bashrc")
            mock_push.assert_not_called()


if __name__ == "__main__":
    unittest.main()
