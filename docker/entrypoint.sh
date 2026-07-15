#!/bin/sh
set -eu

umask 077

: "${GROK2API_CONFIG_SOURCE:=/run/grok2api/config.yaml}"

is_root() {
  [ "$(id -u)" -eq 0 ]
}

pick_writable_config_path() {
  # Prefer mounted/default path, then durable data dir, then tmp.
  # /run is often an empty tmpfs on PaaS, so mkdir there may fail for non-root.
  for candidate in \
    "${GROK2API_CONFIG_SOURCE}" \
    /run/grok2api/config.yaml \
    /app/data/config.yaml \
    /tmp/grok2api-config.yaml
  do
    dir=$(dirname "$candidate")
    if mkdir -p "$dir" 2>/dev/null && [ -w "$dir" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  printf '%s' /tmp/grok2api-config.yaml
}

materialize_config() {
  dest=$1
  dir=$(dirname "$dest")
  mkdir -p "$dir" 2>/dev/null || true

  # Prefer an already-mounted source file when it exists.
  if [ -f "${GROK2API_CONFIG_SOURCE}" ] && [ "${GROK2API_CONFIG_SOURCE}" != "$dest" ]; then
    cp "${GROK2API_CONFIG_SOURCE}" "$dest"
    return 0
  fi
  if [ -f "$dest" ] && [ -z "${GROK2API_CONFIG_B64:-}" ] && [ -z "${GROK2API_CONFIG_YAML:-}" ]; then
    return 0
  fi

  if [ -n "${GROK2API_CONFIG_B64:-}" ]; then
    echo "materializing config from GROK2API_CONFIG_B64 -> ${dest}" >&2
    if ! command -v base64 >/dev/null 2>&1; then
      echo "base64 command not found; cannot decode GROK2API_CONFIG_B64" >&2
      exit 1
    fi
    printf '%s' "${GROK2API_CONFIG_B64}" | base64 -d > "$dest"
    return 0
  fi

  if [ -n "${GROK2API_CONFIG_YAML:-}" ]; then
    echo "materializing config from GROK2API_CONFIG_YAML -> ${dest}" >&2
    printf '%s\n' "${GROK2API_CONFIG_YAML}" > "$dest"
    return 0
  fi

  if [ -f "$dest" ]; then
    return 0
  fi

  echo "missing config: ${GROK2API_CONFIG_SOURCE}" >&2
  echo "mount config.yaml to /run/grok2api/config.yaml" >&2
  echo "or set GROK2API_CONFIG_B64 / GROK2API_CONFIG_YAML for platforms without volume mounts" >&2
  exit 1
}

CONFIG_PATH=$(pick_writable_config_path)
materialize_config "$CONFIG_PATH"
chmod 0600 "$CONFIG_PATH" 2>/dev/null || true

if is_root; then
  if [ "$CONFIG_PATH" != /app/config.yaml ]; then
    cp "$CONFIG_PATH" /app/config.yaml
    CONFIG_PATH=/app/config.yaml
  fi
  chown grok2api:grok2api "$CONFIG_PATH" 2>/dev/null || true
  chmod 0600 "$CONFIG_PATH" 2>/dev/null || true
  echo "running as root (drop to grok2api) with config=${CONFIG_PATH}" >&2
  exec su-exec grok2api:grok2api /app/grok2api --config "$CONFIG_PATH" --listen 0.0.0.0:8000
fi

echo "running as uid=$(id -u) with config=${CONFIG_PATH}" >&2
exec /app/grok2api --config "$CONFIG_PATH" --listen 0.0.0.0:8000
