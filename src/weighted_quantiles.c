/*
 * Weighted Statistics PostgreSQL Extension - Weighted Quantiles
 * 
 * Implementation of weighted quantile functions including:
 * - weighted_quantile: Simple weighted empirical CDF (existing)
 * - wquantile: Weighted Type 7 quantile (linear interpolation)
 * - whdquantile: Weighted Harrell-Davis quantile
 */

#include "postgres.h"
#include "fmgr.h"
#include "utils/array.h"
#include "utils/lsyscache.h"
#include "utils/builtins.h"
#include "catalog/pg_type.h"
#include <math.h>
#include <string.h>

#include "utils.h"

/* Regularized Incomplete Beta Function for Harrell-Davis quantile */
/* Based on "Regularized Incomplete Beta Function" by Lewis Van Winkle */
/* Uses Lentz's algorithm for continued fraction evaluation */
#define STOP 1.0e-8
#define TINY 1.0e-30

static double beta_cdf(double x, double a, double b) {
    const double lbeta_ab = lgamma(a) + lgamma(b) - lgamma(a + b);
    const double front = exp(log(x) * a + log(1.0 - x) * b - lbeta_ab) / a;
    double f = 1.0, c = 1.0, d = 0.0;
    int i, m;
    double numerator;
    double cd;
    
    /* Handle edge cases */
    if (x <= 0.0) return 0.0;
    if (x >= 1.0) return 1.0;
    
    /* Check for invalid parameters */
    if (a <= 0.0 || b <= 0.0) {
        /* Return NaN for invalid parameters */
        return NAN;
    }
    
    /* The continued fraction converges nicely for x < (a+1)/(a+b+2) */
    if (x > (a + 1.0) / (a + b + 2.0)) {
        /* Use the fact that beta is symmetrical */
        return 1.0 - beta_cdf(1.0 - x, b, a);
    }
    
    /* Use Lentz's algorithm to evaluate the continued fraction */
    for (i = 0; i <= 200; ++i) {
        m = i / 2;
        
        if (i == 0) {
            numerator = 1.0; /* First numerator is 1.0 */
        } else if (i % 2 == 0) {
            /* Even term */
            numerator = (m * (b - m) * x) / ((a + 2.0 * m - 1.0) * (a + 2.0 * m));
        } else {
            /* Odd term */
            numerator = -((a + m) * (a + b + m) * x) / ((a + 2.0 * m) * (a + 2.0 * m + 1.0));
        }
        
        /* Do an iteration of Lentz's algorithm */
        d = 1.0 + numerator * d;
        if (fabs(d) < TINY) d = TINY;
        d = 1.0 / d;
        
        c = 1.0 + numerator / c;
        if (fabs(c) < TINY) c = TINY;
        
        cd = c * d;
        f *= cd;
        
        /* Check for stop */
        if (fabs(1.0 - cd) < STOP) {
            return front * (f - 1.0);
        }
    }
    
    /* Did not converge, return NaN */
    return NAN;
}

