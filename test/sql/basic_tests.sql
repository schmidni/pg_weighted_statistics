-- Basic functionality tests for weighted_statistics extension
-- 
-- Tests basic operations and edge cases for weighted mean and quantile functions

-- Test 1: Basic weighted mean
SELECT 
    'Basic weighted mean' AS test_name,
    weighted_mean(ARRAY[1.0, 2.0, 3.0], ARRAY[0.1, 0.2, 0.3]) AS result,
    1.4 AS expected_result;

-- Test 2: Sparse data weighted mean (sum of weights < 1.0)
SELECT 
    'Sparse weighted mean' AS test_name,
    weighted_mean(ARRAY[5.0, 10.0], ARRAY[0.2, 0.3]) AS result,
    4.0 AS expected_result;

-- Test 3: Single value weighted mean
SELECT 
    'Single value weighted mean' AS test_name,
    weighted_mean(ARRAY[7.5], ARRAY[0.4]) AS result,
    3.0 AS expected_result;

-- Test 4: Zero weights weighted mean
SELECT 
    'Zero weights weighted mean' AS test_name,
    weighted_mean(ARRAY[1.0, 2.0, 3.0], ARRAY[0.0, 0.0, 0.0]) AS result,
    0.0 AS expected_result;

-- Test 5: NULL handling for weighted mean
SELECT 
    'NULL weighted mean' AS test_name,
    weighted_mean(NULL, ARRAY[0.1, 0.2, 0.3]) AS result,
    0.0 AS expected_result;

-- Test 6: Basic weighted quantiles
SELECT 
    'Basic weighted quantiles' AS test_name,
    weighted_quantile(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
                      ARRAY[0.1, 0.2, 0.3, 0.2, 0.1], 
                      ARRAY[0.1, 0.5, 0.9]) AS result;

-- Test 7: Sparse data quantiles
SELECT 
    'Sparse weighted quantiles' AS test_name,
    weighted_quantile(ARRAY[10.0, 20.0], 
                      ARRAY[0.3, 0.2], 
                      ARRAY[0.25, 0.5, 0.75]) AS result;

-- Test 8: Median convenience function
SELECT 
    'Weighted median' AS test_name,
    weighted_median(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
                    ARRAY[0.1, 0.2, 0.4, 0.2, 0.1]) AS result;

-- Test 9: Edge case - single quantile
SELECT 
    'Single quantile' AS test_name,
    weighted_quantile(ARRAY[1.0, 2.0, 3.0], 
                      ARRAY[0.3, 0.3, 0.3], 
                      ARRAY[0.5]) AS result;

-- Test 10: Edge case - boundary quantiles
SELECT 
    'Boundary quantiles' AS test_name,
    weighted_quantile(ARRAY[1.0, 2.0, 3.0, 4.0], 
                      ARRAY[0.25, 0.25, 0.25, 0.25], 
                      ARRAY[0.0, 1.0]) AS result;