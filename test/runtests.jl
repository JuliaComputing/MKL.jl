using LinearAlgebra
using MKL
using Test

if MKL.is_lbt_available()
    @test BLAS.get_config().loaded_libs[1].libname == libmkl_rt
else
    @test BLAS.vendor() == :mkl
end

@test LinearAlgebra.peakflops() > 0
