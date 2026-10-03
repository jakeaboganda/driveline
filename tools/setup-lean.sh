#!/bin/sh
# Installs elan, the Lean toolchain manager, then builds formal/.
# elan reads formal/lean-toolchain and downloads that exact Lean version.
set -eu

if ! command -v elan >/dev/null 2>&1 && [ ! -x "$HOME/.elan/bin/elan" ]; then
    curl -sSfL https://elan.lean-lang.org/elan-init.sh \
        | sh -s -- -y --no-modify-path --default-toolchain none
fi
PATH="$HOME/.elan/bin:$PATH"
export PATH

cd "$(dirname "$0")/../formal"
lake build

echo "Lean ready. Add \$HOME/.elan/bin to PATH to use lean and lake directly."
