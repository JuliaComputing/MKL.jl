module MKL

using Preferences
using Libdl

# Choose an MKL provider; taking an explicit preference as the first choice,
# but if nothing is set as a preference, fall back to an environment variable,
# and if that is not given, fall back to the default choice of `MKL_jll`.
const mkl_provider = lowercase(something(
    @load_preference("mkl_provider", nothing),
    get(ENV, "JULIA_MKL_PROVIDER", nothing),
    "mkl_jll",
)::String)

if mkl_provider == "mkl_jll"
    # Only load MKL_jll if we are suppoed to use it as the MKL source
    # to avoid an unnecessary download of the (lazy) artifact.
    import MKL_jll
    const libmkl_rt = MKL_jll.libmkl_rt
    const mkl_path = dirname(libmkl_rt)
elseif mkl_provider == "system"
    # We want to use a "system" MKL, so let's try to find it.
    # The user may provide the path to libmkl_rt via a preference
    # or an environment variable. Otherwise, we expect it to
    # already be loaded, or be on our linker search path.
    const mkl_path = lowercase(something(
        @load_preference("mkl_path", nothing),
        get(ENV, "JULIA_MKL_PATH", nothing),
        "",
    )::String)
    const libmkl_rt = find_library(["libmkl_rt"], [mkl_path])
    libmkl_rt == "" && error("Couldn't find libmkl_rt. Maybe set JULIA_MKL_PATH?")
else
    error("Invalid mkl_provider choice $(mkl_provider).")
end

# Changing the MKL provider preference
function set_mkl_provider(provider)
    if lowercase(provider) ∉ ("mkl_jll", "system")
        error("Invalid mkl_provider choice $(provider)")
    end
    @set_preferences!("mkl_provider" => lowercase(provider))

    @info("New MKL provider set; please restart Julia to see this take effect", provider)
end

JULIA_VER_NEEDED = v"1.7.0-DEV.641"
VERSION > JULIA_VER_NEEDED && using LinearAlgebra

if Base.USE_BLAS64
    const MKLBlasInt = Int64
else
    const MKLBlasInt = Int32
end

@enum Threading begin
    THREADING_INTEL
    THREADING_SEQUENTIAL
    THREADING_PGI
    THREADING_GNU
    THREADING_TBB
end

@enum Interface begin
    INTERFACE_LP64
    INTERFACE_ILP64
    INTERFACE_GNU
end

function set_threading_layer(layer::Threading = THREADING_INTEL)
    err = ccall((:MKL_Set_Threading_Layer, libmkl_rt), Cint, (Cint,), layer)
    err == -1 && throw(ErrorException("return value was -1"))
    return nothing
end

function set_interface_layer(interface = Base.USE_BLAS64 ? INTERFACE_ILP64 : INTERFACE_LP64)
    err = ccall((:MKL_Set_Interface_Layer, libmkl_rt), Cint, (Cint,), interface)
    err == -1 && throw(ErrorException("return value was -1"))
    return nothing
end

function __init__()
    # if MKL_jll.is_available()
    set_threading_layer()
    set_interface_layer()
    VERSION > JULIA_VER_NEEDED && BLAS.lbt_forward(libmkl_rt, clear=true)
    # end
end

function mklnorm(x::Vector{Float64})
    ccall((:dnrm2_, libmkl_rt), Float64,
          (Ref{MKLBlasInt}, Ptr{Float64}, Ref{MKLBlasInt}),
          length(x), x, 1)
end

end # module
