using LinearAlgebra
using MKL
using Test

if VERSION > MKL.JULIA_VER_NEEDED
    @test BLAS.get_config().loaded_libs[1].libname == libmkl_rt
else
    @test BLAS.vendor() == :mkl
end

@test LinearAlgebra.peakflops() > 0
