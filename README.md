# dx-sync-platform

Auto-sync for your personal dots repo across dev containers. No manual steps, no copying files around.

> SSH-authenticated | Feedback-loop safe | Container health monitoring included

---

## Table of Contents

1. [How to Use This Tool](#1-how-to-use-this-tool)
2. [DX Impact](#2-dx-impact)
3. [Demo Walkthrough](#3-demo-walkthrough)
4. [Troubleshooting](#4-troubleshooting)
5. [Analysing the Problem](#5-analysing-the-problem)
6. [Planning the Solution](#6-planning-the-solution)
7. [Architecture](#7-architecture)
8. [Implementation](#8-implementation)
9. [AI Coding Buddy](#9-ai-coding-buddy)

---

## 1. How to Use This Tool

This is a one-time setup. Once you run the install script, the sync agent starts automatically every time your machine boots. You don't need to touch it again.

### Prerequisites

- Docker Desktop installed and running
- A GitHub account with two repositories:
  - `dots-repo` -- create this as a new empty repo on GitHub. This is where your config files get stored and synced.
  - `dx-sync-platform` -- this repo (the sync agent itself)
- An SSH key for GitHub authentication. The install script generates this for you in Step 3.

---

### Step 1 -- Clone this repo

```bash
git clone https://github.com/YOUR_USERNAME/dx-sync-platform.git
cd dx-sync-platform
```

Replace `YOUR_USERNAME` with your GitHub username.

---

### Step 2 -- Set up your environment file

```bash
cp .env.example .env
```

Open `.env` and fill in your values.

**Windows:**
```
SSH_KEY_PATH=C:/Users/YOUR_USERNAME/.ssh/dx_sync_key
DOTS_REPO_URL=git@github.com:YOUR_USERNAME/dots-repo.git
DOTS_DIR=/root/dots
SYNC_INTERVAL=15
SYNC_MODE=all
```

**Linux / macOS:**
```
SSH_KEY_PATH=/home/YOUR_USERNAME/.ssh/dx_sync_key
DOTS_REPO_URL=git@github.com:YOUR_USERNAME/dots-repo.git
DOTS_DIR=/root/dots
SYNC_INTERVAL=15
SYNC_MODE=all
```

Authentication uses SSH. No token, no expiry. The private key gets mounted into each container read-only at `/root/.ssh/dx_sync_key`.

---

### Step 3 -- Run the install script (one time only)

**On Linux / macOS:**
```bash
bash scripts/install.sh
```

**On Windows (run as Administrator):**
```powershell
.\scripts\install.ps1
```

What the install script does:

1. Generates an SSH key pair at `~/.ssh/dx_sync_key` if one doesn't already exist
2. Shows you the public key and waits while you add it to GitHub (Settings > SSH keys)
3. Builds the Docker image
4. Starts the containers in detached mode
5. Registers them to start automatically on every boot/login using systemd on Linux, launchd on macOS, and Task Scheduler on Windows

After this you never touch the tool again. It just runs.

---

### Step 4 -- Verify it's running

```bash
docker ps
```

You should see both containers healthy:
```
dev_container_1   Up 1 minute (healthy)
dev_container_2   Up 1 minute (healthy)
```

---

### Step 5 -- Test the sync

In a new terminal, write a file into dev1:

```bash
docker exec dev_container_1 bash -c "echo 'alias ll=\"ls -la\"' >> /root/dots/.aliases"
```

Watch dev1's logs to confirm it pushed:

```bash
docker logs dev_container_1 --follow
```

You should see:
```
[WATCHER] MODIFIED: /root/dots/.aliases
[GIT] Staging all files
[GIT] Push successful
```

Within about 15 seconds, check dev2 got it automatically without doing anything on dev2:

```bash
docker exec dev_container_2 bash -c "cat /root/dots/.aliases"
```

---

### Step 6 -- Test a brand new container

```bash
docker-compose up -d dev3
docker exec dev_container_3 bash -c "cat /root/dots/.aliases"
```

dev3 cloned the repo on startup so the file is already there. No manual copy needed.

---

### To uninstall

**Linux / macOS:**
```bash
bash scripts/uninstall.sh
```

**Windows:**
```powershell
.\scripts\uninstall.ps1
```

This stops the containers and removes the auto-start registration.

---

### Configuration reference

| Variable | Required | Default | Description |
|---|---|---|---|
| `SSH_KEY_PATH` | yes | -- | Path to the SSH private key on the host machine. Mounted into containers read-only. |
| `DOTS_REPO_URL` | yes | -- | SSH URL for your dots repo: `git@github.com:USER/dots-repo.git` |
| `DOTS_DIR` | no | `/root/dots` | Where the repo gets cloned inside the container |
| `SYNC_INTERVAL` | no | `15` | Seconds between background pulls |
| `SYNC_MODE` | no | `all` | `all` syncs everything, `dotfiles_only` restricts to files starting with `.` |

---

## 2. DX Impact

A good DX tool disappears. You don't notice it's there — you just notice when it's missing.

### Container setup used to mean manual work

Before this, spinning up a new container meant re-adding aliases, re-copying config files, and trying to remember what you had set up in the previous one. That's not a big task once, but it's an annoying one every time — and in a team where developers spin up containers regularly, it's constant low-level friction.

With this solution the container clones the dots repo on startup. The developer's environment is already there when they open a terminal.

### One source of truth, no manual copying

Without sync, the question "which container has my latest `.bashrc`?" becomes a real question. You edit something in dev1, switch to dev3, and it's not there. Did I save it? Did I push it? This solution removes that entirely — GitHub is the source of truth, every container converges to it within 15–23 seconds.

### Nothing to trigger, nothing to remember

The developer edits a file. That's it. The agent detects it, commits it, pushes it, and every other container pulls it on the next tick. No command to run, no flag to set, no sync to check.

---

## 3. Demo Walkthrough

These are the three core scenarios the solution has to satisfy. Run them in order after completing the install steps.

---

### Scenario 1 -- Change in one container reaches all others within 30 seconds

Start dev1 and dev2:

```bash
docker-compose up -d dev1 dev2
```

Write a file into dev1:

```bash
docker exec dev_container_1 bash -c "echo 'alias ll=\"ls -la\"' >> /root/dots/.aliases"
```

Watch dev1 push it:

```bash
docker logs dev_container_1 --follow
```

You should see output like this within about 8 seconds:
```
[WATCHER] MODIFIED: /root/dots/.aliases
[GIT] Staging all files
[GIT] Push successful
```

Within 15 seconds, check dev2 got it without doing anything on dev2:

```bash
docker exec dev_container_2 bash -c "cat /root/dots/.aliases"
```

The alias should be there.

---

### Scenario 2 -- New container starts with the latest state

Spin up a fresh container:

```bash
docker-compose up -d dev3
```

Check it already has the file that was pushed from dev1:

```bash
docker exec dev_container_3 bash -c "cat /root/dots/.aliases"
```

The alias is already there. dev3 cloned the repo on startup.

---

### Scenario 3 -- Auto-start survives a reboot

Shut down the machine and start it again. Once logged in, wait about 30 seconds for Docker Desktop to start, then:

```bash
docker ps
```

All containers should be running without any manual start. Repeat Scenario 1 to confirm sync still works.

---

## 4. Troubleshooting

### Checking sync status at a glance

Each container writes its last sync event to `/tmp/dx_sync_status`. Quick check without reading full logs:

```bash
docker exec dev_container_1 cat /tmp/dx_sync_status
```

Expected output:
```
2026-04-02 20:14:23 UTC | push:ok
```
or
```
2026-04-02 20:14:33 UTC | pull:ok
```

If the file is missing or the timestamp is old, the agent hasn't synced recently. Check `docker logs dev_container_1` for errors.

To check all containers at once:

**Linux / macOS:**
```bash
bash scripts/status.sh
```

**Windows:**
```powershell
.\scripts\status.ps1
```

Expected output:
```
=== DX Sync Platform -- Status ===

  dev_container_1: 2026-04-02 20:14:23 UTC | push:ok
  dev_container_2: 2026-04-02 20:14:33 UTC | pull:ok
  dev_container_3: 2026-04-02 20:14:33 UTC | pull:ok

All containers syncing normally.
```

---

### Containers not starting after reboot

Docker Desktop needs to be running first. Open Docker Desktop and enable "Start Docker Desktop when you log in" in Settings > General.

---

### `docker logs` shows `Permission denied` or `SSH key` error

The SSH private key at `~/.ssh/dx_sync_key` isn't accessible. Check:

1. The key exists: `ls ~/.ssh/dx_sync_key`
2. The path in `.env` matches exactly (Windows uses `C:/Users/...`, Linux/macOS uses `/home/...`)
3. The public key has been added to GitHub: Settings > SSH and GPG keys

---

### Containers show as `unhealthy`

The healthcheck verifies that `/root/dots/.git` exists, meaning the agent successfully cloned the repo. If it fails:

1. Check the SSH key is added to GitHub
2. Check `DOTS_REPO_URL` in `.env` is the SSH format: `git@github.com:USERNAME/dots-repo.git`
3. Run `docker logs dev_container_1` to see the actual error

---

### Changes not syncing between containers

1. Confirm both containers are running: `docker ps`
2. Check dev1 logs for push confirmation: `docker logs dev_container_1 --follow`
3. Check dev2 logs for pull activity: `docker logs dev_container_2 --follow`
4. Make sure the dots repo is accessible: `ssh -T git@github.com`

---

### `ssh -T git@github.com` returns `Permission denied`

Your SSH public key isn't added to GitHub. Run:

```bash
cat ~/.ssh/dx_sync_key.pub
```

Copy the output and add it at GitHub > Settings > SSH and GPG keys > New SSH key.

---

### Status script shows `push:failed` or `pull:failed`

The agent couldn't reach GitHub after retrying. Usually a network issue. Check:

1. Internet connection is active
2. GitHub is reachable: `ssh -T git@github.com`
3. If SSH fails, re-add the public key at GitHub > Settings > SSH and GPG keys

The agent recovers automatically once connectivity is back. No restart needed.

---

### Two containers edited the same file at the same time

The solution uses last-write-wins via GitHub. If two containers push a change to the same file at the same time, the second push detects diverged history, tries a rebase, and if there's a real line-level conflict it resets to remote state. That means the second container's change gets discarded and it converges to whatever GitHub has.

In practice this is rare for personal dotfiles since it's one developer across multiple containers, rarely editing the same line at the same moment. But if a change disappears, check `docker logs dev_container_X` for a rebase conflict warning and re-apply the change.

---

## 5. Analysing the Problem

The challenge describes a real problem in distributed dev setups: developers lose their personal environment every time a new container is created.

When a team uses containers as remote dev environments on IaaS, each developer has their own stuff: shell aliases, custom configs, utility scripts, editor settings. Small things but they matter. Everyone has spent time setting them up and uses them daily.

The problem breaks into two parts:

**Part 1: Keeping existing containers in sync.** A developer updates their `.bashrc` in one container and that change doesn't exist in their other running containers. They either copy it manually or just live with the inconsistency.

**Part 2: New containers starting from scratch.** Every new container is a blank slate. Without something to pull in the developer's tools on startup, they set everything up again from zero. Or they connect a shared volume, which has its own issues (host dependency, no history, disappears when the environment gets recreated).

The core constraint: any change to the dots folder has to reach all other running containers within 30 seconds, new containers have to be immediately up to date, and the developer shouldn't have to do anything to trigger it.

---

## 6. Planning the Solution

I worked through the options before writing code.

**What the solution needs to do:**

- Detect file changes inside the dots folder automatically
- Push those changes somewhere all containers can reach
- Have all containers regularly pull in changes they didn't make
- On startup, a new container has to fetch the latest state before the developer touches anything
- Start automatically on boot. If the developer has to manually start the sync agent every session it's not really a DX tool, it's just another step.

**Options I considered:**

**Shared Docker volume.** Simple to set up but only works if all containers are on the same Docker host. The challenge mentions IaaS where containers can run on different machines. Shared volumes also have no history and don't survive environment recreation. Ruled out.

**Custom sync server / message broker.** Something like a dedicated server or Kafka that containers push to and subscribe from. It works but it's a lot of infrastructure for what should be a lightweight tool. Ruled out.

**Git-based sync via GitHub.** Every developer already has a GitHub account. Git gives you history, works across any host, handles conflicts, and needs zero extra infrastructure. The "dots repo" in the challenge is already a Git repo. This was the natural fit.

**What I went with:**

Each container runs a small Python agent that:

1. On startup, clones the dots repo (or skips if already there) and pulls latest
2. Continuously watches the dots folder for file changes and pushes them to GitHub
3. In the background, pulls from GitHub every 15 seconds to pick up changes from other containers

This covers all three scenarios: existing containers staying in sync, new containers starting up to date, and everything happening automatically.

---

## 7. Architecture

### Overview

```
+---------------------------------------------+
|           GitHub (dots-repo)                |
|         Central source of truth             |
+--------------+-----------------+------------+
               |  push/pull      |  push/pull
     +---------v------+  +-------v---------+
     | dev_container_1 |  | dev_container_2 |  ...
     |  +- Watcher     |  |  +- Watcher     |
     |  +- Pull loop   |  |  +- Pull loop   |
     +-----------------+  +-----------------+
```

### Sync flow

```
Developer edits a file in /root/dots/
        |
Watcher detects change (~1s)
        |
5s debounce (collapses burst edits into one push)
        |
git add -A > git commit > git push (~3s)
        |
GitHub (dots-repo updated)
        |
Other containers pull on their next 15s tick
        |
All containers in sync   (<=23s total, SLA is 30s)
```

### Why this architecture

**Git over a shared volume.** A shared Docker volume ties every container to the same physical host. In an IaaS setup where containers run on different machines, that breaks. Git works across any host, any cloud, any network. It also gives you full history of every change, which a volume never would.

**Git over a custom sync server.** A dedicated sync service means infrastructure to deploy, maintain, and keep secure. Git and GitHub are already part of every developer's workflow. Nothing new to learn or operate.

**Pull loop over webhooks or pub/sub.** Webhooks would need each container to expose a port and handle inbound HTTP, which is complex in a containerised IaaS setup. A pull loop on a 15-second interval is reliable, stateless, and needs no inbound connectivity.

---

## 8. Implementation

### Project structure

```
dx-sync-platform/
+-- sync_agent/
|   +-- __init__.py       # Makes sync_agent a proper Python package
|   +-- main.py           # Entry point, startup sequence and thread orchestration
|   +-- git_handler.py    # All git operations: clone, pull, push, config
|   +-- watcher.py        # File system watcher, detects changes and triggers push
|   +-- logger.py         # Logging configuration
+-- scripts/
|   +-- install.sh        # One-time setup for Linux/macOS (systemd / launchd)
|   +-- install.ps1       # One-time setup for Windows (Task Scheduler)
|   +-- uninstall.sh      # Removes auto-start and stops containers (Linux/macOS)
|   +-- uninstall.ps1     # Removes auto-start and stops containers (Windows)
|   +-- status.sh         # Check sync status across all containers (Linux/macOS)
|   +-- status.ps1        # Check sync status across all containers (Windows)
+-- Dockerfile            # Single image used by all containers
+-- docker-compose.yml    # Defines dev1, dev2, dev3 with health checks
+-- requirements.txt      # watchdog==4.0.0
+-- .env.example          # Safe template, no real credentials
+-- .gitignore            # Ensures .env is never committed
```

### How each component works

**main.py** runs in sequence on startup: configure git identity, clone repo, pull latest, start pull loop thread, hand off to watcher. The pull loop runs as a daemon thread so it doesn't block the watcher. If `DOTS_REPO_URL` is missing it fails immediately with a clear error.

**git_handler.py** handles all git operations. SSH auth is configured via `git config core.sshCommand` pointing to the mounted private key at `/root/.ssh/dx_sync_key`. On startup `ssh-keyscan github.com` adds GitHub to `known_hosts` to avoid interactive prompts. No token, no expiry, nothing stored in `.git/config`. Pull uses `fetch + reset --hard origin/HEAD` rather than `git pull` because it's idempotent. It always converges to remote state regardless of what happened locally. An `is_pulling` threading flag gets set during every pull so the watcher knows to ignore events.

**watcher.py** uses the `watchdog` library which hooks into OS-level inotify events on Linux for instant detection with no polling. Handles created, modified, and deleted events. Before acting on any event it checks: is this a `.git` internal file? Is it an editor temp file (`.lock`, `.swp`, `~`)? Is a pull currently running? A 5-second debounce collapses burst edits into a single push.

**docker-compose.yml** defines three services sharing the same image and `.env`. `restart: unless-stopped` recovers from crashes. The healthcheck uses `python -c "import os, sys; sys.exit(0 if os.path.isdir('/root/dots/.git') else 1)"` which is a Python one-liner rather than `pgrep` because `python:3.11-slim` doesn't include process inspection tools.

**scripts/install.sh and install.ps1** do three things: build the image, start the containers in detached mode, and register them with the OS auto-start mechanism. On Linux that's a systemd service (`After=docker.service`), on macOS a launchd plist, on Windows a Task Scheduler task at login. Run it once, never think about it again.

### Issues I ran into and how I fixed them

These were the main problems that came up during implementation. None of them were obvious from just reading the code.

---

**The feedback loop.** This was the worst one. The first time I ran the watcher and pull loop together, changes pulled from GitHub were immediately getting pushed back. What was happening: `git reset --hard` during a pull replaces files on disk, and watchdog sees those as real filesystem events. So it fires callbacks and tries to push content that just arrived from remote. The agent was basically talking to itself in a loop.

I fixed this with a shared `threading.Event` flag called `is_pulling`. It gets set before every pull and cleared after. The watcher checks this flag before acting on any event. If a pull is running, all events get skipped. That killed the loop completely.

---

**Burst edits causing commit spam.** When you save a file a few times quickly, or an editor writes temp files before the final save, the watcher was firing a push for every single event. That meant a bunch of unnecessary git commits and potential push conflicts.

I added a 5-second debounce. The watcher records when it last pushed and ignores new events within that window. Burst edits collapse into one push. Five seconds is short enough to stay well within the 30-second SLA while absorbing typical editor save patterns.

---

**Healthcheck failing and I had no idea why.** The initial healthcheck used `pgrep -f sync_agent.main` to check if the agent process was running. Every container was showing as `unhealthy` in `docker ps` and there was no useful error message. Turned out `python:3.11-slim` doesn't include `pgrep` at all. The command was just silently failing.

I replaced it with a Python one-liner that checks if `/root/dots/.git` exists. That's actually a better health signal anyway because it validates that the agent successfully connected to GitHub and cloned the repo, not just that a process is running.

---

### Key implementation decisions

**Why pause the watcher during pulls?** Because `git reset --hard` modifies files on disk and watchdog doesn't know the difference between a developer editing a file and git replacing one. Without the pause, every pull triggers a push. With it, the watcher just waits.

**Why `fetch + reset --hard` instead of `git pull`?** `git pull` breaks if there are uncommitted local changes or diverged history, both of which are realistic in a container that's been running and pushing. `--rebase` is better but still assumes a workable local tree. `fetch + reset --hard` is idempotent. It always makes local match remote, no matter what. For a container whose only job is to have the latest content, that's the right behaviour.

**Why `SYNC_MODE=all` as default?** The dots repo isn't just hidden files. Config files like `config.txt`, shell scripts, and tool configs don't start with `.` but are just as important. `dotfiles_only` is there for stricter setups if someone wants it.

---

## 9. AI Coding Buddy

I used Claude (claude-sonnet-4-6) as my AI coding buddy throughout this challenge.

I want to be upfront about how I used it. I didn't have Claude write the solution for me, but I also didn't just use it for autocomplete. I used it at the points where I was stuck or unsure, and it helped me move faster and catch things I would have missed. Below are the key moments where I brought it in and what came out of each one.

---

### First approach didn't work, so I started over

I actually built this twice. My first attempt (separate repo) had the same basic idea: watchdog for file detection, git push/pull for sync, Docker Compose for the containers. It was all in a single Python file with a flat project structure. The sync wasn't working properly. Changes in one container weren't reliably showing up in the other.

Rather than keep patching something that felt wrong, I decided to start fresh with a cleaner structure. I brought my first attempt into Claude and asked:

> "Here's my sync agent code. It's supposed to watch for file changes and sync them across containers using git, but the sync isn't working reliably. Can you go through it and tell me what's broken and what's missing?"

Claude pointed out a few things: the watcher and the pull loop were stepping on each other (more on that below), there was no debounce so every tiny filesystem event was triggering a push, and the error handling was basically nonexistent so failures were silent. That confirmed my gut feeling that the approach wasn't just buggy, it needed restructuring. So I started the second implementation with a proper package layout and addressed each issue from the start.

---

### Figuring out the feedback loop

This was the one that really got me. I had the watcher working and the pull loop working, but when I ran them together, the agent went into a loop: pull a change, watcher sees it, pushes it back, next pull picks it up again. The logs were just a wall of push/pull messages.

I asked Claude:

> "My file watcher and pull loop are running in the same agent. Every time a pull happens the watcher sees the changed files and tries to push them back. How do I stop this loop?"

The answer was to use a threading flag. Set it before a pull, clear it after, and have the watcher check it before doing anything. Simple idea but I hadn't thought of it because I was thinking about the watcher and the pull loop as separate things rather than two threads sharing the same filesystem.

---

### Choosing the pull strategy

My first approach used `git pull --rebase` which worked most of the time but occasionally failed when the local state had gotten weird. I wasn't sure what the right approach was so I asked:

> "I need containers to pull the latest dotfiles from a shared repo. Sometimes local state diverges. What's the most reliable git strategy for this: regular pull, pull --rebase, or fetch + reset --hard?"

Claude walked through the failure modes of each. `git pull` breaks on uncommitted changes or diverged history. `--rebase` is better but still needs a clean-ish local tree. `fetch + reset --hard` just forces local to match remote every time, which is exactly what a receiving container should do. I switched to that and the flaky pull failures went away.

---

### The healthcheck mystery

All my containers were showing as `unhealthy` in `docker ps` and I couldn't figure out why. The healthcheck command looked right. I asked:

> "My Docker healthcheck uses pgrep to check if the sync agent is running but every container shows unhealthy. The agent is definitely running. What's going on?"

Turned out `python:3.11-slim` doesn't ship with `pgrep`. The healthcheck command was failing silently because the binary didn't exist, not because the process wasn't running. Claude suggested checking for `/root/dots/.git` instead using a Python one-liner, which is actually a better health signal since it proves the agent successfully cloned the repo.

---

### Making it feel like a real tool, not just a script

After the sync was working end to end I asked Claude to look at it from a DX perspective:

> "The sync works. But if you were a senior DX engineer reviewing this, what would you say is missing to make it a proper developer tool rather than just a working script?"

A few things came up. The original version used a GitHub token in the URL which is a security problem since tokens expire and can leak into logs. There were no install/uninstall scripts so the developer would have to manually start containers. And there was no easy way to check sync status without reading through container logs. I addressed all of these: switched to SSH key auth, added the install scripts with OS-level auto-start, and added the status file and status scripts.

---

### Verifying the whole thing end to end

Before calling it done I wanted to make sure the entire flow worked from a clean slate, not just that individual pieces worked. I asked Claude to help me build a verification sequence:

> "Help me test the complete flow from scratch. I want to rebuild the containers, make a change in dev1, confirm it pushes, confirm dev2 pulls it, then spin up dev3 and confirm it has the latest state on startup."

This became the demo walkthrough in Section 3. Running through it end to end caught a couple of small issues with the startup sequence that I wouldn't have found by testing individual components. It also meant I knew exactly what "working" looks like in the logs, so if something breaks during a live demo I'll spot it immediately.

---

### How I used AI overall

Looking back, the pattern was pretty consistent. I'd build something, get stuck or feel uncertain, ask Claude a specific question, and then take the answer and implement it myself. The architecture and the technology choices were mine. Claude didn't design the solution. But it caught things I missed (the feedback loop, the pgrep issue), helped me make more informed decisions (pull strategy, language choice), and pushed me to think about the solution as a tool rather than just code that works.

If I'm being honest, the biggest value wasn't in any single answer. It was that having someone to bounce ideas off made me think more carefully about each decision. When you have to explain what you're doing well enough to ask a good question, you often figure out half the problem yourself.