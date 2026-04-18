# Darwin Gödel Machine — Lean 4 Docker Image
# Multi-stage build: Lean 4 compilation + runtime with Python eval harness
#
# Build:   docker build -t dgm .
# Run:     docker run -e OPENAI_API_KEY -e ANTHROPIC_API_KEY dgm

# ── Stage 1: Build the Lean 4 project ────────────────────────────────────────
FROM ubuntu:22.04 AS builder

RUN apt-get update && apt-get install -y \
    curl git build-essential cmake \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install elan (Lean 4 version manager)
RUN curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
ENV PATH="/root/.elan/bin:${PATH}"

WORKDIR /dgm

# Copy lean-toolchain first to cache toolchain download
COPY lean-toolchain .
RUN elan default $(cat lean-toolchain | head -1 | sed 's|leanprover/lean4:||')

# Copy build files and source
COPY lakefile.lean .
COPY DGM.lean .
COPY Main.lean .
COPY DGM/ DGM/

# Build the project
RUN lake build

# ── Stage 2: Runtime image ────────────────────────────────────────────────────
FROM python:3.10-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential git curl docker.io \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install elan for Lean 4 runtime
RUN curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
ENV PATH="/root/.elan/bin:${PATH}"

WORKDIR /dgm

# Copy the entire repository
COPY . .

# Copy built artifacts from builder
COPY --from=builder /dgm/.lake .lake/
COPY --from=builder /root/.elan /root/.elan

# Install Python dependencies (still needed for SWE-bench evaluation)
RUN pip install --no-cache-dir -r requirements.txt

# Set up the lean toolchain
RUN elan default $(cat lean-toolchain | head -1 | sed 's|leanprover/lean4:||')

# Keep the container running by default
CMD ["tail", "-f", "/dev/null"]