#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
WORKSPACE="$ROOT/solana-pci"
ANCHOR_TOML="$WORKSPACE/Anchor.toml"
WORKFLOW_DIR="$ROOT/.github/workflows"
WORKFLOW="$WORKFLOW_DIR/anchor-ci.yml"

if [[ ! -f "$ANCHOR_TOML" || ! -f "$WORKSPACE/Cargo.toml" ]]; then
  echo "ERROR: Anchor workspace not found. Expected: $WORKSPACE"
  exit 1
fi

if [[ -e "$WORKFLOW" ]]; then
  echo "ERROR: $WORKFLOW already exists. Refusing to overwrite it."
  exit 1
fi

python3 - "$ANCHOR_TOML" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
match = re.search(r"(?ms)^\[toolchain\]\s*$\n?(.*?)(?=^\[|\Z)", text)
if match is None:
    if text and not text.endswith("\n"):
        text += "\n"
    text += '\n[toolchain]\nanchor_version = "1.2.2"\nsolana_version = "=4.1.2"\n'
else:
    body = match.group(1)
    lines = body.splitlines()
    updated = []
    seen = set()
    for line in lines:
        key_match = re.match(r"^\s*(anchor_version|solana_version)\s*=", line)
        if key_match:
            key = key_match.group(1)
            if key not in seen:
                value = '"1.2.2"' if key == "anchor_version" else '"=4.1.2"'
                updated.append(f"{key} = {value}")
                seen.add(key)
            continue
        updated.append(line)
    missing = []
    if "anchor_version" not in seen:
        missing.append('anchor_version = "1.2.2"')
    if "solana_version" not in seen:
        missing.append('solana_version = "=4.1.2"')
    while updated and updated[-1] == "":
        updated.pop()
    if missing:
        updated.extend(missing)
    replacement = "[toolchain]\n" + "\n".join(updated) + "\n\n"
    text = text[:match.start()] + replacement + text[match.end():]

path.write_text(text)
PY

mkdir -p "$WORKFLOW_DIR"
cat > "$WORKFLOW" <<'YAML'
name: Anchor build and tests

on:
  push:
  pull_request:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: anchor-ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-test:
    name: Build Anchor program and run LiteSVM tests
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: solana-pci
    steps:
      - name: Check out repository
        uses: actions/checkout@v7
        with:
          persist-credentials: false

      - name: Install Rust 1.89.0
        uses: dtolnay/rust-toolchain@1.89.0

      - name: Install Anchor Version Manager
        run: cargo install --git https://github.com/otter-sec/anchor avm --force

      - name: Install and select Anchor 1.2.2
        run: |
          avm install 1.2.2
          avm use 1.2.2
          avm solana install
          avm platform-tools install
          echo "$HOME/.avm/bin" >> "$GITHUB_PATH"
          echo "$HOME/.cargo/bin" >> "$GITHUB_PATH"
          echo "$HOME/.local/share/solana/install/active_release/bin" >> "$GITHUB_PATH"

      - name: Verify toolchain versions
        run: |
          rustc --version
          cargo --version
          anchor --version
          solana --version
          cargo build-sbf --version

      - name: Build Solana program and generate IDL
        run: anchor build

      - name: Run Rust and LiteSVM integration tests
        run: cargo test --workspace --locked
YAML

