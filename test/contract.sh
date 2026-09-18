#!/usr/bin/env bash
# Boots the exact image + volume shape Railway will run and asserts the things
# that can silently break: the dashboard is up, it refuses anonymous requests,
# it accepts the configured credentials, and it answers on IPv4-mapped v6
# (Railway's health checker speaks v4, its edge speaks v6).
#
# Note on "basic" auth: HERMES_DASHBOARD_BASIC_AUTH_* names the bundled
# password provider, not HTTP Basic. Anonymous requests get a 302 to /login and
# credentials are posted to /auth/password-login, which sets session cookies.
set -euo pipefail

IMAGE=${IMAGE:-hermes-agent-dashboard:test}
NAME=hermes-contract
VOL=hermes-contract-data
PASS=contract-pass-123

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup
docker volume rm -f "$VOL" >/dev/null 2>&1 || true

docker run -d --name "$NAME" -p 18080:8080 -v "$VOL:/opt/data" \
  -e HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin \
  -e HERMES_DASHBOARD_BASIC_AUTH_PASSWORD="$PASS" \
  -e OPENROUTER_API_KEY=sk-contract-placeholder \
  "$IMAGE" >/dev/null

fail() { echo "FAIL: $1"; docker logs "$NAME" 2>&1 | tail -40; exit 1; }

for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/ || true)
  [ "$code" != "000" ] && break
  sleep 2
done

[ "$code" = "302" ] || fail "anonymous request returned $code, expected a 302 to /login"

curl -s -D- -o /dev/null http://127.0.0.1:18080/ | grep -qi 'location: /login' \
  || fail "anonymous request did not redirect to the login page"

# The Railway healthcheck path must answer 200 WITHOUT credentials. Railway's
# prober counts a 302 as a failed attempt, so / cannot be the healthcheck.
code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/login)
[ "$code" = "200" ] || fail "healthcheck path /login returned $code, expected 200"

code=$(curl -s -o /dev/null -w '%{http_code}' -c /tmp/hermes-cookies.txt \
  -X POST http://127.0.0.1:18080/auth/password-login \
  -H 'content-type: application/json' \
  -d "{\"provider\":\"basic\",\"username\":\"admin\",\"password\":\"$PASS\"}")
[ "$code" = "200" ] || fail "login with the configured password returned $code, expected 200"

code=$(curl -s -o /dev/null -w '%{http_code}' -b /tmp/hermes-cookies.txt http://127.0.0.1:18080/)
[ "$code" = "200" ] || fail "authenticated dashboard request returned $code, expected 200"

code=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:18080/auth/password-login \
  -H 'content-type: application/json' \
  -d '{"provider":"basic","username":"admin","password":"wrong"}')
[ "$code" = "401" ] || fail "wrong password returned $code, expected 401"

# Dual-stack: connect to the v6 listener through a v4-mapped address from
# inside the container. A v6-only socket refuses this and Railway's health
# check would fail while the app logs look healthy.
docker exec "$NAME" /opt/hermes/.venv/bin/python -c '
import socket,sys
s=socket.socket(socket.AF_INET6)
s.settimeout(5)
s.connect(("::ffff:127.0.0.1",8080))
s.close()
' || fail "dashboard socket is IPv6-only (IPV6_V6ONLY not cleared)"

# The gateway is the container main process: it must still be running.
docker exec "$NAME" pgrep -f "hermes gateway" >/dev/null || fail "gateway process is not running"

# Stale lock files from a previous container must not survive into the next boot.
docker exec "$NAME" sh -c 'touch /opt/data/gateway.pid /opt/data/gateway.lock'
docker restart "$NAME" >/dev/null
sleep 25
docker exec "$NAME" sh -c '[ ! -e /opt/data/gateway.pid ] || pgrep -f "hermes gateway" >/dev/null' \
  || fail "stale gateway.pid survived restart and no gateway is running"

echo "PASS: all contract checks green"
