-- Comprehensive Test Suite for REIA Weighted Statistics C Extension
-- 
-- This file contains tests to validate mathematical accuracy of the C functions
-- compared to the PL/pgSQL implementations.

\echo 'Starting REIA C Extension Test Suite...'

-- Test 1: Basic weighted mean test
\echo 'Test 1: Basic weighted mean'

SELECT 
    'Basic weighted mean' AS test_name,
    weighted_mean_sparse(ARRAY[1.0, 2.0, 3.0], ARRAY[0.1, 0.2, 0.3]) AS plpgsql_result,
    weighted_mean_sparse_c(ARRAY[1.0, 2.0, 3.0], ARRAY[0.1, 0.2, 0.3]) AS c_result,
    abs(
        weighted_mean_sparse(ARRAY[1.0, 2.0, 3.0], ARRAY[0.1, 0.2, 0.3]) - 
        weighted_mean_sparse_c(ARRAY[1.0, 2.0, 3.0], ARRAY[0.1, 0.2, 0.3])
    ) < 1e-10 AS results_match;

-- Test 2: Sparse data weighted mean (sum of weights < 1.0)
\echo 'Test 2: Sparse data weighted mean'

SELECT 
    'Sparse weighted mean' AS test_name,
    weighted_mean_sparse(ARRAY[5.0, 10.0], ARRAY[0.2, 0.3]) AS plpgsql_result,
    weighted_mean_sparse_c(ARRAY[5.0, 10.0], ARRAY[0.2, 0.3]) AS c_result,
    abs(
        weighted_mean_sparse(ARRAY[5.0, 10.0], ARRAY[0.2, 0.3]) - 
        weighted_mean_sparse_c(ARRAY[5.0, 10.0], ARRAY[0.2, 0.3])
    ) < 1e-10 AS results_match;

-- Test 3: Edge case - single value
\echo 'Test 3: Single value weighted mean'

SELECT 
    'Single value weighted mean' AS test_name,
    weighted_mean_sparse(ARRAY[7.5], ARRAY[0.4]) AS plpgsql_result,
    weighted_mean_sparse_c(ARRAY[7.5], ARRAY[0.4]) AS c_result,
    abs(
        weighted_mean_sparse(ARRAY[7.5], ARRAY[0.4]) - 
        weighted_mean_sparse_c(ARRAY[7.5], ARRAY[0.4])
    ) < 1e-10 AS results_match;

-- Test 4: Edge case - zero weights
\echo 'Test 4: Zero weights weighted mean'

SELECT 
    'Zero weights weighted mean' AS test_name,
    weighted_mean_sparse(ARRAY[1.0, 2.0, 3.0], ARRAY[0.0, 0.0, 0.0]) AS plpgsql_result,
    weighted_mean_sparse_c(ARRAY[1.0, 2.0, 3.0], ARRAY[0.0, 0.0, 0.0]) AS c_result,
    abs(
        weighted_mean_sparse(ARRAY[1.0, 2.0, 3.0], ARRAY[0.0, 0.0, 0.0]) - 
        weighted_mean_sparse_c(ARRAY[1.0, 2.0, 3.0], ARRAY[0.0, 0.0, 0.0])
    ) < 1e-10 AS results_match;

-- Test 5: Basic weighted quantiles
\echo 'Test 5: Basic weighted quantiles'

WITH test_data AS (
    SELECT 
        weighted_quantile_sparse(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
                               ARRAY[0.1, 0.2, 0.3, 0.2, 0.1], 
                               ARRAY[0.1, 0.5, 0.9]) AS plpgsql_result,
        weighted_quantile_sparse_c(ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
                                 ARRAY[0.1, 0.2, 0.3, 0.2, 0.1], 
                                 ARRAY[0.1, 0.5, 0.9]) AS c_result
)
SELECT 
    'Basic weighted quantiles' AS test_name,
    plpgsql_result,
    c_result,
    abs(plpgsql_result[1] - c_result[1]) < 1e-10 AND
    abs(plpgsql_result[2] - c_result[2]) < 1e-10 AND
    abs(plpgsql_result[3] - c_result[3]) < 1e-10 AS results_match
FROM test_data;

