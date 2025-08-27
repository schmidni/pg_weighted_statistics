/*
 * Weighted Statistics PostgreSQL Extension
 * 
 * High-performance C implementation of weighted mean and quantile functions
 * optimized for sparse data (where sum(weights) < 1.0 implies implicit zeros).
 * 
 * All functions in this extension handle sparse data by default, providing
 * significant performance improvements over PL/pgSQL implementations.
 */

#include "postgres.h"
#include "fmgr.h"
#include "utils/array.h"
#include "utils/lsyscache.h"
#include "utils/builtins.h"
#include "catalog/pg_type.h"
#include "access/tupmacs.h"
#include <math.h>
#include <string.h>
#include <stdint.h>

/* PostgreSQL extension module magic */
PG_MODULE_MAGIC;

/* Data structure for value-weight pairs */
typedef struct {
    double value;
    double weight;
} ValueWeight;

/* Structure of Arrays layout for better cache performance */
typedef struct {
    double *values;
    double *weights;
    int *indices;  /* Original indices for stable sorting */
    int count;
    int capacity;
} ValueWeightArrays;

/* Comparison function for sorting value-weight pairs */
static int 
compare_value_weight(const void *a, const void *b) {
    const ValueWeight *vw_a = (const ValueWeight *)a;
    const ValueWeight *vw_b = (const ValueWeight *)b;
    
    if (vw_a->value < vw_b->value) return -1;
    if (vw_a->value > vw_b->value) return 1;
    return 0;
}

/* Radix sort for doubles - much faster than qsort for large arrays */
static void radix_sort_value_weight_pairs(ValueWeight *pairs, int n) {
    if (n <= 1) return;
    
    /* Use radix sort for large arrays, qsort for small ones */
    if (n < 256) {
        qsort(pairs, n, sizeof(ValueWeight), compare_value_weight);
        return;
    }
    
    /* Radix sort implementation for IEEE 754 doubles */
    ValueWeight *temp = (ValueWeight *)palloc(n * sizeof(ValueWeight));
    union { double d; uint64_t u; } conv;
    
    /* Sort by each byte of the double, from most significant */
    for (int byte = 7; byte >= 0; byte--) {
        int count[256] = {0};
        int shift = byte * 8;
        
        /* Count occurrences */
        for (int i = 0; i < n; i++) {
            conv.d = pairs[i].value;
            /* Handle negative numbers by flipping sign bit and all other bits */
            uint64_t key = conv.u;
            if (key & 0x8000000000000000ULL) {
                key = ~key;
            } else {
                key |= 0x8000000000000000ULL;
            }
            count[(key >> shift) & 0xFF]++;
        }
        
        /* Calculate positions */
        for (int i = 1; i < 256; i++) {
            count[i] += count[i-1];
        }
        
        /* Place elements in sorted order */
        for (int i = n - 1; i >= 0; i--) {
            conv.d = pairs[i].value;
            uint64_t key = conv.u;
            if (key & 0x8000000000000000ULL) {
                key = ~key;
            } else {
                key |= 0x8000000000000000ULL;
            }
            int bucket = (key >> shift) & 0xFF;
            temp[--count[bucket]] = pairs[i];
        }
        
        /* Copy back */
        memcpy(pairs, temp, n * sizeof(ValueWeight));
    }
    
    pfree(temp);
}

