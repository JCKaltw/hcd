#!/bin/bash
# run.sh - Process test files with hcd.py and display results
#
# This script demonstrates hcd.py processing with both a successful
# and a failing file, generating device status reports.

set -e  # Exit on error

echo "========================================================================"
echo "Heat Cycle Detection - Test Run"
echo "========================================================================"
echo ""

# Clean previous results
echo "Cleaning previous results..."
rm -rf upload-results
echo ""

# Source virtual environment
echo "Activating Python virtual environment..."
source ./source-venv.sh
echo ""

# Process File 1 - Failing file (no heating detected)
echo "========================================================================"
echo "Processing File 1: RTU 23 (Expected: 0 summary rows)"
echo "========================================================================"
python src/hcd.py --input-file "pg2-uploads/20251027_225619_MC45MDU3.xlsx" --dry-run
echo ""

# Process File 2 - Successful file (heating detected)
echo "========================================================================"
echo "Processing File 2: RTU 9 (Expected: 30 summary rows)"
echo "========================================================================"
python src/hcd.py --input-file "pg2-uploads/80646f049736-45-20251027_130410_MC40MTQw.xlsx" --dry-run
echo ""

# Show results
echo "========================================================================"
echo "Results Summary"
echo "========================================================================"
echo ""
echo "Output Files Created:"
echo "--------------------"
ls -lh test_done/*_heat\ min\ per\ hour.xlsx | tail -2
echo ""
echo "Device Status Reports:"
echo "---------------------"
ls -lh upload-results/*.xlsx
echo ""

# Display status report summary
echo "========================================================================"
echo "Device Status Report Summary"
echo "========================================================================"
python -c "
import pandas as pd
import os

# Read both result files
files = [
    'upload-results/20251027_225619_MC45MDU3-results.xlsx',
    'upload-results/80646f049736-45-20251027_130410_MC40MTQw-results.xlsx'
]

for filepath in files:
    if os.path.exists(filepath):
        df = pd.read_excel(filepath)

        # Extract key metrics
        device_name = df[df['Field'] == 'device_name']['Value'].values[0]
        device_serial = df[df['Field'] == 'device_serial']['Value'].values[0]
        status = df[df['Field'] == 'status']['Value'].values[0]
        summary_rows = df[df['Field'] == 'summary_rows']['Value'].values[0]
        diff_max = df[df['Field'] == 'diff_max']['Value'].values[0]
        rows_above_7c = df[df['Field'] == 'rows_above_7c_threshold']['Value'].values[0]

        print()
        print(f'Device: {device_name} ({device_serial})')
        print(f'  Status: {status}')
        print(f'  Summary Rows: {summary_rows}')
        print(f'  Max Temp Differential: {diff_max:.2f}°C')
        print(f'  Rows above 7°C threshold: {rows_above_7c}')

        # Show key comment
        status_comment = df[df['Field'] == 'status']['Comment'].values[0]
        if pd.notna(status_comment):
            print(f'  Comment: {status_comment}')
"

echo ""
echo "========================================================================"
echo "To view detailed reports:"
echo "  - Multi-sheet workbooks: test_done/*_heat min per hour.xlsx"
echo "  - Device status reports: upload-results/*.xlsx"
echo "========================================================================"
