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
  IO.println "Options:"
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
  IO.println "  --help                            Show this help message"
  IO.println ""
  IO.println "Setup:"
  IO.println "  export OPENAI_API_KEY='...'"
  IO.println "  export ANTHROPIC_API_KEY='...'"
  IO.println "  docker run hello-world    # Verify Docker"
  IO.println "  lake build                # Build the project"
  IO.println "  lake exec dgm_main       # Run DGM"

/-- Darwin Gödel Machine — Lean 4 entry point.
    Runs the outer evolutionary loop with verified self-improvement. -/
def main (args : List String) : IO Unit := do
  if hasFlag args "--help" || hasFlag args "-h" then
    printUsage
    return

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

  let config : DGM.Evolution.Outer.DGMConfig := {
    maxGenerations      := parseFlagNat args "--max_generation" 80
    selfImproveSize     := parseFlagNat args "--selfimprove_size" 2
    selfImproveWorkers  := parseFlagNat args "--selfimprove_workers" 2
    selectionMethod     := selectionMethod
    noiseLeeway         := parseFlagFloat args "--eval_noise" 0.1
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
