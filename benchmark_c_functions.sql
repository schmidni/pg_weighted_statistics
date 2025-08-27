-- Performance Benchmark Suite for REIA Weighted Statistics C Extension
-- 
-- This script compares the performance of C functions vs PL/pgSQL functions
-- across different data sizes to measure performance improvements.

\timing on
\echo 'Starting REIA C Extension Performance Benchmark...'

-- Create a table for storing benchmark results
DROP TABLE IF EXISTS benchmark_results;
CREATE TEMP TABLE benchmark_results (
    test_name TEXT,
    function_type TEXT,
    array_size INTEGER,
    execution_time_ms NUMERIC,
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- Function to generate test data
CREATE OR REPLACE FUNCTION generate_test_arrays(size INTEGER) 
RETURNS TABLE(vals DOUBLE PRECISION[], weights DOUBLE PRECISION[])
AS $$
BEGIN
    RETURN QUERY
    WITH test_data AS (
        SELECT 
            generate_series(1, size)::double precision AS val,
            (random() * 0.001 + 0.0001)::double precision AS weight  -- Sparse weights
    )
    SELECT 
        array_agg(val) AS vals,
        array_agg(weight) AS weights
    FROM test_data;
END;
$$ LANGUAGE plpgsql;

-- Benchmark 1: Small arrays (100 elements)
\echo 'Benchmarking small arrays (100 elements)...'

DO $$
DECLARE
    vals_array DOUBLE PRECISION[];
    weights_array DOUBLE PRECISION[];
    start_time TIMESTAMPTZ;
    end_time TIMESTAMPTZ;
    duration_ms NUMERIC;
    result DOUBLE PRECISION;
BEGIN
    -- Generate test data
    SELECT vals, weights INTO vals_array, weights_array
    FROM generate_test_arrays(100);
    
    -- Benchmark PL/pgSQL weighted_mean_sparse
    start_time := clock_timestamp();
    FOR i IN 1..1000 LOOP
        result := weighted_mean_sparse(vals_array, weights_array);
    END LOOP;
    end_time := clock_timestamp();
    duration_ms := EXTRACT(milliseconds FROM (end_time - start_time));
    
    INSERT INTO benchmark_results VALUES ('weighted_mean_sparse', 'PL/pgSQL', 100, duration_ms);
    
    -- Benchmark C weighted_mean_sparse_c
    start_time := clock_timestamp();
    FOR i IN 1..1000 LOOP
        result := weighted_mean_sparse_c(vals_array, weights_array);
    END LOOP;
    end_time := clock_timestamp();
    duration_ms := EXTRACT(milliseconds FROM (end_time - start_time));
    
    INSERT INTO benchmark_results VALUES ('weighted_mean_sparse', 'C', 100, duration_ms);
END;
$$;

-- Benchmark 2: Medium arrays (1,000 elements)
\echo 'Benchmarking medium arrays (1,000 elements)...'

DO $$
DECLARE
    vals_array DOUBLE PRECISION[];
    weights_array DOUBLE PRECISION[];
    start_time TIMESTAMPTZ;
    end_time TIMESTAMPTZ;
    duration_ms NUMERIC;
    result DOUBLE PRECISION;
BEGIN
    -- Generate test data
    SELECT vals, weights INTO vals_array, weights_array
    FROM generate_test_arrays(1000);
    
    -- Benchmark PL/pgSQL weighted_mean_sparse
    start_time := clock_timestamp();
    FOR i IN 1..100 LOOP
        result := weighted_mean_sparse(vals_array, weights_array);
    END LOOP;
    end_time := clock_timestamp();
    duration_ms := EXTRACT(milliseconds FROM (end_time - start_time));
    
    INSERT INTO benchmark_results VALUES ('weighted_mean_sparse', 'PL/pgSQL', 1000, duration_ms);
    
    -- Benchmark C weighted_mean_sparse_c
    start_time := clock_timestamp();
    FOR i IN 1..100 LOOP
        result := weighted_mean_sparse_c(vals_array, weights_array);
    END LOOP;
    end_time := clock_timestamp();
    duration_ms := EXTRACT(milliseconds FROM (end_time - start_time));
    
    INSERT INTO benchmark_results VALUES ('weighted_mean_sparse', 'C', 1000, duration_ms);
END;
$$;

-- Benchmark 3: Large arrays (10,000 elements)
\echo 'Benchmarking large arrays (10,000 elements)...'

DO $$
DECLARE
    vals_array DOUBLE PRECISION[];
    weights_array DOUBLE PRECISION[];
    start_time TIMESTAMPTZ;
    end_time TIMESTAMPTZ;
    duration_ms NUMERIC;
    result DOUBLE PRECISION;
BEGIN
    -- Generate test data
    SELECT vals, weights INTO vals_array, weights_array
    FROM generate_test_arrays(10000);
    
    -- Benchmark PL/pgSQL weighted_mean_sparse
    start_time := clock_timestamp();
    FOR i IN 1..10 LOOP
        result := weighted_mean_sparse(vals_array, weights_array);
    END LOOP;
    end_time := clock_timestamp();
    duration_ms := EXTRACT(milliseconds FROM (end_time - start_time));
    
    INSERT INTO benchmark_results VALUES ('weighted_mean_sparse', 'PL/pgSQL', 10000, duration_ms);
    
    -- Benchmark C weighted_mean_sparse_c
    start_time := clock_timestamp();
    FOR i IN 1..10 LOOP
        result := weighted_mean_sparse_c(vals_array, weights_array);
    END LOOP;
    end_time := clock_timestamp();
    duration_ms := EXTRACT(milliseconds FROM (end_time - start_time));
    
    INSERT INTO benchmark_results VALUES ('weighted_mean_sparse', 'C', 10000, duration_ms);
END;
$$;

-- Benchmark 4: Quantile functions - Medium arrays (1,000 elements)
\echo 'Benchmarking quantile functions with medium arrays (1,000 elements)...'

DO $$
DECLARE
    vals_array DOUBLE PRECISION[];
    weights_array DOUBLE PRECISION[];
    quantiles_array DOUBLE PRECISION[] := ARRAY[0.1, 0.25, 0.5, 0.75, 0.9];
    start_time TIMESTAMPTZ;
    end_time TIMESTAMPTZ;
    duration_ms NUMERIC;
    result DOUBLE PRECISION[];
BEGIN
    -- Generate test data
    SELECT vals, weights INTO vals_array, weights_array
    FROM generate_test_arrays(1000);
    
    -- Benchmark PL/pgSQL weighted_quantile_sparse
    start_time := clock_timestamp();
    FOR i IN 1..50 LOOP
        result := weighted_quantile_sparse(vals_array, weights_array, quantiles_array);
    END LOOP;
    end_time := clock_timestamp();
    duration_ms := EXTRACT(milliseconds FROM (end_time - start_time));
    
    INSERT INTO benchmark_results VALUES ('weighted_quantile_sparse', 'PL/pgSQL', 1000, duration_ms);
    
    -- Benchmark C weighted_quantile_sparse_c
    start_time := clock_timestamp();
    FOR i IN 1..50 LOOP
        result := weighted_quantile_sparse_c(vals_array, weights_array, quantiles_array);
    END LOOP;
    end_time := clock_timestamp();
    duration_ms := EXTRACT(milliseconds FROM (end_time - start_time));
    
    INSERT INTO benchmark_results VALUES ('weighted_quantile_sparse', 'C', 1000, duration_ms);
END;
$$;

-- Display benchmark results
\echo 'Benchmark Results:'

SELECT 
    test_name,
    array_size,
    function_type,
    execution_time_ms,
    ROUND(
        100.0 * (
            LAG(execution_time_ms) OVER (PARTITION BY test_name, array_size ORDER BY function_type DESC) 
            - execution_time_ms
        ) / LAG(execution_time_ms) OVER (PARTITION BY test_name, array_size ORDER BY function_type DESC), 
        2
    ) AS performance_improvement_percent
FROM benchmark_results 
ORDER BY test_name, array_size, function_type;

-- Summary statistics
\echo 'Performance Summary:'

WITH performance_comparison AS (
    SELECT 
        test_name,
        array_size,
        MAX(CASE WHEN function_type = 'PL/pgSQL' THEN execution_time_ms END) AS plpgsql_time,
        MAX(CASE WHEN function_type = 'C' THEN execution_time_ms END) AS c_time
    FROM benchmark_results
    GROUP BY test_name, array_size
)
SELECT 
    test_name,
    array_size,
    ROUND(plpgsql_time / c_time, 2) AS speedup_factor,
    ROUND(100.0 * (plpgsql_time - c_time) / plpgsql_time, 2) AS performance_improvement_percent
FROM performance_comparison
ORDER BY test_name, array_size;

\echo 'Benchmark Complete!'
\timing off