#!/usr/bin/env bash
set -euo pipefail

ARANGO_CONTAINER_NAME="${ARANGO_CONTAINER_NAME:-gaiaos-arangodb}"
ARANGO_DB="${ARANGO_DB:-gaiaos}"
ARANGO_USER="${ARANGO_USER:-root}"
ARANGO_PASSWORD="${ARANGO_PASSWORD:-gaiaos}"

BACKUP_DIR="${BACKUP_DIR:-/mnt/backups}"
INTERVAL_SECS="${INTERVAL_SECS:-86400}"
RETENTION_COUNT="${RETENTION_COUNT:-7}"

mkdir -p "${BACKUP_DIR}"

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
}

do_backup() {
  local ts
  ts="$(date -u +"%Y%m%d_%H%M%S")"
  local tmp_in_container="/tmp/backup_${ts}"
  local out_prefix="${BACKUP_DIR}/arango_${ts}"
  local out_tar="${out_prefix}.tar.gz"

  log "backup: starting (container=${ARANGO_CONTAINER_NAME} db=${ARANGO_DB})"

  docker exec "${ARANGO_CONTAINER_NAME}" rm -rf "${tmp_in_container}" >/dev/null 2>&1 || true
  docker exec "${ARANGO_CONTAINER_NAME}" mkdir -p "${tmp_in_container}"

  docker exec "${ARANGO_CONTAINER_NAME}" arangodump \
    --server.endpoint "http+tcp://127.0.0.1:8529" \
    --server.username "${ARANGO_USER}" \
    --server.password "${ARANGO_PASSWORD}" \
    --server.database "${ARANGO_DB}" \
    --output-directory "${tmp_in_container}" \
    --overwrite true

  mkdir -p "${out_prefix}"
  docker cp "${ARANGO_CONTAINER_NAME}:${tmp_in_container}/." "${out_prefix}/"

  tar -czf "${out_tar}" -C "${BACKUP_DIR}" "arango_${ts}"
  rm -rf "${out_prefix}"

  docker exec "${ARANGO_CONTAINER_NAME}" rm -rf "${tmp_in_container}" >/dev/null 2>&1 || true

  log "backup: complete ${out_tar}"

  # retention: keep newest N backups
  local backups
  backups="$(ls -1t "${BACKUP_DIR}"/arango_*.tar.gz 2>/dev/null || true)"
  if [[ -n "${backups}" ]]; then
    local to_delete
    to_delete="$(echo "${backups}" | tail -n +"$((RETENTION_COUNT + 1))" || true)"
    if [[ -n "${to_delete}" ]]; then
      log "backup: retention delete older backups"
      echo "${to_delete}" | xargs -r rm -f
    fi
  fi
}

while true; do
  do_backup || log "backup: failed (will retry next interval)"
  sleep "${INTERVAL_SECS}"
done


