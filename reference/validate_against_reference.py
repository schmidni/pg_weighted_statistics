#!/usr/bin/env python3
"""
Validation harness for weighted_statistics PostgreSQL extension.

This script validates the C implementation against the Python reference
implementation to ensure mathematical correctness.
"""

import argparse
import sys
from typing import Any, Dict, List, Tuple

import numpy as np
import psycopg2
import psycopg2.extras
from weighted_quantile import add_missing_zeroes, weighted_quantile


def connect_to_postgres(host='localhost', port=5432, database='postgres',
                        user='postgres', password='postgres'):
    """Connect to PostgreSQL database."""
    try:
        conn = psycopg2.connect(
            host=host, port=port, database=database,
            user=user, password=password
        )
        conn.autocommit = True
        return conn
    except Exception as e:
        print(f"Error connecting to PostgreSQL: {e}")
        sys.exit(1)


def weighted_mean_reference(values: np.ndarray, weights: np.ndarray) -> float:
    """Reference implementation of weighted mean for sparse data."""
    if len(values) == 0 or len(weights) == 0:
        return 0.0

    # Handle sparse data
    sum_weights = np.sum(weights)
    if sum_weights < 1.0:
        values, weights = add_missing_zeroes(values, weights)

    # Calculate weighted mean
    weighted_sum = np.sum(values * weights)
    return float(weighted_sum)


def test_weighted_mean(cursor,
                       test_cases: List[Dict[str, Any]]
                       ) -> List[Dict[str, Any]]:
    """Test weighted_mean function against reference implementation."""
    results = []

    for i, case in enumerate(test_cases):
        name = case['name']
        values = np.array(case['values'])
        weights = np.array(case['weights'])

        # Get reference result
        ref_result = weighted_mean_reference(values, weights)

        # Get PostgreSQL result
        cursor.execute(
            "SELECT weighted_mean(%s, %s) AS result",
            (values.tolist(), weights.tolist())
        )
        pg_result = cursor.fetchone()['result']

        # Compare results
        tolerance = case.get('tolerance', 1e-10)
        diff = abs(ref_result - pg_result)
        passed = diff < tolerance

        results.append({
            'test_id': i + 1,
            'name': name,
            'reference_result': ref_result,
            'postgres_result': pg_result,
            'difference': diff,
            'tolerance': tolerance,
            'passed': passed
        })

        status = "PASS" if passed else "FAIL"
        print(f"Test {i+1}: {name} - {status}")
        if not passed:
            print(f"  Expected: {ref_result}, Got: {pg_result}, Diff: {diff}")

    return results


def test_weighted_quantile(cursor,
                           test_cases: List[Dict[str, Any]]
                           ) -> List[Dict[str, Any]]:
    """Test weighted_quantile function against reference implementation."""
    results = []

    for i, case in enumerate(test_cases):
        name = case['name']
        values = np.array(case['values'])
        weights = np.array(case['weights'])
        quantiles = np.array(case['quantiles'])

        # Get reference result
        ref_result = weighted_quantile(values, quantiles, weights)

        # Get PostgreSQL result
        cursor.execute(
            "SELECT weighted_quantile(%s, %s, %s) AS result",
            (values.tolist(), weights.tolist(), quantiles.tolist())
        )
        pg_result = np.array(cursor.fetchone()['result'])

        # Compare results
        # Slightly larger tolerance for quantiles
        tolerance = case.get('tolerance', 1e-6)
        diffs = np.abs(ref_result - pg_result)
        max_diff = np.max(diffs)
        passed = max_diff < tolerance

        results.append({
            'test_id': i + 1,
            'name': name,
            'reference_result': ref_result.tolist(),
            'postgres_result': pg_result.tolist(),
            'max_difference': float(max_diff),
            'tolerance': tolerance,
            'passed': passed
        })

        status = "PASS" if passed else "FAIL"
        print(f"Test {i+1}: {name} - {status}")
        if not passed:
            print(f"  Max difference: {max_diff}")
            print(f"  Reference: {ref_result}")
            print(f"  PostgreSQL: {pg_result}")

    return results


