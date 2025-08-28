/*
 * Weighted Statistics PostgreSQL Extension - Utility Functions Header
 * 
 * Shared utility functions and data structures for weighted statistics.
 */

#ifndef WEIGHTED_STATS_UTILS_H
#define WEIGHTED_STATS_UTILS_H

#include "postgres.h"
#include "fmgr.h"
#include "utils/array.h"

/* Data structure for value-weight pairs */
typedef struct {
    double value;
    double weight;
} ValueWeight;

/* Function declarations */
int extract_double_arrays(ArrayType *vals_array, ArrayType *weights_array,
                         double **vals, double **weights, int *n_elements);

void optimized_sort_value_weight_pairs(ValueWeight *pairs, int n);

double calculate_weighted_variance(double *vals, double *weights, int n_elements, int ddof);

#endif /* WEIGHTED_STATS_UTILS_H */