/* Counting sort for when value range is small */
static void counting_sort_value_weight_pairs(ValueWeight *pairs, int n) {
    if (n <= 1) return;
    
    /* Find min and max values */
    double min_val = pairs[0].value;
    double max_val = pairs[0].value;
    
    for (int i = 1; i < n; i++) {
        if (pairs[i].value < min_val) min_val = pairs[i].value;
        if (pairs[i].value > max_val) max_val = pairs[i].value;
    }
    
    double range = max_val - min_val;
    
    /* Use counting sort only if range is reasonable */
    if (range <= 0 || range > 10000 || range != floor(range)) {
        /* Fall back to radix sort */
        radix_sort_value_weight_pairs(pairs, n);
        return;
    }
    
    int range_int = (int)range + 1;
    int *count = (int *)palloc0(range_int * sizeof(int));
    ValueWeight *temp = (ValueWeight *)palloc(n * sizeof(ValueWeight));
    
    /* Count occurrences */
    for (int i = 0; i < n; i++) {
        int bucket = (int)(pairs[i].value - min_val);
        count[bucket]++;
    }
    
    /* Calculate positions */
    for (int i = 1; i < range_int; i++) {
        count[i] += count[i-1];
    }
    
    /* Place elements */
    for (int i = n - 1; i >= 0; i--) {
        int bucket = (int)(pairs[i].value - min_val);
        temp[--count[bucket]] = pairs[i];
    }
    
    /* Copy back */
    memcpy(pairs, temp, n * sizeof(ValueWeight));
    
    pfree(count);
    pfree(temp);
}

/* Intelligent sorting dispatch */
static void optimized_sort_value_weight_pairs(ValueWeight *pairs, int n) {
    if (n <= 1) return;
    
    /* For small arrays, use standard qsort */
    if (n < 32) {
        qsort(pairs, n, sizeof(ValueWeight), compare_value_weight);
        return;
    }
    
    /* Analyze value distribution to choose best algorithm */
    double min_val = pairs[0].value;
    double max_val = pairs[0].value;
    bool all_integers = true;
    
    for (int i = 0; i < n; i++) {
        if (pairs[i].value < min_val) min_val = pairs[i].value;
        if (pairs[i].value > max_val) max_val = pairs[i].value;
        if (pairs[i].value != floor(pairs[i].value)) all_integers = false;
    }
    
    double range = max_val - min_val;
    
    /* Use counting sort for small integer ranges */
    if (all_integers && range > 0 && range <= 1000 && n > 100) {
        counting_sort_value_weight_pairs(pairs, n);
    } else {
        /* Use radix sort for everything else */
        radix_sort_value_weight_pairs(pairs, n);
    }
}

/* Utility function to extract double arrays from PostgreSQL arrays */
static int
extract_double_arrays(ArrayType *vals_array, ArrayType *weights_array,
                      double **vals, double **weights, int *n_elements) {
    Datum *vals_datums, *weights_datums;
    bool *vals_nulls, *weights_nulls;
    int vals_count, weights_count;
    int i;
    
    /* Deconstruct the arrays */
    deconstruct_array(vals_array, FLOAT8OID, 8, FLOAT8PASSBYVAL, 'd',
                      &vals_datums, &vals_nulls, &vals_count);
    
    deconstruct_array(weights_array, FLOAT8OID, 8, FLOAT8PASSBYVAL, 'd',
                      &weights_datums, &weights_nulls, &weights_count);
    
    /* Check array lengths match */
    if (vals_count != weights_count) {
        ereport(ERROR,
                (errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
                 errmsg("values and weights arrays must have the same length")));
        return -1;
    }
    
    *n_elements = vals_count;
    
    /* Allocate memory for the arrays */
    *vals = (double *)palloc(vals_count * sizeof(double));
    *weights = (double *)palloc(weights_count * sizeof(double));
    
    /* Copy data, handling NULLs */
    for (i = 0; i < vals_count; i++) {
        *(*vals + i) = vals_nulls[i] ? 0.0 : DatumGetFloat8(vals_datums[i]);
        *(*weights + i) = weights_nulls[i] ? 0.0 : DatumGetFloat8(weights_datums[i]);
    }
    
    return 0;
}

/* 
 * weighted_mean_sparse_c - C implementation of weighted mean for sparse data
 * 
 * Calculates the weighted mean where sum(weights) < 1.0 implies implicit zeros
 * in the dataset. This sparse data representation is useful for incomplete or
 * sampled datasets where missing values are assumed to be zero.
 * 
 * Exposed as: weighted_mean(values[], weights[])
 */
PG_FUNCTION_INFO_V1(weighted_mean_sparse_c);

