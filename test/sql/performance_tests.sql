-- Performance tests for weighted_statistics extension
-- 
-- Tests performance characteristics with various array sizes

\timing on

-- Test 1: Small arrays (100 elements)
\echo 'Performance Test 1: Small arrays (100 elements)'
WITH small_arrays AS (
    SELECT 
        array_agg(random() * 100) AS vals,
        array_agg(random() * 0.01) AS weights
    FROM generate_series(1, 100)
)
SELECT 
    'Small array (100 elements)' AS test_name,
    weighted_mean(vals, weights) AS mean_result,
    array_length(weighted_quantile(vals, weights, ARRAY[0.1, 0.5, 0.9]), 1) AS quantiles_count
FROM small_arrays;

-- Test 2: Medium arrays (1,000 elements)
\echo 'Performance Test 2: Medium arrays (1,000 elements)'
WITH medium_arrays AS (
    SELECT 
        array_agg(random() * 100) AS vals,
        array_agg(random() * 0.001) AS weights
    FROM generate_series(1, 1000)
)
SELECT 
    'Medium array (1,000 elements)' AS test_name,
    weighted_mean(vals, weights) AS mean_result,
    array_length(weighted_quantile(vals, weights, ARRAY[0.1, 0.25, 0.5, 0.75, 0.9]), 1) AS quantiles_count
FROM medium_arrays;

-- Test 3: Large arrays (10,000 elements)
\echo 'Performance Test 3: Large arrays (10,000 elements)'
WITH large_arrays AS (
    SELECT 
        array_agg(random() * 100) AS vals,
        array_agg(random() * 0.0001) AS weights
    FROM generate_series(1, 10000)
)
SELECT 
    'Large array (10,000 elements)' AS test_name,
    weighted_mean(vals, weights) AS mean_result,
    array_length(weighted_quantile(vals, weights, ARRAY[0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95]), 1) AS quantiles_count
FROM large_arrays;

-- Test 4: Multiple quantiles performance
\echo 'Performance Test 4: Multiple quantiles (many quantiles)'
WITH quantile_test AS (
    SELECT 
        array_agg(i * 1.0) AS vals,
        array_agg(0.001) AS weights,  -- Same length as vals
        ARRAY[0.01, 0.02, 0.03, 0.04, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.96, 0.97, 0.98, 0.99] AS quantiles
    FROM generate_series(1, 1000) AS vals_gen(i)
)
SELECT 
    'Multiple quantiles performance' AS test_name,
    array_length(weighted_quantile(vals, weights, quantiles), 1) AS quantiles_computed
FROM quantile_test;

-- Test 5: Sparse data with varying sparsity levels
\echo 'Performance Test 5: Sparse data performance'
WITH sparse_test AS (
    SELECT 
        0.1 AS sparsity_level,
        array_agg(random() * 100) AS vals,
        array_agg(random() * 0.1 / 1000) AS weights_sparse
    FROM generate_series(1, 1000)
    UNION ALL
    SELECT 
        0.5 AS sparsity_level,
        array_agg(random() * 100) AS vals,
        array_agg(random() * 0.5 / 1000) AS weights_sparse
    FROM generate_series(1, 1000)
    UNION ALL
    SELECT 
        0.9 AS sparsity_level,
        array_agg(random() * 100) AS vals,
        array_agg(random() * 0.9 / 1000) AS weights_sparse
    FROM generate_series(1, 1000)
)
SELECT 
    'Sparsity level: ' || sparsity_level AS test_name,
    weighted_mean(vals, weights_sparse) AS mean_result,
    (weighted_quantile(vals, weights_sparse, ARRAY[0.5]))[1] AS median_result
FROM sparse_test
ORDER BY sparsity_level;

-- Test 6: Repeated operations (simulation of real workload)
\echo 'Performance Test 6: Repeated operations'
SELECT 
    'Repeated operations (' || i || '/10)' AS test_name,
    weighted_mean(
        array_agg(random() * 100), 
        array_agg(random() * 0.001)
    ) AS mean_result
FROM generate_series(1, 500), generate_series(1, 10) AS i
GROUP BY i
ORDER BY i;

-- Test 7: Memory efficiency test with cleanup
\echo 'Performance Test 7: Memory efficiency test'
WITH memory_test AS (
    SELECT 
        iter.i AS iteration,
        weighted_mean(
            array_agg(random() * 1000),
            array_agg(random() * 0.0001)
        ) AS result
    FROM generate_series(1, 10000) AS data_gen(i), 
         generate_series(1, 5) AS iter(i)
    GROUP BY iter.i
)
SELECT 
    'Memory test iteration ' || iteration AS test_name,
    round(result::numeric, 4) AS rounded_result
FROM memory_test
ORDER BY iteration
LIMIT 5;  -- Show only first 5 results to avoid overwhelming output

\timing off

\echo 'Performance tests completed. Check timing output for performance characteristics.'