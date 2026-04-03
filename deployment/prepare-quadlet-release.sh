#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${ROOT_DIR}/deployment/artifacts"
ARTIFACT_PATH="${ARTIFACT_DIR}/nkl-stack-playground"

cd "${ROOT_DIR}"

echo "==> building static musl release"
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseFast

echo "==> staging deployment artifact"
install -Dm0755 "${ROOT_DIR}/zig-out/bin/nkl-stack-playground" "${ARTIFACT_PATH}"

echo "==> verifying artifact"
file "${ARTIFACT_PATH}"
ldd "${ARTIFACT_PATH}" || true

cat <<EOF

Prepared:
  ${ARTIFACT_PATH}

Next VPS-side steps:

  sudo podman quadlet install /path/to/nkl-stack-playground/deployment/quadlet
  sudo install -Dm0755 /path/to/nkl-stack-playground/deployment/artifacts/nkl-stack-playground /etc/containers/systemd/artifacts/nkl-stack-playground
  sudo systemctl daemon-reload
  sudo systemctl enable --now nkl-stack-playground.service

EOF
