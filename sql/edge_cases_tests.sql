-- Edge cases tests for weighted_statistics extension
-- 
-- Tests robust handling of corner cases, edge conditions, and error scenarios

-- =============================================================================
-- NULL AND EMPTY ARRAY HANDLING
-- =============================================================================

-- Test 1: NULL values handling for weighted_mean
SELECT 
    'NULL values weighted_mean' AS test_name,
    weighted_mean(NULL, ARRAY[0.1, 0.2, 0.3]) AS null_values,
    weighted_mean(ARRAY[1.0, 2.0, 3.0], NULL) AS null_weights,
    weighted_mean(NULL, NULL) AS both_null;

-- Test 2: NULL handling for quantile functions
SELECT 
    'NULL handling quantiles' AS test_name,
    weighted_quantile(NULL, NULL, ARRAY[0.5]) AS quantile_null,
    wquantile(NULL, NULL, ARRAY[0.5]) AS wquantile_null,
    whdquantile(NULL, NULL, ARRAY[0.5]) AS whdquantile_null;

-- Test 3: NULL handling for variance/std
SELECT 
    'NULL handling variance/std' AS test_name,
    weighted_variance(NULL, NULL, 0) AS variance_null,
    weighted_std(NULL, NULL, 0) AS std_null;

-- =============================================================================
-- ZERO WEIGHTS HANDLING
-- =============================================================================

-- Test 4: All zero weights
SELECT 
    'All zero weights mean' AS test_name,
    weighted_mean(ARRAY[1.0, 2.0, 3.0], ARRAY[0.0, 0.0, 0.0]) AS result;

-- Test 5: Mixed zero weights
SELECT 
    'Mixed zero weights mean' AS test_name,
    weighted_mean(ARRAY[1.0, 2.0, 3.0, 4.0], ARRAY[0.5, 0.0, 0.3, 0.0]) AS result;

-- Test 6: Zero weights for quantiles
SELECT 
    'Zero weights quantiles' AS test_name,
    weighted_quantile(ARRAY[1.0, 2.0, 3.0], ARRAY[0.0, 0.0, 0.0], ARRAY[0.5]) AS result;

-- =============================================================================
-- SINGLE VALUE ARRAYS
-- =============================================================================

-- Test 7: Single value tests for all functions
SELECT 
    'Single value all functions' AS test_name,
    weighted_mean(ARRAY[42.0], ARRAY[0.7]) AS mean_result,
    weighted_quantile(ARRAY[42.0], ARRAY[0.7], ARRAY[0.25, 0.5, 0.75]) AS quantile_result,
    wquantile(ARRAY[42.0], ARRAY[0.7], ARRAY[0.5]) AS wquantile_result,
    whdquantile(ARRAY[42.0], ARRAY[0.7], ARRAY[0.5]) AS whdquantile_result,
    weighted_variance(ARRAY[42.0], ARRAY[0.7], 0) AS variance_result,
    weighted_std(ARRAY[42.0], ARRAY[0.7], 0) AS std_result;

-- =============================================================================
-- EXTREME DDOF VALUES
-- =============================================================================

-- Test 8: High ddof values (should return NULL for insufficient degrees of freedom)
SELECT 
    'High ddof variance' AS test_name,
    weighted_variance(ARRAY[1.0, 2.0], ARRAY[0.5, 0.5], 5) AS variance_high_ddof,
    weighted_std(ARRAY[1.0, 2.0], ARRAY[0.5, 0.5], 5) AS std_high_ddof,
    'Should be NULL due to insufficient degrees of freedom' AS expected;

-- Test 9: ddof equal to effective sample size
WITH effective_n_test AS (
    SELECT 
        ARRAY[1.0, 2.0, 3.0] AS vals,
        ARRAY[0.6, 0.3, 0.1] AS weights
)
SELECT 
    'ddof at boundary' AS test_name,
    weighted_variance(vals, weights, 2) AS variance_boundary,
    weighted_std(vals, weights, 2) AS std_boundary,
    'May be NULL or very large due to n_eff - ddof approaching zero' AS expected
FROM effective_n_test;

-- =============================================================================
-- BOUNDARY QUANTILE VALUES
-- =============================================================================

-- Test 10: Extreme quantile values
SELECT 
    'Extreme quantiles' AS test_name,
    weighted_quantile(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
                      ARRAY[0.2, 0.2, 0.2, 0.2, 0.2], 
                      ARRAY[0.001, 0.999]) AS result,
    'Should be close to min and max values' AS expected;

