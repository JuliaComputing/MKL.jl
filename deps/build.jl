using MKL

if MKL.is_lbt_available()
    @info "Using LBT"
    exit() # Don't want to build the system image, since we will use LBT
end

@info "Using PackageCompiler"
using PackageCompiler
using MKL_jll

# if no environment variable ENV["USE_BLAS64"] is set install.jl
# tries to change USE_BLAS64 = false
const USEBLAS64 = parse(Bool,get(ENV, "USE_BLAS64","false"))

include("../src/install.jl")
enable_mkl_startup()
