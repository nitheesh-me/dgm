<h1 align="center">
    Darwin Gödel Machine:<br/>Open-Ended Evolution of Self-Improving Agents
</h1>

<p align="center">
  <a href="https://github.com/jennyzzt/dgm/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg?style=for-the-badge"></a>
  <a href="https://arxiv.org/abs/2505.22954"><img src="https://img.shields.io/badge/arXiv-2505.22954-b31b1b.svg?logo=arxiv&style=for-the-badge"></a>
  <a href="https://sakana.ai/dgm/"><img src="https://img.shields.io/badge/-Blog-%238D6748?style=for-the-badge&logo=Website&logoColor=white"></a>
  <a href="https://x.com/SakanaAILabs/status/1928272612431646943"><img src="https://img.shields.io/badge/twitter-%230077B5.svg?&style=for-the-badge&logo=twitter&logoColor=white&color=00acee"></a>
  <a href="https://drive.google.com/drive/folders/1Kcu9TbIa9Z50pJ7S6hH9omzzD1pxIYZC?usp=sharing"><img src="https://img.shields.io/badge/Experiment%20Logs-4285F4?style=for-the-badge&logo=googledrive&logoColor=white"></a>
</p>


Repository for **Darwin Gödel Machine (DGM)**, a novel self-improving system that iteratively modifies its own code (thereby also improving its ability to modify its own codebase) and empirically validates each change using coding benchmarks.

<p align="center">
  <img src="./misc/overview.gif" width="100%" height="auto" />
</p>

## Setup

### Quick Start (Lean 4)

```bash
# 1. API keys — add to ~/.bashrc (optional; mock mode is used when keys are absent)
export OPENAI_API_KEY='...'
export ANTHROPIC_API_KEY='...'

# 2. Verify Docker
docker run hello-world

# If a permission error occurs:
sudo usermod -aG docker $USER
newgrp docker

# 3. Run the automated setup script
chmod +x setup.sh
./setup.sh
```

### Mock Mode (No API Keys)

When no API keys are set, the DGM automatically runs in **mock mode**:
- LLM calls return pre-selected probabilistic responses based on prompt content
- Responses are deterministically selected via content hashing for reproducibility
- Mock pools cover diagnosis, improvement evaluation, and coding agent scenarios
- The full pipeline can be exercised end-to-end without incurring API costs

This is useful for:
- Validating the setup and pipeline without API credentials
- Testing changes to the evolution loop or archive logic
- CI/CD environments where API keys are not available

### Manual Setup (Step by Step)

```bash
# Install elan (Lean 4 version manager)
curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh
# The lean-toolchain file pins Lean 4 v4.29.0 (includes grind tactic and other automation)

# Build the project (type-checks all proofs)
lake build

# Clone SWE-bench (needed for evaluation)
cd swe_bench
git clone https://github.com/princeton-nlp/SWE-bench.git
cd SWE-bench
git checkout dc4c087c2b9e4cefebf2e3d201d27e36
pip install -e .
cd ../../

# Install Python dependencies (for evaluation harness)
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Optional: graphviz for analysis
sudo apt-get install graphviz graphviz-dev
pip install -r requirements_dev.txt

# Prepare Polyglot dataset
# Make sure git is properly configured with username and email
python -m polyglot.prepare_polyglot_dataset
```

## Running the DGM

### Lean 4 (Primary)
```bash
# Build and run
lake build && lake exec dgm_main

# With options (same interface as the Python version)
lake exec dgm_main -- \
  --max_generation 80 \
  --selfimprove_size 2 \
  --selfimprove_workers 2 \
  --choose_method score_child_prop

# Continue from a previous run
lake exec dgm_main -- --continue_from output_dgm/20250101120000

# Run with polyglot benchmark
lake exec dgm_main -- --polyglot

# Show help
lake exec dgm_main -- --help
```

### Python (Legacy)
```bash
python DGM_outer.py
```

By default, outputs are saved in the `output_dgm/` directory.

## Verified Self-Evolution (Lean 4)

The Lean 4 implementation includes formal verification of self-evolution properties using Lean's dependent type system and the `grind` tactic for automation.

### Verification Properties
| Property | File | Status |
|----------|------|--------|
| **Stable Subtype Preservation** | `DGM/Proofs/Stability.lean` | ✅ Core proved, chain induction `sorry` |
| **Upgrade Correctness** | `DGM/Proofs/UpgradeCorrectness.lean` | ✅ Core proved, monotonicity `sorry` |
| **Bound Tightening** | `DGM/Proofs/BoundTightening.lean` | ✅ Fully proved + axiom |
| **Archive Monotonicity** | `DGM/Proofs/ArchiveMonotonicity.lean` | ✅ Core proved, Float ordering `sorry` |

