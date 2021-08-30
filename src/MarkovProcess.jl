
abstract type MarkovProcess end
# This type sould define generator(), which is a transition matrix 𝕋 such that
# 𝕋f = lim_{t→0} E[f(x_t)|x_0=x]/t

"""
 computes the stationary distribution corresponding to the MarkovProcess X
"""
function stationary_distribution(X::MarkovProcess; δ = 0.0, ψ = Zeros(length(X.x)))
    δ >= 0 ||  throw(ArgumentError("δ needs to be positive"))
    if δ > 0
        g = abs.((δ * I - generator(X)') \ (δ * ψ))
    else
        η, g = principal_eigenvalue(generator(X)')
        abs(η) <= 1e-5 || @warn "Principal Eigenvalue does not seem to be zero"
    end
    g ./ sum(g)
end


#========================================================================================

Application for Diffusion Process x_t defined by:
dx = μ(x) dt + σ(x) dZ_t

========================================================================================#

mutable struct DiffusionProcess <: MarkovProcess
    x::AbstractVector{<:Real}
    μx::AbstractVector{<:Real}
    σx::AbstractVector{<:Real}
    function DiffusionProcess(x::AbstractVector{<:Real}, μx::AbstractVector{<:Real}, σx::AbstractVector{<:Real})
        length(x) == length(μx) == length(σx) || throw(ArgumentError("Vector for grid, drift, and volatility should have the same size"))
        new(x, μx, σx)
    end
end


state_space(X::DiffusionProcess) = X.x

function generator(X::DiffusionProcess) 
    generator(X.x, Zeros(length(X.x)), X.μx, X.σx)
end

# create operator associated with f ⭌ v * f + μx * ∂f + 0.5 * σx^2 * ∂^2f
function generator(x::AbstractVector, v::AbstractVector, μx::AbstractVector, σx::AbstractVector)
    # The key is that sum of each row = 0.0 and off diagonals are positive
    n = length(x)
    𝕋 = Tridiagonal(zeros(n-1), zeros(n), zeros(n-1))
    @inbounds for i in 1:n
        Δxp =x[min(i, n-1)+1] - x[min(i, n-1)]
        Δxm = x[max(i-1, 1) + 1] - x[max(i-1, 1)]
        Δx = (Δxm + Δxp) / 2
        # upwinding to ensure off diagonals are posititive
        if μx[i] >= 0
            𝕋[i, min(i + 1, n)] += μx[i] / Δxp
            𝕋[i, i] -= μx[i] / Δxp
        else
            𝕋[i, i] += μx[i] / Δxm
            𝕋[i, max(i - 1, 1)] -= μx[i] / Δxm
        end
        𝕋[i, max(i - 1, 1)] += 0.5 * σx[i]^2 / (Δxm * Δx)
        𝕋[i, i] -= 0.5 * σx[i]^2 * 2 / (Δxm * Δxp)
        𝕋[i, min(i + 1, n)] += 0.5 * σx[i]^2 / (Δxp * Δx)
    end
    # ensure machine precision
    c = sum(𝕋, dims = 2)
    for i in 1:n
        𝕋[i, i] += v[i] - c[i]
    end
    return 𝕋
end

# create operator associated with f ⭌ ∂f using upwinding w.r.t. μx
function ∂(X::DiffusionProcess)
    Diagonal(X.μx) \ generator(X.x, Zeros(length(X.x)), X.μx, Zeros(length(X.x)))
end

# Special Diffusion Processes
# it's important to take low p to have the right tail index of Additive functional (see tests)
function OrnsteinUhlenbeck(; xbar = 0.0, κ = 0.1, σ = 1.0, p = 1e-10, length = 100, 
    xmin = quantile(Normal(xbar, σ / sqrt(2 * κ)), p), xmax = quantile(Normal(xbar, σ / sqrt(2 * κ)), 1 - p))
    if xmin > 0
        x = range(xmin^(1/pow), stop = xmax^(1/pow), length = length).^pow
    else
        x = range(xmin, stop = xmax, length = length)
    end
    DiffusionProcess(x, κ .* (xbar .- x), σ * Ones(Base.length(x)))
end

function CoxIngersollRoss(; xbar = 0.1, κ = 0.1, σ = 1.0, p = 1e-10, length = 100, α = 2 * κ * xbar / σ^2, β = σ^2 / (2 * κ), xmin = quantile(Gamma(α, β), p), xmax = quantile(Gamma(α, β), 1 - p), pow = 2)
    # check 0 is not attainable
    @assert (2 * κ * xbar) / σ^2 > 1
    x = range(xmin^(1/pow), stop = xmax^(1/pow), length = length).^pow
    DiffusionProcess(x, κ .* (xbar .- x), σ .* sqrt.(x))
end
