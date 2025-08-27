-- Comprehensive Benchmark Suite for Weighted Statistics Extension
-- 
-- Measures performance characteristics across different data sizes and scenarios

\echo 'Starting Weighted Statistics Benchmark Suite'
\echo '============================================='

\timing on

-- Benchmark 1: Small arrays (100 elements)
\echo 'Benchmark 1: Small arrays (100 elements) - 1000 iterations'
WITH small_benchmark AS (
    SELECT 
        iteration,
        weighted_mean(
            array_agg(random() * 100), 
            array_agg(random() * 0.01)
        ) AS wmean,
        weighted_quantile(
            array_agg(random() * 100), 
            array_agg(random() * 0.01),
            ARRAY[0.1, 0.5, 0.9]
        ) AS wquantiles
    FROM generate_series(1, 100), generate_series(1, 1000) AS iteration
    GROUP BY iteration
)
SELECT 
    'Small arrays summary' AS benchmark,
    count(*) AS iterations_completed,
    round(avg(wmean)::numeric, 2) AS avg_mean,
    round(avg(wquantiles[2])::numeric, 2) AS avg_median
FROM small_benchmark;

-- Benchmark 2: Medium arrays (1,000 elements)
\echo 'Benchmark 2: Medium arrays (1,000 elements) - 100 iterations'
WITH medium_benchmark AS (
    SELECT 
        iteration,
        weighted_mean(
            array_agg(random() * 1000), 
            array_agg(random() * 0.001)
        ) AS wmean,
        weighted_quantile(
            array_agg(random() * 1000), 
            array_agg(random() * 0.001),
            ARRAY[0.25, 0.5, 0.75]
        ) AS wquantiles
    FROM generate_series(1, 1000), generate_series(1, 100) AS iteration
    GROUP BY iteration
)
SELECT 
    'Medium arrays summary' AS benchmark,
    count(*) AS iterations_completed,
    round(avg(wmean)::numeric, 2) AS avg_mean,
    round(avg(wquantiles[2])::numeric, 2) AS avg_median
FROM medium_benchmark;

-- Benchmark 3: Large arrays (10,000 elements)
\echo 'Benchmark 3: Large arrays (10,000 elements) - 10 iterations'
WITH large_benchmark AS (
    SELECT 
        iteration,
        weighted_mean(
            array_agg(random() * 10000), 
            array_agg(random() * 0.0001)
        ) AS wmean,
        weighted_quantile(
            array_agg(random() * 10000), 
            array_agg(random() * 0.0001),
            ARRAY[0.1, 0.3, 0.5, 0.7, 0.9]
        ) AS wquantiles
    FROM generate_series(1, 10000), generate_series(1, 10) AS iteration
    GROUP BY iteration
)
SELECT 
    'Large arrays summary' AS benchmark,
    count(*) AS iterations_completed,
    round(avg(wmean)::numeric, 2) AS avg_mean,
    round(avg(wquantiles[3])::numeric, 2) AS avg_median
FROM large_benchmark;

-- Benchmark 4: Very large arrays (50,000 elements)
\echo 'Benchmark 4: Very large arrays (50,000 elements) - 3 iterations'
WITH xlarge_benchmark AS (
    SELECT 
        iteration,
        weighted_mean(
            array_agg(random() * 50000), 
            array_agg(random() * 0.00002)
        ) AS wmean
    FROM generate_series(1, 50000), generate_series(1, 3) AS iteration
    GROUP BY iteration
)
SELECT 
    'Very large arrays summary' AS benchmark,
    count(*) AS iterations_completed,
    round(avg(wmean)::numeric, 2) AS avg_mean
FROM xlarge_benchmark;

-- Benchmark 5: Multiple quantiles performance
\echo 'Benchmark 5: Multiple quantiles (many quantiles) - 50 iterations'
WITH quantile_benchmark AS (
    SELECT 
        iteration,
        array_length(
            weighted_quantile(
                array_agg(generate_series * 1.0), 
                array_fill(0.001, ARRAY[1000]),
                array_agg(q * 0.01)
            ), 1
        ) AS quantile_count
    FROM generate_series(1, 1000), 
         generate_series(1, 99) AS q,
         generate_series(1, 50) AS iteration
    GROUP BY iteration
)
SELECT 
    'Multiple quantiles summary' AS benchmark,
    count(*) AS iterations_completed,
    avg(quantile_count) AS avg_quantiles_computed
FROM quantile_benchmark;

-- Benchmark 6: Sparse data scenarios
\echo 'Benchmark 6: Sparse data performance - different sparsity levels'
WITH sparse_benchmark AS (
    SELECT 
        sparsity_level,
        weighted_mean(vals, weights_sparse) AS wmean,
        (weighted_quantile(vals, weights_sparse, ARRAY[0.5]))[1] AS median
    FROM (
        SELECT 
            0.1 AS sparsity_level,
            array_agg(random() * 100) AS vals,
            array_agg(random() * 0.1 / 5000) AS weights_sparse
        FROM generate_series(1, 5000)
        UNION ALL
        SELECT 
            0.3 AS sparsity_level,
            array_agg(random() * 100) AS vals,
            array_agg(random() * 0.3 / 5000) AS weights_sparse
        FROM generate_series(1, 5000)
        UNION ALL
        SELECT 
            0.7 AS sparsity_level,
            array_agg(random() * 100) AS vals,
            array_agg(random() * 0.7 / 5000) AS weights_sparse
        FROM generate_series(1, 5000)
        UNION ALL
        SELECT 
            0.95 AS sparsity_level,
            array_agg(random() * 100) AS vals,
            array_agg(random() * 0.95 / 5000) AS weights_sparse
        FROM generate_series(1, 5000)
    ) sparse_data
)
SELECT 
    'Sparsity ' || sparsity_level AS benchmark,
    round(wmean::numeric, 3) AS weighted_mean,
    round(median::numeric, 3) AS weighted_median
FROM sparse_benchmark
ORDER BY sparsity_level;

-- Benchmark 7: Real-world simulation - time series data
\echo 'Benchmark 7: Time series simulation - 1000 time points'
WITH timeseries_benchmark AS (
    SELECT 
        day_group,
        weighted_mean(
            array_agg(sin(point * 0.1) * 50 + 100 + random() * 10),
            array_agg(random() * 0.001)
        ) AS daily_wmean,
        weighted_quantile(
            array_agg(sin(point * 0.1) * 50 + 100 + random() * 10),
            array_agg(random() * 0.001),
            ARRAY[0.05, 0.25, 0.5, 0.75, 0.95]
        ) AS daily_quantiles
    FROM generate_series(1, 10000) AS point,
         (point / 1000) AS day_group
    GROUP BY day_group
    HAVING count(*) = 1000
)
SELECT 
    'Timeseries summary' AS benchmark,
    count(*) AS days_processed,
    round(avg(daily_wmean)::numeric, 2) AS avg_daily_mean,
    round(avg(daily_quantiles[3])::numeric, 2) AS avg_daily_median
FROM timeseries_benchmark;

\timing off

\echo ''
\echo 'Benchmark Suite Completed!'
\echo 'Check timing output above for performance characteristics.'
\echo 'Expected performance:'
\echo '  - Small arrays (100 elements): < 1ms per operation'
\echo '  - Medium arrays (1K elements): < 5ms per operation'
\echo '  - Large arrays (10K elements): < 50ms per operation'
\echo '  - Very large arrays (50K elements): < 500ms per operation'