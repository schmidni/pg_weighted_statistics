#!/bin/bash

# Simple Benchmark Runner for Weighted Statistics Extension

set -e

# Configuration with defaults
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-postgres}"
DB_USER="${DB_USER:-postgres}"

# PostgreSQL connection
export PGPASSWORD="${DB_PASSWORD:-}"
PSQL_CMD="psql -h $DB_HOST -p $DB_PORT -d $DB_NAME -U $DB_USER"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

# Check if we can connect to the database
check_connection() {
    if ! $PSQL_CMD -c "SELECT 1;" > /dev/null 2>&1; then
        print_error "Cannot connect to database"
        print_error "Connection: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
        exit 1
    fi
}

# Check if extension is installed
check_extension() {
    if ! $PSQL_CMD -tAc "SELECT 1 FROM pg_extension WHERE extname = 'weighted_statistics';" | grep -q 1; then
        print_error "Extension 'weighted_statistics' not installed"
        print_error "Run: CREATE EXTENSION weighted_statistics;"
        exit 1
    fi
}

# Show usage
usage() {
    echo "Usage: $0"
    echo ""
    echo "Environment Variables:"
    echo "  DB_HOST      PostgreSQL host (default: localhost)"
    echo "  DB_PORT      PostgreSQL port (default: 5432)"  
    echo "  DB_NAME      Database name (default: postgres)"
    echo "  DB_USER      Username (default: postgres)"
    echo "  DB_PASSWORD  Password (if required)"
    echo ""
    echo "Example:"
    echo "  DB_NAME=mydb DB_USER=myuser ./run_benchmark.sh"
}

# Main function
main() {
    if [[ "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi
    
    echo "Weighted Statistics Performance Test"
    echo "===================================="
    echo "Database: $DB_NAME @ $DB_HOST:$DB_PORT"
    echo "User: $DB_USER"
    echo ""
    
    print_info "Checking connection..."
    check_connection
    print_success "Connected to database"
    
    print_info "Checking extension..."
    check_extension
    print_success "Extension found"
    
    print_info "Running performance tests..."
    echo ""
    
    # Run the benchmark
    if $PSQL_CMD -f "$(dirname "$0")/performance_test.sql"; then
        echo ""
        print_success "Performance test completed"
        echo ""
        print_info "How to interpret results:"
        echo "• Look at 'Time:' values for execution times"
        echo "• Compare times across different array sizes"
        echo "• Check scaling behavior as arrays get larger"
        echo "• Compare single vs multi-quantile performance"
    else
        print_error "Performance test failed"
        exit 1
    fi
}

main "$@"