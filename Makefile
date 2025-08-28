# Weighted Statistics Extension Makefile
# 
# Uses PostgreSQL Extension Building Infrastructure (PGXS)
# for proper compilation and installation.

# Extension metadata
EXTENSION = weighted_statistics
DATA = sql/weighted_statistics--1.0.0.sql
MODULE_big = weighted_statistics
OBJS = src/utils.o src/weighted_mean.o src/weighted_quantiles.o src/weighted_variance.o

# Compiler optimization flags for performance
PG_CPPFLAGS = -O2 -funroll-loops
PG_LDFLAGS = -lm 

# Regression tests
REGRESS = basic_tests accuracy_tests performance_tests
REGRESS_OPTS = --inputdir=test/sql --outputdir=test/results

# Test data directories
TESTDIR = test
SQLDIR = $(TESTDIR)/sql
OUTPUTDIR = $(TESTDIR)/results
EXPECTEDDIR = $(TESTDIR)/expected

# Find PostgreSQL installation
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)

# Include PGXS makefile
include $(PGXS)

# Custom targets for development
.PHONY: debug clean-all test benchmark check-results

# Ensure test output directory exists
$(OUTPUTDIR):
	mkdir -p $(OUTPUTDIR)

# Debug build with symbols and no optimization
debug: PG_CPPFLAGS = -g -O0 -DDEBUG
debug: clean all

# Enhanced clean
clean-all: clean
	rm -f src/*.so src/*.o

# Basic test target (requires extension to be installed)
test:
	@echo "Running basic functionality test:"
	@psql -c "SELECT weighted_mean(ARRAY[1.0,2.0,3.0], ARRAY[0.1,0.2,0.3]) AS result;"

# Compare test results with expected output
check-results: $(OUTPUTDIR)
	@echo "Comparing test results with expected output..."
	@for test in $(REGRESS); do \
		if [ -f "$(EXPECTEDDIR)/$$test.out" ] && [ -f "$(OUTPUTDIR)/$$test.out" ]; then \
			echo "Comparing $$test results..."; \
			diff -u "$(EXPECTEDDIR)/$$test.out" "$(OUTPUTDIR)/$$test.out" || true; \
		else \
			echo "Missing files for $$test comparison"; \
		fi; \
	done

# Performance benchmark target
benchmark:
	@echo "Running performance benchmarks..."
	@psql -f benchmark/benchmark_suite.sql
