import DGM

/-- Parse a command-line flag value: `--flag value` or `--flag=value`. -/
def parseFlag (args : List String) (flag : String) : Option String :=
  match args with
  | [] => none
  | arg :: rest =>
    if arg == flag then
      rest.head?
    else if arg.startsWith (flag ++ "=") then
      some ((arg.drop (flag.length + 1)).toString)
    else
      parseFlag rest flag

/-- Check if a boolean flag is present. -/
def hasFlag (args : List String) (flag : String) : Bool :=
  args.any (· == flag)

/-- Parse a flag that may appear under multiple aliases. -/
def parseFlagAlias (args : List String) (flags : List String) : Option String :=
  flags.findSome? (parseFlag args ·)

/-- Parse a Nat from args, with a default. -/
def parseFlagNat (args : List String) (flag : String) (default : Nat) : Nat :=
  match parseFlag args flag with
  | some s => s.toNat?.getD default
  | none => default

/-- Parse a Float from args, with a default. -/
def parseFlagFloat (args : List String) (flag : String) (default : Float) : Float :=
  match parseFlag args flag with
  | some s =>
    -- Parse "N.M" format
    match s.splitOn "." with
    | [intPart, fracPart] =>
      let intVal := intPart.toNat?.getD 0
      let fracVal := fracPart.toNat?.getD 0
      let fracDivisor := Float.ofNat (10 ^ fracPart.length)
      Float.ofNat intVal + Float.ofNat fracVal / fracDivisor
    | [intPart] =>
      match intPart.toNat? with
      | some n => Float.ofNat n
      | none => default
    | _ => default
  | none => default

/-- Print usage help. -/
def printUsage : IO Unit := do
  IO.println "Darwin Gödel Machine (Lean 4 — Verified Self-Evolution)"
  IO.println ""
  IO.println "Usage: dgm_main [options]"
  IO.println ""
  IO.println "Evolution Mode (DGM_outer.py equivalent):"
  IO.println "  --max_generation N                Maximum evolution generations (default: 80)"
  IO.println "  --selfimprove_size N              Self-improvement attempts per generation (default: 2)"
  IO.println "  --selfimprove_workers N           Parallel workers (default: 2)"
  IO.println "  --choose_method METHOD            Selection: random|best|score_prop|score_child_prop (default: score_child_prop)"
  IO.println "  --choose_selfimproves_method M    Alias for --choose_method"
  IO.println "  --continue_from DIR               Continue from a previous run directory"
  IO.println "  --num_swe_evals N                 Number of SWE evaluations per attempt (default: 1)"
  IO.println "  --eval_noise F                    Noise leeway for archive admission (default: 0.1)"
  IO.println "  --polyglot                        Use polyglot benchmark instead of SWE-bench"
  IO.println "  --post_improve_diagnose           Enable post-improvement diagnosis"
  IO.println "  --shallow_eval                    Run only shallow (small) evaluation"
  IO.println "  --no_full_eval                    Disable full evaluation for top performers"
  IO.println "  --update_archive METHOD           Archive update: keep_all|keep_better (default: keep_all)"
  IO.println "  --run_baseline METHOD             Run baseline: no_selfimprove|no_darwin"
  IO.println "  --output_dir DIR                  Output directory (default: output_dgm)"
  IO.println ""
  IO.println "Eval Mode (test_swebench.py equivalent):"
  IO.println "  --eval                            Run standalone evaluation (no evolution)"
  IO.println "  --model_patch_paths P1,P2,...     Comma-separated patch file paths"
  IO.println "  --model_name_or_path NAME         Name/ID for this evaluation run"
  IO.println "  --max_workers N                   Number of parallel workers (default: 5)"
  IO.println "  --num_evals N                     Number of repeated evaluations (default: 1)"
  IO.println "  --num_evals_parallel N            Parallel repeated evaluations (default: 1)"
  IO.println "  --full_eval                       Evaluate on full dataset"
  IO.println "  --test_big                        Evaluate on big subset"
  IO.println "  --test_med                        Evaluate on medium subset"
  IO.println "  --num_samples N                   Number of samples (0 = all, default: 0)"
  IO.println ""
  IO.println "  --help                            Show this help message"
  IO.println ""
  IO.println "Setup:"
  IO.println "  export OPENAI_API_KEY='...'"
  IO.println "  export ANTHROPIC_API_KEY='...'"
  IO.println "  docker run hello-world    # Verify Docker"
  IO.println "  lake build                # Build the project"
  IO.println "  lake exec dgm_main       # Run DGM"

