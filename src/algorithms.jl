# Algorithms
abstract type BoundaryValueDiffEqAlgorithm <: SciMLBase.AbstractBVPAlgorithm end
abstract type AbstractMIRK <: BoundaryValueDiffEqAlgorithm end

"""
    Shooting(ode_alg = nothing; nlsolve = nothing, jac_alg = BVPJacobianAlgorithm())

Single shooting method, reduces BVP to an initial value problem and solves the IVP.

## Arguments

  - `ode_alg`: ODE algorithm to use for solving the IVP. Any solver which conforms to the
    SciML `ODEProblem` interface can be used! (Defaults to `nothing` which will use
    poly-algorithm if `DifferentialEquations.jl` is loaded else this must be supplied)

## Keyword Arguments

  - `nlsolve`: Internal Nonlinear solver. Any solver which conforms to the SciML
    `NonlinearProblem` interface can be used. Note that any autodiff argument for the solver
    will be ignored and a custom jacobian algorithm will be used.
  - `jac_alg`: Jacobian Algorithm used for the nonlinear solver. Defaults to
    `BVPJacobianAlgorithm()`, which automatically decides the best algorithm to use based
    on the input types and problem type. Only `diffmode` is used (defaults to
    `AutoForwardDiff` if possible else `AutoFiniteDiff`).

!!! note
    For type-stability, the chunksizes for ForwardDiff ADTypes in `BVPJacobianAlgorithm`
    must be provided.
"""
struct Shooting{O, N, L <: BVPJacobianAlgorithm} <: BoundaryValueDiffEqAlgorithm
    ode_alg::O
    nlsolve::N
    jac_alg::L
end

function concretize_jacobian_algorithm(alg::Shooting, prob)
    jac_alg = alg.jac_alg
    diffmode = jac_alg.diffmode === nothing ? __default_nonsparse_ad(prob.u0) :
               jac_alg.diffmode
    return Shooting(alg.ode_alg, alg.nlsolve, BVPJacobianAlgorithm(diffmode))
end

function Shooting(ode_alg = nothing; nlsolve = nothing, jac_alg = nothing)
    jac_alg === nothing && (jac_alg = __propagate_nlsolve_ad_to_jac_alg(nlsolve))
    return Shooting(ode_alg, nlsolve, jac_alg)
end

Shooting(ode_alg, nlsolve; jac_alg = nothing) = Shooting(ode_alg; nlsolve, jac_alg)

# This is a deprecation path. We forward the `ad` from nonlinear solver to `jac_alg`.
# We will drop this function in
function __propagate_nlsolve_ad_to_jac_alg(nlsolve::N) where {N}
    # Defaults so no depwarn
    nlsolve === nothing && return BVPJacobianAlgorithm()
    ad = hasfield(N, :ad) ? nlsolve.ad : nothing
    ad === nothing && return BVPJacobianAlgorithm()

    Base.depwarn("Setting autodiff to the nonlinear solver in Shooting has been deprecated \
                  and will have no effect from the next major release. Update to use \
                  `BVPJacobianAlgorithm` directly", :Shooting)
    return BVPJacobianAlgorithm(ad)
end

"""
    MultipleShooting(nshoots::Int, ode_alg = nothing; nlsolve = nothing,
        grid_coarsening = true, jac_alg = BVPJacobianAlgorithm())

Multiple Shooting method, reduces BVP to an initial value problem and solves the IVP.
Significantly more stable than Single Shooting.

## Arguments

  - `nshoots`: Number of shooting points.
  - `ode_alg`: ODE algorithm to use for solving the IVP. Any solver which conforms to the
    SciML `ODEProblem` interface can be used! (Defaults to `nothing` which will use
    poly-algorithm if `DifferentialEquations.jl` is loaded else this must be supplied)

## Keyword Arguments

  - `nlsolve`: Internal Nonlinear solver. Any solver which conforms to the SciML
    `NonlinearProblem` interface can be used. Note that any autodiff argument for the solver
    will be ignored and a custom jacobian algorithm will be used.
  - `jac_alg`: Jacobian Algorithm used for the nonlinear solver. Defaults to
    `BVPJacobianAlgorithm()`, which automatically decides the best algorithm to use based
    on the input types and problem type.
    - For `TwoPointBVProblem`, only `diffmode` is used (defaults to
      `AutoSparseForwardDiff` if possible else `AutoSparseFiniteDiff`).
    - For `BVProblem`, `bc_diffmode` and `nonbc_diffmode` are used. For `nonbc_diffmode`
      defaults to `AutoSparseForwardDiff` if possible else `AutoSparseFiniteDiff`. For
      `bc_diffmode`, defaults to `AutoForwardDiff` if possible else `AutoFiniteDiff`.
  - `grid_coarsening`: Coarsening the multiple-shooting grid to generate a stable IVP
    solution. Possible Choices:
    - `true`: Halve the grid size, till we reach a grid size of 1.
    - `false`: Do not coarsen the grid. Solve a Multiple Shooting Problem and finally
      solve a Single Shooting Problem.
    - `AbstractVector{<:Int}` or `Ntuple{N, <:Integer}`: Use the provided grid coarsening.
      For example, if `nshoots = 10` and `grid_coarsening = [5, 2]`, then the grid will be
      coarsened to `[5, 2]`. Note that `1` should not be present in the grid coarsening.
    - `Function`: Takes the current number of shooting points and returns the next number
      of shooting points. For example, if `nshoots = 10` and
      `grid_coarsening = n -> n ÷ 2`, then the grid will be coarsened to `[5, 2]`.

!!! note
    For type-stability, the chunksizes for ForwardDiff ADTypes in `BVPJacobianAlgorithm`
    must be provided.
"""
@concrete struct MultipleShooting{J <: BVPJacobianAlgorithm}
    ode_alg
    nlsolve
    jac_alg::J
    nshoots::Int
    grid_coarsening
