#!/usr/bin/env bash
# Cloud Agent start: bring up the local BigQuery emulator and its proxy so dbt
# works immediately on every boot. Idempotent and readiness-checked: if the
# proxy is already serving, it returns right away; otherwise it (re)starts the
# emulator and proxy, waits until the proxy is reachable, and returns.
set -euo pipefail

SUPPORT_DIR="${HOME}/.cursor-bq"
EMULATOR_BIN="${HOME}/.local/bin/bigquery-emulator"
PROXY_HEALTH="http://localhost:9055/bigquery/v2/projects/payment-recon-mart/datasets"
EMULATOR_HEALTH="http://localhost:9050/bigquery/v2/projects/payment-recon-mart/datasets"

if curl -sf -o /dev/null "${PROXY_HEALTH}"; then
  echo "start.sh: emulator proxy already running"
  exit 0
fi

# Emulator (REST :9050, gRPC storage :9060).
if ! curl -sf -o /dev/null "${EMULATOR_HEALTH}"; then
  setsid "${EMULATOR_BIN}" \
    --project=payment-recon-mart \
    --data-from-yaml="${SUPPORT_DIR}/datasets.yaml" \
    --port=9050 --grpc-port=9060 --log-level=info \
    >"${SUPPORT_DIR}/emulator.log" 2>&1 &
  for _ in $(seq 1 30); do
    curl -sf -o /dev/null "${EMULATOR_HEALTH}" && break
    sleep 1
  done
fi

# Proxy (:9055) that dbt talks to.
setsid python3 "${SUPPORT_DIR}/bq_proxy.py" >"${SUPPORT_DIR}/proxy.log" 2>&1 &
for _ in $(seq 1 30); do
  curl -sf -o /dev/null "${PROXY_HEALTH}" && break
  sleep 1
done

if curl -sf -o /dev/null "${PROXY_HEALTH}"; then
  echo "start.sh: emulator + proxy ready"
else
  echo "start.sh: emulator proxy did not become ready" >&2
  exit 1
fi
