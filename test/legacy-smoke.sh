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
# pgrep -f would also match s6's rc.init/main-wrapper shell; target the python process.
GW='pgrep -f "^/opt/hermes/.venv/bin/python3 /opt/hermes/.venv/bin/hermes gateway" | head -1'
check "HERMES_HOME=/data/.hermes in gateway env"  "docker exec \"$NAME\" sh -c 'tr \"\\0\" \"\\n\" < /proc/\$($GW)/environ | grep -qx HERMES_HOME=/data/.hermes'"
check "gateway runs as hermes, not root"          "[ \"\$(docker exec \"$NAME\" sh -c 'stat -c %U /proc/\$($GW)')\" = hermes ]"
check "/data chowned to hermes (outside HERMES_HOME too)" '[ "$(docker exec "$NAME" stat -c %U /data/.config/gws/creds.json)" = hermes ]'
check "/usr/local/bin/python3 is the 3.13 venv"   'docker exec "$NAME" /usr/local/bin/python3 -c "import sys,hermes_cli; assert sys.version_info[:2]==(3,13)"'
check "/usr/bin/node exists"                      'docker exec "$NAME" /usr/bin/node --version'
check "HOME-relative state visible via /opt/data" 'docker exec "$NAME" test -f /opt/data/.config/gws/creds.json'
for _ in $(seq 1 25); do docker exec "$NAME" test -f /data/.hermes/kick-proof 2>/dev/null && break; sleep 3; done
check "watchdog kicked at boot, as hermes"        'docker exec "$NAME" grep -q "kicked as hermes HOME=/data" /data/.hermes/kick-proof'
check "watchdog saw venv python3 on PATH"         'docker exec "$NAME" grep -q "python3=/opt/hermes/.venv/bin/python3" /data/.hermes/kick-proof'
check "IPv4-mapped connect to the v6 listener"    'docker exec "$NAME" /opt/hermes/.venv/bin/python -c "import socket; s=socket.create_connection((\"127.0.0.1\",9119),3); s.close()"'

docker exec "$NAME" cat /data/.hermes/kick-proof 2>/dev/null || true
docker logs "$NAME" 2>&1 | grep -E "legacy-chown|legacy-kick|stage2\] (Setup complete|ERROR)" || true
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
