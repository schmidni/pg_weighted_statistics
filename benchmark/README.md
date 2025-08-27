# Performance Benchmarks

Simple performance testing for the weighted_statistics extension.

## Running Benchmarks

### Quick Start

```bash
# From the repository root
./benchmark/run_benchmark.sh
```

### Custom Database

```bash
DB_NAME=mydb DB_USER=myuser ./benchmark/run_benchmark.sh
```

### Manual Execution

```bash
# Connect to your database and run:
\i benchmark/performance_test.sql
```

## What Gets Tested

The benchmark tests these scenarios:

- **Array sizes**: 100, 1,000, and 10,000 elements
- **Functions**: `weighted_mean()` and `weighted_quantile()`
- **Quantile efficiency**: Single vs multiple quantiles
- **Sparse data**: Different sparsity levels (10% vs 90% weight coverage)
- **Scaling behavior**: Performance across array sizes

## Interpreting Results

Look for these patterns in the timing output:

- **Execution times** - Check the `Time:` values
- **Scaling** - How time increases with array size
- **Function efficiency** - Compare `weighted_mean` vs `weighted_quantile` 
- **Multi-quantile efficiency** - Cost of computing multiple quantiles at once
- **Sparse data impact** - Performance difference between sparse/dense data

## Performance Notes

- Times will vary based on your hardware and database configuration
- The extension is optimized for sparse data scenarios
- Multiple quantiles computed in a single call are more efficient than separate calls
- Performance should scale approximately linearly with array size

## Prerequisites

- PostgreSQL with `weighted_statistics` extension installed
- `psql` client available
- Database connection permissions