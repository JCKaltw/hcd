-- Fix-up script to normalize existing serial numbers in heating device tables
--
-- Purpose: Apply hex_upper() normalization to all existing serial numbers
--          to ensure consistency before the Python fix is deployed.
--
-- Rules:
--   - If serial has 0x or 0X prefix: normalize to lowercase 0x + uppercase hex
--   - If serial has NO prefix: just uppercase the hex digits
--
-- Example transformations:
--   b0a732e4da4a  -> B0A732E4DA4A  (no prefix)
--   0xb0a732e4da4a -> 0xB0A732E4DA4A  (with prefix)
--   0Xb0a732e4da4a -> 0xB0A732E4DA4A  (normalize prefix)
--
-- IMPORTANT: Run this in a transaction and verify before committing!

BEGIN;

-- Show current state before changes
SELECT 'BEFORE NORMALIZATION:' as status;
SELECT device_id, device_serial FROM heating_device ORDER BY device_id;

-- Create temporary function for normalization (PostgreSQL version)
CREATE OR REPLACE FUNCTION hex_upper(serial TEXT) RETURNS TEXT AS $$
BEGIN
    IF serial IS NULL OR serial = '' THEN
        RETURN serial;
    END IF;

    -- Check if serial starts with 0x or 0X
    IF lower(substring(serial from 1 for 2)) = '0x' THEN
        -- Has prefix: normalize to lowercase 0x + uppercase hex
        RETURN '0x' || upper(substring(serial from 3));
    ELSE
        -- No prefix: just uppercase the hex digits
        RETURN upper(serial);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Update heating_device table
UPDATE heating_device
SET device_serial = hex_upper(device_serial)
WHERE device_serial != hex_upper(device_serial);

-- Update heating_device_data table
UPDATE heating_device_data
SET device_serial = hex_upper(device_serial)
WHERE device_serial != hex_upper(device_serial);

-- Show results after normalization
SELECT 'AFTER NORMALIZATION:' as status;
SELECT device_id, device_serial FROM heating_device ORDER BY device_id;

-- Show count of affected rows
SELECT
    'heating_device' as table_name,
    COUNT(*) as total_rows,
    COUNT(CASE WHEN device_serial ~ '^[0-9A-F]+$' THEN 1 END) as uppercase_no_prefix,
    COUNT(CASE WHEN device_serial ~ '^0x[0-9A-F]+$' THEN 1 END) as normalized_with_prefix
FROM heating_device
UNION ALL
SELECT
    'heating_device_data' as table_name,
    COUNT(*) as total_rows,
    COUNT(CASE WHEN device_serial ~ '^[0-9A-F]+$' THEN 1 END) as uppercase_no_prefix,
    COUNT(CASE WHEN device_serial ~ '^0x[0-9A-F]+$' THEN 1 END) as normalized_with_prefix
FROM heating_device_data;

-- Drop the temporary function
DROP FUNCTION hex_upper(TEXT);

-- REVIEW THE OUTPUT ABOVE BEFORE COMMITTING!
-- If everything looks correct, run: COMMIT;
-- If something is wrong, run: ROLLBACK;

-- Uncomment one of these after review:
-- COMMIT;
-- ROLLBACK;
