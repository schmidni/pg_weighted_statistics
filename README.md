# Weighted Statistics PostgreSQL Extension

High-performance PostgreSQL extension providing weighted mean and quantile functions optimized for sparse data.

## Quick Start

```sql
CREATE EXTENSION weighted_statistics;

-- Weighted mean
SELECT weighted_mean(ARRAY[1.0, 2.0, 3.0], ARRAY[0.2, 0.3, 0.5]);
-- Result: 2.3

-- Weighted variance and standard deviation
SELECT 
    weighted_variance(ARRAY[1.0, 2.0, 3.0], ARRAY[0.2, 0.3, 0.5], 0) AS pop_var,
    weighted_std(ARRAY[1.0, 2.0, 3.0], ARRAY[0.2, 0.3, 0.5], 1) AS sample_std;
-- Results: pop_var = 0.61, sample_std = 0.87

-- Weighted quantiles (multiple methods)
SELECT 
    weighted_quantile(ARRAY[10.0, 20.0, 30.0], ARRAY[0.3, 0.4, 0.3], ARRAY[0.5]) AS empirical,
    wquantile(ARRAY[10.0, 20.0, 30.0], ARRAY[0.3, 0.4, 0.3], ARRAY[0.5]) AS type7,
    whdquantile(ARRAY[10.0, 20.0, 30.0], ARRAY[0.3, 0.4, 0.3], ARRAY[0.5]) AS harrell_davis;
-- Results: empirical = {18.57}, type7 = {19.29}, harrell_davis = {19.12}

-- Weighted median (convenience function)
SELECT weighted_median(ARRAY[1.0, 2.0, 3.0], ARRAY[0.2, 0.3, 0.5]);
-- Result: 2.0
```

## Features

- **3-10x faster** than PL/pgSQL implementations
- **Sparse data optimization**: Handles `sum(weights) < 1.0` automatically
- **Mathematically validated**: 100% accuracy against Python reference

## Installation

```bash
git clone <repository-url>
cd weighted_statistics
make clean && make && sudo make install
psql -c "CREATE EXTENSION weighted_statistics;"
```

**Requirements**: PostgreSQL 12+, development headers, C compiler

## Functions

### Core Statistics Functions

#### `weighted_mean(values[], weights[])`
Returns weighted mean accounting for sparse data (implicit zeros when `sum(weights) < 1.0`).

#### `weighted_variance(values[], weights[], ddof DEFAULT 0)`
Returns weighted variance. Use `ddof=0` for population variance, `ddof=1` for sample variance.

#### `weighted_std(values[], weights[], ddof DEFAULT 0)`  
Returns weighted standard deviation. Use `ddof=0` for population, `ddof=1` for sample.

### Quantile Functions

#### `weighted_quantile(values[], weights[], quantiles[])`
Simple weighted quantiles using empirical CDF. Fast and robust for general use.

#### `wquantile(values[], weights[], quantiles[])`
Type 7 weighted quantiles (Hyndman-Fan). Generalizes R/NumPy default quantile method to weighted data.

#### `whdquantile(values[], weights[], quantiles[])`
Harrell-Davis weighted quantiles. Smooths over all data points for improved efficiency with light-tailed distributions.

#### `weighted_median(values[], weights[])`
Convenience function returning weighted median (equivalent to `weighted_quantile(..., ARRAY[0.5])[1]`).

## Sparse Data Handling

Key feature: All functions automatically handle sparse data.

```sql
-- These are equivalent:
SELECT weighted_mean(ARRAY[10, 20, 0, 0], ARRAY[0.2, 0.3, 0.25, 0.25]); -- Explicit zeros
SELECT weighted_mean(ARRAY[10, 20], ARRAY[0.2, 0.3]);                    -- Sparse (implicit 0.5 weight of zeros)
-- Both return: 8.0
```

Perfect for incomplete datasets, survey data, risk assessments where "no event" = 0.

## Testing & Validation

Multi-tier testing ensures both mathematical correctness and behavioral consistency:

```bash
# 1. Mathematical correctness (validates functions work correctly)
cd reference && python validate_against_reference.py --database test_db

# 2. Regression testing (PostgreSQL standard)
make installcheck

# 3. Custom regression testing (alternative approach)
./test/run_tests.sh
```

- **`validate_against_reference.py`**: Compares C implementation against Python reference implementations - confirms mathematical accuracy for all functions
- **`make installcheck`**: Uses PostgreSQL's standard regression test framework (pg_regress) - creates temporary test database and runs comprehensive function tests
- **`run_tests.sh`**: Custom test runner that uses existing database - provides same comprehensive testing with more flexibility