Datum
weighted_mean_sparse_c(PG_FUNCTION_ARGS)
{
    ArrayType *vals_array, *weights_array;
    double *vals, *weights;
    int n_elements;
    double sum_weighted = 0.0;
    double sum_weights = 0.0;
    int i;
    
    /* Handle NULL inputs */
    if (PG_ARGISNULL(0) || PG_ARGISNULL(1)) {
        PG_RETURN_FLOAT8(0.0);
    }
    
    /* Get input arrays */
    vals_array = PG_GETARG_ARRAYTYPE_P(0);
    weights_array = PG_GETARG_ARRAYTYPE_P(1);
    
    /* Extract arrays */
    if (extract_double_arrays(vals_array, weights_array, &vals, &weights, &n_elements) < 0) {
        PG_RETURN_FLOAT8(0.0);
    }
    
    /* Handle empty arrays */
    if (n_elements == 0) {
        pfree(vals);
        pfree(weights);
        PG_RETURN_FLOAT8(0.0);
    }
    
    /* Calculate weighted sum and total weight */
    for (i = 0; i < n_elements; i++) {
        if (weights[i] > 0.0) {
            sum_weighted += vals[i] * weights[i];
            sum_weights += weights[i];
        }
    }
    
    /* Clean up */
    pfree(vals);
    pfree(weights);
    
    /* Return weighted mean (sparse data: sum_weights represents total weight) */
    PG_RETURN_FLOAT8(sum_weighted);
}

/*
 * weighted_quantile_sparse_c - C implementation of weighted quantiles for sparse data
 * 
 * Calculates weighted quantiles where sum(weights) < 1.0 implies implicit zeros
 * in the dataset. This sparse data representation allows efficient processing of
 * incomplete datasets. Supports multiple quantiles in a single pass for efficiency.
 * 
 * Uses linear interpolation for accurate quantile estimation and handles edge cases
 * gracefully (empty data, single values, boundary quantiles).
 * 
 * Exposed as: weighted_quantile(values[], weights[], quantiles[])
 */
PG_FUNCTION_INFO_V1(weighted_quantile_sparse_c);

