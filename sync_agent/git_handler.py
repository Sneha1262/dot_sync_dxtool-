import os
import time
import subprocess
import logging
import socket
import threading
from datetime import datetime, timezone

STATUS_FILE = "/tmp/dx_sync_status"


def _write_status(event, detail=""):
    """Write last sync event to a status file for quick health checks."""
    try:
        with open(STATUS_FILE, "w") as f:
            f.write(f"{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC | {event}")
            if detail:
                f.write(f" | {detail}")
            f.write("\n")
    except Exception:
        pass

HOSTNAME = socket.gethostname()
MAX_RETRIES = 3
SYNC_MODE = os.environ.get("SYNC_MODE", "all")
SSH_KEY_MOUNT = "/root/.ssh/dx_sync_key"   # read-only volume mount
SSH_KEY_PATH  = "/root/.ssh/dx_sync_key_rw"  # writable copy used by SSH

# Shared flag: set while a pull is in progress so the watcher can pause
is_pulling = threading.Event()


def run_command(command, cwd=None):
    result = subprocess.run(
        command,
        cwd=cwd,
        shell=True,
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        raise Exception(result.stderr.strip())
    return result.stdout.strip()


def setup_git_config():
    """Configure git identity and SSH authentication.

    The SSH private key is mounted into the container at /root/.ssh/dx_sync_key.
    Git is configured to use it via core.sshCommand — no token, no expiry,
    no credentials stored anywhere in the repo config.
    """
    logging.info("[GIT] Configuring git identity and SSH auth")

    # Copy the read-only mounted key to a writable path and set correct permissions
    run_command(f"cp {SSH_KEY_MOUNT} {SSH_KEY_PATH}")
    run_command(f"chmod 600 {SSH_KEY_PATH}")

    # Add GitHub to known_hosts to avoid interactive host verification prompt
    run_command("mkdir -p /root/.ssh")
    run_command("ssh-keyscan -H github.com >> /root/.ssh/known_hosts")

    # Tell git to use the specific SSH key for all operations
    run_command(
        f'git config --global core.sshCommand "ssh -i {SSH_KEY_PATH} -o StrictHostKeyChecking=yes"'
    )

    run_command('git config --global user.email "dx-agent@example.com"')
    run_command('git config --global user.name "DX Sync Agent"')
    run_command('git config --global pull.rebase true')

    logging.info("[GIT] SSH auth configured — no token, no expiry")


def clone_repo(repo_url, target_dir):
    if not os.path.exists(target_dir):
        logging.info(f"[GIT] Cloning repo to {target_dir}")
        run_command(f"git clone {repo_url} {target_dir}")
    else:
        logging.info("[GIT] Repo already exists, skipping clone")


def pull_changes(repo_dir):
    """Force-sync local state to match remote HEAD.
    Sets is_pulling while running so the watcher skips spurious events.
    """
    is_pulling.set()
    try:
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                logging.info("[GIT] Pulling latest changes from remote...")
                run_command("git fetch origin", cwd=repo_dir)
                run_command("git reset --hard origin/HEAD", cwd=repo_dir)
                logging.info("[GIT] Pull successful")
                _write_status("pull:ok")
                return
            except Exception as e:
                logging.warning(f"[GIT] Pull attempt {attempt}/{MAX_RETRIES} failed: {e}")
                time.sleep(2 ** attempt)
        logging.error("[GIT] Pull failed after all retries")
        _write_status("pull:failed", "check network / GitHub access")
    finally:
        is_pulling.clear()


def push_changes(repo_dir):
    """Commit any local changes and push to remote."""
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            status = run_command("git status --porcelain", cwd=repo_dir)
            if not status:
                logging.info("[GIT] Nothing to commit")
                return

            _stage_files(repo_dir)
            run_command(f'git commit -m "sync: auto-commit from {HOSTNAME}"', cwd=repo_dir)

            try:
                run_command("git pull --rebase", cwd=repo_dir)
            except Exception:
                logging.warning("[GIT] Rebase conflict — resetting to remote HEAD")
                run_command("git fetch origin", cwd=repo_dir)
                run_command("git reset --hard origin/HEAD", cwd=repo_dir)
                return

            run_command("git push", cwd=repo_dir)
            logging.info("[GIT] Push successful")
            _write_status("push:ok")
            return

        except Exception as e:
            logging.warning(f"[GIT] Push attempt {attempt}/{MAX_RETRIES} failed: {e}")
            time.sleep(2 ** attempt)
    logging.error("[GIT] Push failed after all retries")
    _write_status("push:failed", "check network / GitHub access")


def _stage_files(repo_dir):
    if SYNC_MODE == "dotfiles_only":
        logging.info("[GIT] Staging dotfiles only")
        for root, _, files in os.walk(repo_dir):
            if ".git" in root:
                continue
            for f in files:
                if f.startswith("."):
                    full_path = os.path.join(root, f)
                    try:
                        run_command(f'git add "{full_path}"', cwd=repo_dir)
                    except Exception as e:
                        logging.warning(f"[GIT] Could not stage {full_path}: {e}")
    else:
        logging.info("[GIT] Staging all files")
        run_command("git add -A", cwd=repo_dir)
