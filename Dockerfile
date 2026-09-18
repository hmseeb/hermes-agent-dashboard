# Hermes Agent for Railway: the official image plus the three things Railway
# needs. No source build, no custom web server.
#
# Pin a release tag rather than `latest` so a redeploy cannot silently jump
# versions. Override with the HERMES_IMAGE_VERSION build arg / Railway variable.
ARG HERMES_IMAGE_VERSION=v2026.9.14
FROM nousresearch/hermes-agent:${HERMES_IMAGE_VERSION}

# The image already supervises the dashboard as an s6 service
# (docker/s6-rc.d/dashboard/run): it starts only when HERMES_DASHBOARD is
# truthy, and its auth gate refuses a non-loopback bind unless a
# DashboardAuthProvider is configured. HERMES_DASHBOARD_BASIC_AUTH_USERNAME +
# _PASSWORD (set as Railway variables) satisfy that gate, so the dashboard is
# password-protected the moment it is public. Never set HERMES_DASHBOARD_INSECURE:
# since the June 2026 hardening it no longer disables the gate anyway.
ENV HERMES_DASHBOARD=true \
    HERMES_DASHBOARD_HOST=:: \
    HERMES_DASHBOARD_PORT=8080

# Railway's edge reaches containers over IPv6 while its health checker speaks
# IPv4, so the listener has to answer on both. uvicorn binds an AF_INET6 socket
# for a `::` host and asyncio sets IPV6_V6ONLY=1 per socket, which leaves the
# dashboard v6-only and fails every healthcheck. sitecustomize is imported by
# every python process in this venv before uvicorn builds its socket, so
# coercing the option off there covers the dashboard without patching hermes.
#
# It has to be APPENDED to whichever sitecustomize is already importable, not
# dropped into the venv's site-packages: Debian ships /usr/lib/python3.13/
# sitecustomize.py, the stdlib dir precedes site-packages on sys.path, and only
# the first module named sitecustomize is ever imported. Verified live - the
# venv copy was silently shadowed and the listener stayed v6-only.
RUN set -eu; sc="$(/opt/hermes/.venv/bin/python -c 'import sitecustomize;print(sitecustomize.__file__)' 2>/dev/null || /opt/hermes/.venv/bin/python -c 'import site;print(site.getsitepackages()[0]+"/sitecustomize.py")')"; printf '%s\n' \
    'import socket' \
    '_orig = socket.socket.setsockopt' \
    'def setsockopt(self, level, optname, value, *a):' \
    '    if level == socket.IPPROTO_IPV6 and optname == socket.IPV6_V6ONLY:' \
    '        value = 0' \
    '    return _orig(self, level, optname, value, *a)' \
    'socket.socket.setsockopt = setsockopt' \
    >> "$sc"; /opt/hermes/.venv/bin/python -c 'import socket,sys; sys.exit(0 if socket.socket.setsockopt.__class__.__name__ == "function" else 1)'

# The container's CMD runs as /init's main program, so the container lives and
# dies with the gateway (Railway then restarts it), while s6 supervises the
# dashboard beside it. `sh -c` is routed by main-wrapper.sh's "first arg is an
# executable" branch, which still drops privileges to the hermes user.
#
# The rm is the one fix the official image lacks: hermes writes gateway.pid /
# .lock / .sock and does not remove them on SIGTERM. On Railway those live on a
# persistent volume, so the next container boots into "PID file race lost to
# another gateway instance" or gateway/run.py's "Refusing --replace" (v2026.8.27
# cannot prove a foreign pid owns this HERMES_HOME). Nothing can be running here
# - this is a fresh container - so removing them unconditionally is safe.
CMD ["sh", "-c", "rm -f \"$HERMES_HOME\"/gateway.pid \"$HERMES_HOME\"/gateway.lock \"$HERMES_HOME\"/gateway.sock; exec hermes gateway"]