Datum
weighted_quantile_sparse_c(PG_FUNCTION_ARGS)
{
    ArrayType *vals_array, *weights_array, *quantiles_array;
    double *vals, *weights, *quantiles;
    int n_elements, n_quantiles;
    double total_weight = 0.0;
    ValueWeight *vw_pairs;
    int n_pairs = 0;
    ArrayType *result_array;
    Datum *result_datums;
    Datum *q_datums;
    bool *q_nulls;
    int q_count;
    int i, q_idx;
    
    /* Handle NULL inputs */
    if (PG_ARGISNULL(0) || PG_ARGISNULL(1) || PG_ARGISNULL(2)) {
        /* Return array of zeros */
        quantiles_array = PG_GETARG_ARRAYTYPE_P(2);
        
        deconstruct_array(quantiles_array, FLOAT8OID, 8, FLOAT8PASSBYVAL, 'd',
                          &q_datums, &q_nulls, &q_count);
        
        result_datums = (Datum *)palloc(q_count * sizeof(Datum));
        for (i = 0; i < q_count; i++) {
            result_datums[i] = Float8GetDatum(0.0);
        }
        
        result_array = construct_array(result_datums, q_count, FLOAT8OID,
                                       8, FLOAT8PASSBYVAL, 'd');
        
        pfree(result_datums);
        PG_RETURN_ARRAYTYPE_P(result_array);
    }
    
    /* Get input arrays */
    vals_array = PG_GETARG_ARRAYTYPE_P(0);
    weights_array = PG_GETARG_ARRAYTYPE_P(1);
    quantiles_array = PG_GETARG_ARRAYTYPE_P(2);
    
    /* Extract quantiles array */
    deconstruct_array(quantiles_array, FLOAT8OID, 8, FLOAT8PASSBYVAL, 'd',
                      &q_datums, &q_nulls, &n_quantiles);
    
    quantiles = (double *)palloc(n_quantiles * sizeof(double));
    for (i = 0; i < n_quantiles; i++) {
        quantiles[i] = q_nulls[i] ? 0.0 : DatumGetFloat8(q_datums[i]);
    }
    
    /* Extract value and weight arrays */
    if (extract_double_arrays(vals_array, weights_array, &vals, &weights, &n_elements) < 0) {
        /* Return zeros on error */
        result_datums = (Datum *)palloc(n_quantiles * sizeof(Datum));
        for (i = 0; i < n_quantiles; i++) {
            result_datums[i] = Float8GetDatum(0.0);
        }
        
        result_array = construct_array(result_datums, n_quantiles, FLOAT8OID,
                                       8, FLOAT8PASSBYVAL, 'd');
        
        pfree(quantiles);
        pfree(result_datums);
        PG_RETURN_ARRAYTYPE_P(result_array);
    }
    
    /* Pre-allocate for worst case: all elements + 1 for sparse data */
    vw_pairs = (ValueWeight *)palloc((n_elements + 1) * sizeof(ValueWeight));
    
    /* Create value-weight pairs for non-zero weights */
    for (i = 0; i < n_elements; i++) {
        if (__builtin_expect(weights[i] > 0.0, 1)) {
            vw_pairs[n_pairs].value = vals[i];
            vw_pairs[n_pairs].weight = weights[i];
            total_weight += weights[i];
            n_pairs++;
        }
    }
    
    /* Handle sparse data: add implicit zero if total weight < 1.0 */
    if (total_weight < 1.0) {
        vw_pairs[n_pairs].value = 0.0;
        vw_pairs[n_pairs].weight = 1.0 - total_weight;
        n_pairs++;
        total_weight = 1.0;
    }
    
    /* Sort by value using optimized algorithm */
    optimized_sort_value_weight_pairs(vw_pairs, n_pairs);
    
    /* Single-pass quantile calculation - much more efficient */
    result_datums = (Datum *)palloc(n_quantiles * sizeof(Datum));
    
    /* Pre-compute cumulative weights */
    double *cumulative_weights = (double *)palloc(n_pairs * sizeof(double));
    double cumsum = 0.0;
    for (i = 0; i < n_pairs; i++) {
        cumsum += vw_pairs[i].weight;
        cumulative_weights[i] = cumsum;
    }
    
    /* Calculate all quantiles in single pass */
    for (q_idx = 0; q_idx < n_quantiles; q_idx++) {
        double q = quantiles[q_idx];
        double target_weight = q * total_weight;
        double result_value;
        
        /* Handle edge cases first */
        if (q <= 0.0) {
            result_value = vw_pairs[0].value;
        } else if (q >= 1.0) {
            result_value = vw_pairs[n_pairs - 1].value;
        } else if (target_weight <= vw_pairs[0].weight) {
            result_value = vw_pairs[0].value;
        } else {
            /* Binary search for efficiency with many quantiles */
            int left = 0, right = n_pairs - 1;
            int pos = n_pairs - 1;
            
            /* Find position where cumulative_weight >= target_weight */
            while (left <= right) {
                int mid = (left + right) / 2;
                if (cumulative_weights[mid] >= target_weight) {
                    pos = mid;
                    right = mid - 1;
                } else {
                    left = mid + 1;
                }
            }
            
            if (pos == 0 || cumulative_weights[pos] == target_weight) {
                result_value = vw_pairs[pos].value;
            } else {
                /* Linear interpolation */
                double prev_cumsum = cumulative_weights[pos - 1];
                double curr_cumsum = cumulative_weights[pos];
                double lower_val = vw_pairs[pos - 1].value;
                double upper_val = vw_pairs[pos].value;
                double interp_factor = (target_weight - prev_cumsum) / (curr_cumsum - prev_cumsum);
                result_value = lower_val + interp_factor * (upper_val - lower_val);
            }
        }
        
        result_datums[q_idx] = Float8GetDatum(result_value);
    }
    
    pfree(cumulative_weights);
    
    /* Create result array */
    result_array = construct_array(result_datums, n_quantiles, FLOAT8OID,
                                   8, FLOAT8PASSBYVAL, 'd');
    
    /* Clean up */
    pfree(vals);
    pfree(weights);
    pfree(quantiles);
    pfree(vw_pairs);
    pfree(result_datums);
    
    PG_RETURN_ARRAYTYPE_P(result_array);
}