-- Test 11: Invalid quantile values (should still work within PostgreSQL's bounds)
SELECT 
    'Boundary quantile handling' AS test_name,
    weighted_quantile(ARRAY[10.0, 20.0, 30.0], 
                      ARRAY[0.3, 0.4, 0.3], 
                      ARRAY[0.0, 0.5, 1.0]) AS result;

-- =============================================================================
-- VERY SPARSE DATA
-- =============================================================================

-- Test 12: Extremely sparse data (very low weight sum)
SELECT 
    'Extremely sparse data' AS test_name,
    weighted_mean(ARRAY[1000.0], ARRAY[0.001]) AS sparse_mean,
    weighted_variance(ARRAY[1000.0], ARRAY[0.001], 0) AS sparse_variance,
    weighted_quantile(ARRAY[1000.0], ARRAY[0.001], ARRAY[0.5]) AS sparse_quantile;

-- =============================================================================
-- PRECISION AND EXTREME VALUES
-- =============================================================================

-- Test 13: Very small weights precision
SELECT 
    'Small weights precision' AS test_name,
    weighted_mean(ARRAY[1000.0, 2000.0], ARRAY[1e-10, 2e-10]) AS result,
    'Should handle very small weights without overflow' AS expected;

-- Test 14: Large values stability
SELECT 
    'Large values stability' AS test_name,
    weighted_mean(ARRAY[1e6, 2e6, 3e6], ARRAY[0.3, 0.3, 0.4]) AS large_mean,
    weighted_variance(ARRAY[1e6, 2e6, 3e6], ARRAY[0.3, 0.3, 0.4], 0) AS large_variance;

-- Test 15: Extreme value ranges
SELECT 
    'Extreme value ranges' AS test_name,
    weighted_mean(ARRAY[1e-10, 1e10], ARRAY[0.4, 0.6]) AS extreme_range_mean,
    weighted_variance(ARRAY[1e-10, 1e10], ARRAY[0.4, 0.6], 0) AS extreme_range_variance;

-- =============================================================================
-- NEGATIVE VALUES
-- =============================================================================

-- Test 16: Negative values support
SELECT 
    'Negative values support' AS test_name,
    weighted_mean(ARRAY[-10.0, 0.0, 10.0], ARRAY[0.25, 0.5, 0.25]) AS negative_mean,
    weighted_variance(ARRAY[-10.0, 0.0, 10.0], ARRAY[0.25, 0.5, 0.25], 0) AS negative_variance,
    weighted_quantile(ARRAY[-10.0, 0.0, 10.0], ARRAY[0.25, 0.5, 0.25], ARRAY[0.5]) AS negative_quantile;

-- Test 17: All negative values
SELECT 
    'All negative values' AS test_name,
    weighted_mean(ARRAY[-5.0, -2.0, -1.0], ARRAY[0.3, 0.3, 0.4]) AS all_negative_mean,
    weighted_std(ARRAY[-5.0, -2.0, -1.0], ARRAY[0.3, 0.3, 0.4], 0) AS all_negative_std;

-- =============================================================================
-- ARRAY LENGTH MISMATCHES (Error conditions)
-- =============================================================================

-- Note: These tests expect PostgreSQL to raise errors, but we include them
-- to document expected behavior

-- Test 18: Mismatched array lengths (This should generate an error in practice)
-- SELECT 
--     'Mismatched array lengths' AS test_name,
--     weighted_mean(ARRAY[1.0, 2.0], ARRAY[0.5, 0.3, 0.2]) AS result;

-- =============================================================================
-- IDENTICAL VALUES WITH DIFFERENT WEIGHTS
-- =============================================================================

-- Test 19: Identical values, different weights (should have zero variance)
SELECT 
    'Identical values different weights' AS test_name,
    weighted_mean(ARRAY[5.0, 5.0, 5.0], ARRAY[0.1, 0.2, 0.3]) AS identical_mean,
    weighted_variance(ARRAY[5.0, 5.0, 5.0], ARRAY[0.1, 0.2, 0.3], 0) AS identical_variance,
    weighted_std(ARRAY[5.0, 5.0, 5.0], ARRAY[0.1, 0.2, 0.3], 0) AS identical_std,
    'Mean should be 5.0, variance and std should be 0' AS expected;

-- =============================================================================
-- UNSORTED INPUT DATA
-- =============================================================================

-- Test 20: Unsorted input data (algorithms should handle this correctly)
SELECT 
    'Unsorted input robustness' AS test_name,
    weighted_mean(ARRAY[5.0, 1.0, 3.0, 2.0, 4.0], ARRAY[0.1, 0.3, 0.2, 0.2, 0.2]) AS unsorted_mean,
    weighted_quantile(ARRAY[5.0, 1.0, 3.0, 2.0, 4.0], ARRAY[0.1, 0.3, 0.2, 0.2, 0.2], ARRAY[0.5]) AS unsorted_quantile;

-- =============================================================================
-- VERY LARGE ARRAYS (Memory and performance edge case)
-- =============================================================================

-- Test 21: Reasonably large arrays to test memory handling
WITH large_test AS (
    SELECT 
        array_agg(i * 1.0) AS vals,
        array_agg(1.0 / 500) AS weights
    FROM generate_series(1, 500) AS t(i)
)
SELECT 
    'Large array handling' AS test_name,
    round(weighted_mean(vals, weights)::numeric, 2) AS large_mean,
    round(weighted_std(vals, weights, 0)::numeric, 2) AS large_std,
    array_length(vals, 1) AS array_size
FROM large_test;