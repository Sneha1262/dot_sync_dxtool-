import os
import time
import logging
import threading

from sync_agent.logger import setup_logger
from sync_agent.git_handler import setup_git_config, clone_repo, pull_changes
from sync_agent.watcher import start_watcher

# ── Configuration ─────────────────────────────────────────────
# Read env vars at module level — no side effects, safe to import

DOTS_DIR = os.environ.get("DOTS_DIR", "/root/dots")

try:
    SYNC_INTERVAL = int(os.environ.get("SYNC_INTERVAL", "15"))
except ValueError:
    SYNC_INTERVAL = 15

# ── Background pull loop ──────────────────────────────────────


def periodic_pull(dots_dir, interval):
    """Pull from remote on a fixed interval to catch changes from other containers."""
    while True:
        time.sleep(interval)
        try:
            pull_changes(dots_dir)
        except Exception as e:
            logging.error(f"[PULL LOOP] Unexpected error: {e}")


# ── Entry point ───────────────────────────────────────────────

if __name__ == "__main__":
    # Set up logging before anything else
    setup_logger()

    # Validate required config — fail fast with a clear message
    DOTS_REPO_URL = os.environ.get("DOTS_REPO_URL")
    if not DOTS_REPO_URL:
        raise ValueError("DOTS_REPO_URL environment variable is required")

    logging.info("=== DX Sync Agent starting ===")
    logging.info(f"Repo: {DOTS_REPO_URL}")
    logging.info(f"Dots dir: {DOTS_DIR}")
    logging.info(f"Pull interval: {SYNC_INTERVAL}s")

    # Configure git identity inside the container
    setup_git_config()

    # Clone on first run, skip if already present
    clone_repo(DOTS_REPO_URL, DOTS_DIR)

    # Always pull latest state on startup
    pull_changes(DOTS_DIR)

    # Start background pull loop
    threading.Thread(target=periodic_pull, args=(DOTS_DIR, SYNC_INTERVAL), daemon=True).start()
    logging.info(f"[MAIN] Pull loop running every {SYNC_INTERVAL}s")

    # Block here — watches for file changes and pushes
    start_watcher(DOTS_DIR)
