-- Performance Comparison Tests for Weighted Statistics Extension
--
-- This benchmark compares:
-- 1. C implementation vs PL/pgSQL baseline (mean, variance, std, simple quantiles)
-- 2. Different quantile methods (weighted_quantile vs wquantile vs whdquantile)
--
-- Uses multiple iterations and averages to account for PostgreSQL caching effects

\timing off

\echo '========================================='
\echo 'Weighted Statistics Performance Comparison'
\echo 'Multiple iterations with averaged results'
\echo '========================================='

-- Test data setup
\echo 'Setting up test data...'

-- Create test arrays (1K elements)
DROP TABLE IF EXISTS test_data_1k;
CREATE TEMP TABLE test_data_1k AS
SELECT 
    array_agg(random() * 100) AS vals,
    array_agg(random() * 0.001) AS weights  -- Sum ≈ 1.0 for sparse data test
FROM generate_series(1, 1000);

-- Create test arrays (10K elements) 
DROP TABLE IF EXISTS test_data_10k;
CREATE TEMP TABLE test_data_10k AS
SELECT 
    array_agg(random() * 100) AS vals,
    array_agg(random() * 0.0001) AS weights  -- Sum ≈ 1.0 for sparse data test
FROM generate_series(1, 10000);

-- Create test arrays (100K elements)
DROP TABLE IF EXISTS test_data_100k;
CREATE TEMP TABLE test_data_100k AS
SELECT 
    array_agg(random() * 100) AS vals,
    array_agg(random() * 0.00001) AS weights  -- Sum ≈ 1.0 for sparse data test
FROM generate_series(1, 100000);

-- Create results table for timing
DROP TABLE IF EXISTS benchmark_results;
CREATE TEMP TABLE benchmark_results (
    test_name TEXT,
    array_size TEXT,
    implementation TEXT,
    iteration INTEGER,
    execution_time_ms NUMERIC
);

\echo ''
\echo '========================================='
\echo 'Test Group 1: C vs PL/pgSQL Comparison'
\echo 'Running 5 iterations each for reliable averages'
\echo '========================================='

-- Helper function to time operations
CREATE OR REPLACE FUNCTION time_operation(
    operation_name TEXT,
    array_size_name TEXT, 
    impl_name TEXT,
    iteration_num INTEGER
) RETURNS VOID AS $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    duration_ms NUMERIC;
BEGIN
    start_time := clock_timestamp();
    -- The actual operation timing will be done inline
    end_time := clock_timestamp();
    duration_ms := EXTRACT(epoch FROM (end_time - start_time)) * 1000;
    
    INSERT INTO benchmark_results VALUES (
        operation_name, array_size_name, impl_name, iteration_num, duration_ms
    );
END;
$$ LANGUAGE plpgsql;

\echo ''
\echo '--- Weighted Mean Performance Tests ---'

-- Warm up runs (not counted)
SELECT weighted_mean(vals, weights) FROM test_data_1k;
SELECT weighted_mean_plpgsql(vals, weights) FROM test_data_1k;

-- 1K elements - C implementation
\echo 'Testing weighted_mean C implementation (1K elements)...'
DO $$
DECLARE 
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result DOUBLE PRECISION;
BEGIN
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT weighted_mean(vals, weights) INTO result FROM test_data_1k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'weighted_mean', '1K', 'C', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
END $$;

-- 1K elements - PL/pgSQL implementation  
\echo 'Testing weighted_mean PL/pgSQL implementation (1K elements)...'
DO $$
DECLARE 
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result DOUBLE PRECISION;
BEGIN
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT weighted_mean_plpgsql(vals, weights) INTO result FROM test_data_1k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'weighted_mean', '1K', 'PL/pgSQL', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
END $$;

-- 10K elements - C implementation
\echo 'Testing weighted_mean C implementation (10K elements)...'
DO $$
DECLARE 
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result DOUBLE PRECISION;
BEGIN
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT weighted_mean(vals, weights) INTO result FROM test_data_10k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'weighted_mean', '10K', 'C', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
END $$;

-- 10K elements - PL/pgSQL implementation
\echo 'Testing weighted_mean PL/pgSQL implementation (10K elements)...'
DO $$
DECLARE 
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result DOUBLE PRECISION;
BEGIN
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT weighted_mean_plpgsql(vals, weights) INTO result FROM test_data_10k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'weighted_mean', '10K', 'PL/pgSQL', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
END $$;

