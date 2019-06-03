function symmetrize_vector!(pw::PWGrid, sym_info::SymmetryInfo, irt, v::Array{Float64,2})

    Nsyms = sym_info.Nsyms
    LatVecs = pw.LatVecs
    RecVecs = pw.RecVecs
    s = sym_info.s

    if Nsyms == 1
        return
    end

    Nvecs = size(v)[2]

    tmp = zeros(3,Nvecs)
    
    # bring vector to crystal axis
    for i = 1:Nvecs
        tmp[:,i] = v[1,i]*LatVecs[1,:] + v[2,i]*LatVecs[2,:] + v[3,i]*LatVecs[3,:]
    end
    
    println(tmp)

    # symmetrize in crystal axis
    v[:,:] .= 0.0
    for i = 1:Nvecs
        for isym = 1:Nsyms
            iar = irt[isym,i]
            v[:,i] = v[:,i] + s[:,1,isym]*tmp[1,iar]
                            + s[:,2,isym]*tmp[2,iar]
                            + s[:,3,isym]*tmp[3,iar]
            println(isym, " ", v[:,i])
        end
        #println(v[:,i])
    end
    
    tmp[:,:] = v[:,:]/Nsyms
    
    # bring vector back to cartesian axis
    for i = 1:Nvecs
        v[:,i] = tmp[1,i]*RecVecs[:,1] + tmp[2,i]*RecVecs[:,2] + tmp[3,i]*RecVecs[:,3]
    end

    v = v/(2*pi)

    return
end



function init_irt( atoms::Atoms, sym_info::SymmetryInfo )
    
    Natoms = atoms.Natoms
    tau = atoms.positions
    RecVecs = inv(Matrix(atoms.LatVecs'))  # !! We don't include 2*pi factor here
    atm2species = atoms.atm2species
    
    xau = zeros(3,Natoms)
    rau = zeros(3,Natoms)
    
    for ia = 1:Natoms
        xau[:,ia] = RecVecs[1,:]*tau[1,ia] + RecVecs[2,:]*tau[2,ia] + RecVecs[3,:]*tau[3,ia]
        println(xau[:,ia])
    end

    # checking for supercell is skipped (probably not needed here)

    Nsyms = sym_info.Nsyms
    s = sym_info.s
    ft = sym_info.ft

    irt = zeros(Int64,Nsyms,Natoms)

    Nequal = 0
    for isym = 1:Nsyms
        for ia = 1:Natoms
            rau[:,ia] = s[1,:,isym] * xau[1,ia] + 
                        s[2,:,isym] * xau[2,ia] + 
                        s[3,:,isym] * xau[3,ia]
        end
    end

    for isym = 1:Nsyms
        for ia = 1:Natoms
            for ib = 1:Natoms
                if atm2species[ia] == atm2species[ib]
                    is_equal = eqvect( rau[:,ia], xau[:,ib], ft , 1e-5 )
                    #println("is_equal = ", is_equal)
                    if is_equal
                        Nequal = Nequal + 1
                        #println("is_equal = ", is_equal)
                        irt[isym,ia] = ib
                        break
                    end
                end
            end
        end
    end



    #for isym = 1:Nsyms
    #    for ia = 1:Natoms
    #        @printf("%d ", irt[isym,ia])
    #    end
    #    @printf("\n")
    #end
    #println("Nequal = ", Nequal)

    return irt

end

function eqvect(x, y, f, accep)
  
  # This function test if the difference x-y-f is an integer.
  # x, y = 3d vectors in crystal axis, f = fractional translation
  # adapted from QE-6.4

  res = ( abs(x[1]-y[1]-f[1] - round(Int64, x[1]-y[1]-f[1])) < accep ) &&
        ( abs(x[2]-y[2]-f[2] - round(Int64, x[2]-y[2]-f[2])) < accep ) &&
        ( abs(x[3]-y[3]-f[3] - round(Int64, x[3]-y[3]-f[3])) < accep )
  
  return res
end