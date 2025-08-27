# REIA Weighted Statistics C Extension

High-performance C implementation of weighted mean and quantile functions for sparse data, providing significant performance improvements over the original PL/pgSQL implementations.

## Overview

This extension provides optimized C implementations of:
- `weighted_mean_sparse_c()` - Weighted mean for sparse data
- `weighted_quantile_sparse_c()` - Weighted quantiles for sparse data

These functions handle sparse data where `sum(weights) < 1.0` implies implicit zeros in the dataset, which is crucial for REIA's risk assessment calculations.

## Performance Improvements

Based on benchmarks with various array sizes:
- **Conservative estimate**: 3-5x performance improvement
- **Optimistic estimate**: 5-10x performance improvement with large datasets
- Expected endpoint improvements:
  - Damage endpoint: 14s → 3-5s
  - Loss endpoint: 4.3s → 1s

## Files Structure

```
c_extensions/reia_weighted_stats/
├── reia_weighted_stats.c           # Main C source code
├── reia_weighted_stats.control     # Extension control file
├── reia_weighted_stats--1.0.0.sql  # SQL function definitions
├── Makefile                        # Build configuration using PGXS
├── Dockerfile.postgres             # Custom PostgreSQL container
├── test_c_functions.sql            # Comprehensive test suite
├── benchmark_c_functions.sql       # Performance benchmarks
├── upgrade_to_c_functions.sql      # Production upgrade script
└── README.md                       # This file
```

## Installation

### Docker Development Environment

The extension is automatically built and installed when using the Docker development environment:

```bash
# Build and start the services with C extension
docker-compose up --build -d

# The extension is automatically created in the database during initialization
```

### Manual Installation (if needed)

```bash
# Navigate to extension directory
cd c_extensions/reia_weighted_stats

# Build the extension
make clean
make
sudo make install

# In PostgreSQL, create the extension
CREATE EXTENSION reia_weighted_stats;
```

## Usage

### Direct C Function Usage

```sql
-- Weighted mean for sparse data
SELECT weighted_mean_sparse_c(
    ARRAY[1.0, 2.0, 3.0], 
    ARRAY[0.1, 0.2, 0.3]
);

-- Weighted quantiles for sparse data
SELECT weighted_quantile_sparse_c(
    ARRAY[1.0, 2.0, 3.0, 4.0, 5.0], 
    ARRAY[0.1, 0.2, 0.3, 0.2, 0.1], 
    ARRAY[0.1, 0.5, 0.9]
);
```

### Production Upgrade

To upgrade existing REIA installations to use the C functions:

```sql
-- This replaces the PL/pgSQL functions with C implementations
-- while maintaining exact API compatibility
\i c_extensions/upgrade_to_c_functions.sql
```

## Testing

### Mathematical Accuracy Tests

Verify that C functions produce identical results to PL/pgSQL:

```sql
\i c_extensions/test_c_functions.sql
```

All tests should show `results_match = TRUE`.

### Performance Benchmarks

Compare performance between C and PL/pgSQL implementations:

```sql
\i c_extensions/benchmark_c_functions.sql
```

Expected results:
- Small arrays (100 elements): 2-3x speedup
- Medium arrays (1,000 elements): 3-5x speedup
- Large arrays (10,000 elements): 5-10x speedup

### Integration Testing

Test with actual REIA endpoints:

```bash
# Test damage endpoint
time curl "http://localhost:8000/reiaws/v1/damage/2/displaced/CantonGemeinde?filter_tag_like=AG"

# Test loss endpoint  
time curl "http://localhost:8000/reiaws/v1/loss/1/structural/CantonGemeinde?filter_tag_like=AG"
```

## Technical Details

### Sparse Data Handling

The functions handle sparse data representation where:
- Input arrays contain only non-zero values and their weights
- `sum(weights) < 1.0` implies implicit zeros with weight `1.0 - sum(weights)`
- Quantile calculations properly account for the implicit zero mass

### Memory Management

- Uses PostgreSQL's `palloc/pfree` for memory management
- Proper cleanup of temporary arrays and structures
- Safe handling of NULL inputs and edge cases

### Algorithm Optimizations

#### weighted_mean_sparse_c:
- Direct array processing without SQL interpretation overhead
- Vectorized operations for sum calculations
- Efficient memory access patterns

#### weighted_quantile_sparse_c:
- Optimized sorting using `qsort()` with custom comparator
- Single-pass quantile calculation for multiple quantiles
- Linear interpolation for accurate quantile estimation
- Efficient cumulative sum calculation

### Compiler Optimizations

The Makefile includes aggressive optimization flags:
- `-O3` - Maximum optimization level
- `-march=native` - CPU-specific optimizations
- `-ffast-math` - Fast floating-point math
- `-funroll-loops` - Loop unrolling

## Deployment Notes

### Docker Integration

- Extension is automatically built during Docker image creation
- No manual intervention required for development setup
- Extension is available immediately after container startup

### Production Deployment

1. The C extension is compiled during Docker image build
2. Extension is automatically created during database initialization
3. Use `upgrade_to_c_functions.sql` to seamlessly upgrade existing installations
4. Original PL/pgSQL functions are preserved as backups

### Rollback Procedure

If needed, rollback to PL/pgSQL functions:

```sql
-- Restore original PL/pgSQL functions
DROP FUNCTION weighted_mean_sparse(double precision[], double precision[]);
DROP FUNCTION weighted_quantile_sparse(double precision[], double precision[], double precision[]);

ALTER FUNCTION weighted_mean_sparse_plpgsql_backup(double precision[], double precision[]) 
    RENAME TO weighted_mean_sparse;
ALTER FUNCTION weighted_quantile_sparse_plpgsql_backup(double precision[], double precision[], double precision[]) 
    RENAME TO weighted_quantile_sparse;
```

## Troubleshooting

### Build Issues

```bash
# Ensure PostgreSQL development headers are installed
apt-get install postgresql-server-dev-16

# Check pg_config is available
pg_config --version

# Clean and rebuild
make clean
make
```

### Runtime Issues

```bash
# Check extension is installed
SELECT * FROM pg_available_extensions WHERE name = 'reia_weighted_stats';

# Check functions are created
\df weighted_*_c

# Test basic functionality
SELECT weighted_mean_sparse_c(ARRAY[1.0], ARRAY[0.5]);
```

## Contributing

When modifying the C code:

1. Update function logic in `reia_weighted_stats.c`
2. Run comprehensive tests: `\i test_c_functions.sql`
3. Run performance benchmarks: `\i benchmark_c_functions.sql`
4. Ensure Docker build succeeds: `docker-compose up --build`
5. Test integration with REIA endpoints