## Performance

### Quick Performance Test

Run a simple performance comparison and scaling analysis:

```bash
./benchmark/run_simple_benchmark.sh
```

This compares C vs PL/pgSQL performance and shows:
- **3-10x faster** than PL/pgSQL implementations  
- **Linear scaling** with array size (100 to 10K elements)
- **Multi-quantile efficiency**: Computing 5 quantiles ~1.5x slower than 1 quantile
- **Sparse data optimization**: Consistent performance across sparsity levels

### Key Performance Characteristics
- **Small arrays (100-500 elements)**: ~0.2-0.5ms execution time
- **Medium arrays (1K-5K elements)**: ~0.3-1ms execution time  
- **Optimization**: Compiled with `-O3 -march=native -ffast-math`
- **Memory efficient**: Linear scaling up to 50K+ elements

## Use Cases

```sql
-- Risk assessment with comprehensive statistics
WITH risk_data AS (
    SELECT region, array_agg(risk_value) AS values, array_agg(probability) AS weights
    FROM risk_assessments GROUP BY region
)
SELECT 
    region, 
    weighted_mean(values, weights) AS mean_risk,
    weighted_std(values, weights, 1) AS risk_volatility,
    weighted_quantile(values, weights, ARRAY[0.05, 0.5, 0.95]) AS risk_quantiles,
    wquantile(values, weights, ARRAY[0.25, 0.75]) AS iqr_bounds
FROM risk_data;

-- Survey analysis with different quantile methods
SELECT 
    weighted_quantile(responses, weights, ARRAY[0.5]) AS empirical_median,
    wquantile(responses, weights, ARRAY[0.5]) AS type7_median,  
    whdquantile(responses, weights, ARRAY[0.5]) AS smooth_median
FROM survey_data;

-- Portfolio analysis
SELECT 
    weighted_mean(returns, allocations) AS portfolio_return,
    weighted_variance(returns, allocations, 1) AS portfolio_variance,
    sqrt(weighted_variance(returns, allocations, 1)) AS portfolio_volatility
FROM portfolio_holdings;
```

## Repository Structure

```
weighted_statistics/
├── src/weighted_statistics.c           # C implementation
├── sql/weighted_statistics--1.0.0.sql  # SQL interface
├── weighted_statistics.control         # Extension metadata
├── test/sql/                           # Test files
├── reference/weighted_quantile.py      # Python reference
└── META.json                           # PGXN metadata
```

## Development

```bash
make debug                    # Debug build
make clean && make           # Clean rebuild

# Testing workflow
cd reference && python validate_against_reference.py --database test_db  # Verify math
make installcheck                                                        # Standard regression tests
./test/run_tests.sh                                                      # Custom regression tests
```

## Troubleshooting

**Extension not found**: `sudo apt-get install postgresql-server-dev-$(pg_config --version | grep -oP '\d+')`

**Build issues**: `make clean && make`

**Verify installation**: `psql -c "\df weighted_mean"` (should show "C language")

## Contributing

1. Fork repository
2. Add tests for new functionality  
3. Ensure mathematical correctness: `python reference/validate_against_reference.py`
4. Ensure no regressions: `make installcheck` or `./test/run_tests.sh`
5. Submit pull request

### Testing Requirements

For different PostgreSQL setups, set connection parameters as needed:

```bash
# Standard setup (default port 5432)
make installcheck

# Custom setup (different port/credentials)
PGPORT=5454 PGPASSWORD=mypass make installcheck

# Alternative custom testing
PGPORT=5454 PGPASSWORD=mypass ./test/run_tests.sh
```

---

**Summary**: Production-ready PostgreSQL extension providing a comprehensive suite of mathematically accurate, high-performance weighted statistics with automatic sparse data handling. Perfect for risk analysis, portfolio management, surveys, and incomplete datasets.

**Functions**: 7 weighted statistics functions covering means, variance, standard deviation, and three quantile methods (empirical CDF, Type 7, Harrell-Davis).

- ✅ **Mathematically Validated**: 100% accuracy vs Python reference implementations
- ✅ **High Performance**: 3-10x faster than PL/pgSQL with optimized C code
- ✅ **Comprehensive**: Mean, variance, std dev, and multiple quantile methods  
- ✅ **Robust**: Handles edge cases, NULL values, and sparse data automatically
- ✅ **Well Tested**: Comprehensive regression test suite covering functionality, mathematical properties, and edge cases