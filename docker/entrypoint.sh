#!/bin/sh
set -eu

umask 077

# Default path used by the official Docker image.
: "${GROK2API_CONFIG_SOURCE:=/run/grok2api/config.yaml}"

# Platforms that only inject env vars (e.g. Orkestr) cannot bind-mount a file.
# Support:
#   GROK2API_CONFIG_B64   - base64-encoded full config.yaml
#   GROK2API_CONFIG_YAML  - raw YAML string (prefer B64 if the platform mangles newlines)
# If the source file is missing, materialize it from env before continuing.
if [ ! -f "${GROK2API_CONFIG_SOURCE}" ]; then
  config_dir=$(dirname "${GROK2API_CONFIG_SOURCE}")
  mkdir -p "${config_dir}"

  if [ -n "${GROK2API_CONFIG_B64:-}" ]; then
    echo "materializing config from GROK2API_CONFIG_B64 -> ${GROK2API_CONFIG_SOURCE}" >&2
    if command -v base64 >/dev/null 2>&1; then
      # BusyBox and GNU coreutils both accept -d for decode.
      printf '%s' "${GROK2API_CONFIG_B64}" | base64 -d > "${GROK2API_CONFIG_SOURCE}"
    else
      echo "base64 command not found; cannot decode GROK2API_CONFIG_B64" >&2
      exit 1
    fi
  elif [ -n "${GROK2API_CONFIG_YAML:-}" ]; then
    echo "materializing config from GROK2API_CONFIG_YAML -> ${GROK2API_CONFIG_SOURCE}" >&2
    # printf preserves content; avoid echo -e portability traps
    printf '%s\n' "${GROK2API_CONFIG_YAML}" > "${GROK2API_CONFIG_SOURCE}"
  else
    echo "missing config: ${GROK2API_CONFIG_SOURCE}" >&2
    echo "mount config.yaml to /run/grok2api/config.yaml" >&2
    echo "or set GROK2API_CONFIG_B64 / GROK2API_CONFIG_YAML for platforms without volume mounts" >&2
    exit 1
  fi
fi

cp "${GROK2API_CONFIG_SOURCE}" /app/config.yaml
chown grok2api:grok2api /app/config.yaml
chmod 0600 /app/config.yaml

exec su-exec grok2api:grok2api "$@"
