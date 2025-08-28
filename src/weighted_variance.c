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
    double sum_weighted = 0.0;
    double sum_weights = 0.0;
    double mean = 0.0;
    double variance = 0.0;
    int i;
    double original_sum_weights;
    double sum_weighted_sq_dev;
    double sum_weights_sq;
    double n_eff;
    
    /* Handle NULL inputs */
    if (PG_ARGISNULL(0) || PG_ARGISNULL(1)) {
        PG_RETURN_FLOAT8(0.0);
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
        PG_RETURN_FLOAT8(0.0);
    }
    
    /* Handle empty arrays */
    if (n_elements == 0) {
        pfree(vals);
        pfree(weights);
        PG_RETURN_FLOAT8(0.0);
    }
    
    /* Check for negative weights and calculate total weight */
    for (i = 0; i < n_elements; i++) {
        if (weights[i] < 0.0) {
            pfree(vals);
            pfree(weights);
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                     errmsg("weights must be non-negative")));
        }
        if (weights[i] > 0.0) {
            sum_weights += weights[i];
        }
    }
    
    /* Handle sparse data: if sum_weights < 1.0, we'll add implicit zero */
    original_sum_weights = sum_weights;
    if (sum_weights < 1.0) {
        /* We'll handle the implicit zero separately */
        sum_weights = 1.0;
    }
    
    if (sum_weights == 0.0) {
        pfree(vals);
        pfree(weights);
        PG_RETURN_FLOAT8(0.0);
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
            pfree(vals);
            pfree(weights);
            PG_RETURN_NULL();  /* Return NULL instead of NaN */
        }
        
        /* Unbiased weighted variance */
        variance = sum_weighted_sq_dev / sum_weights * n_eff / (n_eff - ddof);
    }
    
    /* Clean up */
    pfree(vals);
    pfree(weights);
    
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
    double sum_weighted = 0.0;
    double sum_weights = 0.0;
    double mean = 0.0;
    double variance = 0.0;
    int i;
    double original_sum_weights;
    double sum_weighted_sq_dev;
    double sum_weights_sq;
    double n_eff;
    
    /* Handle NULL inputs */
    if (PG_ARGISNULL(0) || PG_ARGISNULL(1)) {
        PG_RETURN_FLOAT8(0.0);
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
        PG_RETURN_FLOAT8(0.0);
    }
    
    /* Handle empty arrays */
    if (n_elements == 0) {
        pfree(vals);
        pfree(weights);
        PG_RETURN_FLOAT8(0.0);
    }
    
    /* Check for negative weights and calculate total weight */
    for (i = 0; i < n_elements; i++) {
        if (weights[i] < 0.0) {
            pfree(vals);
            pfree(weights);
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                     errmsg("weights must be non-negative")));
        }
        if (weights[i] > 0.0) {
            sum_weights += weights[i];
        }
    }
    
    /* Handle sparse data: if sum_weights < 1.0, we'll add implicit zero */
    original_sum_weights = sum_weights;
    if (sum_weights < 1.0) {
        /* We'll handle the implicit zero separately */
        sum_weights = 1.0;
    }
    
    if (sum_weights == 0.0) {
        pfree(vals);
        pfree(weights);
        PG_RETURN_FLOAT8(0.0);
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
            pfree(vals);
            pfree(weights);
            PG_RETURN_NULL();  /* Return NULL instead of NaN */
        }
        
        /* Unbiased weighted variance */
        variance = sum_weighted_sq_dev / sum_weights * n_eff / (n_eff - ddof);
    }
    
    /* Clean up */
    pfree(vals);
    pfree(weights);
    
    /* Return standard deviation (square root of variance) */
    PG_RETURN_FLOAT8(sqrt(variance));
}