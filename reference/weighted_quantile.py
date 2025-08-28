import numpy as np
from scipy.stats import beta


def add_missing_zeroes(values, weights):
    """
    Append a value `0` with the "missing weight" if the sum of weights < 1.

    This ensures that the total probability mass sums to 1, which is required
    by the weighted quantile definitions.

    Parameters
    ----------
    values : array-like
        Data values.
    weights : array-like
        Corresponding weights. Sum may be < 1.

    Returns
    -------
    (values, weights) : tuple of np.ndarray
        Extended arrays including the added zero-value with weight
        (1 - sum(weights)), if sum(weights) < 1. Otherwise, unchanged.
    """
    zero_weight = 1 - np.sum(weights)
    v = np.append(
        values, [0])
    w = np.append(
        weights, [zero_weight])
    return (v, w)


def weighted_quantile(values, quantiles, weights):
    """
    Compute weighted quantiles using a simple weighted empirical CDF.

    This method interpolates quantiles directly from the weighted empirical
    distribution: sort the values, compute cumulative weights, and interpolate
    at the requested quantile levels.

    If the total weight is < 1, the "missing" probability mass is placed at 0.

    Parameters
    ----------
    values : array-like
        Sample values.
    quantiles : array-like
        Quantile levels in [0, 1].
    weights : array-like
        Nonnegative weights, same length as `values`.

    Returns
    -------
    np.ndarray
        Estimated quantiles.

    Notes
    -----
    - This corresponds to the "Type 4" Hyndman-Fan quantile definition (linear
      interpolation on the empirical CDF).
    - Simpler but less statistically efficient than the Type 7 or Harrell-Davis
      approaches (see Akinshin 2023).
    """

    values = np.array(values)
    quantiles = np.array(quantiles)
    weights = np.array(weights)

    sum_weight = np.sum(weights)

    assert np.all(quantiles >= 0) and np.all(quantiles <= 1), \
        'Quantiles should be in [0, 1]'

    if sum_weight < 1:
        values, weights = add_missing_zeroes(values, weights)

    sorter = np.argsort(values)
    values = values[sorter]
    weights = weights[sorter]

    weighted_quantiles = np.cumsum(weights)  # C=0

    return np.interp(quantiles, weighted_quantiles, values)


def wquantile_generic(values, quantiles, cdf_gen, weights):
    """
    Generic weighted quantile estimator with user-specified CDF generator.

    This is the framework used in Akinshin (2023): the quantile is defined
    as a weighted sum of sample values, with weights derived from the chosen
    CDF function evaluated over the weighted empirical distribution.

    Parameters
    ----------
    values : array-like
        Sample values.
    quantiles : array-like
        Quantile levels in [0, 1].
    cdf_gen : callable
        Function `cdf_gen(n_eff, p)` returning a callable CDF(x) for given
        effective sample size `n_eff` and quantile probability `p`.
    weights : array-like
        Nonnegative weights, same length as `values`.

    Returns
    -------
    list
        Quantile estimates (one per requested quantile).
    """
    values = np.array(values)
    quantiles = np.array(quantiles)
    weights = np.array(weights)

    sum_weight = np.sum(weights)

    if sum_weight != 1 and sum_weight < 1:
        values, weights = add_missing_zeroes(values, weights)

    nw = sum(weights)**2 / sum(weights**2)
    sorter = np.argsort(values)
    values = values[sorter]
    weights = weights[sorter]

    weights = weights / sum(weights)
    cdf_probs = np.cumsum(np.insert(weights, 0, [0]))
    res = []
    for prob in quantiles:
        cdf = cdf_gen(nw, prob)
        q = cdf(cdf_probs)
        w = q[1:] - q[:-1]
        res.append(np.sum(w * values))
    return res


def whdquantile(values, quantiles, weights):
    """
    Weighted Harrell-Davis quantile estimator.

    The Harrell-Davis estimator expresses a quantile as a weighted average
    of *all* order statistics, with weights derived from a Beta distribution.
    This weighted variant uses the effective sample size (Kish's formula)
    to adjust the Beta parameters.

    Parameters
    ----------
    values : array-like
        Sample values.
    quantiles : array-like
        Quantile levels in [0, 1].
    weights : array-like
        Nonnegative weights, same length as `values`.

    Returns
    -------
    list
        Weighted Harrell-Davis quantile estimates.

    Notes
    -----
    - Smooths over all data points, improving efficiency for light-tailed
      distributions.
    - Sensitive to outliers (low robustness).
    - See Akinshin (2023), Sec. 4.2.
    """
    def cdf_gen_whd(n, p):
        return lambda x: beta.cdf(x, (n + 1) * p, (n + 1) * (1 - p))
    return wquantile_generic(values, quantiles, cdf_gen_whd, weights)


def type_7_cdf(quantiles, n, p):
    """
    Piecewise-linear CDF for Hyndman-Fan Type 7 quantiles.

    Used to interpolate between two adjacent order statistics.

    Parameters
    ----------
    quantiles : np.ndarray
        Cumulative probability points (CDF grid).
    n : int
        Effective sample size.
    p : float
        Target quantile probability.

    Returns
    -------
    np.ndarray
        Evaluated CDF at grid points.
    """
    h = p * (n - 1) + 1
    u = np.maximum((h - 1) / n, np.minimum(h / n, quantiles))
    return u * n - h + 1


def wquantile(values, quantiles, weights):
    """
    Weighted Type 7 quantile estimator (linear interpolation).

    This method generalizes the widely-used Hyndman-Fan Type 7 definition
    (default in R and NumPy) to weighted samples, following Akinshin (2023).

    Parameters
    ----------
    values : array-like
        Sample values.
    quantiles : array-like
        Quantile levels in [0, 1].
    weights : array-like
        Nonnegative weights, same length as `values`.

    Returns
    -------
    list
        Weighted Type 7 quantile estimates.

    Notes
    -----
    - Uses only the two adjacent order statistics near the target quantile.
    - More robust to outliers than Harrell-Davis, but higher variance.
    - Matches classical Type 7 quantiles when weights are uniform.
    - See Akinshin (2023), Sec. 4.1.
    """
    def cdf_gen_t7(n, p):
        return lambda x: type_7_cdf(x, n, p)
    return wquantile_generic(values, quantiles, cdf_gen_t7, weights)
