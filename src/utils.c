/*
 * Weighted Statistics PostgreSQL Extension - Utility Functions
 * 
 * Shared utility functions for weighted statistics calculations.
 */

#include "postgres.h"
#include "fmgr.h"
#include "utils/array.h"
#include "utils/lsyscache.h"
#include "utils/builtins.h"
#include "catalog/pg_type.h"
#include <math.h>
#include <string.h>
#include <stdint.h>

#include "utils.h"

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
    ValueWeight *temp;
    union { double d; uint64_t u; } conv;
    int byte, i;
    
    if (n <= 1) return;
    
    /* Use radix sort for large arrays, qsort for small ones */
    if (n < 256) {
        qsort(pairs, n, sizeof(ValueWeight), compare_value_weight);
        return;
    }
    
    /* Radix sort implementation for IEEE 754 doubles */
    temp = (ValueWeight *)palloc(n * sizeof(ValueWeight));
    
    /* Sort by each byte of the double, from most significant */
    for (byte = 7; byte >= 0; byte--) {
        int count[256] = {0};
        int shift = byte * 8;
        uint64_t key;
        int bucket;
        
        /* Count occurrences */
        for (i = 0; i < n; i++) {
            conv.d = pairs[i].value;
            key = conv.u;
            /* Transform IEEE 754 bit pattern for correct radix sort ordering:
             * - For negative numbers (sign bit set): flip all bits
             * - For positive numbers (sign bit clear): flip only sign bit */
            if (key & 0x8000000000000000ULL) {
                key = ~key;
            } else {
                key ^= 0x8000000000000000ULL;
            }
            count[(key >> shift) & 0xFF]++;
        }
        
        /* Calculate positions */
        for (i = 1; i < 256; i++) {
            count[i] += count[i-1];
        }
        
        /* Place elements in sorted order */
        for (i = n - 1; i >= 0; i--) {
            conv.d = pairs[i].value;
            key = conv.u;
            if (key & 0x8000000000000000ULL) {
                key = ~key;
            } else {
                key ^= 0x8000000000000000ULL;
            }
            bucket = (key >> shift) & 0xFF;
            temp[--count[bucket]] = pairs[i];
        }
        
        /* Copy back */
        memcpy(pairs, temp, n * sizeof(ValueWeight));
    }
    
    pfree(temp);
}

/* Counting sort for when value range is small */
static void counting_sort_value_weight_pairs(ValueWeight *pairs, int n) {
    double min_val, max_val, range;
    int range_int, *count, bucket, i;
    ValueWeight *temp;
    
    if (n <= 1) return;
    
    /* Find min and max values */
    min_val = pairs[0].value;
    max_val = pairs[0].value;
    
    for (i = 1; i < n; i++) {
        if (pairs[i].value < min_val) min_val = pairs[i].value;
        if (pairs[i].value > max_val) max_val = pairs[i].value;
    }
    
    range = max_val - min_val;
    
    /* Use counting sort only if range is reasonable */
    if (range <= 0 || range > 10000 || range != floor(range)) {
        /* Fall back to radix sort */
        radix_sort_value_weight_pairs(pairs, n);
        return;
    }
    
    range_int = (int)range + 1;
    count = (int *)palloc0(range_int * sizeof(int));
    temp = (ValueWeight *)palloc(n * sizeof(ValueWeight));
    
    /* Count occurrences */
    for (i = 0; i < n; i++) {
        bucket = (int)(pairs[i].value - min_val);
        /* Guard against potential overflow */
        if (bucket < 0 || bucket >= range_int) {
            /* Fall back to radix sort for safety */
            pfree(count);
            pfree(temp);
            radix_sort_value_weight_pairs(pairs, n);
            return;
        }
        count[bucket]++;
    }
    
    /* Calculate positions */
    for (i = 1; i < range_int; i++) {
        count[i] += count[i-1];
    }
    
    /* Place elements */
    for (i = n - 1; i >= 0; i--) {
        bucket = (int)(pairs[i].value - min_val);
        temp[--count[bucket]] = pairs[i];
    }
    
    /* Copy back */
    memcpy(pairs, temp, n * sizeof(ValueWeight));
    
    pfree(count);
    pfree(temp);
}

