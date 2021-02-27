using LinearAlgebra
using MKL
using MKL_jll
using Test

if VERSION > v"1.7.0-DEV.623"
    @test BLAS.get_config().loaded_libs[1].libname == libmkl_rt
else
    @test BLAS.vendor() == :mkl
end

@test LinearAlgebra.peakflops() > 0
