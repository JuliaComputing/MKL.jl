function replace_libblas(base_dir, name)
    file = joinpath(base_dir, "build_h.jl")
    lines = readlines(file)

    libblas_idx   = findfirst(match.(r"const libblas_name", lines)   .!= nothing)
    liblapack_idx = findfirst(match.(r"const liblapack_name", lines) .!= nothing)
    useblas64_idx = findfirst(match.(r"USE_BLAS64", lines) .!= nothing)
    revertline = lines[useblas64_idx] #save to revert to previously set variable

    @assert libblas_idx !== nothing && liblapack_idx !== nothing

    lines[libblas_idx] = "const libblas_name = $(repr(name))"
    lines[liblapack_idx] = "const liblapack_name = $(repr(name))"
    if useblas64_idx != nothing
        if USEBLAS64
            lines[useblas64_idx] = "const USE_BLAS64 = true"
        else
            lines[useblas64_idx] = "const USE_BLAS64 = false"
        end
    end

    write(file, string(join(lines, '\n'), '\n'))
    return revertline
end

function revert_blas64(base_dir, name,revertline)
    file = joinpath(base_dir, "build_h.jl")
    lines = readlines(file)

    useblas64_idx = findfirst(match.(r"USE_BLAS64", lines) .!= nothing)
    lines[useblas64_idx] = revertline

    write(file, string(join(lines, '\n'), '\n'))
end


# Used to insert a load of MKL.jl before the stdlibs and run the __init__ explicitly
# since these need to have been run when LinearAlgebra loads and determines
# what BLAS vendor is used.
# We also have to push to LOAD_PATH since at this stage only @stdlibs
# is in LOAD_PATH and MKL.jl can thus not be found.
const MKL_PAYLOAD = """
    # START MKL INSERT
    pushfirst!(LOAD_PATH, "@v#.#")
    pushfirst!(LOAD_PATH, "@")
    MKL = Base.require(Base, :MKL)
    MKL.MKL_jll.__init__()
    MKL.__init__()
    popfirst!(LOAD_PATH)
    popfirst!(LOAD_PATH)
    # END MKL INSERT"""

const MKL_PAYLOAD_LINES = split(MKL_PAYLOAD, '\n')

function insert_MKL_load(base_dir)
    file = joinpath(base_dir, "sysimg.jl")
    @info "Splicing in code to load MKL in $(file)"
    lines = readlines(file)

    # Be idempotent
    if MKL_PAYLOAD_LINES[1] in lines
        return
    end

    # After this the stdlibs get included, so insert MKL to be loaded here
    if VERSION >= v"1.6.0"
        start_idx = findfirst(match.(r"# Stdlibs sorted in dependency, then alphabetical, order by contrib/print_sorted_stdlibs.jl", lines) .!= nothing)
    else
        start_idx = findfirst(match.(r"Base._track_dependencies\[\] = true", lines) .!= nothing)
    end

    splice!(lines, (start_idx + 1):start_idx, MKL_PAYLOAD_LINES)
    write(file, string(join(lines, '\n'), '\n'))
    return
end

function remove_MKL_load(base_dir)
    file = joinpath(base_dir, "sysimg.jl")
    @info "Removing code to load MKL in $(file)"
    lines = readlines(file)

    start_idx = findfirst(==(MKL_PAYLOAD_LINES[1]), lines)
    end_idx = findfirst(==(MKL_PAYLOAD_LINES[end]), lines)

    if start_idx === nothing || end_idx === nothing
        return
    end

    splice!(lines, start_idx:end_idx)
    write(file, string(join(lines, '\n'), '\n'))
    return
end

function get_precompile_statments_file()
    jl_dev_ver = length(VERSION.prerelease) == 2 && (VERSION.prerelease)[1] == "DEV" # test if running nightly/unreleased version
    jl_gh_tag = jl_dev_ver ? "master" : "release-$(VERSION.major).$(VERSION.minor)"
    prec_jl_url = "https://raw.githubusercontent.com/JuliaLang/julia/$jl_gh_tag/contrib/generate_precompile.jl"
    @info "getting precompile script from: $prec_jl_url"
    prec_jl_fn = tempname()
    download(prec_jl_url, prec_jl_fn)
    prec_jl_content = read(prec_jl_fn, String)
    # PackageCompiler.jl already inits stdio and double initing it leads to bad things
    write(prec_jl_fn, replace(prec_jl_content, "Base.reinit_stdio()" => "# Base.reinit_stdio()"))
    return prec_jl_fn
end

enable_mkl_startup() = change_blas_library(MKL_jll.libmkl_rt)
enable_openblas_startup() = change_blas_library("libopenblas")

function change_blas_library(libblas)

    # First, we need to modify a few files in Julia's base directory
    base_dir = joinpath(Sys.BINDIR, Base.DATAROOTDIR, "julia", "base")
    if libblas == "libopenblas"
        if Sys.WORD_SIZE == 64
            libblas = "$(libblas)64_"
        end
        remove_MKL_load(base_dir)
    else
        insert_MKL_load(base_dir)
    end

    # Replace definitions of `libblas_name`, etc.. to point to MKL or OpenBLAS
    revertline = replace_libblas(base_dir, libblas)

    # Next, build a new system image
    # We don't want to load PackageCompiler in top level scope because
    # we will put MKL.jl in the sysimage and having PackageCompiler loaded
    # means it will also be put there
    @eval begin
        using PackageCompiler
        PackageCompiler.create_sysimage(; incremental=false, replace_default=true,
                                        script=get_precompile_statments_file())
    end

    # revert const USE_BLAS64 to initial state
    revert_blas64(base_dir,libblas,revertline)
end
