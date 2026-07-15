#!/bin/sh
set -eu

umask 077

: "${GROK2API_CONFIG_SOURCE:=/run/grok2api/config.yaml}"

is_root() {
  [ "$(id -u)" -eq 0 ]
}

# Prefer an already-mounted config file. Otherwise always write under /tmp —
# PaaS hosts often make /run and /app/data non-writable despite looking present.
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

if is_root; then
  # Best effort install under /app (may fail on read-only rootfs).
  if cp "${CONFIG_PATH}" /app/config.yaml 2>/dev/null; then
    chown grok2api:grok2api /app/config.yaml 2>/dev/null || true
    chmod 0600 /app/config.yaml 2>/dev/null || true
    CONFIG_PATH=/app/config.yaml
  fi
  echo "entrypoint: root -> su-exec grok2api, config=${CONFIG_PATH}" >&2
  exec su-exec grok2api:grok2api /app/grok2api --config "${CONFIG_PATH}" --listen 0.0.0.0:8000
fi

echo "entrypoint: uid=$(id -u) config=${CONFIG_PATH}" >&2
exec /app/grok2api --config "${CONFIG_PATH}" --listen 0.0.0.0:8000