-- 100K elements - C implementation
\echo 'Testing weighted_mean C implementation (100K elements)...'
DO $$
DECLARE 
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result DOUBLE PRECISION;
BEGIN
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT weighted_mean(vals, weights) INTO result FROM test_data_100k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'weighted_mean', '100K', 'C', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
END $$;

-- 100K elements - PL/pgSQL implementation  
\echo 'Testing weighted_mean PL/pgSQL implementation (100K elements)...'
DO $$
DECLARE 
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result DOUBLE PRECISION;
BEGIN
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT weighted_mean_plpgsql(vals, weights) INTO result FROM test_data_100k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'weighted_mean', '100K', 'PL/pgSQL', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
END $$;

\echo ''
\echo '--- Weighted Quantile Performance Tests ---'

-- Warm up runs
SELECT weighted_quantile(vals, weights, ARRAY[0.25, 0.5, 0.75]) FROM test_data_1k;
SELECT weighted_quantile_plpgsql(vals, weights, ARRAY[0.25, 0.5, 0.75]) FROM test_data_1k;

-- 1K elements - C implementation
\echo 'Testing weighted_quantile C implementation (1K elements)...'
DO $$
DECLARE 
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result DOUBLE PRECISION[];
BEGIN
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT weighted_quantile(vals, weights, ARRAY[0.25, 0.5, 0.75]) INTO result FROM test_data_1k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'weighted_quantile', '1K', 'C', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
END $$;

-- 1K elements - PL/pgSQL implementation
\echo 'Testing weighted_quantile PL/pgSQL implementation (1K elements)...'
DO $$
DECLARE 
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result DOUBLE PRECISION[];
BEGIN
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT weighted_quantile_plpgsql(vals, weights, ARRAY[0.25, 0.5, 0.75]) INTO result FROM test_data_1k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'weighted_quantile', '1K', 'PL/pgSQL', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
END $$;

-- 10K elements - C implementation
\echo 'Testing weighted_quantile C implementation (10K elements)...'
DO $$
DECLARE 
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result DOUBLE PRECISION[];
BEGIN
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT weighted_quantile(vals, weights, ARRAY[0.25, 0.5, 0.75]) INTO result FROM test_data_10k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'weighted_quantile', '10K', 'C', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
END $$;

-- 10K elements - PL/pgSQL implementation
\echo 'Testing weighted_quantile PL/pgSQL implementation (10K elements)...'
DO $$
DECLARE 
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result DOUBLE PRECISION[];
BEGIN
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT weighted_quantile_plpgsql(vals, weights, ARRAY[0.25, 0.5, 0.75]) INTO result FROM test_data_10k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'weighted_quantile', '10K', 'PL/pgSQL', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
END $$;

-- 100K elements - C implementation
\echo 'Testing weighted_quantile C implementation (100K elements)...'
DO $$
DECLARE 
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result DOUBLE PRECISION[];
BEGIN
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT weighted_quantile(vals, weights, ARRAY[0.25, 0.5, 0.75]) INTO result FROM test_data_100k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'weighted_quantile', '100K', 'C', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
END $$;

-- 100K elements - PL/pgSQL implementation
\echo 'Testing weighted_quantile PL/pgSQL implementation (100K elements)...'
DO $$
DECLARE 
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result DOUBLE PRECISION[];
BEGIN
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT weighted_quantile_plpgsql(vals, weights, ARRAY[0.25, 0.5, 0.75]) INTO result FROM test_data_100k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'weighted_quantile', '100K', 'PL/pgSQL', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
END $$;

\echo ''
\echo '============================================'
\echo 'Test Group 2: Quantile Methods Comparison'
\echo '============================================'

-- Warm up runs
SELECT weighted_quantile(vals, weights, ARRAY[0.1, 0.25, 0.5, 0.75, 0.9]) FROM test_data_1k;
SELECT wquantile(vals, weights, ARRAY[0.1, 0.25, 0.5, 0.75, 0.9]) FROM test_data_1k;
SELECT whdquantile(vals, weights, ARRAY[0.1, 0.25, 0.5, 0.75, 0.9]) FROM test_data_1k;

