-- REIA Weighted Statistics C Extension SQL Definition
-- 
-- This file defines the SQL interface to the C functions for weighted
-- statistics on sparse data.

-- Function: weighted_mean_sparse_c
-- 
-- C implementation of weighted mean for sparse data where sum(weights) < 1.0
-- implies implicit zeros in the dataset.
--
CREATE OR REPLACE FUNCTION weighted_mean_sparse_c(
    vals double precision[],
    weights double precision[]
)
RETURNS double precision
AS 'MODULE_PATHNAME', 'weighted_mean_sparse_c'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

-- Function: weighted_quantile_sparse_c
-- 
-- C implementation of weighted quantiles for sparse data where sum(weights) < 1.0
-- implies implicit zeros. Supports multiple quantiles in a single pass.
--
CREATE OR REPLACE FUNCTION weighted_quantile_sparse_c(
    vals double precision[],
    weights double precision[],
    quantiles double precision[]
)
RETURNS double precision[]
AS 'MODULE_PATHNAME', 'weighted_quantile_sparse_c'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;