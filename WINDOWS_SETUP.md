# Windows CUDA Setup

The xmake, clangd, VS Code, and Better Todo Tree configuration follows Project 1.
Project 2 is a console application with a CUDA static library; it does not need
GLM, GLFW, GLEW, or OpenGL. Xmake is the build entry point for this repository.

## Requirements

- Windows with an NVIDIA GPU and a compatible driver.
- Visual Studio 2022 or Build Tools with **Desktop development with C++**.
- CUDA Toolkit 13 or newer, xmake 3.0.0 or newer, and clangd 23.1.0 or newer.

## Build and run

From the repository root in PowerShell:

```powershell
xmake f -m debug -y
xmake
xmake run cis5650_stream_compaction_test
```

`stream_compaction/xmake.lua` builds the five CUDA files into the
`stream_compaction` static library. `src/xmake.lua` links the existing test
program against it. Debug includes host and CUDA device symbols (`-G`).
Windows uses the DLL CRT (`MD`) and the conforming MSVC preprocessor, including
through nvcc, for CUDA 13's CCCL headers.

The executable is `build/debug/cis5650_stream_compaction_test.exe`. The original
test program calls `system("pause")` before exiting; press a key when prompted.
Its scan and compaction functions are still homework TODOs. Initial scan
comparisons can say `passed` because both arrays contain zeros, while the
compaction stubs return `-1` and print `FAIL COUNT`. Neither these messages nor
the process exit code establish algorithm correctness.

Use Release for performance measurements:

```powershell
xmake f -m release -y
xmake
xmake run cis5650_stream_compaction_test
```

Release writes `build/release/cis5650_stream_compaction_test.exe` and includes
CUDA line information (`-lineinfo`). `releasedbg` is also available.

Xmake detects CUDA and, with the default `--cuda_arch=native`, queries
`nvidia-smi` for each GPU's compute capability before falling back to Xmake's
native probe. An explicit architecture permits builds without GPU access:

```powershell
xmake f -m debug --cuda_arch=sm_89 -y
# Restore automatic detection:
xmake f -m debug --cuda_arch=native -y
```

For a custom Toolkit location, pass `--cuda="C:/path/to/CUDA"`. CUDA 13's
`include/cccl` directory is added automatically when present. The Toolkit and
driver must be compatible.

## VS Code workspace

```powershell
code CIS5650-Project2.code-workspace
```

The workspace is named **CIS5650 Project 2** and uses relative paths. Install
the recommended extensions. **Ctrl+Shift+B** builds Debug; **Tasks: Run Task >
xmake: run stream compaction** builds and runs the test program. A separate
Release build task is included. Settings also apply when opening with `code .`.

Better Todo Tree uses the same tags, checkbox highlights, grouping, counts, and
CUDA comment support as Project 1. Disable the old `Gruntfuggly.todo-tree`
extension and use `FanaticPythoner.better-todo-tree`. The fork bundles ripgrep
on Windows, so no executable path is committed. Existing exercise comments
are preserved.

### clangd

Xmake selects `.clangd.win.in` on Windows and `.clangd.nowin.in` on Linux. It
generates a local `.clangd` with the Toolkit path and GPU architecture, and
updates `compile_commands.json` after builds. Both generated files, local
workspace overrides (`*.local.code-workspace`), and build outputs are ignored
by Git. Keep machine-specific `clangd.path` settings in VS Code user settings.

Windows uses clang-cl with forwarded C++17/CUDA flags. NVCC arguments are
filtered for `.cu` files and the CUDA-facing headers in `stream_compaction/`.
Header insertion is disabled by the shared clangd arguments. After configuring
or changing the clangd executable, run **clangd: Restart language server**.

As in Project 1, affected CCCL `string_view` headers receive an editor-only
Clang VFS overlay under `build/clangd/`, applying the compatibility change in
[NVIDIA PR #7904](https://github.com/NVIDIA/cccl/pull/7904). The installed SDK,
nvcc compilation, and assignment sources remain unchanged. Already-fixed
headers need no overlay.

If a global `%LOCALAPPDATA%/clangd/config.yaml` adds a language standard such
as `-std:c++latest`, exclude this project from that override. User configuration
takes precedence over the generated project configuration.

## Debugging and profiling

**Windows: stream compaction (host debug)** in VS Code debugs CPU code using
the Microsoft debugger. For native Windows CUDA kernel debugging, generate a
Visual Studio solution:

```powershell
xmake project -k vsxmake -m "debug,release"
```

Open `vsxmake2022/CIS5650-Project2-xmake.sln` in Visual Studio 2022, select Debug, set
`cis5650_stream_compaction_test` as the startup project, and use **Nsight >
Start CUDA Debugging**. Kernel breakpoints become useful after the TODOs
actually launch kernels. The VS Code CUDA launch configuration uses Linux
`cuda-gdb`; see [Linux setup](LINUX_SETUP.md).

Use Nsight Systems or Nsight Compute with the Release executable for Windows
profiling. Store reports under the ignored `build/profiles/` directory. The
starter's GPU timers already use CUDA events, even before kernels are
implemented. A successful timer call verifies runtime access, not scan or
compaction correctness.

## Validation

Windows checks used an RTX 4080 SUPER (`sm_89`), driver 617.42, CUDA Toolkit
13.3, Visual Studio 2022, and clangd 23.1.0. Debug and Release build and run
successfully with exit code 0 and no stderr output. CUDA event timing is
available in both modes; the five `FAIL COUNT` messages come from the unchanged
compaction stubs. All twelve project source/header files pass clangd checks
with zero errors. These checks disable refactoring self-tests (`--tweaks=`),
which are separate from source diagnostics.

Live debugger breakpoint sessions, profiler captures, and Linux execution have
not been validated during this setup. No assignment source or TODO has been
modified.
