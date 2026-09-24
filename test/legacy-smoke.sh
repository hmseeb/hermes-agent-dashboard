#!/usr/bin/env bash
# Smoke test for Dockerfile.legacy-data against a fake praveen-era volume:
# root-owned files under /data, HERMES_HOME=/data/.hermes, watchdog scripts present.
# Usage: test/legacy-smoke.sh [image]   (default hermes-legacy:smoke)
set -euo pipefail
IMG="${1:-hermes-legacy:smoke}"
VOL="$(mktemp -d)"
NAME="hermes-legacy-smoke-$$"
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$VOL"' EXIT

# Fake legacy volume: root-owned (docker cp'ed in as root), scripts dir with a
# watchdog stub that records it ran, HOME-relative state outside HERMES_HOME.
mkdir -p "$VOL/.hermes/scripts" "$VOL/.config/gws" "$VOL/projects"
cat > "$VOL/.hermes/scripts/ensure-nix-webui-tunnel.sh" <<'EOF'
#!/usr/bin/env bash
echo "kicked as $(id -un) HOME=$HOME python3=$(command -v python3) node=$(command -v node)" > /data/.hermes/kick-proof
EOF
echo "secret=1" > "$VOL/.config/gws/creds.json"
# The kick script discovers watchdogs from cron/jobs.json (enabled, no_agent,
# script name matching ensure|watchdog|tunnel|mux|proxy), like a real volume.
mkdir -p "$VOL/.hermes/cron"
cat > "$VOL/.hermes/cron/jobs.json" <<'EOF2'
{"jobs": [
  {"id": "kick0001", "name": "tunnel watchdog", "script": "ensure-nix-webui-tunnel.sh", "no_agent": true, "enabled": true, "schedule": {"kind": "interval", "minutes": 60}},
  {"id": "kick0002", "name": "disabled watchdog", "script": "ensure-should-not-run.sh", "no_agent": true, "enabled": false, "schedule": {"kind": "interval", "minutes": 60}},
  {"id": "kick0003", "name": "agent job", "script": "ensure-agent-job.sh", "no_agent": false, "enabled": true, "schedule": {"kind": "interval", "minutes": 60}}
]}
EOF2
for s in ensure-should-not-run.sh ensure-agent-job.sh; do echo 'touch /data/.hermes/kick-wrong' > "$VOL/.hermes/scripts/$s"; done

docker run -d --name "$NAME" --platform linux/amd64 \
  -e HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin \
  -e HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=smoke-password-123 \
  -e HERMES_DASHBOARD_BASIC_AUTH_SECRET=0123456789abcdef0123456789abcdef \
  -p 19119:9119 "$IMG" >/dev/null
# Seed the volume as root so ownership starts wrong, like a real migrated volume.
docker cp "$VOL/." "$NAME:/data/"
docker exec -u 0 "$NAME" chown -R 0:0 /data
docker restart "$NAME" >/dev/null

pass=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }

for _ in $(seq 1 60); do curl -fs -o /dev/null http://127.0.0.1:19119/login && break; sleep 3; done
check "dashboard /login answers 200"              'curl -fs -o /dev/null http://127.0.0.1:19119/login'
check "/ redirects to /login (auth gate on)"      '[ "$(curl -s -o /dev/null -w %{http_code} http://127.0.0.1:19119/)" = 302 ]'
check "/opt/data is a symlink to /data"           '[ "$(docker exec "$NAME" readlink /opt/data)" = /data ]'
# pgrep -f would also match s6's rc.init/main-wrapper shell, and the exact argv
# shape changes between releases (v2026.9.21 repeats python3); match the
# venv entry point, which the wrapper shells never contain.
GW='pgrep -f "venv/bin/hermes gateway run" | head -1'
# Prove HERMES_HOME by effect: the gateway writes its state file into HERMES_HOME.
# (Reading /proc/<pid>/environ stopped working in v2026.9.21 - the process is
# not dumpable, so even root in docker exec gets EACCES.) /opt/data -> /data, so
# a gateway on the image default HERMES_HOME would write /data/gateway_state.json.
for _ in $(seq 1 20); do docker exec "$NAME" test -s /data/.hermes/gateway_state.json 2>/dev/null && break; sleep 3; done
check "gateway state lands in /data/.hermes"      'docker exec "$NAME" test -s /data/.hermes/gateway_state.json && ! docker exec "$NAME" test -e /data/gateway_state.json'
check "gateway runs as hermes, not root"          "[ \"\$(docker exec \"$NAME\" sh -c 'stat -c %U /proc/\$($GW)')\" = hermes ]"
check "/data chowned to hermes (outside HERMES_HOME too)" '[ "$(docker exec "$NAME" stat -c %U /data/.config/gws/creds.json)" = hermes ]'
# Run from /tmp: the image WORKDIR is /opt/hermes, where hermes_cli imports from
# the cwd even without the venv, which is how a broken symlink once passed this.
check "/usr/local/bin/python3 is the 3.13 venv"   'docker exec -w /tmp "$NAME" /usr/local/bin/python3 -c "import sys, yaml, hermes_cli; assert sys.version_info[:2]==(3,13) and sys.prefix != sys.base_prefix"'
check "webui import check passes (yaml + AIAgent)" 'docker exec -w /tmp "$NAME" sh -c "PYTHONPATH=\$HERMES_WEBUI_AGENT_DIR \$HERMES_WEBUI_PYTHON -c \"import yaml; from run_agent import AIAgent\""'
check "/usr/bin/node exists"                      'docker exec "$NAME" /usr/bin/node --version'
check "HOME-relative state visible via /opt/data" 'docker exec "$NAME" test -f /opt/data/.config/gws/creds.json'
for _ in $(seq 1 25); do docker exec "$NAME" test -f /data/.hermes/kick-proof 2>/dev/null && break; sleep 3; done
check "watchdog kicked at boot, as hermes"        'docker exec "$NAME" grep -q "kicked as hermes HOME=/data" /data/.hermes/kick-proof'
check "watchdog saw venv python3 on PATH"         'docker exec "$NAME" grep -q "python3=/opt/hermes/.venv/bin/python3" /data/.hermes/kick-proof'
check "kick skipped disabled and agent jobs"     '! docker exec "$NAME" test -e /data/.hermes/kick-wrong'
check "IPv4-mapped connect to the v6 listener"    'docker exec "$NAME" /opt/hermes/.venv/bin/python -c "import socket; s=socket.create_connection((\"127.0.0.1\",9119),3); s.close()"'

docker exec "$NAME" cat /data/.hermes/kick-proof 2>/dev/null || true
docker logs "$NAME" 2>&1 | grep -E "legacy-chown|legacy-kick|stage2\] (Setup complete|ERROR)" || true
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
