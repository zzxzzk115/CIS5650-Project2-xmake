set_project("CIS5650-Project2-xmake")
set_xmakever("3.0.0")
set_allowedplats("linux", "windows")
set_languages("cxx17")
set_defaultmode("debug")

-- mode.debug supplies host symbols (-g) and CUDA device symbols (-G).
add_rules("mode.debug", "mode.release", "mode.releasedbg")
add_rules("plugin.compile_commands.autoupdate", {outputdir = ".", lsp = "clangd"})

-- Configure CUDA headers and generate local clangd paths and architecture.
rule("cuda.environment")
    add_deps("cuda.gencodes")
    on_load(function (target)
        import("core.project.config")
        if (config.get("cuda_arch") or "native"):trim():lower() ~= "native" then
            return
        end
        -- Query the driver without compiling/running a temporary CUDA executable.
        -- Leave "native" to Xmake's CUDA probe if nvidia-smi is unavailable.
        local output = try {function ()
            return os.iorunv("nvidia-smi", {"--query-gpu=compute_cap", "--format=csv,noheader,nounits"})
        end}
        local archs = {}
        for _, line in ipairs((output or ""):split("\n")) do
            local major, minor = line:trim():match("^(%d+)%.(%d+)$")
            if major then
                table.insert(archs, "sm_" .. major .. minor)
            end
        end
        if #archs > 0 then
            -- Include every reported GPU architecture on multi-GPU hosts.
            archs = table.unique(archs)
            target:set("cugencodes", archs)
            cprint("checking for CUDA architecture ... ${green}%s${clear} (nvidia-smi)", table.concat(archs, ", "))
        end
    end)
    on_config(function (target)
        import("core.base.json")
        local cuda = target:data("cuda")
        if not cuda then
            return
        end
        local flags = table.concat(table.wrap(target:get("cuflags")), " ")
        local arch = flags:match("code=%[?sm_(%d+%a*)") or flags:match("arch=compute_(%d+%a*)")
        assert(arch, "Cannot detect CUDA architecture; configure with --cuda_arch=sm_XX")
        -- CUDA 13 installs Thrust, CUB, and libcudacxx under include/cccl.
        local cccl = path.join(cuda.sdkdir, "include", "cccl")
        if os.isdir(cccl) then
            target:add("includedirs", cccl)
        end
        local root = os.projectdir()
        local windows = is_host("windows")
        local template = windows and ".clangd.win.in" or ".clangd.nowin.in"
        local contents = io.readfile(path.join(root, template))
        contents = contents:gsub("@CUDA_PATH@", function ()
            local flag = (windows and "/clang:" or "") .. "--cuda-path=" .. cuda.sdkdir
            return json.encode(flag):gsub("\\/", "/")
        end)
        contents = contents:gsub("@CUDA_ARCH@", "sm_" .. arch)
        for placeholder, dirname in pairs({CUDA_INCLUDE = "include", CUDA_CCCL = "include/cccl"}) do
            contents = contents:gsub("@" .. placeholder .. "@", function ()
                local flag = (windows and "/I" or "-I") .. path.join(cuda.sdkdir, dirname)
                return json.encode(flag):gsub("\\/", "/")
            end)
        end
        -- Editor-only copy of NVIDIA's Clang compatibility fix; never patch the SDK.
        -- https://github.com/NVIDIA/cccl/pull/7904
        local string_view = path.join(cuda.sdkdir, "include/cccl/cuda/std/string_view")
        if os.isfile(string_view) then
            local patched, count = io.readfile(string_view):gsub("_CCCL_HOST basic_string_view%(", "basic_string_view(")
            if count > 0 then
                local overlaydir = path.join(root, "build/clangd")
                os.mkdir(overlaydir)
                local header = path.join(overlaydir, "string_view")
                local overlay = path.join(overlaydir, "cuda-headers.json")
                if not os.isfile(header) or io.readfile(header) ~= patched then
                    io.writefile(header, patched)
                end
                local overlay_contents = json.encode({version = 0, roots = {
                    {type = "file", name = string_view, ["external-contents"] = header}
                }})
                if not os.isfile(overlay) or io.readfile(overlay) ~= overlay_contents then
                    io.writefile(overlay, overlay_contents)
                end
                local prefix = windows and "/clang:" or ""
                contents = contents .. "\n---\nCompileFlags:\n  Add: ["
                    .. json.encode(prefix .. "-ivfsoverlay") .. ", " .. json.encode(prefix .. overlay) .. "]\n"
            end
        end
        local output = path.join(root, ".clangd")
        if not os.isfile(output) or io.readfile(output) ~= contents then
            io.writefile(output, contents)
        end
    end)
rule_end()
add_rules("cuda", "cuda.environment")

option("cuda_arch")
    set_default("native")
    set_showmenu(true)
    set_description("CUDA GPU architecture (native, or an explicit value such as sm_89)")
option_end()

-- An explicit architecture permits compilation without access to a GPU.
add_cugencodes(get_config("cuda_arch"))
set_targetdir("build/$(mode)")
add_includedirs(".")
if is_plat("windows") then
    set_arch("x64")
    set_runtimes("MD")
    -- CUDA 13's CCCL headers require the conforming MSVC preprocessor.
    add_cxxflags("/Zc:preprocessor")
    add_cuflags("-Xcompiler=/Zc:preprocessor")
end
if is_mode("release", "releasedbg") then
    add_cuflags("-lineinfo")
end

includes("stream_compaction", "src")
