-- Functionality tests for weighted_statistics extension
-- 
-- Tests core functionality for all weighted statistics functions

-- =============================================================================
-- WEIGHTED MEAN TESTS
-- =============================================================================

-- Test 1: Basic weighted mean
SELECT 
    'Basic weighted mean' AS test_name,
    weighted_mean(ARRAY[1.0, 2.0, 3.0], ARRAY[0.1, 0.2, 0.3]) AS result;

-- Test 2: Sparse data weighted mean (sum of weights < 1.0)
SELECT 
    'Sparse weighted mean' AS test_name,
    weighted_mean(ARRAY[5.0, 10.0], ARRAY[0.2, 0.3]) AS result;

-- Test 3: Full weight weighted mean (sum = 1.0)
SELECT 
    'Full weight weighted mean' AS test_name,
    weighted_mean(ARRAY[1.0, 2.0, 3.0], ARRAY[0.2, 0.3, 0.5]) AS result;

-- Test 4: Single value weighted mean
SELECT 
    'Single value weighted mean' AS test_name,
    weighted_mean(ARRAY[7.5], ARRAY[0.4]) AS result;

-- =============================================================================
-- WEIGHTED QUANTILE TESTS (Simple empirical CDF)
-- =============================================================================

-- Test 5: Basic weighted quantiles
SELECT 
    'Basic weighted quantiles' AS test_name,
    weighted_quantile(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
                      ARRAY[0.1, 0.2, 0.3, 0.2, 0.2], 
                      ARRAY[0.25, 0.5, 0.75]) AS result;

-- Test 6: Sparse data quantiles
SELECT 
    'Sparse weighted quantiles' AS test_name,
    weighted_quantile(ARRAY[10.0, 20.0], 
                      ARRAY[0.3, 0.2], 
                      ARRAY[0.25, 0.5, 0.75]) AS result;

-- Test 7: Single quantile
SELECT 
    'Single quantile' AS test_name,
    weighted_quantile(ARRAY[1.0, 2.0, 3.0], 
                      ARRAY[0.3, 0.3, 0.3], 
                      ARRAY[0.5]) AS result;

-- Test 8: Boundary quantiles
SELECT 
    'Boundary quantiles' AS test_name,
    weighted_quantile(ARRAY[1.0, 2.0, 3.0, 4.0], 
                      ARRAY[0.25, 0.25, 0.25, 0.25], 
                      ARRAY[0.0, 1.0]) AS result;

-- =============================================================================
-- WQUANTILE TESTS (Type 7 / Hyndman-Fan)
-- =============================================================================

-- Test 9: Basic wquantile
SELECT 
    'Basic wquantile (Type 7)' AS test_name,
    wquantile(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
              ARRAY[0.1, 0.2, 0.3, 0.2, 0.2], 
              ARRAY[0.25, 0.5, 0.75]) AS result;

-- Test 10: Sparse wquantile
SELECT 
    'Sparse wquantile' AS test_name,
    wquantile(ARRAY[10.0, 20.0], 
              ARRAY[0.3, 0.2], 
              ARRAY[0.25, 0.5, 0.75]) AS result;

-- =============================================================================
-- WHDQUANTILE TESTS (Harrell-Davis)
-- =============================================================================

-- Test 11: Basic whdquantile
SELECT 
    'Basic whdquantile (Harrell-Davis)' AS test_name,
    whdquantile(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
                ARRAY[0.1, 0.2, 0.3, 0.2, 0.2], 
                ARRAY[0.25, 0.5, 0.75]) AS result;

-- Test 12: Sparse whdquantile
SELECT 
    'Sparse whdquantile' AS test_name,
    whdquantile(ARRAY[10.0, 20.0], 
                ARRAY[0.3, 0.2], 
                ARRAY[0.25, 0.5, 0.75]) AS result;

-- =============================================================================
-- WEIGHTED MEDIAN TESTS
-- =============================================================================

