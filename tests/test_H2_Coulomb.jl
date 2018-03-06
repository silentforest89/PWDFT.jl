using PWDFT

function test_main( ; method="SCF" )
    const LatVecs = 16.0*diagm( ones(3) )
    ecutwfc_Ry = 40.0
    pw = PWGrid( ecutwfc_Ry*0.5, LatVecs )
    println(pw)

    #
    # Atoms
    #
    atoms = init_atoms_xyz("H2.xyz")
    println(atoms)

    #
    # Structure factor
    #
    strf = calc_strfact( atoms, pw )

    #
    # Initialize Hamiltonian
    #
    Ham = PWHamiltonian(pw)
    Ham.potentials.Ps_loc = init_V_coulomb_G( pw, strf, [1.0] )
    println("sum V Ps loc = ", sum(Ham.potentials.Ps_loc))

    #
    # calculate E_NN
    #
    Ham.energies.NN = calc_E_NN( pw, strf, atoms.positions, atoms.Nspecies, atoms.atm2species, [1.0])

    println("\nAfter calculating E_NN")
    println(Ham.energies)

    if method == "SCF"
        λ, v = KS_solve_SCF!( Ham )
        println("\nAfter calling KS_solve_SCF:")
    elseif method == "Emin"
        λ, v = KS_solve_Emin_PCG!( Ham, I_CG_BETA=2 )
        println("\nAfter calling KS_solve_Emin_PCG:")
    else
        println("ERROR: unknow method = ", method)
    end

    Nstates = Ham.electrons.Nstates
    println("\nEigenvalues")
    for ist = 1:Nstates
        @printf("%8d  %18.10f\n", ist, λ[ist])
    end
    println("\nTotal energy components")
    println(Ham.energies)

end

@time test_main(method="Emin")
@time test_main(method="SCF")