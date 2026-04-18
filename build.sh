#!/usr/bin/env bash
# Darwin Gödel Machine — Build Script
# Builds the Lean 4 project, installs elan/toolchain if needed.
#
# Usage:
#   chmod +x build.sh
#   ./build.sh

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Ensure elan is in PATH
export PATH="$HOME/.elan/bin:$PATH"

# Install elan if not present
if ! command -v elan &> /dev/null && ! command -v lean &> /dev/null; then
  echo "Installing elan (Lean 4 version manager)..."
  curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
  export PATH="$HOME/.elan/bin:$PATH"
fi

# Build
echo "Building DGM (Lean 4)..."
if lake build; then
  echo -e "${GREEN}Build succeeded.${NC}"
else
  echo -e "${RED}Build failed.${NC}"
  exit 1
fi
