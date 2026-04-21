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
CYAN='\033[0;36m'
NC='\033[0m'

REQUIRED_TOOLCHAIN="leanprover/lean4:v4.29.0"
TOOLCHAIN_DIR_NAME="leanprover-lean4-v4.29.0"

# Ensure elan is in PATH
export PATH="$HOME/.elan/bin:$PATH"

# Install elan if not present
if ! command -v elan &> /dev/null && ! command -v lean &> /dev/null; then
  echo -e "${CYAN}Installing elan (Lean 4 version manager)...${NC}"
  curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
  export PATH="$HOME/.elan/bin:$PATH"
fi

# If elan is present but toolchain not installed, download it directly from GitHub
if command -v elan &> /dev/null; then
  if ! elan toolchain list 2>/dev/null | grep -q "$TOOLCHAIN_DIR_NAME" && \
     [ ! -d "$HOME/.elan/toolchains/$TOOLCHAIN_DIR_NAME" ]; then
    echo -e "${CYAN}Lean toolchain $REQUIRED_TOOLCHAIN not found. Downloading...${NC}"
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
      ASSET="lean-4.29.0-linux_aarch64.tar.zst"
    else
      ASSET="lean-4.29.0-linux.tar.zst"
    fi
    URL="https://github.com/leanprover/lean4/releases/download/v4.29.0/$ASSET"
    TMPFILE=$(mktemp /tmp/lean-toolchain-XXXXXX.tar.zst)
    echo -e "${CYAN}  Downloading $URL ...${NC}"
    curl --progress-bar -L "$URL" -o "$TMPFILE"
    mkdir -p "$HOME/.elan/toolchains/$TOOLCHAIN_DIR_NAME"
    tar --use-compress-program=unzstd -xf "$TMPFILE" \
      -C "$HOME/.elan/toolchains/$TOOLCHAIN_DIR_NAME" --strip-components=1
    rm "$TMPFILE"
    echo -e "${GREEN}  Toolchain installed.${NC}"
  fi
  # Add installed toolchain bin to PATH as a fallback
  export PATH="$HOME/.elan/toolchains/$TOOLCHAIN_DIR_NAME/bin:$PATH"
fi

# Build
echo -e "${CYAN}Building DGM (Lean 4)...${NC}"
if lake build; then
  echo -e "${GREEN}Build succeeded.${NC}"
else
  echo -e "${RED}Build failed.${NC}"
  exit 1
fi
