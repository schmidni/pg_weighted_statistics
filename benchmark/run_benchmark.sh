#!/bin/bash

# Benchmark Runner for Weighted Statistics Extension
#
# This script runs performance comparisons between C and PL/pgSQL implementations
# and compares different quantile methods.

set -e

EXTENSION_NAME="weighted_statistics"

# Use standard PostgreSQL environment variables with fallbacks (aligned with test/run_tests.sh)
TEST_DB="${TEST_DATABASE:-${PGDATABASE:-postgres}}"
TEST_USER="${TEST_USER:-${PGUSER:-postgres}}"
TEST_HOST="${TEST_HOST:-${PGHOST:-localhost}}"
TEST_PORT="${TEST_PORT:-${PGPORT:-5432}}"

# Build connection options - only specify what's needed
PSQL_OPTS=""

# Add database if specified
[[ -n "$TEST_DB" && "$TEST_DB" != "" ]] && PSQL_OPTS="$PSQL_OPTS -d $TEST_DB"

# Add user if different from system user
[[ -n "$TEST_USER" && "$TEST_USER" != "$(whoami)" ]] && PSQL_OPTS="$PSQL_OPTS -U $TEST_USER"

# Only add host/port if they're specified and different from defaults
if [[ -n "$TEST_HOST" && "$TEST_HOST" != "" ]] || [[ -n "$TEST_PORT" && "$TEST_PORT" != "5432" ]]; then
    [[ -n "$TEST_HOST" ]] && PSQL_OPTS="$PSQL_OPTS -h $TEST_HOST"
    [[ -n "$TEST_PORT" ]] && PSQL_OPTS="$PSQL_OPTS -p $TEST_PORT"
fi

PSQL_CMD="psql $PSQL_OPTS"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if we can connect to the database
check_connection() {
    if ! $PSQL_CMD -c "SELECT 1;" > /dev/null 2>&1; then
        print_error "Cannot connect to database"
        print_error "Connection: $TEST_USER@$TEST_HOST:$TEST_PORT/$TEST_DB"
        print_error "Set environment variables: PGDATABASE, PGUSER, PGHOST, PGPORT"
        print_error "Or use: TEST_DATABASE, TEST_USER, TEST_HOST, TEST_PORT"
        exit 1
    fi
}

# Check if extension is installed
check_extension() {
    if ! $PSQL_CMD -tAc "SELECT 1 FROM pg_extension WHERE extname = '$EXTENSION_NAME';" | grep -q 1; then
        print_error "Extension '$EXTENSION_NAME' not installed"
        print_error "Run: CREATE EXTENSION $EXTENSION_NAME;"
        exit 1
    fi
}

# Load PL/pgSQL functions for comparison
setup_plpgsql_functions() {
    print_info "Loading PL/pgSQL comparison functions..."
    if ! $PSQL_CMD -f "$(dirname "$0")/plpgsql_functions.sql" > /dev/null 2>&1; then
        print_error "Failed to load PL/pgSQL functions"
        exit 1
    fi
    print_success "PL/pgSQL functions loaded"
}

# Show usage
usage() {
    echo "Usage: $0"
    echo ""
    echo "Environment Variables (PostgreSQL standard):"
    echo "  PGDATABASE   Database name (default: postgres)"
    echo "  PGUSER       Username (default: postgres)"  
    echo "  PGHOST       PostgreSQL host (default: localhost)"
    echo "  PGPORT       PostgreSQL port (default: 5432)"
    echo ""
    echo "Alternative Variables:"
    echo "  TEST_DATABASE, TEST_USER, TEST_HOST, TEST_PORT"
    echo ""
    echo "Examples:"
    echo "  PGDATABASE=mydb PGUSER=myuser ./run_benchmark.sh"
    echo "  TEST_DATABASE=testdb ./run_benchmark.sh"
}

# Main function
main() {
    if [[ "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi
    
    echo "Weighted Statistics Performance Benchmark"
    echo "========================================"
    echo "Database: $TEST_DB @ $TEST_HOST:$TEST_PORT"
    echo "User: $TEST_USER"
    echo ""
    
    print_info "Checking database connection..."
    check_connection
    print_success "Connected to database"
    
    print_info "Checking extension installation..."
    check_extension
    print_success "Extension found"
    
    setup_plpgsql_functions
    
    print_info "Running performance comparisons..."
    print_warning "This may take 1-2 minutes..."
    echo ""
    
    # Run the benchmark
    if $PSQL_CMD -f "$(dirname "$0")/performance_test.sql"; then
        echo ""
        print_success "Performance benchmark completed"
        echo ""
        print_info "Benchmark Results Summary:"
        echo "• Group 1: C vs PL/pgSQL comparison (mean, variance, std, quantiles)"
        echo "• Group 2: Quantile methods comparison (empirical vs Type 7 vs Harrell-Davis)"
        echo "• Review 'Time:' values in output above for performance differences"
        echo ""
        print_info "Next Steps:"
        echo "• Calculate speedup ratios from timing results"
        echo "• Update README files with actual performance measurements"
    else
        print_error "Performance benchmark failed"
        exit 1
    fi
}

main "$@"