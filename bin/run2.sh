#!/bin/bash
source ./source-venv.sh

IDIR="downloads"

for i in $IDIR/ORSb0a732e4da4a_2510240835.rtu24.xlsx; do
   # output file written to dir: test_done
   echo "******** $i *********"
   echo "python src/hcd.py \\"
   echo "    --input-file \"$i\" \\"
   echo "    --insert-db \\"
   echo "    --upserts \\"
   echo "    --logging"

   python src/hcd.py \
      --input-file "$i" \
      --insert-db \
      --upserts \
      --logging

   echo "*********************"
done
