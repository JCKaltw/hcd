# HCD User Guide

## Heat Cycle Detection System - Comprehensive Documentation

**Version:** 1.0
**Last Updated:** October 28, 2025

---

## Table of Contents

1. [Overview](#overview)
2. [What HCD Does](#what-hcd-does)
3. [System Architecture](#system-architecture)
4. [Processing Pipeline](#processing-pipeline)
5. [File Naming Conventions](#file-naming-conventions)
6. [Device Status Reports](#device-status-reports)
7. [Command-Line Usage](#command-line-usage)
8. [PGUI Integration](#pgui-integration)
9. [Output Files](#output-files)
10. [Understanding Results](#understanding-results)
11. [Troubleshooting](#troubleshooting)

---

## Overview

The Heat Cycle Detection (HCD) system analyzes Excel files containing HVAC heating device data to detect, validate, and summarize heating cycles. The system processes temperature readings from heating devices, identifies genuine heating events, and stores validated results in a PostgreSQL database.

**Primary Purpose:** Identify when heating systems are actively heating and generate hourly summaries for energy analysis.

---

## What HCD Does

### Core Functionality

1. **Reads Excel Files** - Processes HVAC device data exported from heating monitoring systems
2. **Detects Heating Cycles** - Identifies when heating is active based on temperature patterns
3. **Validates Cycles** - Ensures detected heating cycles meet quality thresholds
4. **Generates Reports** - Creates detailed Excel workbooks with multiple analysis sheets
5. **Database Storage** - Inserts validated heating data into PostgreSQL for long-term tracking
6. **Device Status Analysis** - NEW: Generates diagnostic reports explaining why files succeed or fail

### Key Features

- **Temperature-based Detection** - Uses supply and return temperature differentials
- **Multi-threshold Validation** - 5°C trigger threshold, 7°C validation threshold
- **Timestamp Normalization** - Fills gaps and handles duplicates in minute-level data
- **Serial Number Normalization** - Ensures consistent device identification
- **Timezone Handling** - Converts America/Detroit timestamps to UTC for database storage
- **Batch Processing** - Can process single files or entire directories

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         PGUI Web Application                     │
│  (Next.js - File Upload Interface)                              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Bull Queue System                           │
│  (Redis-backed job queue)                                        │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Bull Worker Process                          │
│  (pgui/scripts/bullWorker.js)                                    │
│  - Monitors queue for new upload jobs                            │
│  - Invokes hcd.py for each file                                  │
│  - Captures results and updates job status                       │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                      hcd.py (Python)                             │
│  - Processes Excel files                                         │
│  - Detects heating cycles                                        │
│  - Generates output files                                        │
│  - Returns JSON summary                                          │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                   PostgreSQL Database                            │
│  Tables:                                                         │
│  - heating_device (device_serial PK)                             │
│  - heating_device_data (readings)                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Processing Pipeline

### Stage 1: File Loading & Header Detection

```python
Input: Excel file (e.g., ORS80646f049736_2510270903-RTU9.xlsx)
```

1. Opens Excel file using pandas
2. Reads raw data without header
3. Searches for "State" column to identify header row
4. Extracts device metadata:
   - Device Name (cell B1)
   - MAC Serial # (cell A2, strips "DevID: " prefix)
5. Normalizes serial number using `hex_upper()`:
   - Uppercase hex digits
   - Lowercase "0x" prefix if present
   - Does NOT add prefix if missing

**Example:**
```
Raw: DevID: 80646f049736
Normalized: 80646F049736

Raw: DevID: 0x80646f049736
Normalized: 0x80646F049736
```

### Stage 2: Data Filtering

1. Renames 7th column to "Note"
2. Filters for rows where `Note == "Test Run"`
3. Adds "Enable" and "Disable" columns based on State
4. Validates sufficient columns exist (must have at least 7)

### Stage 3: Timestamp Cleaning

**Problem:** Raw data often has:
- Duplicate timestamps (device malfunction)
- Missing minute-level readings (gaps)

**Solution:**
1. Removes duplicate timestamps (keeps last occurrence)
2. Generates complete minute-level range from first to last timestamp
3. Forward-fills missing row values from previous valid readings
4. Drops rows with missing critical temperature data

**Result:** Clean, continuous minute-by-minute data

### Stage 4: Temperature Statistics Collection

Before heating detection, the system collects comprehensive statistics:

```python
- Test Run Rows: Total rows after filtering
- Supply Temperature: min, max, mean
- Return Temperature: min, max, mean
- Temperature Differential: Supply - Return (min, max, mean)
- Rows where Supply > Return
- Rows where Supply >= Return + 7°C
```

These statistics are used to generate device status reports.

### Stage 5: Heating Detection

**Algorithm:**

```python
for each row i in data:
    delta = supply[i] - supply[i-1]

    # Turn heating ON
    if (NOT in_heating AND
        delta > 5°C AND
        supply[i] > return[i] AND
        row i not previously triggered):
        in_heating = True
        group_id++
        mark row as "On"

    # Turn heating OFF
    elif (in_heating AND delta <= -2.7°C):
        in_heating = False
        mark row as "Off"

    # Maintain state
    else:
        mark row as current state
```

**Key Thresholds:**
- **Turn ON:** Temperature jump > 5°C AND supply > return
- **Turn OFF:** Temperature drop <= -2.7°C
- **Prevents Re-triggering:** Each row can only trigger heating once

### Stage 6: Heating Cycle Validation

Not all detected heating groups are valid. Each group must pass:

**60% Rule:**
```
Valid rows = count where (Supply >= Return + 7°C)
If (valid_rows / total_group_rows) >= 0.6:
    Group is VALID
Else:
    Group is INVALID (removed)
```

**Example:**
```
Group 1: 100 rows detected
- 65 rows have Supply >= Return + 7°C
- 65/100 = 65% >= 60% ✓ VALID

Group 2: 50 rows detected
- 20 rows have Supply >= Return + 7°C
- 20/50 = 40% < 60% ✗ INVALID (removed)
```

### Stage 7: Hourly Summarization

For each hour that contains valid heating:

1. Check Enable/Disable consistency:
   - If Enable count >= 55 minutes: Energy Saver ON
   - If Disable count >= 55 minutes: Energy Saver OFF
2. Count "Heating On" minutes in that hour
3. Create summary row with:
   - Device Name & Serial
   - Date/Time On (start of hour)
   - Date/Time Off (end of hour)
   - Enable/Disable status
   - Heating On minutes

**Output:** Summary DataFrame with one row per valid heating hour

### Stage 8: Excel Output Generation

Creates multi-sheet workbook:

1. **Original Data** - Raw unmodified data
2. **Filtered Test Run** - After "Test Run" filtering
3. **Heating Data Set** - Only hours with heating activity
4. **Heat Cleaned Data** - Final hourly summaries
5. **Discarded** - Duplicate/invalid rows removed

**Visual Highlighting:**
- Cells with "Heating == On" highlighted in light orange
- Supply Temp column highlighted during heating

### Stage 9: Database Insertion

If `--insert-db` flag is used:

1. **Device Table:**
   ```sql
   INSERT INTO heating_device (device_serial)
   VALUES ('80646F049736')
   ON CONFLICT (device_serial) DO NOTHING
   ```

2. **Data Table:**
   ```sql
   INSERT INTO heating_device_data (
       device_serial, epoch_date_stamp, date_stamp,
       energy_saver_on, heating_on_minutes, device_name,
       date_time_on, date_time_off
   ) VALUES (...)
   ON CONFLICT (device_serial, epoch_date_stamp)
   DO NOTHING  -- or DO UPDATE if --upserts flag
   ```

**Timezone Conversion:**
- Local time (America/Detroit) → UTC
- Stores as epoch timestamp for indexing
- Stores datetime for human readability

### Stage 10: Device Status Report Generation

**NEW FEATURE (October 2025)**

After processing one or more files, generates a diagnostic Excel report:

**Filename:**
- Single file mode: `{input-filename}-results.xlsx`
- Batch mode: `batch-{timestamp}-results.xlsx`

**Location:** `upload-results/` directory (sibling to source folder)

**Contents:**
- One row per processed file
- Comprehensive temperature statistics
- Heating detection results
- Status indicators (success, no_heating_detected, errors)

---

## File Naming Conventions

### Input Files

**Format:** `ORS{serial}_{timestamp}-{location}.xlsx`

**Examples:**
```
ORS80646f049736_2510270903-RTU9.xlsx
ORS80646f047032_2510271855-RTU23.xlsx
ORSb0a732e61eba_2504141148.xlsx
```

**Components:**
- `ORS` - Prefix (Omni Recirculation System?)
- `{serial}` - Device MAC serial (12 hex digits)
- `{timestamp}` - YYMMDDHHMM format
- `{location}` - Optional location identifier

### Upload Processing Files

When PGUI uploads files, they are renamed:

**Single Upload:**
```
{timestamp}_{base64}.xlsx

Example: 20251027_225619_MC45MDU3.xlsx
```

**Chunked Upload (large files):**
```
{timestamp}_{base64}.xlsx

Example: 20251027_130410_MC40MTQw.xlsx
```

**Post-Processing Rename (if successful):**
```
{serial}-{device_id}-{timestamp}_{base64}.xlsx

Example: 80646f049736-45-20251027_130410_MC40MTQw.xlsx
```

**Note:** Files with 0 summary rows are NOT renamed (remain as `{timestamp}_{base64}.xlsx`)

### Output Files

**Processed Data:**
```
test_done/{input_filename}_heat min per hour.xlsx

Example:
test_done/80646f049736-45-20251027_130410_MC40MTQw_heat min per hour.xlsx
```

**Device Status Reports:**
```
upload-results/{input_filename}-results.xlsx          (single file)
upload-results/batch-{timestamp}-results.xlsx         (batch mode)

Examples:
upload-results/20251027_225619_MC45MDU3-results.xlsx
upload-results/batch-20251028_123417-results.xlsx
```

**Log Files (when --logging enabled):**
```
logs/{timestamp}.out.log
logs/{timestamp}.err.log

Example:
logs/2025-10-28T12:34:56.78.out.log
logs/2025-10-28T12:34:56.78.err.log
```

---

## Device Status Reports

### Purpose

Device status reports provide diagnostic information explaining why files succeed or fail to produce heating data. This is essential for troubleshooting devices that appear to have data but generate 0 summary rows.

### Report Columns

| Column | Description | Purpose |
|--------|-------------|---------|
| `filepath` | Full path to processed file | Identification |
| `device_name` | Device name from Excel (e.g., "Amazon DTW1 RTU 23") | Identification |
| `device_serial` | Normalized MAC serial | Identification |
| `status` | Processing status (see below) | Quick diagnosis |
| `test_run_rows` | Rows after "Test Run" filtering | Data volume check |
| `summary_rows` | Final heating hours generated | Success metric |
| `supply_min` | Minimum supply temperature (°C) | Temperature range |
| `supply_max` | Maximum supply temperature (°C) | Temperature range |
| `supply_mean` | Average supply temperature (°C) | Temperature baseline |
| `return_min` | Minimum return temperature (°C) | Temperature range |
| `return_max` | Maximum return temperature (°C) | Temperature range |
| `return_mean` | Average return temperature (°C) | Temperature baseline |
| `diff_min` | Minimum temp differential (°C) | Heating capability |
| `diff_max` | Maximum temp differential (°C) | **Critical for heating validation** |
| `diff_mean` | Average temp differential (°C) | System behavior |
| `rows_supply_gt_return` | Count where supply > return | Basic heating indicator |
| `rows_above_7c_threshold` | Count where diff >= 7°C | **Validation threshold** |
| `heating_groups_detected` | Raw heating cycles found | Detection metric |
| `valid_heating_groups` | Cycles passing 60% rule | Validation metric |

### Status Values

| Status | Meaning | Action Required |
|--------|---------|-----------------|
| `success` | File produced heating data successfully | None - normal operation |
| `no_heating_detected` | File never reached +7°C threshold | Check if device was in heating mode |
| `heating_failed_validation` | Heating detected but failed 60% rule | Check sensor accuracy or thresholds |
| `error_no_note_column` | 'Note' column not found after renaming | File format issue |
| `error_insufficient_columns` | File has fewer than 7 columns | File format issue |
| `error_multiple_serials` | Multiple device serials in one file | Data integrity issue |
| `error_db_insertion` | Database insertion failed | Check database connectivity |

### Example: Understanding a Failed File

```
Device: Amazon DTW1 RTU 23 (80646F047032)
Status: no_heating_detected
Test Run Rows: 8,345
Summary Rows: 0
Temp Diff Max: 6.2°C          ← NEVER REACHES 7°C!
Rows above +7°C: 0             ← CRITICAL: No valid heating
```

**Diagnosis:** RTU 23 was not operating in heating mode. Supply temperature never exceeded return temperature by the required 7°C differential. Possible causes:
- System in cooling mode
- Heating not activated during monitoring period
- Sensor malfunction (swapped supply/return)
- Unit configured as cooling-only

---

## Command-Line Usage

### Basic Syntax

```bash
source ./source-venv.sh
python src/hcd.py [OPTIONS]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--input-file PATH` | Process single file (relative to cwd) | Process all .xlsx in cwd |
| `--insert-db` | Insert data into PostgreSQL | No database operations |
| `--upserts` | Use UPSERT (DO UPDATE) instead of DO NOTHING | DO NOTHING |
| `--logging` | Log stdout/stderr to timestamped files | Print to console |
| `--dry-run` | Show SQL without executing | Execute SQL |

### Usage Examples

**1. Process single file (no database):**
```bash
python src/hcd.py --input-file "uploads/device123.xlsx"
```

**2. Process single file with database insertion:**
```bash
python src/hcd.py --input-file "uploads/device123.xlsx" --insert-db
```

**3. Process single file with dry-run:**
```bash
python src/hcd.py --input-file "uploads/device123.xlsx" --insert-db --dry-run
```

**4. Process all files in current directory:**
```bash
cd uploads
python ../src/hcd.py --insert-db --logging
```

**5. Process with upserts (update existing records):**
```bash
python src/hcd.py --input-file "uploads/device123.xlsx" --insert-db --upserts
```

### Output

**JSON Summary (always printed to original stdout):**
```json
{
  "mode": "live-run",
  "summary-rows": 30,
  "heating-devices": 1,
  "heating-device-readings": 30,
  "heating-serial-devices": [
    {
      "device_id": 45,
      "device_serial": "80646F049736"
    }
  ]
}
```

**Console Messages:**
```
📄 Processing file: /path/to/file.xlsx
Summary Rows: 30
✅ Processed and saved: ./test_done/file_heat min per hour.xlsx
📊 Device status report written to: ./upload-results/file-results.xlsx
```

---

## PGUI Integration

### Bull Worker Architecture

The PGUI web application uses a Bull queue system (Redis-backed) to process file uploads asynchronously.

**Flow:**

```
1. User uploads file via PGUI web interface (Next.js)
   ↓
2. File saved to uploads/ directory
   ↓
3. Job added to Bull queue with metadata:
   {
     mode: "single" | "chunked",
     originalFileName: "ORS80646f049736_2510270903-RTU9.xlsx",
     destinationPath: "/home/chris/projects/.../uploads/file.xlsx",
     ...
   }
   ↓
4. Bull Worker (pgui/scripts/bullWorker.js) picks up job
   ↓
5. Worker executes hcd.py:
   python src/hcd.py --input-file "{destinationPath}" --insert-db --logging
   ↓
6. Worker captures JSON output from hcd.py
   ↓
7. Worker updates job status in PGUI database
   ↓
8. User sees results in PGUI job monitor
```

### Bull Worker Script

**Location:** `pgui/scripts/bullWorker.js`

**Key Responsibilities:**
- Monitor Bull queue for new jobs
- Execute hcd.py with appropriate arguments
- Parse JSON output
- Handle success/failure
- Update PGUI job status
- Rename files on success (adds serial-deviceid prefix)

**Typical Invocation:**
```javascript
const result = await execAsync(
  `python ${hcdPath} --input-file "${filePath}" --insert-db --logging`,
  { cwd: hcdDir }
);
const jsonResult = JSON.parse(result.stdout);
```

### Job Status in PGUI

Users can view job results in the PGUI interface:

```json
{
  "mode": "single",
  "originalFileName": "ORS80646f049736_2510270903-RTU9.xlsx",
  "destinationPath": "/home/chris/projects/heat-cycle-detection/uploads/20251027_130410_MC40MTQw.xlsx",
  "resultJSON": {
    "mode": "live-run",
    "summary-rows": 30,
    "heating-devices": 1,
    "heating-device-readings": 30,
    "heating-serial-devices": [
      {
        "device_id": 45,
        "device_serial": "80646f049736"
      }
    ]
  }
}
```

**File Rename Behavior:**

After successful processing (summary-rows > 0), the Bull worker renames:
```
Before: 20251027_130410_MC40MTQw.xlsx
After:  80646f049736-45-20251027_130410_MC40MTQw.xlsx
        └─serial──┘ └id┘
```

**Note:** PGUI job monitor stores the **original** filename, which may not match the actual file after rename.

---

## Output Files

### 1. Processed Excel Workbook

**Location:** `test_done/{filename}_heat min per hour.xlsx`

**Sheets:**

#### Original Data
- Unmodified raw data from source file
- All rows and columns preserved

#### Filtered Test Run
- Rows where `Note == "Test Run"`
- Device Name and MAC Serial added as first columns
- Supply Temp/C cells highlighted orange during heating
- Heating column shows "On"/"Off"
- Heating_Group shows group ID or 0

#### Heating Data Set
- Only hours containing heating activity
- Includes all full hours where heating occurred
- Used for detailed temperature analysis

#### Heat Cleaned Data
- **This is the summary data that gets inserted into the database**
- One row per hour with ≥55 minutes consistent state
- Columns:
  - Device Name
  - MAC Serial #
  - Date/Time On
  - Date/Time Off
  - Enable (1 if energy saver enabled)
  - Disable (1 if energy saver disabled)
  - Heating On (minutes of heating in that hour)

#### Discarded
- Duplicate timestamps (removed)
- Rows with missing critical data
- Rows before first valid timestamp

### 2. Device Status Report

**Location:** `upload-results/{filename}-results.xlsx`

**Purpose:** Diagnostic information for each processed file

**When Generated:**
- After processing one or more files
- One row per file processed in that run
- Batch mode: Combines all files in single report

**Use Cases:**
- Troubleshooting files with 0 summary rows
- Comparing device performance
- Identifying sensor issues
- Validating heating system operation

### 3. Log Files

**Location:** `logs/{timestamp}.out.log` and `logs/{timestamp}.err.log`

**Enabled with:** `--logging` flag

**Contents:**
- **stdout:** All processing messages, SQL statements (if dry-run)
- **stderr:** Error messages, warnings

**Note:** JSON summary is ALWAYS written to original stdout (not log files)

---

## Understanding Results

### Successful Processing

**Indicators:**
- Summary rows > 0
- Device inserted/found in database
- Readings inserted into database
- Status report shows `success`

**Example:**
```json
{
  "mode": "live-run",
  "summary-rows": 30,
  "heating-devices": 1,
  "heating-device-readings": 30,
  "heating-serial-devices": [
    {"device_id": 45, "device_serial": "80646F049736"}
  ]
}
```

**Status Report:**
```
Device: Amazon DTW1 RTU 9 (80646F049736)
Status: success
Temp Diff Max: 11.5°C
Rows above +7°C: 242
Valid heating groups: 33
```

### No Heating Detected

**Indicators:**
- Summary rows = 0
- No database insertions
- Status: `no_heating_detected`
- `diff_max` < 7.0°C

**Example:**
```json
{
  "mode": "live-run",
  "summary-rows": 0,
  "heating-devices": 0,
  "heating-device-readings": 0,
  "heating-serial-devices": []
}
```

**Status Report:**
```
Device: Amazon DTW1 RTU 23 (80646F047032)
Status: no_heating_detected
Temp Diff Max: 6.2°C          ← Below 7°C threshold
Rows above +7°C: 0             ← No valid heating
Valid heating groups: 0
```

**Common Causes:**
1. **Cooling Mode:** Supply cooler than return (negative differential)
2. **Heating Inactive:** System never turned on heating during monitoring
3. **Sensor Issues:** Supply/return sensors swapped or malfunctioning
4. **Short Cycles:** Brief heating events that don't sustain 7°C differential

### Validation Failures

**Indicators:**
- Heating groups detected > 0
- Valid heating groups = 0
- Status: `heating_failed_validation`
- Some rows above 7°C but < 60% of any group

**Cause:** Detected heating cycles don't maintain sufficient temperature differential

**Example:**
```
Heating groups detected: 5
Valid heating groups: 0
Rows above +7°C: 45
```

This means temperature briefly exceeded 7°C but couldn't sustain it for 60% of any detected cycle.

---

## Troubleshooting

### Issue: File Processed But No Heating Detected

**Symptoms:**
- File completes without errors
- summary-rows = 0
- Status: `no_heating_detected`

**Diagnosis Steps:**

1. **Check Device Status Report:**
   ```bash
   # Look at the results file
   ls upload-results/*-results.xlsx
   ```

2. **Examine Temperature Statistics:**
   - Is `diff_max` >= 7.0°C?
   - Is `diff_mean` positive or negative?
   - How many `rows_above_7c_threshold`?

3. **Review Filtered Test Run Sheet:**
   - Open the `_heat min per hour.xlsx` file
   - Check "Filtered Test Run" sheet
   - Look at Supply Temp/C vs Return Temp/C columns

**Solutions:**

| Symptom | Cause | Solution |
|---------|-------|----------|
| diff_mean << 0 | Cooling mode | No action - system not heating |
| diff_max < 7.0 | Insufficient heating | Check if device was in heating mode |
| diff_max > 7.0 but rows_above_7c_threshold = 0 | Data inconsistency | Review raw data for sensor issues |
| Supply always < Return | Swapped sensors | Check sensor wiring |

### Issue: Files Missing After Processing

**Symptom:** Job monitor shows file, but file not found in uploads/

**Cause:** Successful files are renamed by Bull worker

**Original Name:**
```
20251027_130410_MC40MTQw.xlsx
```

**Renamed To:**
```
80646f049736-45-20251027_130410_MC40MTQw.xlsx
```

**Solution:** Look for files matching the pattern `{serial}-{id}-{original}`:
```bash
ls -ltr uploads/ | grep 20251027_130410
```

### Issue: Database Insertion Fails

**Symptoms:**
- Processing completes
- Excel files generated
- JSON shows 0 devices/readings
- Logs show database errors

**Common Causes:**

1. **Missing Environment Variables:**
   ```bash
   # Check required vars
   echo $PGHOST_2
   echo $PGDATABASE_2
   echo $PGUSER_2
   echo $PGPORT_2
   ```

2. **Missing .pgpass File:**
   ```bash
   # Check ~/.pgpass exists and has correct permissions
   ls -l ~/.pgpass
   # Should be: -rw------- (0600)
   ```

3. **Network Connectivity:**
   ```bash
   # Test connection
   psql -h $PGHOST_2 -p $PGPORT_2 -U $PGUSER_2 -d $PGDATABASE_2 -c "SELECT 1"
   ```

4. **Foreign Key Constraint:**
   - If serial number format changed, old data may conflict
   - Check `normalize-existing-serials.sql` has been run

### Issue: All Files Show 0 Summary Rows

**Symptom:** Batch processing shows all files with status `no_heating_detected`

**Diagnosis:**

1. **Check if seasonal:**
   - Files from summer months may have no heating
   - Verify date range in file timestamps

2. **Database query to verify:**
   ```sql
   SELECT device_serial, COUNT(*), MAX(date_stamp)
   FROM heating_device_data
   GROUP BY device_serial;
   ```

3. **Compare with known-good file:**
   ```bash
   # Process a file that previously worked
   python src/hcd.py --input-file "downloads/known-good-file.xlsx" --dry-run
   ```

### Issue: Incorrect Heating Detection

**Symptom:** Heating marked "On" during periods that should be "Off"

**Possible Causes:**

1. **False Triggers:** Brief temperature spikes triggering heating detection
2. **Threshold Too Low:** 5°C trigger may be too sensitive
3. **Sensor Noise:** Erratic sensor readings

**Investigation:**
1. Open `_heat min per hour.xlsx`
2. Go to "Filtered Test Run" sheet
3. Find orange-highlighted rows (Heating = On)
4. Check:
   - Delta Supply column
   - Supply Temp/C vs Return Temp/C
   - Is differential consistently > 7°C?

**Tuning (Advanced):**
Edit `src/hcd.py` line ~174:
```python
# Current trigger threshold
if delta > 5 and supply[i] > return_temp[i]:

# Stricter threshold (example)
if delta > 8 and supply[i] > return_temp[i]:
```

---

## Best Practices

### For PGUI Operators

1. **Monitor Job Status:** Check PGUI job monitor regularly for failures
2. **Review Status Reports:** Check `upload-results/` for diagnostic reports
3. **Archive Old Files:** Periodically move processed files to archive location
4. **Database Maintenance:** Run `VACUUM ANALYZE` on heating tables monthly

### For Developers

1. **Test Changes:** Always test with both successful and failing test files
2. **Preserve Serials:** Never modify serial normalization without migration
3. **Logging:** Use `--logging` for production, omit for quick tests
4. **Dry Run First:** Test database operations with `--dry-run` before live
5. **Version Control:** Commit after any changes to detection thresholds

### For Analysts

1. **Use Status Reports:** Check device-status reports before investigating issues
2. **Seasonal Awareness:** Expect 0 heating in summer months
3. **Trend Analysis:** Compare `diff_max` over time to detect sensor degradation
4. **Validation Rate:** Monitor `valid_heating_groups / heating_groups_detected` ratio

---

## Appendix A: Database Schema

### heating_device

```sql
CREATE TABLE heating_device (
    device_id SERIAL PRIMARY KEY,
    device_serial VARCHAR(20) UNIQUE NOT NULL
);
```

### heating_device_data

```sql
CREATE TABLE heating_device_data (
    device_serial VARCHAR(20) NOT NULL,
    epoch_date_stamp BIGINT NOT NULL,
    date_stamp TIMESTAMP NOT NULL,
    energy_saver_on BOOLEAN NOT NULL,
    heating_on_minutes INTEGER NOT NULL,
    device_name VARCHAR(100),
    date_time_on TIMESTAMP,
    date_time_off TIMESTAMP,

    PRIMARY KEY (device_serial, epoch_date_stamp),
    FOREIGN KEY (device_serial)
        REFERENCES heating_device(device_serial)
);
```

---

## Appendix B: Temperature Threshold Rationale

### Why 7°C Validation Threshold?

The 7°C (12.6°F) differential between supply and return air is used because:

1. **Industry Standard:** Typical heating systems maintain 15-25°F differential during active heating
2. **Sensor Accuracy:** Provides buffer for ±1°C sensor tolerance
3. **Distinguishes Heating from Circulation:** Fan-only mode has minimal differential
4. **Validation Confidence:** 7°C sustained differential confirms genuine heating

### Why 60% Validation Rule?

Requiring 60% of a heating cycle to maintain 7°C differential:

1. **Allows Startup/Shutdown:** Systems take time to reach full temperature
2. **Prevents False Positives:** Brief spikes don't qualify as heating
3. **Sensor Tolerance:** Accommodates temporary sensor glitches
4. **Empirical Validation:** Based on analysis of known-good heating cycles

---

## Appendix C: Common SQL Queries

### Find All Devices
```sql
SELECT device_id, device_serial
FROM heating_device
ORDER BY device_id;
```

### Heating Summary by Device
```sql
SELECT
    device_serial,
    COUNT(*) as reading_count,
    SUM(heating_on_minutes) as total_heating_minutes,
    MIN(date_stamp) as first_reading,
    MAX(date_stamp) as last_reading
FROM heating_device_data
GROUP BY device_serial;
```

### Recent Heating Activity
```sql
SELECT
    device_serial,
    device_name,
    date_stamp,
    heating_on_minutes,
    energy_saver_on
FROM heating_device_data
WHERE date_stamp >= NOW() - INTERVAL '7 days'
ORDER BY date_stamp DESC
LIMIT 50;
```

### Devices with No Recent Data
```sql
SELECT d.device_serial
FROM heating_device d
LEFT JOIN heating_device_data dd ON d.device_serial = dd.device_serial
    AND dd.date_stamp >= NOW() - INTERVAL '30 days'
WHERE dd.device_serial IS NULL;
```

---

## Support

For issues, questions, or improvements:

1. Check this guide first
2. Review device status reports in `upload-results/`
3. Check log files in `logs/` (if using --logging)
4. Contact development team with:
   - Input filename
   - JSON output
   - Device status report
   - Relevant log files

---

**End of Guide**