/*
 * weighted_quantile_sparse_c - Simple weighted quantile using empirical CDF
 * 
 * This is the existing implementation that corresponds to Python's weighted_quantile
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
    double *cumulative_weights;
    double cumsum;
    
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
        /* Validate quantile values */
        if (quantiles[i] < 0.0 || quantiles[i] > 1.0 || isnan(quantiles[i]) || isinf(quantiles[i])) {
            pfree(quantiles);
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                     errmsg("quantile values must be between 0 and 1")));
        }
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
        if (weights[i] > 0.0) {
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
    
    /* Single-pass quantile calculation */
    result_datums = (Datum *)palloc(n_quantiles * sizeof(Datum));
    
    /* Pre-compute cumulative weights */
    cumulative_weights = (double *)palloc(n_pairs * sizeof(double));
    cumsum = 0.0;
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

/*
 * wquantile_sparse_c - Weighted Type 7 quantile (linear interpolation)
 * 
 * Generalizes Hyndman-Fan Type 7 to weighted samples
 */
PG_FUNCTION_INFO_V1(wquantile_sparse_c);

Datum
wquantile_sparse_c(PG_FUNCTION_ARGS)
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
    int i, q_idx;
    double sum_weights_sq, n_eff;
    double *cum_probs;
    
    /* Handle NULL inputs */
    if (PG_ARGISNULL(0) || PG_ARGISNULL(1) || PG_ARGISNULL(2)) {
        quantiles_array = PG_GETARG_ARRAYTYPE_P(2);
        deconstruct_array(quantiles_array, FLOAT8OID, 8, FLOAT8PASSBYVAL, 'd',
                          &q_datums, &q_nulls, &n_quantiles);
        
        result_datums = (Datum *)palloc(n_quantiles * sizeof(Datum));
        for (i = 0; i < n_quantiles; i++) {
            result_datums[i] = Float8GetDatum(0.0);
        }
        
        result_array = construct_array(result_datums, n_quantiles, FLOAT8OID,
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
        /* Validate quantile values */
        if (quantiles[i] < 0.0 || quantiles[i] > 1.0 || isnan(quantiles[i]) || isinf(quantiles[i])) {
            pfree(quantiles);
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                     errmsg("quantile values must be between 0 and 1")));
        }
    }
    
    /* Extract value and weight arrays */
    if (extract_double_arrays(vals_array, weights_array, &vals, &weights, &n_elements) < 0) {
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
        if (weights[i] > 0.0) {
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
    
    /* Sort by value */
    optimized_sort_value_weight_pairs(vw_pairs, n_pairs);
    
    /* Normalize weights */
    for (i = 0; i < n_pairs; i++) {
        vw_pairs[i].weight /= total_weight;
    }
    
    /* Calculate effective sample size using Kish's formula */
    sum_weights_sq = 0.0;
    for (i = 0; i < n_pairs; i++) {
        sum_weights_sq += vw_pairs[i].weight * vw_pairs[i].weight;
    }
    n_eff = 1.0 / sum_weights_sq;
    
    /* Pre-compute cumulative probabilities */
    cum_probs = (double *)palloc((n_pairs + 1) * sizeof(double));
    cum_probs[0] = 0.0;
    for (i = 0; i < n_pairs; i++) {
        cum_probs[i + 1] = cum_probs[i] + vw_pairs[i].weight;
    }
    
    result_datums = (Datum *)palloc(n_quantiles * sizeof(Datum));
    
    /* Calculate each quantile using Type 7 method */
    for (q_idx = 0; q_idx < n_quantiles; q_idx++) {
        double p = quantiles[q_idx];
        double result_value = 0.0;
        double h, u_val, w;
        
        if (p <= 0.0) {
            result_value = vw_pairs[0].value;
        } else if (p >= 1.0) {
            result_value = vw_pairs[n_pairs - 1].value;
        } else {
            /* Type 7 CDF calculation following Python reference */
            h = p * (n_eff - 1) + 1;
            
            /* Calculate weights for each value using Type 7 CDF */
            for (i = 0; i < n_pairs; i++) {
                /* Type 7 CDF: u = max((h-1)/n, min(h/n, cum_probs[i+1])) */
                u_val = fmax((h - 1) / n_eff, fmin(h / n_eff, cum_probs[i + 1]));
                
                /* Weight is the CDF evaluated at this point: w = u*n - h + 1 */
                w = u_val * n_eff - h + 1;
                
                /* Only previous point contributes negatively */
                if (i > 0) {
                    double u_prev = fmax((h - 1) / n_eff, fmin(h / n_eff, cum_probs[i]));
                    double w_prev = u_prev * n_eff - h + 1;
                    w -= w_prev;
                }
                
                result_value += w * vw_pairs[i].value;
            }
        }
        
        result_datums[q_idx] = Float8GetDatum(result_value);
    }
    
    pfree(cum_probs);
    
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

/*
 * whdquantile_sparse_c - Weighted Harrell-Davis quantile
 * 
 * Uses Beta distribution weights for smoothing
 */
PG_FUNCTION_INFO_V1(whdquantile_sparse_c);

Datum
whdquantile_sparse_c(PG_FUNCTION_ARGS)
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
    int i, q_idx;
    double sum_weights_sq, n_eff;
    double *cum_probs;
    
    /* Handle NULL inputs */
    if (PG_ARGISNULL(0) || PG_ARGISNULL(1) || PG_ARGISNULL(2)) {
        quantiles_array = PG_GETARG_ARRAYTYPE_P(2);
        deconstruct_array(quantiles_array, FLOAT8OID, 8, FLOAT8PASSBYVAL, 'd',
                          &q_datums, &q_nulls, &n_quantiles);
        
        result_datums = (Datum *)palloc(n_quantiles * sizeof(Datum));
        for (i = 0; i < n_quantiles; i++) {
            result_datums[i] = Float8GetDatum(0.0);
        }
        
        result_array = construct_array(result_datums, n_quantiles, FLOAT8OID,
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
        /* Validate quantile values */
        if (quantiles[i] < 0.0 || quantiles[i] > 1.0 || isnan(quantiles[i]) || isinf(quantiles[i])) {
            pfree(quantiles);
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                     errmsg("quantile values must be between 0 and 1")));
        }
    }
    
    /* Extract value and weight arrays */
    if (extract_double_arrays(vals_array, weights_array, &vals, &weights, &n_elements) < 0) {
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
        if (weights[i] > 0.0) {
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
    
    /* Sort by value */
    optimized_sort_value_weight_pairs(vw_pairs, n_pairs);
    
    /* Normalize weights */
    for (i = 0; i < n_pairs; i++) {
        vw_pairs[i].weight /= total_weight;
    }
    
    /* Calculate effective sample size using Kish's formula */
    sum_weights_sq = 0.0;
    for (i = 0; i < n_pairs; i++) {
        sum_weights_sq += vw_pairs[i].weight * vw_pairs[i].weight;
    }
    n_eff = 1.0 / sum_weights_sq;
    
    /* Pre-compute cumulative probabilities */
    cum_probs = (double *)palloc((n_pairs + 1) * sizeof(double));
    cum_probs[0] = 0.0;
    for (i = 0; i < n_pairs; i++) {
        cum_probs[i + 1] = cum_probs[i] + vw_pairs[i].weight;
    }
    
    result_datums = (Datum *)palloc(n_quantiles * sizeof(Datum));
    
    /* Calculate each quantile using Harrell-Davis method */
    for (q_idx = 0; q_idx < n_quantiles; q_idx++) {
        double p = quantiles[q_idx];
        double result_value = 0.0;
        
        /* Beta distribution parameters */
        double a = (n_eff + 1) * p;
        double b = (n_eff + 1) * (1 - p);
        
        /* Check for degenerate cases that should return NaN */
        if (p <= 0.0 || p >= 1.0 || n_eff <= 1.0 || n_pairs <= 1 || a <= 0.0 || b <= 0.0) {
            result_value = NAN;  /* Return NaN to match Python behavior */
        } else {
            /* Calculate weights using Beta CDF */
            for (i = 0; i < n_pairs; i++) {
                double q_low = beta_cdf(cum_probs[i], a, b);
                double q_high = beta_cdf(cum_probs[i + 1], a, b);
                double w = q_high - q_low;
                result_value += w * vw_pairs[i].value;
            }
        }
        
        result_datums[q_idx] = Float8GetDatum(result_value);
    }
    
    pfree(cum_probs);
    
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