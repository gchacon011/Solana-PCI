#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: Run this script from inside the Solana-PCI Git repository."
  exit 1
}

if [[ ! -f "$ROOT/solana-pci/Cargo.toml" || ! -f "$ROOT/solana-pci/rust-toolchain.toml" ]]; then
  echo "ERROR: Expected the Anchor workspace at solana-pci/."
  exit 1
fi

WORKFLOW_DIR="$ROOT/.github/workflows"
WORKFLOW_FILE="$WORKFLOW_DIR/rustfmt.yml"

if [[ -e "$WORKFLOW_FILE" ]]; then
  echo "ERROR: $WORKFLOW_FILE already exists. Refusing to overwrite it."
  exit 1
fi

mkdir -p "$WORKFLOW_DIR"
cat > "$WORKFLOW_FILE" <<'YAML'
name: Rust formatting

on:
  push:
  pull_request:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: rustfmt-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  rustfmt:
    name: Check Rust formatting
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: solana-pci
    steps:
      - name: Check out repository
        uses: actions/checkout@v7
        with:
          persist-credentials: false

      - name: Install Rust 1.89.0 and rustfmt
        uses: dtolnay/rust-toolchain@1.89.0
        with:
          components: rustfmt

      - name: Check formatting
        run: cargo fmt --all -- --check
YAML

printf 'Created workflow: %s\n\n' "$WORKFLOW_FILE"
printf '%s\n' 'Workflow contents:'
cat "$WORKFLOW_FILE"
printf '\n%s\n' 'Next: run git add .github/workflows/rustfmt.yml and commit/push this file.'
