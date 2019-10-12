# Code for contracting two arrays, both for general AbstractArrays as well as
# for SymArrays.
# we only have a few specialized functions that we have needed up to now
# but carefully optimize each of them

using TensorOperations
using CuArrays
using LinearAlgebra

# Array[i]*SymArray[(i,j,k)]
# indices 1, 2, and 3 are exchangeable here
function contract(A::Vector{T},S::SymArray{U,3,(3,)},n::Union{Val{1},Val{2},Val{3}}) where {T,U}
    TU = promote_type(T,U)
    @assert size(S,1) == length(A)
    res = SymArray{TU,2,(2,)}(size(S,1),size(S,2))
    contract!(res,A,S,n)
end

# We know that $j\leq k$ (because $R$ is itself exchange symmetric)
# \begin{align}
# R_{jk} &= \sum_{i=1}^N g_i S_{ijk}
# \end{align}

# Matrix elements represented by $S_{ijk}$:
# \begin{equation}
# \begin{cases}
# S_{ijk}, S_{ikj}, S_{jik}, S_{jki}, S_{kij}, S_{kji} & i<j<k\\
# S_{ijk}, S_{jik}, S_{jki} & i<j=k\\
# S_{ijk}, S_{ikj}, S_{kij} & i=j<k\\
# S_{ijk} & i=j=k
# \end{cases}
# \end{equation}
# We only need to take the contributions that show up for each $R_{jk}$

# Array[i]*SymArray[(i,j,k)]
# indices 1, 2, and 3 are exchangeable here
function contract!(res::SymArray{TU,2,(2,)}, A::Vector{T}, S::SymArray{U,3,(3,)}, n::Union{Val{1},Val{2},Val{3}}) where {T,U,TU}
    # only loop over S once, and put all the values where they should go
    # R[j,k] = sum_i A[i] B[i,j,k]
    # S[i,j,k] with i<=j<=k represents the 6 (not always distinct) terms: Bijk, Bikj, Bjik, Bjki, Bkij, Bkji
    # since R[j,k] is also exchange symmetric, we only need to calculate j<=k
    # commented out terms below are the ones where j>k
    @assert size(S,1) == length(A)
    @assert size(S,1) == size(res,1)
    res.data .= 0
    @inbounds for (v,inds) in zip(S.data,CartesianIndices(S))
        i,j,k = Tuple(inds)
        res[j,k] += v*A[i]
        if i==j==k
            continue
        elseif i==j # i=j < k
            # exch. terms: Sikj and Skij
            # res[k,j] += v*A[i] i2>i3
            res[i,j] += v*A[k]
        elseif j==k # i < j=k
            # exch. terms Sjik, Sjki
            res[i,k] += v*A[j]
            # res[k,i] += v*A[j] i3>i2
        else # i<j<k
            # exch. terms Sikj, Sjik, Sjki, Skij, Skji
            # res[k,j] += v*A[i] i3>i2
            res[i,k] += v*A[j]
            # res[k,i] += v*A[j] i3>i2
            res[i,j] += v*A[k]
            # res[j,i] += v*A[k] i3>i2
        end
    end
    res
end

# Array[k]*SymArray[(i,j),k]
function contract(A::Vector{T},S::SymArray{U,3,(2,1)},n::Val{3}) where {T,U}
    TU = promote_type(T,U)
    sumsize = length(A)
    @assert sumsize == size(S,3)
    res = SymArray{TU,2,(2,)}(size(S,1),size(S,2))
    contract!(res,A,S,n)
end

# Array[k]*SymArray[(i,j),k]
function contract!(res::SymArray{TU,2,(2,)},A::Vector{T},S::SymArray{U,3,(2,1)},::Val{3}) where {T,U,TU}
    # use that S[(i,j),k] == S[I,k] (i.e., the two symmetric indices act like a "big" index)
    mul!(res.data,reshape(S.data,:,length(A)),A)
    res
end

# Array[i]*SymArray[(i,j),k)]
# since indices 1 and 2 are exchangeable here, use this
function contract(A::Vector{T},S::SymArray{U,3,(2,1)},n::Union{Val{1},Val{2}}) where {T,U}
    TU = promote_type(T,U)
    @assert size(S,1) == length(A)
    # the result is a normal 2D array
    res = Array{TU,2}(undef,size(S,2),size(S,3))
    contract!(res,A,S,n)
end

# Array[i]*SymArray[(i,j),k]
# since indices 1 and 2 are exchangeable here, use this
function contract!(res::Array{TU,2},A::Vector{T},S::SymArray{U,3,(2,1)},::Union{Val{1},Val{2}}) where {T,U,TU}
    # only loop over S once, and put all the values where they should go
    @assert size(A,1) == size(S,1)
    @assert size(res,1) == size(S,1)
    @assert size(res,2) == size(S,3)
    res .= zero(TU)
    @inbounds for (v,inds) in zip(S.data,CartesianIndices(S))
        i1,i2,i3 = Tuple(inds)
        res[i2,i3] += v*A[i1]
        # if i1 != i2, we have to add the equal contribution from S[i2,i1,i3]
        if i1 != i2
            res[i1,i3] += v*A[i2]
        end
    end
    res
end

# Array[i]*SymArray[(i,j)]
# this is symmetric in i1 and i2
function contract!(res::Array{TU,1},A::Vector{T},S::SymArray{U,2,(2,)},::Union{Val{1},Val{2}}) where {T,U,TU}
    @assert size(A,1) == size(S,1)
    @assert size(res,1) == size(S,1)
    res .= zero(TU)
    # only loop over S once, and put all the values where they should go
    for (v,inds) in zip(S.data,CartesianIndices(S))
        i1,i2 = Tuple(inds)
        res[i2] += v*A[i1]
        # if i1 != i2, we have to add the contribution from S[i2,i1]
        if i1 != i2
            res[i1] += v*A[i2]
        end
    end
    res
end

# Array[i_n]*Array[i1,i2,i3,...,iN]
function contract(A::AbstractVector{T},B::AbstractArray{U,N},::Val{n}) where {T,U,N,n}
    TU = promote_type(T,U)
    @assert 1 <= n <= N
    
    resdims = size(B)[1:N .!= n]
    res = similar(B,TU,resdims)

    contract!(res,A,B,Val{n}())
end

# Array[i_n]*Array[i1,i2,i3,...,iN]
function contract!(res::AbstractArray{TU},A::AbstractVector{TU},B::AbstractArray{TU,N},::Val{n}) where {TU,N,n}
    mygemv! = res isa CuArray ? CuArrays.CUBLAS.gemv! : BLAS.gemv!
    nsum = length(A)
    @assert size(B,n) == nsum
    @assert ndims(res)+1 == ndims(B)
    ii = 0
    for jj = 1:ndims(B)
        jj==n && continue
        ii += 1
        @assert size(B,jj) == size(res,ii)
    end
    
    if n==1      # A[i]*B[i,...]
        mygemv!('T',one(TU),reshape(B,nsum,:),A,zero(TU),vec(res))
    elseif n==N  # B[...,i]*A[i]
        mygemv!('N',one(TU),reshape(B,:,nsum),A,zero(TU),vec(res))
    else
        rightsize = prod(size(B,i) for i=n+1:N)
        Br = reshape(B,:,nsum,rightsize)
        resr = reshape(res,:,rightsize)
        if res isa CuArray
            @tensor resr[i,k] = Br[i,j,k] * A[j]
        else
            @inbounds for k=1:size(Br,3)
                mul!(@view(resr[:,k]), @view(Br[:,:,k]), A)
            end
        end
    end
    res
end
