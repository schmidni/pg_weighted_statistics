-- Weighted Statistics Extension SQL Definition
-- 
-- This extension provides high-performance C implementations of weighted statistics
-- functions optimized for sparse data. All functions handle sparse data where 
-- sum(weights) < 1.0 implies implicit zeros in the dataset.

-- Function: weighted_mean
-- 
-- Calculates weighted mean for sparse data. When sum(weights) < 1.0, implicit
-- zeros with weight (1.0 - sum(weights)) are assumed in the calculation.
--
-- Parameters:
--   vals: Array of values (double precision[])
--   weights: Array of corresponding weights (double precision[])
--
-- Returns: Weighted mean (double precision)
--
CREATE OR REPLACE FUNCTION weighted_mean(
    vals double precision[],
    weights double precision[]
)
RETURNS double precision
AS 'MODULE_PATHNAME', 'weighted_mean_sparse_c'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

-- Function: weighted_quantile
-- 
-- Calculates weighted quantiles for sparse data. When sum(weights) < 1.0, 
-- implicit zeros with weight (1.0 - sum(weights)) are assumed in the calculation.
-- Supports multiple quantiles in a single pass for efficiency.
--
-- Parameters:
--   vals: Array of values (double precision[])
--   weights: Array of corresponding weights (double precision[])
--   quantiles: Array of desired quantiles between 0.0 and 1.0 (double precision[])
--
-- Returns: Array of calculated quantiles (double precision[])
--
CREATE OR REPLACE FUNCTION weighted_quantile(
    vals double precision[],
    weights double precision[],
    quantiles double precision[]
)
RETURNS double precision[]
AS 'MODULE_PATHNAME', 'weighted_quantile_sparse_c'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

-- Convenience function: weighted_median
--
-- Calculates the weighted median (50th percentile) for sparse data.
--
-- Parameters:
--   vals: Array of values (double precision[])
--   weights: Array of corresponding weights (double precision[])
--
-- Returns: Weighted median (double precision)
--
CREATE OR REPLACE FUNCTION weighted_median(
    vals double precision[],
    weights double precision[]
)
RETURNS double precision
AS $$
    SELECT (weighted_quantile(vals, weights, ARRAY[0.5]))[1];
$$ LANGUAGE SQL IMMUTABLE STRICT PARALLEL SAFE;