end

function concretize_jacobian_algorithm(alg::MultipleShooting, prob)
    jac_alg = concrete_jacobian_algorithm(alg.jac_alg, prob, alg)
    return MultipleShooting(alg.ode_alg, alg.nlsolve, jac_alg, alg.nshoots,
        alg.grid_coarsening)
end

function update_nshoots(alg::MultipleShooting, nshoots::Int)
    return MultipleShooting(alg.ode_alg, alg.nlsolve, alg.jac_alg, nshoots,
        alg.grid_coarsening)
end

function MultipleShooting(nshoots::Int, ode_alg = nothing; nlsolve = nothing,
        grid_coarsening = true, jac_alg = BVPJacobianAlgorithm())
    @assert grid_coarsening isa Bool || grid_coarsening isa Function ||
            grid_coarsening isa AbstractVector{<:Integer} ||
            grid_coarsening isa NTuple{N, <:Integer} where {N}
    grid_coarsening isa Tuple && (grid_coarsening = Vector(grid_coarsening...))
    if grid_coarsening isa AbstractVector
        sort!(grid_coarsening; rev = true)
        @assert all(grid_coarsening .> 0) && 1 ∉ grid_coarsening
    end
    return MultipleShooting(ode_alg, nlsolve, jac_alg, nshoots, grid_coarsening)
end

for order in (2, 3, 4, 5, 6)
    alg = Symbol("MIRK$(order)")

    @eval begin
        """
            $($alg)(; nlsolve = NewtonRaphson(), jac_alg = BVPJacobianAlgorithm())

        $($order)th order Monotonic Implicit Runge Kutta method.

        ## Keyword Arguments

          - `nlsolve`: Internal Nonlinear solver. Any solver which conforms to the SciML
            `NonlinearProblem` interface can be used. Note that any autodiff argument for
            the solver will be ignored and a custom jacobian algorithm will be used.
          - `jac_alg`: Jacobian Algorithm used for the nonlinear solver. Defaults to
            `BVPJacobianAlgorithm()`, which automatically decides the best algorithm to
            use based on the input types and problem type.
            - For `TwoPointBVProblem`, only `diffmode` is used (defaults to
              `AutoSparseForwardDiff` if possible else `AutoSparseFiniteDiff`).
            - For `BVProblem`, `bc_diffmode` and `nonbc_diffmode` are used. For
              `nonbc_diffmode` defaults to `AutoSparseForwardDiff` if possible else
              `AutoSparseFiniteDiff`. For `bc_diffmode`, defaults to `AutoForwardDiff` if
              possible else `AutoFiniteDiff`.

        !!! note
            For type-stability, the chunksizes for ForwardDiff ADTypes in
            `BVPJacobianAlgorithm` must be provided.

        ## References

        @article{Enright1996RungeKuttaSW,
            title={Runge-Kutta Software with Defect Control for Boundary Value ODEs},
            author={Wayne H. Enright and Paul H. Muir},
            journal={SIAM J. Sci. Comput.},
            year={1996},
            volume={17},
            pages={479-497}
        }
        """
        Base.@kwdef struct $(alg){N, J <: BVPJacobianAlgorithm} <: AbstractMIRK
            nlsolve::N = nothing
            jac_alg::J = BVPJacobianAlgorithm()
        end
    end
end

