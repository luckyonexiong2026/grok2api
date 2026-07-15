#!/bin/sh
set -eu

umask 077

: "${GROK2API_CONFIG_SOURCE:=/run/grok2api/config.yaml}"

# Prefer an already-mounted config file. Otherwise materialize under /tmp.
if [ -f "${GROK2API_CONFIG_SOURCE}" ]; then
  CONFIG_PATH="${GROK2API_CONFIG_SOURCE}"
else
  CONFIG_PATH=/tmp/grok2api-config.yaml
  if [ -n "${GROK2API_CONFIG_B64:-}" ]; then
    echo "materializing config from GROK2API_CONFIG_B64 -> ${CONFIG_PATH}" >&2
    command -v base64 >/dev/null 2>&1 || { echo "base64 not found" >&2; exit 1; }
    printf '%s' "${GROK2API_CONFIG_B64}" | base64 -d > "${CONFIG_PATH}"
  elif [ -n "${GROK2API_CONFIG_YAML:-}" ]; then
    echo "materializing config from GROK2API_CONFIG_YAML -> ${CONFIG_PATH}" >&2
    printf '%s\n' "${GROK2API_CONFIG_YAML}" > "${CONFIG_PATH}"
  else
    echo "missing config: ${GROK2API_CONFIG_SOURCE}" >&2
    echo "mount config.yaml to /run/grok2api/config.yaml" >&2
    echo "or set GROK2API_CONFIG_B64 / GROK2API_CONFIG_YAML" >&2
    exit 1
  fi
  chmod 0600 "${CONFIG_PATH}" 2>/dev/null || true
fi

# Best-effort install under /app when the rootfs allows it.
if cp "${CONFIG_PATH}" /app/config.yaml 2>/dev/null; then
  chown grok2api:grok2api /app/config.yaml 2>/dev/null || true
  chmod 0600 /app/config.yaml 2>/dev/null || true
  CONFIG_PATH=/app/config.yaml
fi

# Drop privileges when permitted. Orkestr (and similar hosts) often run as
# root without CAP_SETUID/CAP_SETGID, so su-exec fails with setgroups EPERM.
if [ "$(id -u)" -eq 0 ] && command -v su-exec >/dev/null 2>&1; then
  if su-exec grok2api:grok2api /bin/true 2>/dev/null; then
    echo "entrypoint: su-exec grok2api config=${CONFIG_PATH}" >&2
    exec su-exec grok2api:grok2api /app/grok2api --config "${CONFIG_PATH}" --listen 0.0.0.0:8000
  fi
  echo "entrypoint: su-exec not permitted; running as uid=$(id -u) config=${CONFIG_PATH}" >&2
else
  echo "entrypoint: uid=$(id -u) config=${CONFIG_PATH}" >&2
fi

exec /app/grok2api --config "${CONFIG_PATH}" --listen 0.0.0.0:8000