/* Intelligent sorting dispatch */
void optimized_sort_value_weight_pairs(ValueWeight *pairs, int n) {
    double min_val, max_val, range;
    bool all_integers;
    int i;
    
    if (n <= 1) return;
    
    /* For small arrays, use standard qsort */
    if (n < 32) {
        qsort(pairs, n, sizeof(ValueWeight), compare_value_weight);
        return;
    }
    
    /* Analyze value distribution to choose best algorithm */
    min_val = pairs[0].value;
    max_val = pairs[0].value;
    all_integers = true;
    
    for (i = 0; i < n; i++) {
        if (pairs[i].value < min_val) min_val = pairs[i].value;
        if (pairs[i].value > max_val) max_val = pairs[i].value;
        if (pairs[i].value != floor(pairs[i].value)) all_integers = false;
    }
    
    range = max_val - min_val;
    
    /* Use counting sort for small integer ranges */
    if (all_integers && range > 0 && range <= 1000 && n > 100) {
        counting_sort_value_weight_pairs(pairs, n);
    } else {
        /* Use radix sort for everything else */
        radix_sort_value_weight_pairs(pairs, n);
    }
}

/* Utility function to extract double arrays from PostgreSQL arrays */
int
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
 * Shared weighted variance calculation function
 * Returns NaN for invalid parameters, otherwise returns variance
 */
double
calculate_weighted_variance(double *vals, double *weights, int n_elements, int ddof) {
    double sum_weighted = 0.0;
    double sum_weights = 0.0;
    double mean = 0.0;
    double variance = 0.0;
    int i;
    double original_sum_weights;
    double sum_weighted_sq_dev;
    double sum_weights_sq;
    double n_eff;
    
    /* Validate inputs */
    if (!vals || !weights || n_elements < 0 || ddof < 0) {
        return NAN;
    }
    
    /* Handle empty arrays */
    if (n_elements == 0) {
        return 0.0;
    }
    
    /* Check for negative weights and calculate total weight */
    for (i = 0; i < n_elements; i++) {
        if (weights[i] < 0.0) {
            return NAN;
        }
        if (weights[i] > 0.0) {
            sum_weights += weights[i];
        }
    }
    
    /* Handle sparse data: if sum_weights < 1.0, we'll add implicit zero */
    original_sum_weights = sum_weights;
    if (sum_weights < 1.0) {
        sum_weights = 1.0;
    }
    
    if (sum_weights == 0.0) {
        return 0.0;
    }
    
    /* Calculate weighted mean first */
    for (i = 0; i < n_elements; i++) {
        if (weights[i] > 0.0) {
            sum_weighted += vals[i] * weights[i];
        }
    }
    mean = sum_weighted / sum_weights;
    
    /* Calculate weighted variance */
    sum_weighted_sq_dev = 0.0;
    
    /* Sum of weighted squared deviations for explicit values */
    for (i = 0; i < n_elements; i++) {
        if (weights[i] > 0.0) {
            double deviation = vals[i] - mean;
            sum_weighted_sq_dev += weights[i] * deviation * deviation;
        }
    }
    
    /* Add contribution from implicit zero if needed */
    if (original_sum_weights < 1.0) {
        double zero_weight = 1.0 - original_sum_weights;
        double deviation = 0.0 - mean;
        sum_weighted_sq_dev += zero_weight * deviation * deviation;
    }
    
    /* Calculate variance based on ddof */
    if (ddof == 0) {
        /* Population variance */
        variance = sum_weighted_sq_dev / sum_weights;
    } else {
        /* Sample variance with Bessel's correction */
        /* Calculate effective sample size */
        sum_weights_sq = 0.0;
        
        for (i = 0; i < n_elements; i++) {
            if (weights[i] > 0.0) {
                sum_weights_sq += weights[i] * weights[i];
            }
        }
        
        /* Add contribution from implicit zero if needed */
        if (original_sum_weights < 1.0) {
            double zero_weight = 1.0 - original_sum_weights;
            sum_weights_sq += zero_weight * zero_weight;
        }
        
        n_eff = sum_weights * sum_weights / sum_weights_sq;
        
        if (n_eff <= ddof) {
            return NAN;
        }
        
        /* Unbiased weighted variance */
        variance = sum_weighted_sq_dev / sum_weights * n_eff / (n_eff - ddof);
    }
    
    return variance;
}