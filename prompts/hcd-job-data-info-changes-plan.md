# HCD Job Data Information Changes - Implementation Plan

**Date:** October 28, 2025
**Project:** Heat Cycle Detection System
**Purpose:** Eliminate file renaming, add Job ID to data, and store complete device array

---

## Table of Contents

1. [Overview](#1-overview)
2. [Current State Analysis](#2-current-state-analysis)
3. [Problems Identified](#3-problems-identified)
4. [Proposed Changes](#4-proposed-changes)
5. [Implementation Plan](#5-implementation-plan)
6. [Testing Strategy](#6-testing-strategy)
7. [Rollback Plan](#7-rollback-plan)

---

## 1. Overview

### Current Issues

The current implementation has several issues related to job data management:

1. **File Renaming Inconsistency**: Files are renamed after processing to include device serial and ID, but job data still references the old filename
2. **Limited Device Information**: Only the first device from `heating-serial-devices` array is used for renaming
3. **Missing Job ID**: Job data doesn't include its own Job ID for reference
4. **Data Mismatch**: Job Monitor displays `destinationPath` that no longer exists after successful processing

### Objectives

- [x] **Eliminate file renaming** - Keep original uploaded filename for consistency
- [x] **Add Job ID** to job data structure for easy cross-referencing
- [x] **Store complete device array** - Preserve all devices, not just the first one
- [x] **Maintain backward compatibility** with existing job monitoring UI

---

## 2. Current State Analysis

### 2.1 Current Job Data Structure

**Initial Creation** (esaverUpload.js):
```javascript
// Chunked upload
{
  mode: "chunked",
  chunkCount: 3,
  originalFileName: "ORS80646f049736_2510270903-RTU9.xlsx",
  assembledPath: "/path/to/uploads/20251027_130410_MC40MTQw.xlsx"
}

// Single upload
{
  mode: "single",
  originalFileName: "ORS80646f047032_2510271855-RTU23.xlsx",
  destinationPath: "/path/to/uploads/20251027_225619_MC45MDU3.xlsx"
}
```

**After Processing** (bullWorker.js adds resultJSON):
```javascript
{
  mode: "single",
  originalFileName: "ORS80646f047032_2510271855-RTU23.xlsx",
  destinationPath: "/path/to/uploads/20251027_225619_MC45MDU3.xlsx",
  resultJSON: {
    mode: "live-run",
    summary-rows: 0,
    heating-devices: 0,
    heating-device-readings: 0,
    heating-serial-devices: []  // ← Only used to get first device
  }
}
```

**After File Rename** (successful processing):
```
File on disk: 80646F049736-45-20251027_130410_MC40MTQw.xlsx
Job data destinationPath: /path/to/uploads/20251027_130410_MC40MTQw.xlsx  ← BROKEN
```

### 2.2 Current File Renaming Logic

**Location:** `pgui/scripts/bullWorker.js` lines 64-78

```javascript
// Attempt to rename if device info is found
const devices = result["heating-serial-devices"];
if (Array.isArray(devices) && devices.length > 0) {
  const { device_id, device_serial } = devices[0];  // ← ONLY USES FIRST DEVICE
  const prefix = `${device_serial}-${device_id}-`;
  const oldPath = assembledPath;
  const newName = prefix + path.basename(assembledPath);
  const newPath = path.join(UPLOAD_DIR, newName);
  try {
    fs.renameSync(oldPath, newPath);
    log(`Renamed file to ${newName}`);
  } catch (renameErr) {
    log(`Failed to rename file: ${renameErr}`);
  }
}
```

### 2.3 File Chunking Mechanism

**Overview:**

The system supports uploading large files (>512KB) by splitting them into chunks during transport. This is purely a **network optimization** - by the time hcd.py processes the file, all chunks have been reassembled into a single complete file.

**Chunking Process:**

1. **Upload Detection** (`esaverUpload.js`):
   - Files ≤512KB: Single upload mode
   - Files >512KB: Chunked upload mode (512KB chunks)

2. **Chunk Assembly** (`esaverUpload.js`):
   - Server receives chunks sequentially
   - Chunks are written to temporary directory
   - When all chunks received, they're concatenated into single file
   - Complete file is moved to `uploads/` directory with timestamp-based filename (e.g., `20251027_130410_MC40MTQw.xlsx`)

3. **Job Data Tracking**:
   ```javascript
   // Single upload
   {
     mode: "single",
     originalFileName: "ORSxxxx.xlsx",
     destinationPath: "/uploads/timestamp_base64.xlsx"
   }

   // Chunked upload
   {
     mode: "chunked",
     chunkCount: 5,
     originalFileName: "ORSxxxx.xlsx",
     assembledPath: "/uploads/timestamp_base64.xlsx"  // Complete reassembled file
   }
   ```

4. **Processing** (`bullWorker.js` → `hcd.py`):
   - Bull worker receives job with complete file path (`assembledPath` or `destinationPath`)
   - Executes `hcd.py --input-file "complete_file.xlsx"`
   - **hcd.py has NO knowledge of chunking** - it only sees the complete file
   - Generates JSON output based on complete file content

5. **Result JSON**:
   - JSON output contains `mode: "live-run"` or `mode: "dry-run"` (processing mode, not upload mode)
   - **No trace of chunking in JSON** - reflects only the data found in the complete file
   - Device information extracted from complete workbook only

**Key Point: Chunking is Transparent to Processing**

The chunking mechanism is **completely transparent** to the data processing pipeline:
- ✅ Chunks are reassembled **before** hcd.py execution
- ✅ hcd.py always processes a **single complete Excel file**
- ✅ JSON output reflects **complete file data only**
- ❌ No chunk boundaries in JSON
- ❌ No chunk metadata in results

The only way to know a file was chunked is to check `job.data.mode === "chunked"` in the Bull queue job data.

### 2.4 Files Involved

| File | Role | Changes Required |
|------|------|------------------|
| `pgui/scripts/bullWorker.js` | Processes jobs, renames files | **Remove** rename logic, **Add** job ID and devices array |
| `pgui/src/pages/api/esaverUpload.js` | Creates initial job data | No changes needed |
| `pgui/src/pages/esaver/index.js` | Displays job data in UI | **Update** to show devices array (optional) |

---

## 3. Problems Identified

### 3.1 File Path Mismatch

**Problem:**
Job data stores `destinationPath: "/path/to/uploads/20251027_130410_MC40MTQw.xlsx"` but actual file is renamed to `80646F049736-45-20251027_130410_MC40MTQw.xlsx`.

**Impact:**
- Job Monitor shows incorrect filename
- Cannot locate file using job data alone
- Confusion when troubleshooting

**Root Cause:**
File is renamed after job data is updated, and job data is not re-updated with new path.

### 3.2 Lost Device Information

**Problem:**
If a file contains multiple devices, only the first device is used for renaming. Other devices are ignored.

**Impact:**
- Loss of information about additional devices
- Cannot determine all devices processed without examining `resultJSON.heating-serial-devices`
- Filename doesn't reflect true content for multi-device files

**Root Cause:**
Code only extracts `devices[0]` from array.

### 3.3 Missing Job ID

**Problem:**
Job data doesn't include its own Job ID for self-reference.

**Impact:**
- Difficult to cross-reference job data with job ID
- Must rely on UI to show both separately
- No easy way to link logs/files to specific job

**Root Cause:**
Job ID is managed by Bull queue, not explicitly stored in job.data.

---

## 4. Proposed Changes

### 4.1 New Job Data Structure

**Proposed Structure:**
```javascript
{
  jobId: 12345,                                    // ← NEW: Self-referencing job ID
  mode: "single",
  originalFileName: "ORS80646f047032_2510271855-RTU23.xlsx",
  destinationPath: "/path/to/uploads/20251027_225619_MC45MDU3.xlsx",
  devices: [],                                     // ← NEW: Complete device array
  statusReportPath: null,                          // ← NEW: Path to device status report (*-results.xlsx)
  heatAnalysisPath: null,                          // ← NEW: Path to heat analysis workbook (*_heat min per hour.xlsx)
  resultJSON: {
    mode: "live-run",
    summary-rows: 0,
    heating-devices: 0,
    heating-device-readings: 0,
    heating-serial-devices: []                     // ← Keep for backward compatibility
  }
}
```

**Example with Devices:**
```javascript
{
  jobId: 12346,
  mode: "chunked",
  originalFileName: "ORS80646f049736_2510270903-RTU9.xlsx",
  destinationPath: "/path/to/uploads/20251027_130410_MC40MTQw.xlsx",  // ← NEVER CHANGES
  devices: [                                       // ← NEW: Flattened for easy access
    {
      device_id: 45,
      device_serial: "80646F049736"
    }
  ],
  statusReportPath: "/path/to/upload-results/20251027_130410_MC40MTQw-results.xlsx",  // ← NEW
  heatAnalysisPath: "/path/to/test_done/20251027_130410_MC40MTQw_heat min per hour.xlsx",  // ← NEW
  resultJSON: {
    mode: "live-run",
    summary-rows: 30,
    heating-devices: 1,
    heating-device-readings: 30,
    heating-serial-devices: [
      { device_id: 45, device_serial: "80646F049736" }
    ]
  }
}
```

### 4.2 Benefits of New Structure

- [x] **Consistent File Paths** - `destinationPath` always matches actual file
- [x] **Complete Device Information** - All devices accessible at top level
- [x] **Self-Referencing** - Job ID included in data for easy correlation
- [x] **Downloadable Reports** - Direct paths to status reports and heat analysis files for PGUI download links
- [x] **Backward Compatible** - `resultJSON` structure unchanged
- [x] **Simplified Troubleshooting** - Single source of truth for all job information

### 4.3 File Paths for PGUI Downloads

The PGUI will be able to provide download links for generated files using the stored paths:

**1. Device Status Report** (`statusReportPath`):
- Location: `upload-results/` directory
- Filename: `{input_basename}-results.xlsx`
- Content: Vertical format diagnostic report with temperature statistics and validation failures
- Available: Always (for every processed file)

**2. Heat Analysis Workbook** (`heatAnalysisPath`):
- Location: `test_done/` directory
- Filename: `{input_basename}_heat min per hour.xlsx`
- Content: Multi-sheet workbook with 5 sheets (Original Data, Filtered Test Run, Heating Data Set, Heat Cleaned Data, Discarded)
- Available: Always (created even for 0 summary rows)

**Path Extraction from hcd.py Output:**

The Python script already generates these files with predictable naming patterns. The bullWorker.js will need to:
1. Construct the expected file paths based on input filename
2. Verify files exist
3. Store absolute paths in job data

---

## 5. Implementation Plan

### Phase 1: Remove File Renaming Logic

**File:** `pgui/scripts/bullWorker.js`

**Task 1.1:** Remove file rename code

- [ ] Remove lines 64-78 (file renaming logic)
- [ ] Keep the resultJSON storage logic (lines 80-89)
- [ ] Add comment explaining why renaming was removed

**Before:**
```javascript
// Attempt to rename if device info is found
const devices = result["heating-serial-devices"];
if (Array.isArray(devices) && devices.length > 0) {
  const { device_id, device_serial } = devices[0];
  const prefix = `${device_serial}-${device_id}-`;
  const oldPath = assembledPath;
  const newName = prefix + path.basename(assembledPath);
  const newPath = path.join(UPLOAD_DIR, newName);
  try {
    fs.renameSync(oldPath, newPath);
    log(`Renamed file to ${newName}`);
  } catch (renameErr) {
    log(`Failed to rename file: ${renameErr}`);
  }
}

// Store the parsed Python JSON in the job's data property
job.data.resultJSON = result;
```

**After:**
```javascript
// NOTE: File renaming removed as of 2025-10-28
// Files now retain their original uploaded names for consistency with job data.
// Device information is stored in job.data.devices array instead.

// Store the parsed Python JSON in the job's data property
job.data.resultJSON = result;
```

### Phase 2: Add Job ID to Job Data

**File:** `pgui/scripts/bullWorker.js`

**Task 2.1:** Store job ID in job data

- [ ] After parsing JSON result, add `job.data.jobId = job.id`
- [ ] Place before `job.update()` call

**Implementation:**
```javascript
// Store the parsed Python JSON in the job's data property
job.data.resultJSON = result;

// Add job ID for self-reference
job.data.jobId = job.id;

// Store complete devices array at top level for easy access
const devices = result["heating-serial-devices"];
if (Array.isArray(devices)) {
  job.data.devices = devices;
} else {
  job.data.devices = [];
}

try {
  // Bull 3.29.0 => we can call job.update(...) to store changed data
  await job.update(job.data);
} catch (updateErr) {
  log(`Failed to update job data with Python JSON: ${updateErr}`);
}
```

### Phase 3: Store Complete Device Array

**File:** `pgui/scripts/bullWorker.js`

**Task 3.1:** Extract and store full devices array

- [ ] Extract `heating-serial-devices` from result
- [ ] Store in `job.data.devices` (not nested in resultJSON)
- [ ] Handle empty array case
- [ ] Validate array structure

**Implementation (combined with Phase 2):**
```javascript
const devices = result["heating-serial-devices"];
if (Array.isArray(devices)) {
  job.data.devices = devices;
  log(`Stored ${devices.length} device(s) in job data`);
} else {
  job.data.devices = [];
  log(`No devices array found, set to empty array`);
}
```

### Phase 4: Update Complete bullWorker.js Logic

**File:** `pgui/scripts/bullWorker.js`

**Task 4.1:** Replace lines 62-89 with new logic

- [ ] Remove file renaming block (lines 64-78)
- [ ] Add job ID storage
- [ ] Add devices array storage
- [ ] Add file path storage for generated reports
- [ ] Keep resultJSON storage
- [ ] Update logging

**Complete Replacement (lines 62-98):**
```javascript
try {
  const result = JSON.parse(jsonLine);

  // NOTE: File renaming removed as of 2025-10-28
  // Files now retain their original uploaded names for consistency with job data.
  // Device information is stored in job.data.devices array instead.

  // Store the parsed Python JSON in the job's data property
  job.data.resultJSON = result;

  // Add job ID for self-reference
  job.data.jobId = job.id;

  // Store complete devices array at top level for easy access
  const devices = result["heating-serial-devices"];
  if (Array.isArray(devices)) {
    job.data.devices = devices;
    log(`Stored ${devices.length} device(s) in job data`);
  } else {
    job.data.devices = [];
    log(`No devices array found, set to empty array`);
  }

  // Store file paths for generated reports (for PGUI download links)
  const inputBasename = path.basename(assembledPath, '.xlsx');
  const statusReportPath = path.join(PYTHON_SCRIPT_HCD_HOME, 'upload-results', `${inputBasename}-results.xlsx`);
  const heatAnalysisPath = path.join(PYTHON_SCRIPT_HCD_HOME, 'test_done', `${inputBasename}_heat min per hour.xlsx`);

  // Verify files exist before storing paths
  job.data.statusReportPath = fs.existsSync(statusReportPath) ? statusReportPath : null;
  job.data.heatAnalysisPath = fs.existsSync(heatAnalysisPath) ? heatAnalysisPath : null;

  if (job.data.statusReportPath) {
    log(`Status report available: ${job.data.statusReportPath}`);
  }
  if (job.data.heatAnalysisPath) {
    log(`Heat analysis available: ${job.data.heatAnalysisPath}`);
  }

  try {
    // Bull 3.29.0 => we can call job.update(...) to store changed data
    await job.update(job.data);
    log(`Job ${job.id} data updated successfully with jobId, devices, and file paths`);
  } catch (updateErr) {
    log(`Failed to update job data: ${updateErr}`);
  }

  log(`Job ${job.id} completed successfully`);

  // Return success
  resolve();
} catch (parseErr) {
  log(`JSON parse error: ${parseErr}`);
  reject(new Error("Invalid JSON output"));
}
```

### Phase 5: Update Documentation

**Files to Update:**

- [ ] `hcd-user-guide.md` - Update file naming section
- [ ] `CLAUDE.md` - Update if file naming is mentioned
- [ ] `prompts/hcd-job-data-info-changes.md` - Mark as implemented

**Task 5.1:** Update hcd-user-guide.md

**Section:** "File Naming Conventions"

- [ ] Remove references to post-processing rename
- [ ] Update examples to show files keep original names
- [ ] Add note about `devices` array in job data

**Task 5.2:** Update "PGUI Integration" section

- [ ] Update file rename behavior documentation
- [ ] Document new job data structure
- [ ] Update troubleshooting section

---

## 6. Testing Strategy

### 6.1 Unit Testing

**Test 6.1.1: Single file upload with heating detected**

- [ ] Upload single file with heating data
- [ ] Verify job data contains `jobId`
- [ ] Verify `devices` array populated correctly
- [ ] Verify `statusReportPath` points to existing file in `upload-results/`
- [ ] Verify `heatAnalysisPath` points to existing file in `test_done/`
- [ ] Verify file NOT renamed
- [ ] Verify `destinationPath` matches actual file

**Test 6.1.2: Single file upload with no heating**

- [ ] Upload single file with no heating
- [ ] Verify job data contains `jobId`
- [ ] Verify `devices` array is empty `[]`
- [ ] Verify `statusReportPath` still exists (report generated even for failures)
- [ ] Verify `heatAnalysisPath` still exists (workbook created even with 0 summary rows)
- [ ] Verify file NOT renamed
- [ ] Verify `destinationPath` matches actual file

**Test 6.1.3: Chunked file upload with heating detected**

- [ ] Upload large file (chunked) with heating data
- [ ] Verify job data contains `jobId`
- [ ] Verify `devices` array populated correctly
- [ ] Verify `statusReportPath` points to existing file
- [ ] Verify `heatAnalysisPath` points to existing file
- [ ] Verify file NOT renamed
- [ ] Verify `assembledPath` matches actual file

**Test 6.1.4: Multi-device file (if possible)**

- [ ] If multi-device files exist, test with one
- [ ] Verify ALL devices stored in `devices` array
- [ ] Verify order preserved from `heating-serial-devices`

### 6.2 Integration Testing

**Test 6.2.1: Job Monitor Display**

- [ ] Upload file and process
- [ ] Check Job Monitor table shows correct data
- [ ] Expand "Data" column, verify new fields present
- [ ] Verify `jobId` matches row ID
- [ ] Verify `devices` array visible
- [ ] Verify `statusReportPath` and `heatAnalysisPath` visible
- [ ] Test download links for both files (if PGUI implements download feature)
- [ ] Verify downloaded files match the stored paths

**Test 6.2.2: File Location**

- [ ] After processing, locate file in `uploads/` directory
- [ ] Verify filename matches `destinationPath` or `assembledPath` from job data
- [ ] Verify no renamed files exist

**Test 6.2.3: Backward Compatibility**

- [ ] Verify old jobs (before changes) still display correctly
- [ ] Verify no errors when accessing jobs without `jobId` or `devices` fields

### 6.3 Regression Testing

**Test 6.3.1: Database Insertion**

- [ ] Verify hcd.py still inserts data correctly
- [ ] Verify device_serial matches job data
- [ ] Verify summary rows count matches

**Test 6.3.2: Logging**

- [ ] Check `esaver-upload.log` for new log messages
- [ ] Verify no errors during job data update
- [ ] Verify device count logged correctly

---

## 7. Rollback Plan

### 7.1 Rollback Procedure

If issues arise, rollback can be performed quickly:

**Step 7.1.1: Revert bullWorker.js**

- [ ] Restore previous version from git:
  ```bash
  cd /path/to/pgui
  git checkout HEAD~1 scripts/bullWorker.js
  ```

**Step 7.1.2: Restart Bull Worker**

- [ ] Stop current worker process
- [ ] Start worker with reverted code
- [ ] Monitor logs for successful startup

**Step 7.1.3: Verify Operation**

- [ ] Process test file
- [ ] Verify old behavior (file renaming) works
- [ ] Check job data structure

### 7.2 Rollback Considerations

**Data Compatibility:**
- New fields (`jobId`, `devices`) are additive only
- Old code will ignore new fields gracefully
- No data migration needed for rollback

**File Names:**
- Files processed with new code will NOT be renamed
- Files processed with old code WILL be renamed
- Mixed state is acceptable, no conflicts

---

## Implementation Checklist

### Pre-Implementation

- [ ] Review plan with team
- [ ] Backup current `bullWorker.js`
- [ ] Note current git commit hash
- [ ] Schedule maintenance window (if needed)

### Implementation

- [ ] **Phase 1:** Remove file renaming logic
- [ ] **Phase 2:** Add job ID to job data
- [ ] **Phase 3:** Store complete device array
- [ ] **Phase 4:** Update complete bullWorker.js logic
- [ ] **Phase 5:** Update documentation

### Testing

- [ ] **Test 6.1.1:** Single file with heating
- [ ] **Test 6.1.2:** Single file without heating
- [ ] **Test 6.1.3:** Chunked file with heating
- [ ] **Test 6.1.4:** Multi-device file (if available)
- [ ] **Test 6.2.1:** Job Monitor display
- [ ] **Test 6.2.2:** File location verification
- [ ] **Test 6.2.3:** Backward compatibility
- [ ] **Test 6.3.1:** Database insertion
- [ ] **Test 6.3.2:** Logging verification

### Post-Implementation

- [ ] Monitor production logs for 24 hours
- [ ] Verify no errors in Job Monitor
- [ ] Confirm files not being renamed
- [ ] Update issue tracker (if applicable)
- [ ] Mark this plan as complete

---

## Appendix A: Example Job Data Comparison

### Before Changes

```json
{
  "mode": "single",
  "originalFileName": "ORS80646f047032_2510271855-RTU23.xlsx",
  "destinationPath": "/home/chris/projects/heat-cycle-detection/uploads/20251027_225619_MC45MDU3.xlsx",
  "resultJSON": {
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
}
```

**Actual file on disk after rename:**
`80646F049736-45-20251027_225619_MC45MDU3.xlsx` ← **MISMATCH**

### After Changes

```json
{
  "jobId": 12346,
  "mode": "single",
  "originalFileName": "ORS80646f047032_2510271855-RTU23.xlsx",
  "destinationPath": "/home/chris/projects/heat-cycle-detection/uploads/20251027_225619_MC45MDU3.xlsx",
  "devices": [
    {
      "device_id": 45,
      "device_serial": "80646F049736"
    }
  ],
  "statusReportPath": "/home/chris/projects/heat-cycle-detection/upload-results/20251027_225619_MC45MDU3-results.xlsx",
  "heatAnalysisPath": "/home/chris/projects/heat-cycle-detection/test_done/20251027_225619_MC45MDU3_heat min per hour.xlsx",
  "resultJSON": {
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
}
```

**Actual files on disk:**
- Input file: `20251027_225619_MC45MDU3.xlsx` ← **MATCHES destinationPath**
- Status report: `upload-results/20251027_225619_MC45MDU3-results.xlsx` ← **MATCHES statusReportPath**
- Heat analysis: `test_done/20251027_225619_MC45MDU3_heat min per hour.xlsx` ← **MATCHES heatAnalysisPath**

---

## Appendix B: Code Diff Summary

### bullWorker.js Changes

**Lines to Remove:** 64-78 (file renaming block)

**Lines to Add:** After line 62 (after JSON parse)

```javascript
// Add after: const result = JSON.parse(jsonLine);

// NOTE: File renaming removed as of 2025-10-28
job.data.resultJSON = result;
job.data.jobId = job.id;
const devices = result["heating-serial-devices"];
job.data.devices = Array.isArray(devices) ? devices : [];

// Store file paths for PGUI download links
const inputBasename = path.basename(assembledPath, '.xlsx');
const statusReportPath = path.join(PYTHON_SCRIPT_HCD_HOME, 'upload-results', `${inputBasename}-results.xlsx`);
const heatAnalysisPath = path.join(PYTHON_SCRIPT_HCD_HOME, 'test_done', `${inputBasename}_heat min per hour.xlsx`);
job.data.statusReportPath = fs.existsSync(statusReportPath) ? statusReportPath : null;
job.data.heatAnalysisPath = fs.existsSync(heatAnalysisPath) ? heatAnalysisPath : null;

log(`Job ${job.id}: stored ${job.data.devices.length} device(s), paths: status=${!!job.data.statusReportPath}, analysis=${!!job.data.heatAnalysisPath}`);
```

**Total Lines Changed:** ~15 lines removed, ~15 lines added
**Net Change:** ~0 lines (similar size, more functionality)

---

## Appendix C: PGUI Download Implementation

### C.1 API Endpoint for File Downloads

The PGUI will need a new API endpoint to serve the generated report files:

**Location:** `pgui/src/pages/api/downloadReport.js` (new file)

**Purpose:** Securely serve device status reports and heat analysis workbooks

**Example Implementation:**
```javascript
import fs from 'fs';
import path from 'path';

export default async function handler(req, res) {
  const { filePath } = req.query;

  // Security: Validate file path is within allowed directories
  const allowedDirs = [
    path.join(process.env.NEXT_PUBLIC_PYTHON_SCRIPT_HCD_HOME, 'upload-results'),
    path.join(process.env.NEXT_PUBLIC_PYTHON_SCRIPT_HCD_HOME, 'test_done')
  ];

  const resolvedPath = path.resolve(filePath);
  const isAllowed = allowedDirs.some(dir => resolvedPath.startsWith(dir));

  if (!isAllowed) {
    return res.status(403).json({ error: 'Access denied' });
  }

  if (!fs.existsSync(resolvedPath)) {
    return res.status(404).json({ error: 'File not found' });
  }

  // Serve the file
  const filename = path.basename(resolvedPath);
  res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);

  const fileStream = fs.createReadStream(resolvedPath);
  fileStream.pipe(res);
}
```

### C.2 UI Component Updates

**Location:** `pgui/src/pages/esaver/index.js`

**Changes Needed:**

1. **Add Download Buttons in Job Monitor Table:**
   ```jsx
   // In the job row, add download links
   {job.data?.statusReportPath && (
     <a
       href={`/api/downloadReport?filePath=${encodeURIComponent(job.data.statusReportPath)}`}
       download
       className="text-blue-600 hover:underline mr-2"
     >
       📊 Status Report
     </a>
   )}
   {job.data?.heatAnalysisPath && (
     <a
       href={`/api/downloadReport?filePath=${encodeURIComponent(job.data.heatAnalysisPath)}`}
       download
       className="text-blue-600 hover:underline"
     >
       📈 Heat Analysis
     </a>
   )}
   ```

2. **Add Downloads Column to Table:**
   ```jsx
   <thead>
     <tr>
       <th>ID</th>
       <th>Status</th>
       <th>File</th>
       <th>Devices</th>
       <th>Summary Rows</th>
       <th>Downloads</th>  {/* NEW COLUMN */}
       <th>Data</th>
     </tr>
   </thead>
   ```

3. **Display Download Status:**
   ```jsx
   // Show availability of reports
   <td>
     {job.data?.statusReportPath ? '✅' : '⏳'} Status<br/>
     {job.data?.heatAnalysisPath ? '✅' : '⏳'} Analysis
   </td>
   ```

### C.3 User Experience Flow

**After Upload:**
1. User uploads file via PGUI
2. Job appears in Job Monitor with "Processing..." status
3. When complete, Download column shows available reports
4. User clicks "📊 Status Report" to download diagnostic info
5. User clicks "📈 Heat Analysis" to download multi-sheet workbook
6. Files download with original naming convention

**Benefits:**
- Immediate access to diagnostic reports
- No need to SSH into server
- Self-service troubleshooting
- Historical report access via Bull job retention

---

**End of Implementation Plan**