### Key Verification Types
- **`AgentSpec`** — Formal behavioral contract (preconditions, postconditions, invariants)
- **`AgentImpl`** — Implementation carrying proof of spec satisfaction
- **`StableSubtype`** — Proves behavior is invariant on the stable domain across upgrades
- **`UpgradeDelta`** — Captures intended behavioral changes, separate from stable core
- **`EvolutionStep`** — A verified evolution step: parent → child with stability proof

## Architecture

### Lean 4 Implementation
```
DGM/
├── Types/                      — Core type-theoretic foundation
│   ├── Basic.lean              — Messages, tools, metrics, languages
│   ├── AgentSpec.lean          — Refinement types: AgentSpec, AgentImpl, StableSubtype
│   ├── Subtyping.lean          — Behavioral subtyping (LSP), bound tightening
│   └── Evolution.lean          — EvolutionStep, EvolutionChain, ArchiveEntry
├── Proofs/                     — Formal verification
│   ├── Stability.lean          — Stable subtypes preserved across evolution
│   ├── BoundTightening.lean    — Supertyping preserves behavioral contracts
│   ├── UpgradeCorrectness.lean — Changes confined to intended delta domain
│   └── ArchiveMonotonicity.lean — Archive best score never decreases
├── Agent/                      — Agent and LLM interface
│   ├── MockLLM.lean            — Mock responses when API keys are missing
│   ├── LLM.lean                — Real LLM API calls via curl (Anthropic + OpenAI)
│   ├── CodingAgent.lean        — SWE-bench coding agent
│   └── PolyglotAgent.lean      — Multi-language agent variant
├── Tools/                      — Tool system
│   ├── Tool.lean               — Tool typeclass and registry
│   ├── Bash.lean               — Bash execution via IO.Process
│   └── Edit.lean               — File operations with path validation
├── Evolution/                  — Evolution engine
│   ├── Archive.lean            — Verified archive with weighted selection
│   ├── SelfImprove.lean        — Self-improvement pipeline
│   └── Outer.lean              — Main loop with Task-based parallelism
├── Utils/                      — Utilities
│   ├── Docker.lean             — Docker container management
│   ├── Git.lean                — Git operations
│   ├── Common.lean             — File I/O helpers
│   ├── EvalUtils.lean          — Evaluation scoring
│   └── LogParsers.lean         — Test log parsing (pytest, cargo, go)
├── Eval/                       — Evaluation harnesses
│   ├── SWEBench.lean           — SWE-bench evaluation
│   └── Polyglot.lean           — Polyglot evaluation
├── Prompts/                    — Prompt templates
│   ├── SelfImprovement.lean    — Diagnosis and improvement prompts
│   ├── DiagnoseImprovement.lean — Before/after comparison
│   ├── TestRepo.lean           — Test execution instructions
│   └── ToolUse.lean            — Tool format for non-native LLMs
└── Analysis/
    └── Progress.lean           — Progress tracking, CSV/DOT export
```

### Python (Legacy)
- `DGM_outer.py` — Entry point for the evolution loop
- `coding_agent.py` — Initial coding agent
- `self_improve_step.py` — Self-improvement step
- `llm.py`, `llm_withtools.py` — LLM API calls
- `tools/` — Bash and edit tools
- `swe_bench/` — SWE-bench evaluation
- `polyglot/` — Polyglot evaluation

## Docker

### Build the image
```bash
docker build -t dgm .
```

### Run with API keys
```bash
docker run -e OPENAI_API_KEY -e ANTHROPIC_API_KEY dgm \
  lake exec dgm_main -- --max_generation 10
```

## Logs from Experiments
This [google drive folder](https://drive.google.com/drive/folders/1Kcu9TbIa9Z50pJ7S6hH9omzzD1pxIYZC?usp=sharing) contains all the foundation model output logs from the experiments shown in the paper.

## Safety Consideration
> [!WARNING]  
> This repository involves executing untrusted, model-generated code. We strongly advise users to be aware of the associated safety risks. While it is highly unlikely that such code will perform overtly malicious actions under our current settings and with the models we use, it may still behave destructively due to limitations in model capability or alignment. By using this repository, you acknowledge and accept these risks.

## Acknowledgement

The evaluation framework implementations are based on the [SWE-bench](https://github.com/swe-bench/SWE-bench) and [polyglot-benchmark](https://github.com/Aider-AI/polyglot-benchmark) repositories.

## Citing
If you find this project useful, please consider citing:
```bibtex
@article{zhang2025darwin,
  title={Darwin Godel Machine: Open-Ended Evolution of Self-Improving Agents},
  author={Zhang, Jenny and Hu, Shengran and Lu, Cong and Lange, Robert and Clune, Jeff},
  journal={arXiv preprint arXiv:2505.22954},
  year={2025}
}
```