-- Test 13: Basic weighted median
SELECT 
    'Basic weighted median' AS test_name,
    weighted_median(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
                    ARRAY[0.1, 0.2, 0.4, 0.2, 0.1]) AS result;

-- Test 14: Sparse weighted median
SELECT 
    'Sparse weighted median' AS test_name,
    weighted_median(ARRAY[5.0, 15.0], ARRAY[0.3, 0.2]) AS result;

-- =============================================================================
-- WEIGHTED VARIANCE TESTS
-- =============================================================================

-- Test 15: Population variance (ddof=0)
SELECT 
    'Population variance (ddof=0)' AS test_name,
    weighted_variance(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
                      ARRAY[0.2, 0.2, 0.2, 0.2, 0.2], 
                      0) AS result;

-- Test 16: Sample variance (ddof=1)
SELECT 
    'Sample variance (ddof=1)' AS test_name,
    weighted_variance(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
                      ARRAY[0.2, 0.2, 0.2, 0.2, 0.2], 
                      1) AS result;

-- Test 17: Sparse data variance
SELECT 
    'Sparse data variance' AS test_name,
    weighted_variance(ARRAY[10.0, 20.0], 
                      ARRAY[0.3, 0.2], 
                      0) AS result;

-- Test 18: Default ddof (should be 0)
SELECT 
    'Default ddof variance' AS test_name,
    weighted_variance(ARRAY[1.0, 2.0, 3.0], 
                      ARRAY[0.3, 0.3, 0.3]) AS result;

-- =============================================================================
-- WEIGHTED STANDARD DEVIATION TESTS
-- =============================================================================

-- Test 19: Population std dev (ddof=0)
SELECT 
    'Population std dev (ddof=0)' AS test_name,
    weighted_std(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
                 ARRAY[0.2, 0.2, 0.2, 0.2, 0.2], 
                 0) AS result;

-- Test 20: Sample std dev (ddof=1)
SELECT 
    'Sample std dev (ddof=1)' AS test_name,
    weighted_std(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
                 ARRAY[0.2, 0.2, 0.2, 0.2, 0.2], 
                 1) AS result;

-- Test 21: Sparse data std dev
SELECT 
    'Sparse data std dev' AS test_name,
    weighted_std(ARRAY[10.0, 20.0], 
                 ARRAY[0.3, 0.2], 
                 0) AS result;

-- Test 22: Default ddof std dev
SELECT 
    'Default ddof std dev' AS test_name,
    weighted_std(ARRAY[1.0, 2.0, 3.0], 
                 ARRAY[0.3, 0.3, 0.3]) AS result;

-- =============================================================================
-- MIXED FUNCTION COMPARISON TESTS
-- =============================================================================

-- Test 23: Compare all quantile methods on same data
WITH test_data AS (
    SELECT 
        ARRAY[1.0, 2.0, 3.0, 4.0, 5.0] AS vals,
        ARRAY[0.1, 0.2, 0.4, 0.2, 0.1] AS weights,
        ARRAY[0.5] AS quantiles
)
SELECT 
    'Quantile methods comparison (median)' AS test_name,
    weighted_quantile(vals, weights, quantiles) AS empirical_cdf,
    wquantile(vals, weights, quantiles) AS type7,
    whdquantile(vals, weights, quantiles) AS harrell_davis,
    ARRAY[weighted_median(vals, weights)] AS median_func
FROM test_data;

-- Test 24: Variance and std consistency (std should equal sqrt(variance))
WITH variance_test AS (
    SELECT 
        ARRAY[2.0, 4.0, 6.0, 8.0] AS vals,
        ARRAY[0.25, 0.25, 0.25, 0.25] AS weights
)
SELECT 
    'Variance-std consistency' AS test_name,
    weighted_variance(vals, weights, 0) AS variance_result,
    weighted_std(vals, weights, 0) AS std_result,
    sqrt(weighted_variance(vals, weights, 0)) AS sqrt_variance,
    abs(weighted_std(vals, weights, 0) - sqrt(weighted_variance(vals, weights, 0))) < 1e-10 AS consistent
FROM variance_test;