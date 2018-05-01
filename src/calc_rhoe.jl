function calc_rhoe( pw::PWGrid, Focc, psik::Array{Array{Complex128,2},1} )
    Ω  = pw.Ω
    Ns = pw.Ns
    Nkpt = pw.gvecw.kpoints.Nkpt
    Ngw = pw.gvecw.Ngw
    wk = pw.gvecw.kpoints.wk
    Npoints = prod(Ns)
    Nstates = size(psik[1])[2]

    cpsi = zeros( Complex128, Npoints, Nstates )
    psiR = zeros( Complex128, Npoints, Nstates )
    rho = zeros(Float64,Npoints)

    for ik = 1:Nkpt
        cpsi[:,:] = 0.0 + im*0.0
        # Transform to real space
        idx = pw.gvecw.idx_gw2r[ik]
        psi = psik[ik]
        cpsi[idx,:] = psi[:,:]
        psiR = G_to_R(pw, cpsi)
        # orthonormalization in real space
        ortho_gram_schmidt!( Nstates, psiR )
        scale!( sqrt(Npoints/Ω), psiR )
        #
        for ist = 1:Nstates
            for ip = 1:Npoints
                rho[ip] = rho[ip] + wk[ik]*Focc[ist]*real( conj(psiR[ip,ist])*psiR[ip,ist] )
            end
        end
    end

    # Ensure that there is no negative rhoe
    for ip = 1:Nstates
        if rho[ip] < eps()
            rho[ip] = eps()
        end
    end

    # renormalize
    integ_rho = sum(rho)*Ω/Npoints
    Nelectrons = sum(Focc)
    rho = Nelectrons/integ_rho * rho

    return rho
end



function calc_rhoe( ik::Int64, pw::PWGrid, Focc, psi::Array{Complex128,2} )
    Ω  = pw.Ω
    Ns = pw.Ns
    Npoints = prod(Ns)
    Nstates = size(psi)[2]

    # Transform to real space
    cpsi = zeros( Complex128, Npoints, Nstates )
    idx = pw.gvecw.idx_gw2r[ik]
    cpsi[idx,:] = psi[:,:]
    psiR = G_to_R(pw, cpsi)

    # orthonormalization in real space
    ortho_gram_schmidt!( Nstates, psiR )
    scale!( sqrt(Npoints/Ω), psiR )

    rho = zeros(Float64,Npoints)
    for ist = 1:Nstates
        for ip = 1:Npoints
            rho[ip] = rho[ip] + Focc[ist]*real( conj(psiR[ip,ist])*psiR[ip,ist] )
        end
    end

    # Ensure that there is no negative rhoe
    for ip = 1:Nstates
        if rho[ip] < eps()
            rho[ip] = eps()
        end
    end
    # renormalize
    integ_rho = sum(rho)*Ω/Npoints
    Nelectrons = sum(Focc)
    rho = Nelectrons/integ_rho * rho

    return rho
end
