# return succeed or not
# modify Ham (internally)
# return success_or_not, α, αt
function linmin_quad_vector!( Ham::Hamiltonian,
    psiks_orig::BlochWavefunc,
    g::BlochWavefunc, d::BlochWavefunc, α::Vector{Float64}, αt::Vector{Float64},
    E_orig::Float64, minim_params::MinimizeParams
)

    psiks = deepcopy(psiks_orig)
    psiks_tmp = deepcopy(psiks)

    Nkspin = length(psiks)

    αPrev = zeros(Nkspin)
    gdotd = dot_BlochWavefunc(g,d) # directional derivative at starting point

    if gdotd >= 0.0
        @printf("Bad step direction: g.d = %f > 0.0\n", gdotd)
        α = αPrev
        return false, α, αt
    end

    # These should be parameters
    N_α_adjust_max = minim_params.N_α_adjust_max
    αt_min = minim_params.αt_min
    αt_reduceFactor = minim_params.αt_reduceFactor
    αt_increaseFactor = minim_params.αt_increaseFactor

    E_trial = zeros(Float64,Nkspin)
    E_actual = zeros(Float64,Nkspin)

    for s in 1:N_α_adjust_max
        
        for i in 1:Nkspin
            if αt[i] < αt_min
                println("αt below threshold. Quitting step.")
                α[i] = αPrev[i]
            end
            return false, α[i], αt[i]
        end

        # Try the test step
        psiks_tmp = deepcopy(psiks)
        for i in 1:Nkspin
            psiks = deepcopy(psiks_tmp)
            # Step only the i-th kpt
            do_step!( psiks[i], αt[i] - αPrev[i], d[i] )        
            αPrev[i] = αt[i]
            E_trial[i] = calc_energies_only!( Ham, psiks )
        end
        
        # Check if step crossed domain of validity of parameter space:
        #if !isfinite(E_trial)
        #    αt = αt * αt_reduceFactor
        #    @printf("Test step failed, E_trial = %le, reducing αt to %le.\n", E_trial, αt)
        #    continue
        #end


        # Predict step size:
        for i in 1:Nkspin
            α[i] = 0.5 * αt[i]^2 *gdotd[i] / (αt[i] * gdotd[i] + E_orig - E_trial[i])
        end

        # Check reasonableness of predicted step size:
        for i in 1:Nkspin
            if α < 0
                # Curvature has the wrong sign
                # That implies E_trial < E, so accept step for now, and try descending further next time
                αt = αt * αt_increaseFactor;
                @printf("Wrong curvature in test step, increasing αt to %le.\n", αt)
            end
        end
        if any(α <. 0)
            return true, α, αt
        end
        
        #if α/αt > αt_increaseFactor
        #    αt = αt * αt_increaseFactor
        #    @printf("Predicted α/αt > %lf, increasing αt to %le.\n", αt_increaseFactor, αt)
        #    continue
        #end

        #if αt/α < αt_reduceFactor
        #    αt = αt * αt_reduceFactor
        #    @printf("Predicted α/αt < %lf, reducing αt to %le.\n", αt_reduceFactor, αt)
        #    continue
        #end
        
        # Successful test step:
        break
    end


    if !isfinite(E_actual)
        @printf("Test step failed %d times. Quitting step.\n", N_α_adjust_max)
        α = αPrev
        return false, α, αt
    end


    # Actual step:
    for s in 1:N_α_adjust_max        
        # Try the step:
        do_step!( psiks, α - αPrev, d )
        αPrev = α
        E_actual = calc_energies_only!( Ham, psiks )

        @printf("linmin actual step: α = %18.10e E = %18.10f\n", α, E_actual)
        
        if !isfinite(E_actual)
            α = α * αt_reduceFactor;
            @printf("Step failed: E = %le, reducing α to %le.\n", E_actual, α)
            continue
        end
        
        if E_actual > E_orig
            α = α * αt_reduceFactor
            @printf("Step increased by: %le, reducing α to %le.\n", E_actual - E_orig, α)
            continue
        end
        
        # Step successful:
        break
    end
    
    if !isfinite(E_actual) || (E_actual > E_orig)
        @printf("Step failed to reduce after %d attempts. Quitting step.\n", N_α_adjust_max)
        return false, α, αt
    end

    return true, α, αt
end