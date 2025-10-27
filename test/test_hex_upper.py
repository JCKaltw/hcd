#!/usr/bin/env python3
"""
Unit tests for hex_upper() function in hcd.py

Tests the serial number normalization logic:
- Uppercase hex digits
- Normalize 0x/0X prefix to lowercase 0x (if present)
- Do NOT add prefix if it doesn't exist
"""

import sys
import os

# Add src directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from hcd import hex_upper


def test_hex_upper_no_prefix():
    """Test serial numbers without prefix - should just uppercase"""
    assert hex_upper("a34f") == "A34F"
    assert hex_upper("b0a732e61eba") == "B0A732E61EBA"
    assert hex_upper("B0A732E4DA4A") == "B0A732E4DA4A"
    assert hex_upper("80646fffb17e") == "80646FFFB17E"
    print("✅ No prefix tests passed")


def test_hex_upper_with_prefix():
    """Test serial numbers with prefix - should normalize prefix + uppercase"""
    assert hex_upper("0Xa34f") == "0xA34F"
    assert hex_upper("0xa34f") == "0xA34F"
    assert hex_upper("0XB0A732E61EBA") == "0xB0A732E61EBA"
    assert hex_upper("0xb0a732e61eba") == "0xB0A732E61EBA"
    assert hex_upper("0X80646fffb17e") == "0x80646FFFB17E"
    print("✅ With prefix tests passed")


def test_hex_upper_edge_cases():
    """Test edge cases"""
    # Empty string
    assert hex_upper("") == ""

    # None
    assert hex_upper(None) == None

    # Whitespace handling - no prefix
    assert hex_upper("  a34f  ") == "A34F"

    # Whitespace handling - with prefix
    assert hex_upper("  0xa34f  ") == "0xA34F"

    # Already normalized - no prefix
    assert hex_upper("A34F") == "A34F"

    # Already normalized - with prefix
    assert hex_upper("0xA34F") == "0xA34F"

    print("✅ Edge case tests passed")


def test_hex_upper_real_world_serials():
    """Test with actual serial numbers from production"""
    # Current production serials (lowercase, no prefix)
    assert hex_upper("80646fffb17e") == "80646FFFB17E"
    assert hex_upper("b0a732e61eba") == "B0A732E61EBA"
    assert hex_upper("b0a732e6229e") == "B0A732E6229E"
    assert hex_upper("b0a732e4da4a") == "B0A732E4DA4A"
    assert hex_upper("80646fffb196") == "80646FFFB196"
    assert hex_upper("b0a732e617c2") == "B0A732E617C2"
    assert hex_upper("083a8d1adca2") == "083A8D1ADCA2"
    assert hex_upper("80646fffa962") == "80646FFFA962"
    assert hex_upper("b0a732e3e30e") == "B0A732E3E30E"
    assert hex_upper("80646f049736") == "80646F049736"

    print("✅ Real world serial tests passed")


def run_all_tests():
    """Run all test functions"""
    print("\n" + "="*60)
    print("Running hex_upper() unit tests")
    print("="*60 + "\n")

    try:
        test_hex_upper_no_prefix()
        test_hex_upper_with_prefix()
        test_hex_upper_edge_cases()
        test_hex_upper_real_world_serials()

        print("\n" + "="*60)
        print("✅ ALL TESTS PASSED")
        print("="*60 + "\n")
        return 0
    except AssertionError as e:
        print(f"\n❌ TEST FAILED: {e}")
        return 1
    except Exception as e:
        print(f"\n❌ UNEXPECTED ERROR: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(run_all_tests())
