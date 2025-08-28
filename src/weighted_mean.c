/*
 * Weighted Statistics PostgreSQL Extension - Weighted Mean
 * 
 * Implementation of weighted mean function for sparse data.
 */

#include "postgres.h"
#include "fmgr.h"
#include "utils/array.h"
#include "utils/lsyscache.h"
#include "utils/builtins.h"
#include <math.h>

#include "utils.h"

/* PostgreSQL extension module magic */
PG_MODULE_MAGIC;

/* 
 * weighted_mean_sparse_c - C implementation of weighted mean for sparse data
 * 
 * Calculates the weighted mean where sum(weights) < 1.0 implies implicit zeros
 * in the dataset. This matches the implementation in weighted_stats.py.
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
        PG_RETURN_NULL();
    }
    
    /* Get input arrays */
    vals_array = PG_GETARG_ARRAYTYPE_P(0);
    weights_array = PG_GETARG_ARRAYTYPE_P(1);
    
    /* Extract arrays */
    if (extract_double_arrays(vals_array, weights_array, &vals, &weights, &n_elements) < 0) {
        PG_RETURN_NULL();
    }
    
    /* Handle empty arrays */
    if (n_elements == 0) {
        pfree(vals);
        pfree(weights);
        PG_RETURN_NULL();
    }
    
    /* Calculate weighted sum and total weight */
    for (i = 0; i < n_elements; i++) {
        if (weights[i] < 0.0) {
            pfree(vals);
            pfree(weights);
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                     errmsg("weights must be non-negative")));
        }
        if (isnan(vals[i]) || isinf(vals[i]) || isnan(weights[i]) || isinf(weights[i])) {
            pfree(vals);
            pfree(weights);
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                     errmsg("input arrays must not contain NaN or infinite values")));
        }
        if (weights[i] > 0.0) {
            sum_weighted += vals[i] * weights[i];
            sum_weights += weights[i];
        }
    }
    
    /* Handle sparse data: if sum_weights < 1.0, add implicit zero */
    if (sum_weights < 1.0) {
        /* Implicit zero with weight (1.0 - sum_weights) */
        /* sum_weighted += 0.0 * (1.0 - sum_weights) = unchanged */
        sum_weights = 1.0;
    }
    
    /* Clean up */
    pfree(vals);
    pfree(weights);
    
    /* Return weighted mean */
    if (sum_weights == 0.0) {
        PG_RETURN_NULL();
    }
    
    PG_RETURN_FLOAT8(sum_weighted / sum_weights);
}