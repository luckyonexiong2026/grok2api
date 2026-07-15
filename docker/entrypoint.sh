#!/bin/sh
set -eu

umask 077

: "${GROK2API_CONFIG_SOURCE:=/run/grok2api/config.yaml}"

is_root() {
  [ "$(id -u)" -eq 0 ]
}

# Always prefer an already-mounted file. Otherwise materialize into a path that
# is writable even on read-only-root / empty-/run PaaS runtimes (e.g. Orkestr).
resolve_config_path() {
  if [ -f "${GROK2API_CONFIG_SOURCE}" ]; then
    printf '%s' "${GROK2API_CONFIG_SOURCE}"
    return 0
  fi
  # Prefer app data volume when present and writable.
  if mkdir -p /app/data 2>/dev/null && [ -w /app/data ]; then
    printf '%s' /app/data/config.yaml
    return 0
  fi
  printf '%s' /tmp/grok2api-config.yaml
}

write_config() {
  dest=$1
  dir=$(dirname "$dest")
  mkdir -p "$dir"

  if [ -f "${GROK2API_CONFIG_SOURCE}" ] && [ "${GROK2API_CONFIG_SOURCE}" != "$dest" ]; then
    cp "${GROK2API_CONFIG_SOURCE}" "$dest"
  elif [ -n "${GROK2API_CONFIG_B64:-}" ]; then
    echo "materializing config from GROK2API_CONFIG_B64 -> ${dest}" >&2
    command -v base64 >/dev/null 2>&1 || {
      echo "base64 command not found" >&2
      exit 1
    }
    printf '%s' "${GROK2API_CONFIG_B64}" | base64 -d > "$dest"
  elif [ -n "${GROK2API_CONFIG_YAML:-}" ]; then
    echo "materializing config from GROK2API_CONFIG_YAML -> ${dest}" >&2
    printf '%s\n' "${GROK2API_CONFIG_YAML}" > "$dest"
  elif [ -f "$dest" ]; then
    :
  else
    echo "missing config: ${GROK2API_CONFIG_SOURCE}" >&2
    echo "mount config.yaml to /run/grok2api/config.yaml" >&2
    echo "or set GROK2API_CONFIG_B64 / GROK2API_CONFIG_YAML" >&2
    exit 1
  fi
  chmod 0600 "$dest" 2>/dev/null || true
}

CONFIG_PATH=$(resolve_config_path)
write_config "$CONFIG_PATH"

if is_root; then
  if [ "$CONFIG_PATH" != /app/config.yaml ]; then
    cp "$CONFIG_PATH" /app/config.yaml
    CONFIG_PATH=/app/config.yaml
  fi
  chown grok2api:grok2api "$CONFIG_PATH" 2>/dev/null || true
  chmod 0600 "$CONFIG_PATH" 2>/dev/null || true
  echo "entrypoint: root -> su-exec grok2api, config=${CONFIG_PATH}" >&2
  exec su-exec grok2api:grok2api /app/grok2api --config "$CONFIG_PATH" --listen 0.0.0.0:8000
fi

echo "entrypoint: uid=$(id -u) config=${CONFIG_PATH}" >&2
exec /app/grok2api --config "$CONFIG_PATH" --listen 0.0.0.0:8000
