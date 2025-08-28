/*
 * Weighted Statistics PostgreSQL Extension - Weighted Variance & Std Dev
 * 
 * Implementation of weighted variance and standard deviation functions.
 */

#include "postgres.h"
#include "fmgr.h"
#include "utils/array.h"
#include "utils/lsyscache.h"
#include "utils/builtins.h"
#include <math.h>

#include "utils.h"

/*
 * weighted_variance_sparse_c - Weighted variance for sparse data
 * 
 * Calculates weighted variance with optional ddof (degrees of freedom) parameter.
 * When ddof=0 (default): population variance
 * When ddof=1: sample variance with Bessel's correction
 * 
 * Exposed as: weighted_variance(values[], weights[], ddof DEFAULT 0)
 */
PG_FUNCTION_INFO_V1(weighted_variance_sparse_c);

Datum
weighted_variance_sparse_c(PG_FUNCTION_ARGS)
{
    ArrayType *vals_array, *weights_array;
    double *vals, *weights;
    int n_elements;
    int ddof = 0;
    double variance;
    
    /* Handle NULL inputs */
    if (PG_ARGISNULL(0) || PG_ARGISNULL(1)) {
        PG_RETURN_NULL();
    }
    
    /* Get input arrays */
    vals_array = PG_GETARG_ARRAYTYPE_P(0);
    weights_array = PG_GETARG_ARRAYTYPE_P(1);
    
    /* Get optional ddof parameter (default 0) */
    if (!PG_ARGISNULL(2)) {
        ddof = PG_GETARG_INT32(2);
        if (ddof < 0) {
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                     errmsg("ddof must be non-negative")));
        }
    }
    
    /* Extract arrays */
    if (extract_double_arrays(vals_array, weights_array, &vals, &weights, &n_elements) < 0) {
        PG_RETURN_NULL();
    }
    
    /* Check for negative weights and invalid values */
    for (int i = 0; i < n_elements; i++) {
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
    }
    
    /* Calculate variance using shared function */
    variance = calculate_weighted_variance(vals, weights, n_elements, ddof);
    
    /* Clean up */
    pfree(vals);
    pfree(weights);
    
    /* Handle NaN result */
    if (isnan(variance)) {
        PG_RETURN_NULL();
    }
    
    PG_RETURN_FLOAT8(variance);
}

/*
 * weighted_std_sparse_c - Weighted standard deviation for sparse data
 * 
 * Calculates weighted standard deviation as sqrt of variance.
 * 
 * Exposed as: weighted_std(values[], weights[], ddof DEFAULT 0)
 */
PG_FUNCTION_INFO_V1(weighted_std_sparse_c);

Datum
weighted_std_sparse_c(PG_FUNCTION_ARGS)
{
    ArrayType *vals_array, *weights_array;
    double *vals, *weights;
    int n_elements;
    int ddof = 0;
    double variance;
    
    /* Handle NULL inputs */
    if (PG_ARGISNULL(0) || PG_ARGISNULL(1)) {
        PG_RETURN_NULL();
    }
    
    /* Get input arrays */
    vals_array = PG_GETARG_ARRAYTYPE_P(0);
    weights_array = PG_GETARG_ARRAYTYPE_P(1);
    
    /* Get optional ddof parameter (default 0) */
    if (!PG_ARGISNULL(2)) {
        ddof = PG_GETARG_INT32(2);
        if (ddof < 0) {
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                     errmsg("ddof must be non-negative")));
        }
    }
    
    /* Extract arrays */
    if (extract_double_arrays(vals_array, weights_array, &vals, &weights, &n_elements) < 0) {
        PG_RETURN_NULL();
    }
    
    /* Check for negative weights and invalid values */
    for (int i = 0; i < n_elements; i++) {
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
    }
    
    /* Calculate variance using shared function */
    variance = calculate_weighted_variance(vals, weights, n_elements, ddof);
    
    /* Clean up */
    pfree(vals);
    pfree(weights);
    
    /* Handle NaN result */
    if (isnan(variance)) {
        PG_RETURN_NULL();
    }
    
    /* Return standard deviation (square root of variance) */
    PG_RETURN_FLOAT8(sqrt(variance));
}