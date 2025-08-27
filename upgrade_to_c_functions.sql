-- Upgrade Script: Replace PL/pgSQL functions with C implementations
-- 
-- This script creates wrapper functions that replace the existing PL/pgSQL
-- implementations with calls to the optimized C functions, maintaining
-- API compatibility while providing significant performance improvements.

\echo 'Upgrading to C-based weighted statistics functions...'

-- Backup existing functions by renaming them
ALTER FUNCTION weighted_mean_sparse(double precision[], double precision[]) 
    RENAME TO weighted_mean_sparse_plpgsql_backup;

ALTER FUNCTION weighted_quantile_sparse(double precision[], double precision[], double precision[]) 
    RENAME TO weighted_quantile_sparse_plpgsql_backup;

-- Create new wrapper functions that call the C implementations
-- These maintain the exact same API as the original PL/pgSQL functions

CREATE OR REPLACE FUNCTION weighted_mean_sparse(
    vals double precision[],
    weights double precision[]
)
RETURNS double precision
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE
AS $$
    SELECT weighted_mean_sparse_c(vals, weights);
$$;

COMMENT ON FUNCTION weighted_mean_sparse(double precision[], double precision[]) IS 
'Optimized C implementation of weighted mean for sparse data. Wrapper for weighted_mean_sparse_c.';

CREATE OR REPLACE FUNCTION weighted_quantile_sparse(
    vals double precision[],
    weights double precision[],
    quantiles double precision[]
)
RETURNS double precision[]
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE
AS $$
    SELECT weighted_quantile_sparse_c(vals, weights, quantiles);
$$;

COMMENT ON FUNCTION weighted_quantile_sparse(double precision[], double precision[], double precision[]) IS 
'Optimized C implementation of weighted quantiles for sparse data. Wrapper for weighted_quantile_sparse_c.';

-- Verify the upgrade was successful
\echo 'Verifying function upgrade...'

-- Test that the upgraded functions work correctly
SELECT 
    'Function upgrade verification' AS test_name,
    weighted_mean_sparse(ARRAY[1.0, 2.0, 3.0], ARRAY[0.1, 0.2, 0.3]) AS mean_result,
    weighted_quantile_sparse(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
                           ARRAY[0.1, 0.2, 0.2, 0.2, 0.1], 
                           ARRAY[0.25, 0.5, 0.75]) AS quantile_result;

\echo 'Function upgrade complete! The existing function names now use optimized C implementations.';
\echo 'Original PL/pgSQL functions have been backed up with _plpgsql_backup suffix.';

-- Optional: Clean up backup functions (uncomment if desired)
-- DROP FUNCTION weighted_mean_sparse_plpgsql_backup(double precision[], double precision[]);
-- DROP FUNCTION weighted_quantile_sparse_plpgsql_backup(double precision[], double precision[], double precision[]);