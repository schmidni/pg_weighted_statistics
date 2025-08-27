# REIA Weighted Statistics C Extension Makefile
# 
# Uses PostgreSQL Extension Building Infrastructure (PGXS)
# for proper compilation and installation.

# Extension metadata
EXTENSION = reia_weighted_stats
DATA = reia_weighted_stats--1.0.0.sql
MODULE_big = reia_weighted_stats
OBJS = reia_weighted_stats.o

# Compiler optimization flags for performance
PG_CPPFLAGS = -O3 -march=native -ffast-math -funroll-loops
PG_LDFLAGS = 

# Find PostgreSQL installation
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)

# Include PGXS makefile
include $(PGXS)

# Custom targets for development
.PHONY: debug clean-all test

# Debug build with symbols and no optimization
debug: PG_CPPFLAGS = -g -O0 -DDEBUG
debug: clean all

# Enhanced clean
clean-all: clean
	rm -f *.so *.o

# Basic test target (requires extension to be installed)
test:
	@echo "Run: SELECT weighted_mean_sparse_c(ARRAY[1.0,2.0,3.0], ARRAY[0.1,0.2,0.3]);"
	@echo "Expected result should be: 2.0"