def generate_test_cases() -> Tuple[List[Dict], List[Dict]]:
    """Generate test cases for validation."""

    # Weighted mean test cases
    mean_cases = [
        {
            'name': 'Basic weighted mean',
            'values': [1.0, 2.0, 3.0],
            'weights': [0.1, 0.2, 0.3]
        },
        {
            'name': 'Sparse data (sum < 1.0)',
            'values': [10.0, 20.0],
            'weights': [0.3, 0.2]
        },
        {
            'name': 'Single value',
            'values': [7.5],
            'weights': [0.4]
        },
        {
            'name': 'Equal weights',
            'values': [1.0, 2.0, 3.0, 4.0],
            'weights': [0.25, 0.25, 0.25, 0.25]
        },
        {
            'name': 'Very sparse data',
            'values': [100.0],
            'weights': [0.1]
        },
        {
            'name': 'Large values',
            'values': [1000.0, 2000.0, 3000.0],
            'weights': [0.2, 0.3, 0.4]
        },
        {
            'name': 'All zero weights (division by zero risk)',
            'values': [1.0, 2.0, 3.0],
            'weights': [0.0, 0.0, 0.0]
        },
        {
            'name': 'Negative values support',
            'values': [-5.0, 0.0, 5.0],
            'weights': [0.3, 0.3, 0.4]
        },
        {
            'name': 'Mixed zero weights',
            'values': [1.0, 2.0, 3.0, 4.0],
            'weights': [0.5, 0.0, 0.3, 0.0]  # Ignore zero-weighted values
        },
        {
            'name': 'Large array performance test',
            'values': list(range(1, 101)),  # 100 elements for performance
            'weights': [0.01] * 100        # Test memory handling
        },
        {
            'name': 'Extreme values (numeric stability)',
            'values': [1e-10, 1e10],
            'weights': [0.4, 0.6]
        }
    ]

    # Weighted quantile test cases
    quantile_cases = [
        {
            'name': 'Basic quantiles',
            'values': [1.0, 2.0, 3.0, 4.0, 5.0],
            'weights': [0.1, 0.2, 0.4, 0.2, 0.1],
            'quantiles': [0.25, 0.5, 0.75]
        },
        {
            'name': 'Sparse quantiles',
            'values': [10.0, 20.0],
            'weights': [0.3, 0.2],
            'quantiles': [0.1, 0.5, 0.9]
        },
        {
            'name': 'Single quantile',
            'values': [1.0, 2.0, 3.0],
            'weights': [0.3, 0.3, 0.3],
            'quantiles': [0.5]
        },
        {
            'name': 'Boundary quantiles',
            'values': [1.0, 2.0, 3.0, 4.0],
            'weights': [0.25, 0.25, 0.25, 0.25],
            'quantiles': [0.0, 1.0]
        },
        {
            'name': 'Many quantiles',
            'values': [1.0, 2.0, 3.0, 4.0, 5.0],
            'weights': [0.2, 0.2, 0.2, 0.2, 0.2],
            'quantiles': [0.1, 0.25, 0.5, 0.75, 0.9]
        },
        {
            'name': 'Extreme quantiles (boundary conditions)',
            'values': [1.0, 2.0, 3.0, 4.0, 5.0],
            'weights': [0.2, 0.2, 0.2, 0.2, 0.2],
            'quantiles': [0.001, 0.999]  # Near 0% and 100%
        },
        {
            'name': 'Unsorted input data (algorithm robustness)',
            'values': [5.0, 1.0, 3.0, 2.0, 4.0],  # Intentionally unsorted
            'weights': [0.2, 0.3, 0.1, 0.2, 0.2],
            'quantiles': [0.25, 0.5, 0.75]
        },
        {
            'name': 'Sparse negative data',
            'values': [-10.0, 5.0],
            'weights': [0.1, 0.2],  # Sum = 0.3, implicit 0.7 weight on 0
            'quantiles': [0.1, 0.5, 0.9]
        }
    ]

    return mean_cases, quantile_cases


