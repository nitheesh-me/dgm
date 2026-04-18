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
<!-- <p align="center">
<img src="./misc/conceptual.svg"/></a><br>
</p> -->


## Lean 4 Implementation (Verified Self-Evolution)

This repository includes a **Lean 4** implementation with formal verification of self-evolution properties. The Lean 4 version uses refinement types to identify stable subtypes during upgrades, ensuring behavior changes only for intended improvements.

### Key Verification Properties
- **Stable Subtype Preservation**: Behavior on the stable domain is invariant across upgrades
- **Upgrade Correctness**: Changes are confined to the intended delta domain
- **Bound Tightening**: Supertyping preserves behavioral contracts
- **Archive Monotonicity**: The archive's best score never decreases

### Setup (Lean 4)
```bash
# Install elan (Lean 4 version manager)
curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh

# The lean-toolchain file specifies Lean 4 v4.29.0
# Build the project
lake build

# Run the executable
lake exec dgm_main
```

```bash
# API keys (still needed for LLM calls)
export OPENAI_API_KEY='...'
export ANTHROPIC_API_KEY='...'
```

```bash
# Docker setup (still needed for agent evaluation)
docker run hello-world

# If a permission error occurs
sudo usermod -aG docker $USER
newgrp docker
```

### Setup (Python — Legacy)
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Optional: for running analysis
sudo apt-get install graphviz graphviz-dev
pip install -r requirements_dev.txt
```

```bash
# Clone SWE-bench
cd swe_bench
git clone https://github.com/princeton-nlp/SWE-bench.git
cd SWE-bench
git checkout dc4c087c2b9e4cefebf2e3d201d27e36
pip install -e .
cd ../../

# Prepare Polyglot
python -m polyglot.prepare_polyglot_dataset
```

## Running the DGM

### Lean 4 (Verified)
```bash
lake build && lake exec dgm_main
```

### Python (Legacy)
```bash
python DGM_outer.py
```
By default, outputs will be saved in the `output_dgm/` directory.

## File Structure

### Lean 4 (Verified Implementation)
```
DGM/
├── Types/
│   ├── Basic.lean          — Core types (messages, tools, metrics, languages)
│   ├── AgentSpec.lean       — Refinement types: AgentSpec, AgentImpl, StableSubtype, UpgradeDelta
│   ├── Subtyping.lean       — Behavioral subtyping (LSP), bound tightening, subtype chains
│   └── Evolution.lean       — EvolutionStep, EvolutionChain, ArchiveEntry, EvolutionArchive
├── Proofs/
│   ├── Stability.lean       — Stable subtypes preserved across evolution chains
│   ├── BoundTightening.lean — Supertyping preserves behavioral contracts
│   ├── UpgradeCorrectness.lean — Behavior changes only in intended delta domain
│   └── ArchiveMonotonicity.lean — Archive best score never decreases
├── Agent/
│   ├── LLM.lean             — LLM client, tool-use protocol, agentic chat loop
│   ├── CodingAgent.lean     — SWE-bench coding agent (AgenticSystem)
│   └── PolyglotAgent.lean   — Multi-language agent variant
├── Tools/
│   ├── Tool.lean            — Tool typeclass and registry
│   ├── Bash.lean            — Bash execution with IO monad
│   └── Edit.lean            — File operations with path validation
├── Evolution/
│   ├── Archive.lean         — Verified archive with selection methods
│   ├── SelfImprove.lean     — Self-improvement pipeline with verification
│   └── Outer.lean           — Main evolutionary loop
├── Utils/
│   ├── Docker.lean          — Docker container management
│   ├── Git.lean             — Git operations (diff, reset, apply)
│   ├── Common.lean          — File I/O utilities
│   ├── EvalUtils.lean       — Evaluation scoring
│   └── LogParsers.lean      — Test log parsing (pytest, django, cargo, go)
├── Eval/
│   ├── SWEBench.lean        — SWE-bench evaluation harness
│   └── Polyglot.lean        — Polyglot evaluation harness
├── Prompts/
│   ├── SelfImprovement.lean — Diagnosis and improvement prompts
│   ├── DiagnoseImprovement.lean — Before/after comparison prompts
│   ├── TestRepo.lean        — Test description generation
│   └── ToolUse.lean         — Tool usage format for non-native LLMs
└── Analysis/
    └── Progress.lean        — Progress tracking, CSV/DOT export
```

### Python (Legacy)
- `analysis/` scripts used for plotting and analysis
- `initial/` SWE-bench logs and performance of the initial agent
- `initial_polyglot/` Polyglot logs and performance of the initial agent
- `swe_bench/` code needed for SWE-bench evaluation
- `polyglot/` code needed for Polyglot evaluation
- `prompts/` prompts used for foundation models
- `tests/` tests for the DGM system
- `tools/` tools available to the foundation models
- `coding_agent.py` main implementation of the initial coding agent
- `DGM_outer.py` entry point for running the DGM algorithm

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
