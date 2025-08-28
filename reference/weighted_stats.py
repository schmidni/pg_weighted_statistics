#!/usr/bin/env python3
"""
Weighted statistics functions using numpy and scipy.

This module provides reference implementations for weighted statistical
calculations including mean, variance, and standard deviation.
All functions handle sparse data where sum(weights) < 1.0 implies
implicit zeros.
"""

import numpy as np


def weighted_mean(values: np.ndarray, weights: np.ndarray) -> float:
    """
    Calculate weighted mean for sparse data where sum(weights) < 1.0
    implies implicit zeros.

    Parameters
    ----------
    values : np.ndarray
        Array of values
    weights : np.ndarray
        Array of weights (may sum to less than 1.0)

    Returns
    -------
    float
        The weighted mean accounting for implicit zeros
    """
    if len(values) == 0 or len(weights) == 0:
        return 0.0

    if len(values) != len(weights):
        raise ValueError("Values and weights must have the same length")

    # Convert to numpy arrays if needed
    values = np.asarray(values)
    weights = np.asarray(weights)

    # Check for negative weights
    if np.any(weights < 0):
        raise ValueError("Weights must be non-negative")

    sum_weights = np.sum(weights)

    # Handle sparse data by adding implicit zero
    if sum_weights < 1.0:
        # Add a zero with remaining weight
        values = np.append(values, 0.0)
        weights = np.append(weights, 1.0 - sum_weights)
        sum_weights = 1.0

    if sum_weights == 0:
        return 0.0

    # Use numpy's average function for weighted mean
    return np.average(values, weights=weights)


def weighted_variance(values: np.ndarray, weights: np.ndarray,
                      ddof: int = 0) -> float:
    """
    Calculate weighted variance for sparse data where sum(weights) < 1.0
    implies implicit zeros.

    Parameters
    ----------
    values : np.ndarray
        Array of values
    weights : np.ndarray
        Array of weights (may sum to less than 1.0)
    ddof : int, optional
        Delta degrees of freedom. Default is 0 (population variance).
        Use ddof=1 for sample variance.

    Returns
    -------
    float
        The weighted variance accounting for implicit zeros

    Notes
    -----
    The weighted variance is calculated as:
    - For ddof=0: sum(weights * (values - mean)^2) / sum(weights)
    - For ddof=1: uses Bessel's correction with effective sample size
    """
    if len(values) == 0 or len(weights) == 0:
        return 0.0

    if len(values) != len(weights):
        raise ValueError("Values and weights must have the same length")

    # Convert to numpy arrays if needed
    values = np.asarray(values)
    weights = np.asarray(weights)

    # Check for negative weights
    if np.any(weights < 0):
        raise ValueError("Weights must be non-negative")

    sum_weights = np.sum(weights)

    # Handle sparse data by adding implicit zero
    if sum_weights < 1.0:
        # Add a zero with remaining weight
        values = np.append(values, 0.0)
        weights = np.append(weights, 1.0 - sum_weights)
        sum_weights = 1.0

    if sum_weights == 0:
        return 0.0

    # Calculate weighted mean using numpy
    mean = np.average(values, weights=weights)

    # Calculate weighted variance using numpy operations
    if ddof == 0:
        # Population variance using numpy
        variance = np.average((values - mean) ** 2, weights=weights)
    else:
        # Sample variance with Bessel's correction
        # For weighted data, the effective sample size is used
        n_eff = sum_weights ** 2 / np.sum(weights ** 2)

        if n_eff <= ddof:
            return np.nan

        # Unbiased weighted variance
        variance = np.average((values - mean) ** 2,
                              weights=weights) * n_eff / (n_eff - ddof)

    return variance


def weighted_std(values: np.ndarray, weights: np.ndarray,
                 ddof: int = 0) -> float:
    """
    Calculate weighted standard deviation for sparse data
    where sum(weights) < 1.0 implies implicit zeros.

    Parameters
    ----------
    values : np.ndarray
        Array of values
    weights : np.ndarray
        Array of weights (may sum to less than 1.0)
    ddof : int, optional
        Delta degrees of freedom. Default is 0 (population standard deviation).
        Use ddof=1 for sample standard deviation.

    Returns
    -------
    float
        The weighted standard deviation accounting for implicit zeros
    """
    variance = weighted_variance(values, weights, ddof=ddof)
    return np.sqrt(variance)
