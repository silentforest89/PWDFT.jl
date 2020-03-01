using Printf
using Random
using LinearAlgebra
using NLsolve

using PWDFT

const DIR_PWDFT = joinpath(dirname(pathof(PWDFT)), "..")
const DIR_PSP = joinpath(DIR_PWDFT, "pseudopotentials", "pade_gth")

function init_Hamiltonian()
    atoms = Atoms(xyz_string_frac=
        """
        8

        Si   0.000000000000000   0.000000000000000   0.000000000000000 
        Si   0.750000000000000   0.750000000000000   0.250000000000000 
        Si   0.500000000000000   0.000000000000000   0.500000000000000 
        Si   0.750000000000000   0.250000000000000   0.750000000000000 
        Si   0.000000000000000   0.500000000000000   0.500000000000000 
        Si   0.250000000000000   0.250000000000000   0.250000000000000 
        Si   0.250000000000000   0.750000000000000   0.750000000000000 
        Si   0.500000000000000   0.500000000000000   0.000000000000000 
        """, in_bohr=true, LatVecs=gen_lattice_cubic(10.2631))

    pspfiles = [joinpath(DIR_PSP, "Si-q4.gth")]
    ecutwfc = 15.0
    return Hamiltonian( atoms, pspfiles, ecutwfc, meshk=[6,6,6] )
end


"""
NLsolve driver.
Adapted from DFTK.jl
"""
function scf_NLsolve_solver( m=5; kwargs... )

    function fix_point_solver( f, x0, tol, NiterMax )
        res = NLsolve.nlsolve(x -> f(x) - x, x0;
            m=m, method=:anderson, xtol=tol, ftol=0.0, show_trace=true,
            iterations=NiterMax, kwargs... )
        ( fixpoint=res.zero, converged=NLsolve.converged(res) )
    end

    return fix_point_solver

end



function KS_solve_SCF_NLsolve!( Ham::Hamiltonian )

    Random.seed!(1234)

    Npoints = prod(Ham.pw.Ns)
    Nspin = Ham.electrons.Nspin
    Nkpt = Ham.pw.gvecw.kpoints.Nkpt
    Nkspin = Nkpt*Nspin
    Nstates = Ham.electrons.Nstates
    Nstates_occ = Ham.electrons.Nstates_occ

    Rhoe = zeros(Float64, Npoints, Nspin)
    psiks = rand_BlochWavefunc(Ham)
    
    #calc_rhoe!( Ham, psiks, Rhoe )
    Rhoe[:,1] = guess_rhoe( Ham )

    # calculate E_NN and PspCore energies
    Ham.energies.NN = calc_E_NN( Ham.atoms )
    Ham.energies.PspCore = calc_PspCore_ene( Ham.atoms, Ham.pspots )

    evals = zeros( Float64, Nstates, Nkspin )

    ethr_last = 1e-5
    betamix = 1.0 # use Rhoe_out directly

    function density_map( Rhoe_in )
    
        update!( Ham, Rhoe_in )
    
        evals =
        diag_LOBPCG!( Ham, psiks, verbose=false, verbose_last=false, tol=ethr_last,
                      Nstates_conv=Nstates_occ )

        Rhoe_out = calc_rhoe( Ham, psiks )

        # simple mixing here?
        Rhoe_next = betamix*Rhoe_out + (1 - betamix)*Rhoe_in
        return Rhoe_next

    end

    NiterMax = 100
    solver = scf_NLsolve_solver()
    fpres = solver(density_map, Rhoe, 1e-5, NiterMax)
    
    update!( Ham, fpres.fixpoint )

    println()
    println("Total energy")
    println("------------")

    Ham.energies = calc_energies( Ham, psiks )
    println( Ham.energies )

end


function precKerker( pw::PWGrid, R::Array{Float64,2} )
    Ng = pw.gvec.Ng
    G2 = pw.gvec.G2
    idx_g2r = pw.gvec.idx_g2r

    λ = 1.0
    Ag = λ*minimum(G2[2:end])
    #println("Ag = ", Ag)

    Nspin = size(R,2)
    Npoints = size(R,1)
    Rg = zeros(ComplexF64, Npoints, Nspin)
    Rout = zeros(Float64, Npoints, Nspin)

    for ispin in 1:Nspin

        Rg[:,ispin] = R_to_G( pw, R[:,ispin] )
        
        for ig = 2:Ng
            ip = idx_g2r[ig]
            Rg[ip,ispin] = G2[ig]/(G2[ig] + Ag)*Rg[ip,ispin]
            #@printf("%10d %18.10f %18.10f\n", ig, G2[ig], G2[ig]/(G2[ig] + Ag))
        end
        Rout[:,ispin] = real( G_to_R(pw, Rg[:,ispin]) )
    end

    println("norm in:  ", norm(R))
    println("norm out: ", norm(Rout))

    return Rout
