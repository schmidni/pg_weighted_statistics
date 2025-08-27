-- Performance Test for Weighted Statistics Extension
--
-- Simple benchmark without assumptions or interpretations.
-- Run with \timing on to see execution times.

\timing on

-- Test 1: Small Arrays (100 elements)
\echo 'Test 1: Small arrays (100 elements)'

SELECT 'weighted_mean' AS function_name, count(*) AS iterations
FROM (
    SELECT weighted_mean(
        array_agg(random() * 100), 
        array_agg(random() * 0.01)
    )
    FROM generate_series(1, 100), generate_series(1, 100) AS iter
    GROUP BY iter
) results;

SELECT 'weighted_quantile' AS function_name, count(*) AS iterations
FROM (
    SELECT weighted_quantile(
        array_agg(random() * 100), 
        array_agg(random() * 0.01),
        ARRAY[0.25, 0.5, 0.75]
    )
    FROM generate_series(1, 100), generate_series(1, 100) AS iter
    GROUP BY iter
) results;

-- Test 2: Medium Arrays (1,000 elements)
\echo 'Test 2: Medium arrays (1,000 elements)'

SELECT 'weighted_mean' AS function_name, count(*) AS iterations
FROM (
    SELECT weighted_mean(
        array_agg(random() * 100), 
        array_agg(random() * 0.001)
    )
    FROM generate_series(1, 1000), generate_series(1, 50) AS iter
    GROUP BY iter
) results;

SELECT 'weighted_quantile' AS function_name, count(*) AS iterations
FROM (
    SELECT weighted_quantile(
        array_agg(random() * 100), 
        array_agg(random() * 0.001),
        ARRAY[0.1, 0.5, 0.9]
    )
    FROM generate_series(1, 1000), generate_series(1, 50) AS iter
    GROUP BY iter
) results;

-- Test 3: Large Arrays (10,000 elements)  
\echo 'Test 3: Large arrays (10,000 elements)'

SELECT 'weighted_mean' AS function_name, count(*) AS iterations
FROM (
    SELECT weighted_mean(
        array_agg(random() * 100), 
        array_agg(random() * 0.0001)
    )
    FROM generate_series(1, 10000), generate_series(1, 10) AS iter
    GROUP BY iter
) results;

SELECT 'weighted_quantile' AS function_name, count(*) AS iterations
FROM (
    SELECT weighted_quantile(
        array_agg(random() * 100), 
        array_agg(random() * 0.0001),
        ARRAY[0.25, 0.5, 0.75]
    )
    FROM generate_series(1, 10000), generate_series(1, 10) AS iter
    GROUP BY iter
) results;

-- Test 4: Multi-Quantile Efficiency
\echo 'Test 4: Multi-quantile efficiency'

-- Single quantile
SELECT 'single_quantile' AS test_type, count(*) AS iterations
FROM (
    SELECT weighted_quantile(
        array_agg(random() * 100), 
        array_agg(random() * 0.001),
        ARRAY[0.5]
    )
    FROM generate_series(1, 1000), generate_series(1, 50) AS iter
    GROUP BY iter
) results;

-- Multiple quantiles
SELECT 'multiple_quantiles' AS test_type, count(*) AS iterations
FROM (
    SELECT weighted_quantile(
        array_agg(random() * 100), 
        array_agg(random() * 0.001),
        ARRAY[0.1, 0.25, 0.5, 0.75, 0.9]
    )
    FROM generate_series(1, 1000), generate_series(1, 50) AS iter
    GROUP BY iter
) results;

-- Test 5: Sparse Data Performance
\echo 'Test 5: Sparse data scenarios'

-- 10% weight coverage (sparse)
SELECT 'sparse_10pct' AS sparsity_level, count(*) AS iterations
FROM (
    SELECT weighted_mean(
        array_agg(random() * 100), 
        array_agg(random() * 0.0001)  -- Sum = 0.1 for 1000 elements
    )
    FROM generate_series(1, 1000), generate_series(1, 50) AS iter
    GROUP BY iter
) results;

-- 90% weight coverage (dense)
SELECT 'dense_90pct' AS sparsity_level, count(*) AS iterations
FROM (
    SELECT weighted_mean(
        array_agg(random() * 100), 
        array_agg(random() * 0.0009)  -- Sum = 0.9 for 1000 elements
    )
    FROM generate_series(1, 1000), generate_series(1, 50) AS iter
    GROUP BY iter
) results;

-- Test 6: Scaling Test
\echo 'Test 6: Scaling across array sizes'

SELECT '100_elements' AS array_size;
SELECT weighted_mean(array_agg(random() * 100), array_agg(0.01))
FROM generate_series(1, 100);

SELECT '1000_elements' AS array_size;
SELECT weighted_mean(array_agg(random() * 100), array_agg(0.001))  
FROM generate_series(1, 1000);

SELECT '5000_elements' AS array_size;
SELECT weighted_mean(array_agg(random() * 100), array_agg(0.0002))
FROM generate_series(1, 5000);

SELECT '10000_elements' AS array_size;
SELECT weighted_mean(array_agg(random() * 100), array_agg(0.0001))
FROM generate_series(1, 10000);

\timing off

\echo 'Performance test completed. Review timing output above.'