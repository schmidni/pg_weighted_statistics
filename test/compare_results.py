#!/usr/bin/env python3
"""
Compare test results with tolerance for floating-point differences.
"""
import sys
import re
import argparse

def extract_numbers(line):
    """Extract all floating-point numbers from a line."""
    # Regex to match floating-point numbers including scientific notation
    pattern = r'-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?'
    return re.findall(pattern, line)

def numbers_close(num1_str, num2_str, tolerance=1e-10):
    """Check if two number strings represent values within tolerance."""
    try:
        num1 = float(num1_str)
        num2 = float(num2_str)
        
        # Handle very small numbers (close to zero)
        if abs(num1) < tolerance and abs(num2) < tolerance:
            return True
        
        # Relative tolerance for larger numbers
        if abs(num1) > tolerance or abs(num2) > tolerance:
            max_val = max(abs(num1), abs(num2))
            return abs(num1 - num2) / max_val < tolerance
        
        # Absolute tolerance for small numbers
        return abs(num1 - num2) < tolerance
    except ValueError:
        return num1_str == num2_str

def lines_equivalent(line1, line2, tolerance=1e-10):
    """Check if two lines are equivalent allowing for floating-point differences."""
    # First try exact match
    if line1.strip() == line2.strip():
        return True
    
    # Extract numbers from both lines
    nums1 = extract_numbers(line1)
    nums2 = extract_numbers(line2)
    
    # If different number of numbers, not equivalent
    if len(nums1) != len(nums2):
        return False
    
    # Check if all numbers are close
    all_close = all(numbers_close(n1, n2, tolerance) 
                   for n1, n2 in zip(nums1, nums2))
    
    if not all_close:
        return False
    
    # Replace numbers with placeholders and check structure
    line1_struct = line1
    line2_struct = line2
    for n1, n2 in zip(nums1, nums2):
        line1_struct = line1_struct.replace(n1, 'NUM', 1)
        line2_struct = line2_struct.replace(n2, 'NUM', 1)
    
    return line1_struct.strip() == line2_struct.strip()

def compare_files(expected_file, actual_file, tolerance=1e-10):
    """Compare two files with floating-point tolerance."""
    try:
        with open(expected_file, 'r') as f1, open(actual_file, 'r') as f2:
            lines1 = f1.readlines()
            lines2 = f2.readlines()
    except FileNotFoundError as e:
        return False, f"File not found: {e}"
    
    if len(lines1) != len(lines2):
        return False, f"Different number of lines: {len(lines1)} vs {len(lines2)}"
    
    differences = []
    for i, (line1, line2) in enumerate(zip(lines1, lines2), 1):
        if not lines_equivalent(line1, line2, tolerance):
            differences.append(f"Line {i}:\n  Expected: {line1.strip()}\n  Actual:   {line2.strip()}")
    
    if differences:
        return False, "\n".join(differences)
    
    return True, "Files match within tolerance"

def main():
    parser = argparse.ArgumentParser(description='Compare test results with floating-point tolerance')
    parser.add_argument('expected', help='Expected results file')
    parser.add_argument('actual', help='Actual results file')
    parser.add_argument('--tolerance', '-t', type=float, default=1e-10,
                       help='Floating-point tolerance (default: 1e-10)')
    
    args = parser.parse_args()
    
    success, message = compare_files(args.expected, args.actual, args.tolerance)
    
    if success:
        print(f"✓ Files match within tolerance ({args.tolerance})")
        sys.exit(0)
    else:
        print(f"✗ Files differ: {message}")
        sys.exit(1)

if __name__ == '__main__':
    main()