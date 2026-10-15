# Linux CUDA Setup

Use the same xmake and VS Code workflow as Project 1. Project 2 only needs
CUDA, a compatible NVIDIA driver, a supported host C++ compiler, and xmake
3.0.0 or newer. It has no OpenGL, GLFW, GLEW, GLM, or XWayland dependencies.
Xmake is the build entry point. Native Windows setup is documented in
[Windows setup](WINDOWS_SETUP.md).

## Build and run

From the repository root:

```sh
xmake f -m debug -y
xmake
xmake run cis5650_stream_compaction_test
```

The CUDA static library is defined in `stream_compaction/xmake.lua`; the test
executable is defined in `src/xmake.lua`. Binaries are written under
`build/{debug,release}/`. Debug includes CUDA device symbols (`-G`). For
performance measurements, configure Release, which includes `-lineinfo`:

```sh
xmake f -m release -y
xmake
xmake run cis5650_stream_compaction_test
```

The default `--cuda_arch=native` queries `nvidia-smi` for local GPU compute
capabilities, falling back to Xmake's native CUDA probe. To build without GPU
access, pass an explicit architecture such as `--cuda_arch=sm_89`; restore
automatic detection with `--cuda_arch=native`. For a custom Toolkit location,
use `--cuda=/path/to/cuda`. CUDA 13's `include/cccl` is added when present.

All algorithm TODOs and the original test harness are preserved. Zero-filled
scan outputs may compare equal before implementation, and compaction stubs
return `-1`, causing `FAIL COUNT`. These results are not correctness validation.
The starter also calls `system("pause")`, a Windows command: a Linux shell may
print `pause: not found` at the end. This does not come from xmake or CUDA.

## VS Code, clangd, and TODO navigation

```sh
code CIS5650-Project2.code-workspace
```

Install the recommended clangd, xmake, Nsight, C/C++, and Better Todo Tree
extensions. **Ctrl+Shift+B** builds Debug. **Tasks: Run Task > xmake: run stream
compaction** builds and runs the program. Shared folder settings also work
with `code .`; local preferences can go in the ignored
`CIS5650-Project2.local.code-workspace`.

Xmake updates `compile_commands.json` and selects `.clangd.nowin.in` to generate
`.clangd` with local CUDA paths and architecture. Both generated files are
ignored by Git; only the platform templates are shared. Use a recent clangd
(23.1.0 is used for the Windows checks), then run **clangd: Restart language
server** after configuring. C/C++ IntelliSense and the xmake extension's
separate compilation database generation are disabled. Automatic header
insertion is disabled by `--header-insertion=never`.

Better Todo Tree retains Project 1's tags, checkbox highlights, grouped counts,
and CUDA comment recognition. Disable the original Todo Tree before using the
fork. Keep personal ripgrep paths out of shared settings. Source TODO comments
have not been rewritten.

## CUDA debugging

Put the Toolkit's `cuda-gdb` on `PATH`, configure Debug, and select **CUDA:
stream compaction (Linux, xmake debug)** in Run and Debug. Press **F5** to build
and stop at `main`, then continue to a CUDA breakpoint. Kernel breakpoints
require the TODO implementations to launch a kernel. **Shift+F5** stops the
session. No graphics environment wrapper or GLM pretty-printer is needed.

## Profiling

Install Nsight Systems and/or Nsight Compute, then build Release:

```sh
mkdir -p build/profiles
nsys profile --trace=cuda,nvtx --sample=none --cpuctxsw=none \
  --force-overwrite=true --output=build/profiles/stream-compaction-systems \
  xmake run cis5650_stream_compaction_test
nsys-ui build/profiles/stream-compaction-systems.nsys-rep
```

Once kernels are implemented, capture one launch with Nsight Compute:

```sh
ncu --target-processes all --set=basic --launch-count=1 \
  --force-overwrite --export=build/profiles/stream-compaction-compute \
  xmake run cis5650_stream_compaction_test
ncu-ui build/profiles/stream-compaction-compute.ncu-repz
```

`--target-processes all` includes the child process launched by xmake. The
unimplemented starter has no scan/compaction kernel launches to collect.
Profile after implementing the homework and increase its input size as needed
for useful measurements. Reports remain under the ignored `build/` directory.

This Linux configuration follows Project 1; it has not been run on a Linux
host during this setup.
