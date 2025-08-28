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
-- Calculates weighted quantiles for sparse data using simple empirical CDF.
-- When sum(weights) < 1.0, implicit zeros with weight (1.0 - sum(weights)) 
-- are assumed. Supports multiple quantiles in a single pass for efficiency.
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

-- Function: wquantile
-- 
-- Calculates weighted Type 7 quantiles (linear interpolation).
-- Generalizes Hyndman-Fan Type 7 to weighted samples.
--
-- Parameters:
--   vals: Array of values (double precision[])
--   weights: Array of corresponding weights (double precision[])
--   quantiles: Array of desired quantiles between 0.0 and 1.0 (double precision[])
--
-- Returns: Array of calculated quantiles (double precision[])
--
CREATE OR REPLACE FUNCTION wquantile(
    vals double precision[],
    weights double precision[],
    quantiles double precision[]
)
RETURNS double precision[]
AS 'MODULE_PATHNAME', 'wquantile_sparse_c'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

-- Function: whdquantile
-- 
-- Calculates weighted Harrell-Davis quantiles.
-- Uses Beta distribution weights for smoothing over all data points.
--
-- Parameters:
--   vals: Array of values (double precision[])
--   weights: Array of corresponding weights (double precision[])
--   quantiles: Array of desired quantiles between 0.0 and 1.0 (double precision[])
--
-- Returns: Array of calculated quantiles (double precision[])
--
CREATE OR REPLACE FUNCTION whdquantile(
    vals double precision[],
    weights double precision[],
    quantiles double precision[]
)
RETURNS double precision[]
AS 'MODULE_PATHNAME', 'whdquantile_sparse_c'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

-- Function: weighted_variance
-- 
-- Calculates weighted variance for sparse data.
-- When sum(weights) < 1.0, implicit zeros are assumed.
--
-- Parameters:
--   vals: Array of values (double precision[])
--   weights: Array of corresponding weights (double precision[])
--   ddof: Delta degrees of freedom (integer, default 0)
--         0 = population variance, 1 = sample variance with Bessel's correction
--
-- Returns: Weighted variance (double precision)
--
CREATE OR REPLACE FUNCTION weighted_variance(
    vals double precision[],
    weights double precision[],
    ddof integer DEFAULT 0
)
RETURNS double precision
AS 'MODULE_PATHNAME', 'weighted_variance_sparse_c'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- Function: weighted_std
-- 
-- Calculates weighted standard deviation for sparse data.
-- When sum(weights) < 1.0, implicit zeros are assumed.
--
-- Parameters:
--   vals: Array of values (double precision[])
--   weights: Array of corresponding weights (double precision[])
--   ddof: Delta degrees of freedom (integer, default 0)
--         0 = population std dev, 1 = sample std dev with Bessel's correction
--
-- Returns: Weighted standard deviation (double precision)
--
CREATE OR REPLACE FUNCTION weighted_std(
    vals double precision[],
    weights double precision[],
    ddof integer DEFAULT 0
)
RETURNS double precision
AS 'MODULE_PATHNAME', 'weighted_std_sparse_c'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

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