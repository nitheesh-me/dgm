/-!
# DGM.Utils.Docker — Docker Container Management

Docker operations for building, running, and managing containers
used for isolated agent evaluation.
Ported from: `utils/docker_utils.py`
-/

namespace DGM.Utils.Docker

/-! ## Container Configuration -/

/-- Docker container configuration. -/
structure ContainerConfig where
  /-- Docker image name. -/
  imageName : String := "dgm"
  /-- Container name. -/
  containerName : String
  /-- Whether to force rebuild the image. -/
  forceRebuild : Bool := false
  /-- Repository path to mount. -/
  repoPath : String := "."
  deriving Repr, Inhabited

/-- Docker container handle (opaque). -/
structure Container where
  /-- Container ID or name. -/
  id : String
  /-- Whether the container is running. -/
  running : Bool := false
  deriving Repr, Inhabited

/-! ## Container Operations -/

/-- Remove an existing container if present. -/
def removeExisting (containerName : String) : IO Unit := do
  let _ ← IO.Process.output {
    cmd := "docker"
    args := #["rm", "-f", containerName]
  }
  return ()

/-- Build a Docker container for DGM evaluation.
Ported from `build_dgm_container` in `utils/docker_utils.py`. -/
def buildContainer (imageName containerName : String)
    (forceRebuild : Bool := false) : IO Container := do
  -- Remove existing container if present
  let _ ← removeExisting containerName

  if forceRebuild then
    -- Build the Docker image
    let buildResult ← IO.Process.output {
      cmd := "docker"
      args := #["build", "-t", imageName, "."]
    }
    if buildResult.exitCode != 0 then
      throw <| IO.userError s!"Docker build failed: {buildResult.stderr}"

  -- Create and start container
  let createResult ← IO.Process.output {
    cmd := "docker"
    args := #["create", "--name", containerName, imageName, "sleep", "infinity"]
  }
  if createResult.exitCode != 0 then
    throw <| IO.userError s!"Docker create failed: {createResult.stderr}"

  let startResult ← IO.Process.output {
    cmd := "docker"
    args := #["start", containerName]
  }
  if startResult.exitCode != 0 then
    throw <| IO.userError s!"Docker start failed: {startResult.stderr}"

  return { id := containerName, running := true }

/-- Copy a file to a running container.
Ported from `copy_to_container` in `utils/docker_utils.py`. -/
def copyToContainer (container : Container) (sourcePath destPath : String) : IO Unit := do
  let result ← IO.Process.output {
    cmd := "docker"
    args := #["cp", sourcePath, s!"{container.id}:{destPath}"]
  }
  if result.exitCode != 0 then
    throw <| IO.userError s!"Docker cp failed: {result.stderr}"

/-- Copy a file from a running container.
Ported from `copy_from_container` in `utils/docker_utils.py`. -/
def copyFromContainer (container : Container) (sourcePath destPath : String) : IO Unit := do
  let result ← IO.Process.output {
    cmd := "docker"
    args := #["cp", s!"{container.id}:{sourcePath}", destPath]
  }
  if result.exitCode != 0 then
    throw <| IO.userError s!"Docker cp failed: {result.stderr}"

/-- Execute a command inside a container. -/
def execInContainer (container : Container) (command : String) : IO String := do
  let result ← IO.Process.output {
    cmd := "docker"
    args := #["exec", container.id, "/bin/bash", "-c", command]
  }
  if result.exitCode != 0 then
    throw <| IO.userError s!"Docker exec failed (exit {result.exitCode}): {result.stderr}"
  return result.stdout

/-- Clean up a container (stop and remove). -/
def cleanupContainer (container : Container) : IO Unit := do
  let _ ← IO.Process.output {
    cmd := "docker"
    args := #["stop", container.id]
  }
  let _ ← IO.Process.output {
    cmd := "docker"
    args := #["rm", container.id]
  }
  return ()

end DGM.Utils.Docker