-- Test quantile methods on 1K elements
\echo 'Testing quantile methods (1K elements)...'
DO $$
DECLARE 
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result DOUBLE PRECISION[];
BEGIN
    -- Empirical CDF (weighted_quantile)
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT weighted_quantile(vals, weights, ARRAY[0.1, 0.25, 0.5, 0.75, 0.9]) INTO result FROM test_data_1k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'quantile_empirical', '1K', 'C', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
    
    -- Type 7 (wquantile)
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT wquantile(vals, weights, ARRAY[0.1, 0.25, 0.5, 0.75, 0.9]) INTO result FROM test_data_1k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'quantile_type7', '1K', 'C', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
    
    -- Harrell-Davis (whdquantile)
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT whdquantile(vals, weights, ARRAY[0.1, 0.25, 0.5, 0.75, 0.9]) INTO result FROM test_data_1k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'quantile_harrell_davis', '1K', 'C', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
END $$;

-- Test quantile methods on 10K elements
\echo 'Testing quantile methods (10K elements)...'
DO $$
DECLARE 
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result DOUBLE PRECISION[];
BEGIN
    -- Empirical CDF (weighted_quantile)
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT weighted_quantile(vals, weights, ARRAY[0.1, 0.25, 0.5, 0.75, 0.9]) INTO result FROM test_data_10k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'quantile_empirical', '10K', 'C', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
    
    -- Type 7 (wquantile)
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT wquantile(vals, weights, ARRAY[0.1, 0.25, 0.5, 0.75, 0.9]) INTO result FROM test_data_10k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'quantile_type7', '10K', 'C', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
    
    -- Harrell-Davis (whdquantile)
    FOR i IN 1..5 LOOP
        start_time := clock_timestamp();
        SELECT whdquantile(vals, weights, ARRAY[0.1, 0.25, 0.5, 0.75, 0.9]) INTO result FROM test_data_10k;
        end_time := clock_timestamp();
        
        INSERT INTO benchmark_results VALUES (
            'quantile_harrell_davis', '10K', 'C', i,
            EXTRACT(epoch FROM (end_time - start_time)) * 1000
        );
    END LOOP;
END $$;

\echo ''
\echo '========================================='
\echo 'Performance Results Summary'
\echo '========================================='

\echo ''
\echo 'C vs PL/pgSQL Performance (Average of 5 runs):'
SELECT 
    test_name,
    array_size,
    implementation,
    ROUND(AVG(execution_time_ms), 3) AS avg_time_ms,
    ROUND(STDDEV(execution_time_ms), 3) AS stddev_ms
FROM benchmark_results 
WHERE test_name IN ('weighted_mean', 'weighted_quantile')
GROUP BY test_name, array_size, implementation
ORDER BY test_name, array_size, implementation;

\echo ''
\echo 'Quantile Methods Comparison (Average of 5 runs):'
SELECT 
    CASE 
        WHEN test_name = 'quantile_empirical' THEN 'Empirical CDF'
        WHEN test_name = 'quantile_type7' THEN 'Type 7'
        WHEN test_name = 'quantile_harrell_davis' THEN 'Harrell-Davis'
    END AS method,
    array_size,
    ROUND(AVG(execution_time_ms), 3) AS avg_time_ms,
    ROUND(STDDEV(execution_time_ms), 3) AS stddev_ms
FROM benchmark_results 
WHERE test_name LIKE 'quantile_%'
GROUP BY test_name, array_size
ORDER BY array_size, test_name;

\echo ''
\echo 'Performance Ratios (PL/pgSQL vs C):'
WITH c_times AS (
    SELECT test_name, array_size, AVG(execution_time_ms) as c_avg
    FROM benchmark_results 
    WHERE implementation = 'C' AND test_name IN ('weighted_mean', 'weighted_quantile')
    GROUP BY test_name, array_size
),
plpgsql_times AS (
    SELECT test_name, array_size, AVG(execution_time_ms) as plpgsql_avg
    FROM benchmark_results 
    WHERE implementation = 'PL/pgSQL'
    GROUP BY test_name, array_size
)
SELECT 
    c.test_name,
    c.array_size,
    ROUND(c.c_avg, 3) AS c_avg_ms,
    ROUND(p.plpgsql_avg, 3) AS plpgsql_avg_ms,
    ROUND(p.plpgsql_avg / c.c_avg, 1) AS speedup_ratio
FROM c_times c
JOIN plpgsql_times p ON c.test_name = p.test_name AND c.array_size = p.array_size
ORDER BY c.test_name, c.array_size;

\echo ''
\echo '========================================='
\echo 'Performance test completed.'
\echo 'Results show averages of 5 iterations each.'
\echo '========================================='