end


#
# This function is adapted from Anderson mixing function in KSSOLV
#
# vin is the result
# vin will be overwritten for next SCF iteration
function mix_kerker_anderson!( vin, vout, pw::PWGrid,
                               beta::Float64, df::Array{Float64,2}, dv::Array{Float64,2},
                               iter::Int64, mixdim::Int64 )
    # Residual
    dvout = precKerker( pw, vout - vin )

    iterused = min(iter-1,mixdim)
    ipos = iter - 1 - floor(Int64, (iter-2)/mixdim)*mixdim

    if iter > 1
        df[:,ipos] = df[:,ipos] - dvout[:]
        dv[:,ipos] = dv[:,ipos] - vin[:]
    end

    vinsave  = copy(vin)
    dvoutsave = copy(dvout)

    if (iter > 1)
        gammas = pinv(df[:,1:iterused])*dvout  
        for i = 1:iterused
            vin[:]  = vin[:]  - gammas[i] * dv[:,i]
            dvout[:] = dvout[:] - gammas[i] * df[:,i]
        end
    end

    inext = iter - floor( Int64, (iter - 1) / mixdim) * mixdim

    df[:,inext] = dvoutsave[:]
    dv[:,inext] = vinsave[:]

    vin[:] = vin[:] + beta*dvout[:]

    return
end




function my_scf!( Ham::Hamiltonian; NiterMax=150, betamix=0.2, etot_conv_thr=1e-6 )
    
    pw = Ham.pw
    Nelectrons = Ham.electrons.Nelectrons

    psiks = rand_BlochWavefunc(Ham)
    
    Rhoe = calc_rhoe(Ham, psiks)
    update!(Ham, Rhoe)
    
    Rhoe_new = similar(Rhoe)
    
    Ham.energies.NN = calc_E_NN(Ham.atoms)
    Ham.energies.PspCore = calc_PspCore_ene(Ham.atoms, Ham.pspots)

    Etot_old = 0.0
    Nconv = 0

    # For Anderson mixing
    mixdim = 5
    Npoints = size(Rhoe,1)
    Nspin = size(Rhoe,2)
    df = zeros(Float64,Npoints*Nspin, mixdim)
    dv = zeros(Float64,Npoints*Nspin, mixdim)

    @printf("\n")
    @printf("SCF iteration starts (with density mixing), betamix = %f\n", betamix)
    @printf("\n")
    
    for iterSCF = 1:NiterMax
        
        _ = diag_LOBPCG!( Ham, psiks )
        
        Rhoe_new = calc_rhoe( Ham, psiks )
        
        println("norm diff Rhoe = ", norm(Rhoe_new - Rhoe))

        #Rhoe = betamix*Rhoe_new + (1-betamix)*Rhoe
        
        #Rhoe = betamix*precKerker( pw, Rhoe_new - Rhoe ) + Rhoe
        #mix_kerker_anderson!( Rhoe, Rhoe_new, pw, betamix, df, dv, iterSCF, mixdim )
        mix_anderson!( Rhoe, Rhoe_new, betamix, df, dv, iterSCF, mixdim )

        #Rhoe[:] = betamix*( Rhoe_new - Rhoe ) + Rhoe[:]

        update!(Ham, Rhoe)
        
        Ham.energies = calc_energies(Ham, psiks)
        Etot = sum(Ham.energies)
        diffEtot = abs(Etot - Etot_old)
        
        @printf("%5d %18.10f %18.10e\n", iterSCF, Etot, diffEtot)
        
        if diffEtot <= etot_conv_thr
            Nconv = Nconv + 1
        else
            Nconv = 0
        end
        
        if Nconv >= 2
            @printf("SCF is converged in iter: %d\n", iterSCF)
            return
        end
        
        Etot_old = Etot
        flush(stdout)
    end

    @printf("WARNING: SCF is not converged after %d iterations\n", NiterMax)
    return
end


function main()
    Random.seed!(1234)
    Ham = init_Hamiltonian()
    #my_scf!( Ham, NiterMax=100, betamix=0.5 )
    #KS_solve_SCF!( Ham, mix_method="linear_adaptive" )
    KS_solve_SCF_NLsolve!( Ham )
end

main()