-- Test 6: Sparse data quantiles
\echo 'Test 6: Sparse data weighted quantiles'

WITH test_data AS (
    SELECT 
        weighted_quantile_sparse(ARRAY[2.0, 4.0, 6.0], 
                               ARRAY[0.15, 0.25, 0.35], 
                               ARRAY[0.1, 0.5, 0.9]) AS plpgsql_result,
        weighted_quantile_sparse_c(ARRAY[2.0, 4.0, 6.0], 
                                 ARRAY[0.15, 0.25, 0.35], 
                                 ARRAY[0.1, 0.5, 0.9]) AS c_result
)
SELECT 
    'Sparse weighted quantiles' AS test_name,
    plpgsql_result,
    c_result,
    abs(plpgsql_result[1] - c_result[1]) < 1e-10 AND
    abs(plpgsql_result[2] - c_result[2]) < 1e-10 AND
    abs(plpgsql_result[3] - c_result[3]) < 1e-10 AS results_match
FROM test_data;

-- Test 7: Edge case quantiles - single value
\echo 'Test 7: Single value quantiles'

WITH test_data AS (
    SELECT 
        weighted_quantile_sparse(ARRAY[10.0], 
                               ARRAY[0.5], 
                               ARRAY[0.1, 0.5, 0.9]) AS plpgsql_result,
        weighted_quantile_sparse_c(ARRAY[10.0], 
                                 ARRAY[0.5], 
                                 ARRAY[0.1, 0.5, 0.9]) AS c_result
)
SELECT 
    'Single value quantiles' AS test_name,
    plpgsql_result,
    c_result,
    abs(plpgsql_result[1] - c_result[1]) < 1e-10 AND
    abs(plpgsql_result[2] - c_result[2]) < 1e-10 AND
    abs(plpgsql_result[3] - c_result[3]) < 1e-10 AS results_match
FROM test_data;

-- Test 8: Large array performance test
\echo 'Test 8: Large array accuracy test (100 elements)'

WITH large_test_data AS (
    SELECT 
        generate_series(1, 100)::double precision AS vals,
        (random() * 0.01)::double precision AS weights
),
arrays AS (
    SELECT 
        array_agg(vals) AS val_array,
        array_agg(weights) AS weight_array
    FROM large_test_data
),
test_results AS (
    SELECT 
        weighted_mean_sparse(val_array, weight_array) AS plpgsql_mean,
        weighted_mean_sparse_c(val_array, weight_array) AS c_mean,
        weighted_quantile_sparse(val_array, weight_array, ARRAY[0.25, 0.5, 0.75]) AS plpgsql_quantiles,
        weighted_quantile_sparse_c(val_array, weight_array, ARRAY[0.25, 0.5, 0.75]) AS c_quantiles
    FROM arrays
)
SELECT 
    'Large array accuracy' AS test_name,
    abs(plpgsql_mean - c_mean) < 1e-8 AS mean_match,
    abs(plpgsql_quantiles[1] - c_quantiles[1]) < 1e-8 AND
    abs(plpgsql_quantiles[2] - c_quantiles[2]) < 1e-8 AND
    abs(plpgsql_quantiles[3] - c_quantiles[3]) < 1e-8 AS quantiles_match
FROM test_results;

-- Test 9: NULL handling
\echo 'Test 9: NULL handling'

SELECT 
    'NULL handling' AS test_name,
    weighted_mean_sparse(NULL, ARRAY[0.1, 0.2]) AS plpgsql_null_vals,
    weighted_mean_sparse_c(NULL, ARRAY[0.1, 0.2]) AS c_null_vals,
    weighted_mean_sparse(ARRAY[1.0, 2.0], NULL) AS plpgsql_null_weights,
    weighted_mean_sparse_c(ARRAY[1.0, 2.0], NULL) AS c_null_weights,
    (weighted_mean_sparse(NULL, ARRAY[0.1, 0.2]) = weighted_mean_sparse_c(NULL, ARRAY[0.1, 0.2])) AND
    (weighted_mean_sparse(ARRAY[1.0, 2.0], NULL) = weighted_mean_sparse_c(ARRAY[1.0, 2.0], NULL)) AS null_handling_match;

\echo 'Test Suite Complete. Check that all results_match columns show TRUE.'