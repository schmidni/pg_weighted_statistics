-- Mathematical accuracy tests for weighted_statistics extension
-- 
-- Validates mathematical correctness by comparing results against known values
-- and checking mathematical properties

-- Test 1: Known weighted mean calculations
SELECT 
    'Known weighted mean 1' AS test_name,
    weighted_mean(ARRAY[1.0, 2.0, 3.0], ARRAY[0.5, 0.3, 0.2]) AS result,
    1.7 AS expected_result,
    abs(weighted_mean(ARRAY[1.0, 2.0, 3.0], ARRAY[0.5, 0.3, 0.2]) - 1.7) < 1e-10 AS accurate;

-- Test 2: Sparse data mathematical correctness
-- Values [10, 20] with weights [0.3, 0.2] should give: (10*0.3 + 20*0.2 + 0*0.5) = 7.0
SELECT 
    'Sparse weighted mean accuracy' AS test_name,
    weighted_mean(ARRAY[10.0, 20.0], ARRAY[0.3, 0.2]) AS result,
    7.0 AS expected_result,
    abs(weighted_mean(ARRAY[10.0, 20.0], ARRAY[0.3, 0.2]) - 7.0) < 1e-10 AS accurate;

-- Test 3: Property - weighted mean should be bounded by min/max values when sum(weights) = 1.0
WITH test_values AS (
    SELECT weighted_mean(ARRAY[5.0, 15.0, 25.0], ARRAY[0.3, 0.4, 0.3]) AS wmean
)
SELECT 
    'Bounded mean property (full weights)' AS test_name,
    wmean,
    wmean >= 5.0 AND wmean <= 25.0 AS within_bounds
FROM test_values;

-- Test 4: Property - weighted mean with sparse data should account for implicit zeros
WITH test_values AS (
    SELECT weighted_mean(ARRAY[10.0, 20.0], ARRAY[0.2, 0.3]) AS wmean
)
SELECT 
    'Sparse data bounds property' AS test_name,
    wmean,
    wmean >= 0.0 AND wmean <= 20.0 AS within_bounds
FROM test_values;

-- Test 5: Quantile accuracy - median of symmetric distribution
SELECT 
    'Symmetric median' AS test_name,
    (weighted_quantile(ARRAY[1.0, 2.0, 3.0], ARRAY[0.33, 0.34, 0.33], ARRAY[0.5]))[1] AS result,
    abs((weighted_quantile(ARRAY[1.0, 2.0, 3.0], ARRAY[0.33, 0.34, 0.33], ARRAY[0.5]))[1] - 2.0) < 0.1 AS accurate;

-- Test 6: Quantile properties - monotonicity
WITH quantile_results AS (
    SELECT weighted_quantile(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
                           ARRAY[0.2, 0.2, 0.2, 0.2, 0.2], 
                           ARRAY[0.1, 0.3, 0.5, 0.7, 0.9]) AS q
)
SELECT 
    'Quantile monotonicity' AS test_name,
    q,
    (q[1] <= q[2] AND q[2] <= q[3] AND q[3] <= q[4] AND q[4] <= q[5]) AS monotonic
FROM quantile_results;

-- Test 7: Quantile boundary conditions
SELECT 
    'Quantile boundaries' AS test_name,
    weighted_quantile(ARRAY[1.0, 5.0, 10.0], ARRAY[0.3, 0.3, 0.4], ARRAY[0.0, 1.0]) AS result,
    'Should be approximately [min_value, max_value]' AS expected_note;

-- Test 8: Consistency between median function and quantile(0.5)
WITH median_comparison AS (
    SELECT 
        weighted_median(ARRAY[2.0, 4.0, 6.0, 8.0], ARRAY[0.25, 0.25, 0.25, 0.25]) AS median_result,
        (weighted_quantile(ARRAY[2.0, 4.0, 6.0, 8.0], ARRAY[0.25, 0.25, 0.25, 0.25], ARRAY[0.5]))[1] AS quantile_result
)
SELECT 
    'Median vs quantile(0.5) consistency' AS test_name,
    median_result,
    quantile_result,
    abs(median_result - quantile_result) < 1e-10 AS consistent
FROM median_comparison;

-- Test 9: Large array mathematical accuracy
WITH large_array AS (
    SELECT 
        array_agg(generate_series) AS vals,
        array_fill(0.01, ARRAY[100]) AS weights
    FROM generate_series(1, 100)
),
large_test AS (
    SELECT weighted_mean(vals, weights) AS wmean
    FROM large_array
)
SELECT 
    'Large array accuracy' AS test_name,
    wmean,
    abs(wmean - 50.5) < 0.1 AS accurate  -- Expected mean of 1-100 series
FROM large_test;

-- Test 10: Precision test with very small weights
SELECT 
    'Small weights precision' AS test_name,
    weighted_mean(ARRAY[1000.0, 2000.0], ARRAY[0.0001, 0.0002]) AS result,
    abs(weighted_mean(ARRAY[1000.0, 2000.0], ARRAY[0.0001, 0.0002]) - 500.0) < 1.0 AS reasonable
;