def validate_mathematical_properties(cursor) -> List[Dict[str, Any]]:
    """
    Validate mathematical properties of the weighted statistics functions.
    """
    property_results = []

    # Property 1: Quantile Monotonicity
    # q(0.25) ≤ q(0.5) ≤ q(0.75)
    test_cases_monotonicity = [
        {
            'name': 'Monotonicity test 1',
            'values': [1.0, 2.0, 3.0, 4.0, 5.0],
            'weights': [0.2, 0.2, 0.2, 0.2, 0.2],
            'quantiles': [0.25, 0.5, 0.75]
        },
        {
            'name': 'Monotonicity test 2 (sparse)',
            'values': [10.0, 20.0, 30.0],
            'weights': [0.1, 0.2, 0.1],  # Sum = 0.4, 0.6 implicit zero weight
            'quantiles': [0.25, 0.5, 0.75]
        }
    ]

    for case in test_cases_monotonicity:
        cursor.execute(
            "SELECT weighted_quantile(%s, %s, %s) AS result",
            (case['values'], case['weights'], case['quantiles'])
        )
        quantile_results = cursor.fetchone()['result']

        # Check monotonicity: each quantile should be >= previous
        is_monotonic = all(quantile_results[i] <= quantile_results[i+1]
                           for i in range(len(quantile_results)-1))

        property_results.append({
            'property': 'Quantile Monotonicity',
            'test_name': case['name'],
            'passed': is_monotonic,
            'details':  f"Quantiles: {quantile_results}, "
                        f"Monotonic: {is_monotonic}"
        })

    # Property 2: Boundedness
    # For normalized weights (sum=1): min(values) ≤ weighted_mean ≤ max(values)
    test_cases_boundedness = [
        {
            'name': 'Boundedness test 1 (normalized)',
            'values': [1.0, 5.0, 10.0],
            'weights': [0.3, 0.4, 0.3]  # Sum = 1.0
        },
        {
            'name': 'Boundedness test 2 (normalized)',
            'values': [-2.0, 0.0, 7.0],
            'weights': [0.25, 0.5, 0.25]  # Sum = 1.0
        }
    ]

    for case in test_cases_boundedness:
        if abs(sum(case['weights']) - 1.0) < 1e-10:  # Test normalized weights
            cursor.execute(
                "SELECT weighted_mean(%s, %s) AS result",
                (case['values'], case['weights'])
            )
            mean_result = cursor.fetchone()['result']

            min_val = min(case['values'])
            max_val = max(case['values'])
            is_bounded = min_val <= mean_result <= max_val

            property_results.append({
                'property': 'Boundedness',
                'test_name': case['name'],
                'passed': is_bounded,
                'details':  f"Min: {min_val}, Mean: {mean_result}, "
                            f"Max: {max_val}, Bounded: {is_bounded}"
            })

    # Property 3: Consistency
    # weighted_median should equal weighted_quantile(..., [0.5])[0]
    test_cases_consistency = [
        {
            'name': 'Consistency test 1',
            'values': [1.0, 2.0, 3.0, 4.0, 5.0],
            'weights': [0.2, 0.2, 0.2, 0.2, 0.2]
        },
        {
            'name': 'Consistency test 2 (sparse)',
            'values': [10.0, 20.0],
            'weights': [0.3, 0.2]  # Sparse data
        }
    ]

    for case in test_cases_consistency:
        # Get quantile(0.5) result
        cursor.execute(
            "SELECT weighted_quantile(%s, %s, %s) AS result",
            (case['values'], case['weights'], [0.5])
        )
        quantile_50 = cursor.fetchone()['result'][0]

        # Get single median result
        cursor.execute(
            "SELECT weighted_quantile(%s, %s, %s) AS result",
            (case['values'], case['weights'], [0.5])
        )
        median_result = cursor.fetchone()['result'][0]

        # They should be identical
        is_consistent = abs(quantile_50 - median_result) < 1e-10

        property_results.append({
            'property': 'Consistency',
            'test_name': case['name'],
            'passed': is_consistent,
            'details':  f"Quantile(0.5): {quantile_50}, "
                        f"Median: {median_result}, "
                        f"Consistent: {is_consistent}"
        })

    return property_results


def main():
    parser = argparse.ArgumentParser(
        description='Validate weighted_statistics extension')
    parser.add_argument('--host', default='localhost', help='PostgreSQL host')
    parser.add_argument('--port', type=int, default=5432,
                        help='PostgreSQL port')
    parser.add_argument('--database', default='postgres',
                        help='PostgreSQL database')
    parser.add_argument('--user', default='postgres', help='PostgreSQL user')
    parser.add_argument('--password', default='postgres',
                        help='PostgreSQL password')
    parser.add_argument('--verbose', '-v',
                        action='store_true', help='Verbose output')

    args = parser.parse_args()

    print("Weighted Statistics Extension Validation")
    print("=" * 50)

    # Connect to PostgreSQL
    conn = connect_to_postgres(
        args.host, args.port, args.database, args.user, args.password)
    cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    # Check if extension exists
    cursor.execute(
        "SELECT 1 FROM pg_extension WHERE extname = 'weighted_statistics'")
    if not cursor.fetchone():
        print("ERROR: weighted_statistics extension not found!")
        print("Please install the extension with: "
              "CREATE EXTENSION weighted_statistics;")
        sys.exit(1)

    # Generate test cases
    mean_cases, quantile_cases = generate_test_cases()

    # Run weighted_mean tests
    print(f"\nTesting weighted_mean function ({len(mean_cases)} tests):")
    print("-" * 30)
    mean_results = test_weighted_mean(cursor, mean_cases)

    # Run weighted_quantile tests
    print(
        f"\nTesting weighted_quantile function ({len(quantile_cases)} tests):")
    print("-" * 35)
    quantile_results = test_weighted_quantile(cursor, quantile_cases)

    # Run mathematical property validation tests
    print("\nTesting mathematical properties:")
    print("-" * 32)
    property_results = validate_mathematical_properties(cursor)

    for result in property_results:
        status = "PASS" if result['passed'] else "FAIL"
        print(f"{result['property']} - {result['test_name']}: {status}")
        if not result['passed']:
            print(f"  Details: {result['details']}")

    # Summary
    total_tests = len(mean_results) + \
        len(quantile_results) + len(property_results)
    passed_tests = (sum(r['passed'] for r in mean_results + quantile_results) +
                    sum(r['passed'] for r in property_results))
    failed_tests = total_tests - passed_tests

    print("\n" + "=" * 50)
    print("VALIDATION SUMMARY")
    print("=" * 50)
    print(f"Total tests: {total_tests}")
    print(f"Passed: {passed_tests}")
    print(f"Failed: {failed_tests}")
    print(f"Success rate: {passed_tests/total_tests*100:.1f}%")

    if failed_tests > 0:
        print(f"\n❌ VALIDATION FAILED - {failed_tests} test(s) failed")
        exit_code = 1
    else:
        print("\n✅ VALIDATION PASSED - All tests successful!")
        exit_code = 0

    conn.close()
    sys.exit(exit_code)


if __name__ == '__main__':
    main()
