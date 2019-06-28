function grad_obj_function!(
    Ham::Hamiltonian,
    psiks::BlochWavefunc,
    g::BlochWavefunc,
    Haux::Array{Matrix{ComplexF64},1},
    g_Haux::Array{Matrix{ComplexF64},1};
    rhoe_symm::Union{Nothing,RhoeSymmetrizer}=nothing,
    kT::Float64=1e-3,    
    skip_ortho=false
)

    Nkpt = Ham.pw.gvecw.kpoints.Nkpt
    Nspin = Ham.electrons.Nspin
    Nkspin = Nkpt*Nspin
    Nstates = Ham.electrons.Nstates
    Nelectrons = Ham.electrons.Nelectrons    
    wk = Ham.pw.gvecw.kpoints.wk

    evals = zeros( Float64, Nstates, Nkspin )
    U_Haux = copy(Haux)
    for i in 1:Nkspin
        evals[:,i], U_Haux[i] = eigen( Haux[i] )
    end

    Ham.electrons.Focc, E_fermi = calc_Focc( Nelectrons, wk, kT, evals, Nspin )
    Entropy = calc_entropy( wk, kT, evals, E_fermi, Nspin )

    # DEBUG, only for Nkspin=1
    #@printf("E_fermi = %18.10f\n", E_fermi)
    #@printf("eigenvalues, focc = \n")
    #for i in 1:Nstates
    #    @printf("%5d %18.10f %18.10f\n", i, evals[i,1], Ham.electrons.Focc[i,1])
    #end

    if !skip_ortho
        for i = 1:length(psiks)
            ortho_sqrt!(psiks[i])
        end
    end

    # rotate psiks
    for i = 1:Nkspin
        psiks[i] = psiks[i]*U_Haux[i]
        #ortho_check(psiks[i])
    end

    Rhoe = calc_rhoe( Ham, psiks )
    if rhoe_symm != nothing
        #if Ham.sym_info.Nsyms > 1
        symmetrize_rhoe!( Ham, rhoe_symm, Rhoe )
    end
    update!( Ham, Rhoe )

    for ispin = 1:Nspin
        for ik = 1:Nkpt
            Ham.ispin = ispin
            Ham.ik = ik
            ikspin = ik + (ispin-1)*Nkpt
            g[ikspin], _, _, g_Haux[ikspin] =
              calc_grad_Haux( Ham, psiks[ikspin], evals[:,ikspin], kT )
        end
    end

    return

end