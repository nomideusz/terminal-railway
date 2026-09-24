# Deploy and Host a Linux Terminal (Ubuntu Web Shell + SSH + tmux) on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/ubuntu-terminal?utm_medium=integration&utm_source=button&utm_campaign=ubuntu-terminal)

This template gives you an always-on Ubuntu 24.04 shell. Open your Railway domain for a terminal in the browser, or SSH in through Railway's TCP proxy. Both land in the same `tmux` session, so a job you start from your laptop is still running when you reconnect from your phone. Your home directory lives on a volume, so repos, GitHub auth and dotfiles survive every redeploy.

## About Hosting an Ubuntu Terminal

One service, one volume. The image ships `git`, `gh`, Python 3 + `uv`, `tmux`, `ripgrep`, `jq`, `vim`, build tools and an OpenSSH server. A `ttyd` web terminal (basic-auth gated) and `sshd` (password or key) both drop you into the same `tmux` session, so you can start a long job from your laptop and pick it up from your phone. SSH host keys are stored on the volume, so your client never sees a "host key changed" warning after a redeploy.

## Common Use Cases

- A shell that keeps running: start a long script, close the tab, come back later
- Code from an iPad, Chromebook or phone: the browser terminal needs no SSH client
- A disposable root box with a stable IP for scripts, scraping, cron-style jobs or CI debugging
- Keep a persistent workspace for side projects that is reachable from anywhere

## Dependencies for Ubuntu Terminal Hosting

- None. Single service, no database.

### Deployment Dependencies

- [ttyd](https://github.com/tsl0922/ttyd) web terminal
- [GitHub CLI](https://cli.github.com/)

### Implementation Details

**First use:** open your Railway domain, log in with `WEB_USER` and the generated `WEB_PASSWORD` (service Variables tab). You are in a `tmux` session named `main`; close the tab, reopen it, and everything is still there.

**SSH:** Railway creates a TCP proxy for port 22 on deploy. Copy the host and port from Settings → Networking and run `ssh root@<host> -p <port>` with `ROOT_PASSWORD`, or add your public key to `AUTHORIZED_KEYS` and clear `ROOT_PASSWORD` for key-only login.

**Handy commands inside the box:**

- `tmux new -s work` opens a second session; `tmux ls` and `tmux attach -t work` get back to it
- `gh auth login` or set `GH_TOKEN` to push to GitHub
- `apt install <pkg>` works (you are root); anything outside `/root` is gone after a redeploy

Notes and limits:

- You are root. Anything you install outside `/root` disappears on redeploy; anything under `/root` stays.
- 512 MB of RAM is enough for a shell; size up for builds.
- There is no Docker daemon inside the box.
- The web terminal password is the whole security model for a root shell. Keep it strong and do not share the URL.
- Want Claude Code preinstalled? The same author publishes a [Claude Code dev box](https://railway.com/deploy/claude-code) template.

## Why Deploy an Ubuntu Terminal on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying an Ubuntu terminal on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
