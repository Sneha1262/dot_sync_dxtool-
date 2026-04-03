import os
import time
import logging
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

from sync_agent.git_handler import push_changes, is_pulling

SYNC_MODE = os.environ.get("SYNC_MODE", "all")
DEBOUNCE_SECONDS = 5


class ChangeHandler(FileSystemEventHandler):
    def __init__(self, repo_dir):
        self.repo_dir = repo_dir
        self.last_push_time = 0

    def _should_sync(self, path: str) -> bool:
        normalized = os.path.normpath(path).replace("\\", "/")
        filename = os.path.basename(normalized)

        # Ignore git internals
        if ".git" in normalized:
            return False

        # Ignore editor temp / lock files
        if filename.endswith((".lock", "~", ".tmp", ".swp")):
            return False

        # In dotfiles_only mode, only sync files that start with '.'
        if SYNC_MODE == "dotfiles_only" and not filename.startswith("."):
            return False

        return True

    def _trigger_push(self, event_type: str, path: str) -> None:
        if not self._should_sync(path):
            return

        # Skip events caused by git reset --hard during a pull.
        # Without this guard, pull-triggered file writes would fire another push,
        # creating an infinite push→pull→push feedback loop across containers.
        if is_pulling.is_set():
            return

        now = time.time()
        if now - self.last_push_time < DEBOUNCE_SECONDS:
            return

        self.last_push_time = now
        logging.info(f"[WATCHER] {event_type}: {path}")

        try:
            push_changes(self.repo_dir)
        except Exception as e:
            logging.error(f"[WATCHER] Push failed: {e}")

    def on_created(self, event):
        if not event.is_directory:
            self._trigger_push("CREATED", str(event.src_path))

    def on_modified(self, event):
        if not event.is_directory:
            self._trigger_push("MODIFIED", str(event.src_path))

    def on_deleted(self, event):
        if not event.is_directory:
            self._trigger_push("DELETED", str(event.src_path))


def start_watcher(repo_dir: str) -> None:
    handler = ChangeHandler(repo_dir)
    observer = Observer()
    observer.schedule(handler, path=repo_dir, recursive=True)
    observer.start()

    logging.info(f"[WATCHER] Monitoring {repo_dir} (mode={SYNC_MODE})")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        logging.info("[WATCHER] Shutting down...")
        observer.stop()

    observer.join()