"""
    BVPM2(; max_num_subintervals = 3000, method_choice = 4, diagnostic_output = 1,
        error_control = 1, singular_term = nothing)
    BVPM2(max_num_subintervals::Int, method_choice::Int, diagnostic_output::Int,
        error_control::Int, singular_term)

Fortran code for solving two-point boundary value problems. For detailed documentation, see
[ODEInterface.jl](https://github.com/luchr/ODEInterface.jl/blob/master/doc/SolverOptions.md#bvpm2).

## Keyword Arguments:

    - `max_num_subintervals`: Number of maximal subintervals, default as 3000.
    - `method_choice`: Choice for IVP-solvers, default as Runge-Kutta method of order 4, available choices:
        - `2`: Runge-Kutta method of order 2.
        - `4`: Runge-Kutta method of order 4.
        - `6`: Runge-Kutta method of order 6.
    - `diagnostic_output`: Diagnostic output for BVPM2, default as non printout, available choices:
        - `-1`: Full diagnostic printout.
        - `0`: Selected printout.
        - `1`: No printout.
    - `error_control`: Determines the error-estimation for which RTOL is used, default as defect control, available choices:
        - `1`: Defect control.
        - `2`: Global error control.
        - `3`: Defect and then global error control.
        - `4`: Linear combination of defect and global error control.
    - `singular_term`: either nothing if the ODEs have no singular terms at the left boundary or a constant (d,d) matrix for the
        singular term.

!!! warning
    Only supports inplace two-point boundary value problems, with very limited forms of
    input structures!

!!! note
    Only available if the `ODEInterface` package is loaded.
"""
Base.@kwdef struct BVPM2{S} <: BoundaryValueDiffEqAlgorithm
    max_num_subintervals::Int = 3000
    method_choice::Int = 4
    diagnostic_output::Int = -1
    error_control::Int = 1
    singular_term::S = nothing
end

"""
    BVPSOL(; bvpclass = 2, sol_method = 0, odesolver = nothing)
    BVPSOL(bvpclass::Int, sol_methods::Int, odesolver)

A FORTRAN77 code which solves highly nonlinear two point boundary value problems using a
local linear solver (condensing algorithm) or a global sparse linear solver for the solution
of the arising linear subproblems, by Peter Deuflhard, Georg Bader, Lutz Weimann.
For detailed documentation, see
[ODEInterface.jl](https://github.com/luchr/ODEInterface.jl/blob/master/doc/SolverOptions.md#bvpsol).

## Keyword Arguments

    - `bvpclass`: Boundary value problem classification, default as highly nonlinear with bad initial data, available choices:
        - `0`: Linear boundary value problem.
        - `1`: Nonlinear with good initial data.
        - `2`: Highly Nonlinear with bad initial data.
        - `3`: Highly nonlinear with bad initial data and initial rank reduction to seperable
            linear boundary conditions.
    - `sol_method`: Switch for solution methods, default as local linear solver with condensing algorithm, available choices:
        - `0`: Use local linear solver with condensing algorithm.
        - `1`: Use global sparse linear solver.
    - `odesolver`: Either `nothing` or ode-solver(dopri5, dop853, seulex, etc.).

!!! warning
    Only supports inplace two-point boundary value problems, with very limited forms of
    input structures!

!!! note
    Only available if the `ODEInterface` package is loaded.
"""
Base.@kwdef struct BVPSOL{O} <: BoundaryValueDiffEqAlgorithm
    bvpclass::Int = 2
    sol_method::Int = 0
    odesolver::O = nothing
end

"""
    COLNEW(; bvpclass = 2, collocationpts = 7, autodiff = :central)
    COLNEW(bvpclass::Int, collocationpts::Int, autodiff)

## Keyword Arguments:

    - `bvpclass`: Boundary value problem classification, default as nonlinear and "extra sensitive", available choices:
        - `0`: Linear boundary value problem.
        - `1`: Nonlinear and regular.
        - `2`: Nonlinear and "extra sensitive" (first relax factor is rstart and the
            nonlinear iteration does not rely on past convergence).
        - `3`: fail-early: return immediately upon:
            (a) two successive non-convergences.
            (b) after obtaining an error estimate for the first time.
    - `collocationpts`: Number of collocation points per subinterval. Require orders[i] ≤ k ≤ 7, default as 7
    - `diagnostic_output`: Diagnostic output for COLNEW, default as no printout, available choices:
        - `-1`: Full diagnostic printout.
        - `0`: Selected printout.
        - `1`: No printout.
    - `max_num_subintervals`: Number of maximal subintervals, default as 3000.

A Fortran77 code solves a multi-points boundary value problems for a mixed order system of ODEs.
It incorporates a new basis representation replacing b-splines, and improvements for
the linear and nonlinear algebraic equation solvers.

!!! warning
    Only supports two-point boundary value problems.

!!! note
    Only available if the `ODEInterface` package is loaded.
"""
Base.@kwdef struct COLNEW <: BoundaryValueDiffEqAlgorithm
    bvpclass::Int = 1
    collocationpts::Int = 7
    diagnostic_output::Int = 1
    max_num_subintervals::Int = 3000
end
