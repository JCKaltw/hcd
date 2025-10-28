# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Heat Cycle Detection (HCD) system for analyzing heating device data from Excel files. The system processes HVAC heating cycle data, detects heating patterns, validates cycles, and stores results in a PostgreSQL database.

**Main script**: `src/hcd.py` - Processes Excel files containing heating device readings and generates analysis reports

## Python Environment Setup

This project uses a Python virtual environment managed by shell scripts:

```bash
# Initial setup (creates venv and installs dependencies)
./setup-venv.sh

# Activate environment before running Python scripts
source ./source-venv.sh && python src/hcd.py [args]
```

**Dependencies** (installed by setup-venv.sh):
- pandas, openpyxl, matplotlib, numpy, psycopg2-binary

## Running the Application

### Basic Usage

Process all Excel files in current directory:
```bash
source ./source-venv.sh && python src/hcd.py
```

Process a specific file:
```bash
source ./source-venv.sh && python src/hcd.py --input-file "path/to/file.xlsx"
```

### Command-Line Arguments

- `--input-file`: Process only the specified Excel file (relative to current directory)
- `--insert-db`: Insert processed data into PostgreSQL heating_device_data table
- `--upserts`: Perform upserts (INSERT ... ON CONFLICT DO UPDATE) instead of DO NOTHING
- `--logging`: Enable logging to timestamped files in ./logs directory
- `--dry-run`: Display SQL statements without executing database operations

### Example Batch Processing Scripts

Two example scripts in `bin/` demonstrate typical usage patterns:

- `bin/run.sh`: Processes multiple devices with upserts and logging
- `bin/run2.sh`: Processes a single specific device

Both scripts source the venv and iterate over files in the downloads directory.

## Running Tests

Execute unit tests for the hex_upper() serial normalization function:

```bash
source ./source-venv.sh && python test/test_hex_upper.py
```

## Database Configuration

The application connects to PostgreSQL using environment variables and .pgpass for authentication:

**Required environment variables**:
- `PGHOST_2`: Database host
- `PGDATABASE_2`: Database name
- `PGUSER_2`: Database user
- `PGPORT_2`: Database port

Password is automatically read from `~/.pgpass` file by psycopg2.

**Database schema** (referenced in code):
- `heating_device`: Parent table with device_serial (unique constraint)
- `heating_device_data`: Child table with readings (foreign key to heating_device on device_serial)

## Core Architecture

### Data Processing Pipeline (process_file function in hcd.py)

1. **Excel File Loading**: Reads device data from Excel files with specific format expectations
2. **Header Detection**: Dynamically finds header row containing "State" column
3. **Data Extraction**: Extracts device name and MAC serial number from fixed positions
4. **Serial Normalization**: Applies hex_upper() to ensure consistent format (uppercase hex, lowercase 0x prefix if present)
5. **Timestamp Cleaning**: Handles duplicates and fills missing minute-level timestamps
6. **Heating Detection**: Multi-threshold algorithm to detect heating cycles
7. **Validation**: Filters heating groups based on supply/return temperature differential
8. **Hourly Summarization**: Creates summaries for hours with ≥55 minutes consistent Enable/Disable state
9. **Excel Output**: Generates multi-sheet workbook with Original, Filtered, Heating Data Set, Heat Cleaned Data, and Discarded sheets
10. **Highlighting**: Applies visual highlighting to heating periods in output Excel
11. **Database Insertion**: Optional insertion/upsertion into PostgreSQL database

### Heating Detection Algorithm

Located in process_file() around lines 162-218:

- **Turn ON conditions**: delta > 5°C, supply > return, not previously triggered
- **Turn OFF conditions**: delta ≤ -2.7°C
- **Validation**: Groups must have ≥60% of readings with supply ≥ return + 7°C
- Maintains triggered_rows set to prevent re-triggering same rows

### Serial Number Normalization (hex_upper function)

Critical function (lines 31-66) that normalizes MAC serial numbers:

- **With 0x/0X prefix**: Normalizes to lowercase "0x" + uppercase hex digits
- **Without prefix**: Uppercase hex digits only
- **Never adds prefix** if not already present
- Used consistently before all database operations to ensure data integrity

## Directory Structure

```
src/hcd.py              # Main processing script
bin/run.sh, run2.sh     # Example batch processing scripts
test/test_hex_upper.py  # Unit tests for serial normalization
sql/                    # Database migration scripts
  normalize-existing-serials.sql  # Fix-up script for existing data
downloads/              # Input Excel files (gitignored)
test_done/              # Processed output Excel files (gitignored)
uploads/                # Additional upload storage (gitignored)
logs/                   # Timestamped log files when --logging enabled (gitignored)
credentials/            # Sensitive credentials (gitignored)
```

## Output Format

The script generates JSON summary to stdout:

```json
{
  "mode": "live-run" | "dry-run",
  "summary-rows": <count>,
  "heating-devices": <count>,
  "heating-device-readings": <count>,
  "heating-serial-devices": [
    {"device_id": <id>, "device_serial": "<serial>"},
    ...
  ]
}
```

When `--logging` is enabled, stdout/stderr are redirected to timestamped files in logs/ directory, but JSON summary is always written to original stdout.

## Important Notes

- **Timezone**: All timestamp conversions use America/Detroit timezone before storing as UTC epoch in database
- **File Processing**: Only processes .xlsx files, skips temporary Excel files (starting with ~$)
- **Conflict Handling**: Database insertions use ON CONFLICT clauses to handle duplicate device_serial + epoch_date_stamp combinations
- **Serial Normalization**: Applied at multiple points (file extraction, device insertion, reading insertion) to ensure consistency
