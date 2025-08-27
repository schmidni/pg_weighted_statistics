/*
 * REIA Weighted Statistics C Extension
 * 
 * High-performance C implementation of weighted mean and quantile functions
 * for sparse data (where sum(weights) < 1.0 implies implicit zeros).
 * 
 * This replaces the PL/pgSQL functions with optimized C code for significant
 * performance improvements on large datasets.
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

/* Version for extension */
PG_MODULE_MAGIC;

/* Data structure for value-weight pairs */
typedef struct {
    double value;
    double weight;
} ValueWeight;

/* Comparison function for sorting value-weight pairs */
static int 
compare_value_weight(const void *a, const void *b) {
    const ValueWeight *vw_a = (const ValueWeight *)a;
    const ValueWeight *vw_b = (const ValueWeight *)b;
    
    if (vw_a->value < vw_b->value) return -1;
    if (vw_a->value > vw_b->value) return 1;
    return 0;
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
 * This function calculates the weighted mean where sum(weights) < 1.0 implies
 * implicit zeros in the dataset (sparse data representation).
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
 * This function calculates weighted quantiles where sum(weights) < 1.0 implies
 * implicit zeros in the dataset. Supports multiple quantiles in a single pass.
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
    
    /* Create value-weight pairs for non-zero weights */
    vw_pairs = (ValueWeight *)palloc(n_elements * sizeof(ValueWeight));
    for (i = 0; i < n_elements; i++) {
        if (weights[i] > 0.0) {
            vw_pairs[n_pairs].value = vals[i];
            vw_pairs[n_pairs].weight = weights[i];
            total_weight += weights[i];
            n_pairs++;
        }
    }
    
    /* Handle sparse data: add implicit zero if total weight < 1.0 */
    if (total_weight < 1.0) {
        vw_pairs = (ValueWeight *)repalloc(vw_pairs, (n_pairs + 1) * sizeof(ValueWeight));
        vw_pairs[n_pairs].value = 0.0;
        vw_pairs[n_pairs].weight = 1.0 - total_weight;
        n_pairs++;
        total_weight = 1.0;
    }
    
    /* Sort by value */
    qsort(vw_pairs, n_pairs, sizeof(ValueWeight), compare_value_weight);
    
    /* Calculate quantiles */
    result_datums = (Datum *)palloc(n_quantiles * sizeof(Datum));
    
    for (q_idx = 0; q_idx < n_quantiles; q_idx++) {
        double q = quantiles[q_idx];
        double target_weight = q * total_weight;
        double cumsum = 0.0;
        double result_value = 0.0;
        
        /* Handle edge cases */
        if (q <= 0.0 || target_weight <= vw_pairs[0].weight) {
            result_value = vw_pairs[0].value;
        } else if (q >= 1.0) {
            result_value = vw_pairs[n_pairs - 1].value;
        } else {
            /* Find position using cumulative sum */
            for (i = 0; i < n_pairs; i++) {
                double prev_cumsum = cumsum;
                cumsum += vw_pairs[i].weight;
                
                if (cumsum >= target_weight) {
                    if (i == 0 || cumsum == target_weight) {
                        result_value = vw_pairs[i].value;
                    } else {
                        /* Linear interpolation */
                        double lower_val = vw_pairs[i-1].value;
                        double upper_val = vw_pairs[i].value;
                        double interp_factor = (target_weight - prev_cumsum) / vw_pairs[i].weight;
                        result_value = lower_val + interp_factor * (upper_val - lower_val);
                    }
                    break;
                }
            }
        }
        
        result_datums[q_idx] = Float8GetDatum(result_value);
    }
    
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