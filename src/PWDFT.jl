__precompile__()

module PWDFT

export Ry2eV, ANG2BOHR
# constants
const Ry2eV = 13.6058         # Ry to eV
const ANG2BOHR = 1.889725989  # angstrom to bohr

export Atoms
include("Atoms/Atoms.jl")

#
# Essentials: FFTW
#
export c_G_to_R
export c_R_to_G
export R_to_G
export G_to_R
include("FFT/wrappers_fft.jl")


#
# Submodules begin here
#

module Utilities
    export PrintMatrix
    include("Utilities/PrintMatrix.jl")
end

module PW
    export PWGrid
    export GVectors
    export GVectorsW
    include("PW/PWGrid_v03.jl")
end

module PsPot
    export PsPot_HGH
    export HGH_eval_Vloc_G
    export HGH_eval_proj_G
    export info_PsPot_HGH
    include("PsPot/PsPot_HGH.jl")
end

#
# End of submodules
#

end
