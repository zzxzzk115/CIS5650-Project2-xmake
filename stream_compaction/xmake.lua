target("stream_compaction")
    set_kind("static")
    -- The executable contains only C++; resolve CUDA device code in this library.
    set_policy("build.cuda.devlink", true)
    set_default(false)
    add_files("*.cu")
    add_headerfiles("*.h")
target_end()
