#!/usr/bin/env bash
# Darwin Gödel Machine — Setup Script (Lean 4)
# This replaces the Python-based setup workflow.
#
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
#
# What this script does:
#   1. Installs elan (Lean 4 version manager) if not present
#   2. Builds the Lean 4 project
#   3. Verifies Docker is configured
#   4. Prepares SWE-bench / Polyglot datasets
#   5. Validates API keys

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }

echo "╔══════════════════════════════════════════════════════╗"
echo "║  Darwin Gödel Machine — Lean 4 Setup                ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── 1. Install elan (Lean 4 version manager) ──────────────────────────────────
info "Checking for elan (Lean 4 version manager)..."
if command -v elan &> /dev/null; then
    ok "elan is installed: $(elan --version)"
elif command -v lean &> /dev/null; then
    ok "lean is available: $(lean --version)"
else
    info "Installing elan..."
    curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
    # Add to PATH for this session
    export PATH="$HOME/.elan/bin:$PATH"
    ok "elan installed successfully"
fi

# Ensure elan is in PATH
export PATH="$HOME/.elan/bin:$PATH"

# ── 2. Verify lean-toolchain ──────────────────────────────────────────────────
info "Checking lean-toolchain..."
if [ -f lean-toolchain ]; then
    TOOLCHAIN=$(head -1 lean-toolchain)
    ok "Toolchain: $TOOLCHAIN"
else
    fail "lean-toolchain file not found!"
    exit 1
fi

# ── 2a. Pre-download toolchain if elan can't resolve it ─────────────────────
TOOLCHAIN_VER="${TOOLCHAIN##*:}"                          # e.g. v4.29.0
TOOLCHAIN_DIR_NAME="leanprover-lean4-${TOOLCHAIN_VER}"  # matches elan directory naming
if command -v elan &> /dev/null; then
    if ! elan toolchain list 2>/dev/null | grep -q "$TOOLCHAIN_DIR_NAME" && \
       [ ! -d "$HOME/.elan/toolchains/$TOOLCHAIN_DIR_NAME" ]; then
        info "Toolchain not installed locally. Downloading directly from GitHub..."
        ARCH=$(uname -m)
        if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
            ASSET="lean-${TOOLCHAIN_VER#v}-linux_aarch64.tar.zst"
        else
            ASSET="lean-${TOOLCHAIN_VER#v}-linux.tar.zst"
        fi
        TMPFILE=$(mktemp /tmp/lean-toolchain-XXXXXX.tar.zst)
        curl --progress-bar -L \
            "https://github.com/leanprover/lean4/releases/download/$TOOLCHAIN_VER/$ASSET" \
            -o "$TMPFILE"
        mkdir -p "$HOME/.elan/toolchains/$TOOLCHAIN_DIR_NAME"
        tar --use-compress-program=unzstd -xf "$TMPFILE" \
            -C "$HOME/.elan/toolchains/$TOOLCHAIN_DIR_NAME" --strip-components=1
        rm "$TMPFILE"
        ok "Toolchain $TOOLCHAIN_VER installed."
    else
        ok "Lean toolchain already installed."
    fi
    # Ensure toolchain bin is in PATH (fallback for environments where elan shims time out)
    export PATH="$HOME/.elan/toolchains/$TOOLCHAIN_DIR_NAME/bin:$PATH"
fi

# ── 3. Build the Lean 4 project ──────────────────────────────────────────────
info "Building DGM (Lean 4)..."
info "This may take a few minutes on first build (compiling Lean modules)..."
if lake build; then
    ok "DGM built successfully"
else
    fail "Build failed! Check the error messages above."
    exit 1
fi

# ── 4. Verify Docker ─────────────────────────────────────────────────────────
info "Checking Docker..."
if command -v docker &> /dev/null; then
    if docker info &> /dev/null; then
        DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        ok "Docker is configured (version: $DOCKER_VERSION)"
    else
        warn "Docker is installed but not accessible."
        warn "Try: sudo usermod -aG docker \$USER && newgrp docker"
    fi
else
    warn "Docker is not installed."
    warn "Docker is required for agent evaluation."
    warn "Install: https://docs.docker.com/get-docker/"
fi

# ── 5. API Keys ──────────────────────────────────────────────────────────────
info "Checking API keys..."
if [ -n "${OPENAI_API_KEY:-}" ]; then
    ok "OPENAI_API_KEY is set"
else
    warn "OPENAI_API_KEY is not set"
    warn "  Add to ~/.bashrc: export OPENAI_API_KEY='...'"
fi

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    ok "ANTHROPIC_API_KEY is set"
else
    warn "ANTHROPIC_API_KEY is not set"
    warn "  Add to ~/.bashrc: export ANTHROPIC_API_KEY='...'"
fi

# ── 6. SWE-bench setup ───────────────────────────────────────────────────────
info "Checking SWE-bench..."
if [ -d "swe_bench/SWE-bench" ]; then
    ok "SWE-bench repository already cloned"
else
    info "Cloning SWE-bench..."
    if [ -d "swe_bench" ]; then
        cd swe_bench
        git clone https://github.com/princeton-nlp/SWE-bench.git
        cd SWE-bench
        git checkout dc4c087c2b9e4cefebf2e3d201d27e36
        cd ../..
        ok "SWE-bench cloned and checked out"
    else
        warn "swe_bench/ directory not found — skipping SWE-bench setup"
    fi
fi

# SWE-bench Python dependencies (still needed for evaluation harness)
if command -v python3 &> /dev/null; then
    info "Checking Python dependencies for evaluation..."
    if [ -f "requirements.txt" ]; then
        if python3 -c "import docker, unidiff, rich" 2>/dev/null; then
            ok "Python evaluation dependencies available"
        else
            info "Installing Python dependencies for evaluation harness..."
            python3 -m pip install -q -r requirements.txt 2>/dev/null || \
                warn "Could not install Python deps. Eval harness may need them."
        fi
    fi
else
    warn "Python 3 not found — evaluation harness requires Python for SWE-bench"
fi

# ── 7. Polyglot setup ────────────────────────────────────────────────────────
info "Checking Polyglot..."
if [ -f "polyglot/polyglot_benchmark_metadata.json" ]; then
    ok "Polyglot dataset already prepared"
else
    if command -v python3 &> /dev/null && [ -f "polyglot/prepare_polyglot_dataset.py" ]; then
        info "Preparing Polyglot dataset..."
        python3 -m polyglot.prepare_polyglot_dataset 2>/dev/null || \
            warn "Could not prepare Polyglot dataset (may need git config)"
    else
        warn "Polyglot dataset not prepared (needs Python 3)"
    fi
fi

# ── 8. Verify the build ──────────────────────────────────────────────────────
info "Running smoke test..."
if lake exec dgm_main -- --help 2>/dev/null; then
    ok "DGM executable works"
else
    warn "DGM executable smoke test failed (may be expected if --help not implemented)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Setup Complete!                                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "To run the DGM:"
echo "  lake exec dgm_main"
echo ""
echo "With options:"
echo "  lake exec dgm_main -- --max_generation 80 --selfimprove_size 2"
echo ""
echo "For help:"
echo "  lake exec dgm_main -- --help"
echo ""
echo "To type-check all proofs:"
echo "  lake build"
echo ""