/-- Run standalone evaluation mode (equivalent to test_swebench.py). -/
def runEvalMode (args : List String) : IO Unit := do
  IO.println "Darwin Gödel Machine — Eval Mode (test_swebench.py equivalent)"
  IO.println ""

  -- Parse eval-mode args
  let maxWorkers    := parseFlagNat args "--max_workers" 5
  let numEvals      := parseFlagNat args "--num_evals" 1
  let numEvalsParal := parseFlagNat args "--num_evals_parallel" 1
  -- numSamples=0 means "all" (matches --num_samples default of -1 in Python, but Nat can't be -1)
  let numSamples    := parseFlagNat args "--num_samples" 0
  let polyglot      := hasFlag args "--polyglot"
  let fullEval      := hasFlag args "--full_eval"
  let testBig       := hasFlag args "--test_big"
  let testMed       := hasFlag args "--test_med"

  -- Model patch paths
  let patchPathsStr  := (parseFlag args "--model_patch_paths").getD ""
  let patchPaths     := if patchPathsStr.isEmpty then []
                        else patchPathsStr.splitOn ","

  -- Model name
  let ns ← IO.monoNanosNow
  let defaultName := s!"original_{ns}"
  let modelName := (parseFlag args "--model_name_or_path").getD defaultName

  -- Load test task list
  let subsetDir := if polyglot then "./polyglot/subsets" else "./swe_bench/subsets"
  let taskListPath := if fullEval then ""
    else if testBig then s!"{subsetDir}/big.json"
    else if testMed then s!"{subsetDir}/medium.json"
    else s!"{subsetDir}/small.json"

  IO.println s!"Eval config:"
  IO.println s!"  Model:           {modelName}"
  IO.println s!"  Patch paths:     {patchPaths}"
  IO.println s!"  Max workers:     {maxWorkers}"
  IO.println s!"  Num evals:       {numEvals}"
  IO.println s!"  Parallel evals:  {numEvalsParal}"
  IO.println s!"  Full eval:       {fullEval}"
  IO.println s!"  Num samples:     {if numSamples == 0 then "all" else toString numSamples}"
  IO.println s!"  Task list:       {if taskListPath.isEmpty then "full dataset" else taskListPath}"
  IO.println ""

  -- Build the harness command (delegates to Python harness for actual Docker eval)
  let patchArgs := patchPaths.foldl (fun acc p => acc ++ [" --model_patch_paths", p]) []
  let patchArgsStr := String.intercalate " " patchArgs
  let cmd := s!"python -m swe_bench.harness " ++
    s!"--model_name_or_path {modelName} " ++
    s!"{patchArgsStr} " ++
    s!"--max_workers {maxWorkers} " ++
    s!"--num_evals {numEvals} " ++
    s!"--num_evals_parallel {numEvalsParal} " ++
    (if fullEval then "" else s!"--test_task_list {taskListPath} ") ++
    (if numSamples > 0 then s!"--num_samples {numSamples}" else "")
  IO.println s!"Running: {cmd}"
  let result ← IO.Process.output { cmd := "bash", args := #["-c", cmd] }
  if result.exitCode != 0 then
    IO.eprintln s!"Harness failed with exit code {result.exitCode}"
    IO.eprintln result.stderr
  else
    IO.println result.stdout
  IO.println "Eval complete."

/-- Darwin Gödel Machine — Lean 4 entry point.
    Supports both evolution mode (DGM_outer.py) and
    standalone eval mode (test_swebench.py). -/
def main (args : List String) : IO Unit := do
  if hasFlag args "--help" || hasFlag args "-h" then
    printUsage
    return

  -- Eval mode: standalone evaluation (test_swebench.py equivalent)
  if hasFlag args "--eval" then
    return ← runEvalMode args

  IO.println "╔══════════════════════════════════════════════════════╗"
  IO.println "║  Darwin Gödel Machine (Lean 4 — Verified Evolution) ║"
  IO.println "╚══════════════════════════════════════════════════════╝"

  -- Parse CLI arguments (mirrors Python argparse in DGM_outer.py)
  -- Accept both --choose_method and --choose_selfimproves_method (Python compat)
  let selectionMethod :=
    match parseFlagAlias args ["--choose_method", "--choose_selfimproves_method"] with
    | some "random"          => DGM.Types.SelectionMethod.random
    | some "best"            => DGM.Types.SelectionMethod.best
    | some "score_prop"      => DGM.Types.SelectionMethod.scoreProp
    | some "score_child_prop" | _ => DGM.Types.SelectionMethod.scoreChildProp

  let outputDir := (parseFlag args "--output_dir").getD "output_dgm"

  let config : DGM.Evolution.Outer.DGMConfig := {
    maxGenerations      := parseFlagNat args "--max_generation" 80
    selfImproveSize     := parseFlagNat args "--selfimprove_size" 2
    selfImproveWorkers  := parseFlagNat args "--selfimprove_workers" 2
    selectionMethod     := selectionMethod
    noiseLeeway         := parseFlagFloat args "--eval_noise" 0.1
    outputDir           := outputDir
    prevRunDir          := parseFlag args "--continue_from"
    polyglot            := hasFlag args "--polyglot"
    numEvals            := parseFlagNat args "--num_swe_evals" 1
    postImproveDiagnose := hasFlag args "--post_improve_diagnose"
    runBaseline         := parseFlag args "--run_baseline"
    shallowEval         := hasFlag args "--shallow_eval"
    noFullEval          := hasFlag args "--no_full_eval"
    updateArchive       := (parseFlag args "--update_archive").getD "keep_all"
  }

  IO.println s!"Config:"
  IO.println s!"  Max generations:     {config.maxGenerations}"
  IO.println s!"  Self-improve size:   {config.selfImproveSize}"
  IO.println s!"  Workers:             {config.selfImproveWorkers}"
  IO.println s!"  Output dir:          {config.outputDir}"
  IO.println s!"  Polyglot:            {config.polyglot}"
  IO.println s!"  Shallow eval:        {config.shallowEval}"
  IO.println s!"  Post-improve diag:   {config.postImproveDiagnose}"
  let baselineStr := config.runBaseline.getD "none"
  IO.println s!"  Run baseline:        {baselineStr}"

  -- Verify environment
  let anthropicKey ← IO.getEnv "ANTHROPIC_API_KEY"
  let openaiKey ← IO.getEnv "OPENAI_API_KEY"
  match (anthropicKey, openaiKey) with
  | (none, none) =>
    IO.eprintln "INFO: No API keys set. Running in MOCK MODE with pre-selected responses."
    IO.eprintln "  To use real LLMs, set: export OPENAI_API_KEY='...' and/or ANTHROPIC_API_KEY='...'"
  | _ => pure ()

  -- Verify Docker
  let dockerCheck ← IO.Process.output { cmd := "docker", args := #["info", "--format", "{{.ServerVersion}}"] }
  if dockerCheck.exitCode != 0 then
    IO.eprintln "WARNING: Docker is not available. Agent evaluation will fail."
    IO.eprintln "  Run: sudo usermod -aG docker $USER && newgrp docker"
  else
    IO.println s!"  Docker version:      {dockerCheck.stdout.trimAscii.toString}"

  IO.println ""

  -- Run the evolution loop
  let _finalArchive ← DGM.Evolution.Outer.runEvolutionLoop config
  IO.println "DGM run complete."
  return ()
