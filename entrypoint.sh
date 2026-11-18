#!/bin/bash
# Never exits on a bad variable or a full volume: each step logs and falls back, so a
# typo or a cleared password can't leave the service crash-looping (Railway then marks
# the deploy CRASHED). The web terminal is never served without a login.
log() { echo "railway: $*"; }

# Railway's healthcheck probes $PORT, so nginx always listens there; the other ports
# step aside instead (ttyd's internal port, and sshd if PORT is 22).
case "${PORT:-}" in
  ''|*[!0-9]*) log "PORT='${PORT:-}' is not a number, using 7681"; PORT=7681 ;;
esac
export PORT
TTYD_PORT=7682
[ "$PORT" = 7682 ] && TTYD_PORT=7683

# /root is a Railway volume: empty on first boot, root-owned. Seed dotfiles once
# (flag file, not per-file checks: local docker pre-copies the image's /root into a
# fresh volume, which would otherwise shadow our skel).
if [ ! -f /root/.ubuntu-box-seeded ]; then
  cp -af /opt/skel/. /root/ && touch /root/.ubuntu-box-seeded
fi
# Dotfiles added to skel later (.profile) reach existing volumes; edited ones are kept.
cp -an /opt/skel/. /root/ 2>/dev/null || true
mkdir -p /root/.ssh /root/src && chmod 700 /root/.ssh || log "warning: can't write /root (is the volume full?)"

# Persist SSH host keys on the volume so clients don't see "host key changed" after redeploys.
mkdir -p /root/.ssh-host
for t in rsa ed25519; do
  if [ -s "/root/.ssh-host/ssh_host_${t}_key" ] || ssh-keygen -q -t "$t" -N '' -f "/root/.ssh-host/ssh_host_${t}_key" </dev/null; then
    cp -f "/root/.ssh-host/ssh_host_${t}_key" "/root/.ssh-host/ssh_host_${t}_key.pub" /etc/ssh/
  else
    # Volume full or read-only: a host key for this boot only, so sshd still starts.
    log "warning: can't keep the $t SSH host key on the volume, using one for this boot"
    rm -f "/etc/ssh/ssh_host_${t}_key" "/etc/ssh/ssh_host_${t}_key.pub"
    ssh-keygen -q -t "$t" -N '' -f "/etc/ssh/ssh_host_${t}_key" </dev/null
  fi
  chmod 600 "/etc/ssh/ssh_host_${t}_key"
done

# Root login: password from ROOT_PASSWORD, optional keys from AUTHORIZED_KEYS.
if [ -n "${ROOT_PASSWORD:-}" ]; then
  printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd || log "warning: ROOT_PASSWORD could not be set (one line, no newlines)"
fi
if [ -n "${AUTHORIZED_KEYS:-}" ]; then
  { printf '%s\n' "$AUTHORIZED_KEYS" > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys; } \
    || log "warning: can't write /root/.ssh/authorized_keys (is the volume full?)"
fi
cat > /etc/ssh/sshd_config.d/railway.conf <<CFG
Port 22
ListenAddress 0.0.0.0
ListenAddress ::
PermitRootLogin yes
PasswordAuthentication $([ -n "${ROOT_PASSWORD:-}" ] && echo yes || echo no)
ClientAliveInterval 60
CFG
if [ "$PORT" = 22 ]; then
  log "PORT is 22, which SSH uses: the web terminal takes it and sshd is not started"
else
  /usr/sbin/sshd || log "warning: sshd did not start; the web terminal still works"
fi

# Make service variables visible to SSH sessions too (sshd strips the environment).
env | grep -E '^(GH_TOKEN|GITHUB_TOKEN|TZ|PORT)' | sed 's/^/export /; s/=/="/; s/$/"/' > /etc/profile.d/railway-env.sh || true

# nginx on $PORT: unauthenticated /healthcheck for Railway, everything else to ttyd.
cat > /etc/nginx/sites-enabled/default <<CFG
server {
  listen ${PORT} default_server;
  listen [::]:${PORT} default_server;
  location = /healthcheck { return 200 "ok"; }
  location / {
    proxy_pass http://127.0.0.1:${TTYD_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_read_timeout 1d;
  }
}
CFG
nginx || log "error: nginx did not start on port $PORT"

# Railway counts the kernel's cache of files this container has touched as the
# service's memory, and with no memory pressure it is never freed: one pip
# install shows as hundreds of MB. Drop it for the home volume every 15 min.
( while sleep 900; do nice -n 19 drop-file-cache /root /tmp || true; done ) &

# Web terminal login. ttyd splits user:password at the first colon, so a user name
# can't hold one. An empty password gets a one-off one printed here, never open access.
web_user=$(printf '%s' "${WEB_USER:-}" | tr -d '[:space:]')
case "$web_user" in
  '') web_user=admin ;;
  *:*) log "WEB_USER may not contain ':', using 'admin'"; web_user=admin ;;
esac
web_pass=${WEB_PASSWORD:-}
if [ -z "$web_pass" ]; then
  web_pass=$(head -c 18 /dev/urandom | base64 | tr -d '/+=')
  log "WEB_PASSWORD is empty. A temporary password for this boot only: $web_pass"
  log "set the WEB_PASSWORD variable to keep one that survives restarts"
fi

echo "== ubuntu-box ready: web terminal on :${PORT}, sshd on :22"
# Web terminal: ttyd with basic auth, each tab attaches to the same tmux session, in ~.
cd /root
exec ttyd -i 127.0.0.1 -p "$TTYD_PORT" -W -c "$web_user:$web_pass" \
  -t titleFixed="ubuntu-box" -t fontSize=14 \
  bash -lc 'exec tmux new -A -s main'
