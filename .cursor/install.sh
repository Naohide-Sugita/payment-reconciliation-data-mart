#!/usr/bin/env bash
# Cloud Agent install: prepare an offline dbt + BigQuery development loop for the
# payment_reconciliation project. Idempotent; safe to re-run.
#
# It installs the pinned Python/dbt dependencies into a venv, downloads the
# goccy/bigquery-emulator binary, and installs the local dbt profile + emulator
# support files. The emulator and its proxy are started per boot via the
# `terminals` entries in .cursor/environment.json, after which `dbt debug`,
# `dbt seed`, `dbt run`, and `dbt test` all work with no Google Cloud creds.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${HOME}/.venvs/payment-recon"
BIN_DIR="${HOME}/.local/bin"
SUPPORT_DIR="${HOME}/.cursor-bq"
EMULATOR_VERSION="v0.8.1"
EMULATOR_BIN="${BIN_DIR}/bigquery-emulator"

mkdir -p "${BIN_DIR}" "${SUPPORT_DIR}" "${HOME}/.dbt"

# 1. Python venv with the project's pinned dbt-bigquery dependencies.
if [ ! -x "${VENV_DIR}/bin/python" ]; then
  if ! python3 -m venv "${VENV_DIR}" 2>/dev/null; then
    sudo apt-get update -y
    pyver="$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')"
    sudo apt-get install -y "python${pyver}-venv" || sudo apt-get install -y python3-venv
    python3 -m venv "${VENV_DIR}"
  fi
fi
"${VENV_DIR}/bin/python" -m pip install --quiet --upgrade pip
"${VENV_DIR}/bin/pip" install --quiet -r "${REPO_ROOT}/requirements.txt"

# Expose `dbt` on PATH (~/.local/bin is already on PATH in the base image).
ln -sf "${VENV_DIR}/bin/dbt" "${BIN_DIR}/dbt"

# 2. BigQuery emulator binary (pinned; re-download only if missing/mismatched).
if ! "${EMULATOR_BIN}" --version 2>/dev/null | grep -q "${EMULATOR_VERSION}"; then
  arch="$(uname -m)"
  case "${arch}" in
    x86_64) emu_arch="amd64" ;;
    aarch64 | arm64) emu_arch="arm64" ;;
    *) emu_arch="amd64" ;;
  esac
  url="https://github.com/goccy/bigquery-emulator/releases/download/${EMULATOR_VERSION}/bigquery-emulator_${EMULATOR_VERSION}_linux_${emu_arch}.tar.gz"
  tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/bq.tgz" "${url}"
  tar -xzf "${tmp}/bq.tgz" -C "${tmp}"
  install -m 0755 "${tmp}/bigquery-emulator" "${EMULATOR_BIN}"
  rm -rf "${tmp}"
fi

# 3. Emulator support files copied to stable $HOME paths so the per-boot
#    terminals do not depend on the working directory.
cp "${REPO_ROOT}/.cursor/bq-emulator/bq_proxy.py" "${SUPPORT_DIR}/bq_proxy.py"
cp "${REPO_ROOT}/.cursor/bq-emulator/datasets.yaml" "${SUPPORT_DIR}/datasets.yaml"

# 4. Local dbt profile. Generated here (not committed) because dbt's standard
#    .gitignore excludes profiles.yml. The `dev` target runs the whole pipeline
#    against the local emulator proxy, so no Google Cloud credentials are needed;
#    CI writes its own profile that targets real BigQuery.
cat > "${HOME}/.dbt/profiles.yml" <<'EOF'
payment_reconciliation:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth-secrets
      token: emulator-local-token
      project: payment-recon-mart
      dataset: raw
      location: asia-northeast1
      threads: 4
      api_endpoint: http://localhost:9055
      job_execution_timeout_seconds: 300
      job_retries: 0
EOF

echo "install.sh: dbt $("${VENV_DIR}/bin/dbt" --version 2>/dev/null | head -1 || true) and emulator ${EMULATOR_VERSION} ready"
