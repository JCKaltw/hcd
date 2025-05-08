#!/bin/bash
source ./source-venv.sh

IDIR="downloads"

for i in $IDIR/ORSb0a732e6229e_* $IDIR/ORS80646fffb17e_* $IDIR/ORSb0a732e50022_* $IDIR/ORSb0a732e61eba_*; do
   # output file written to dir: test_done
   echo "******** $i *********"
   echo "python src/hcd.py \\"
   echo "    --input-file \"$i\" \\"
   echo "    --insert-db \\"
   echo "    --upsert \\"
   echo "    --dry-run \\"
   echo "    --logging"

   python src/hcd.py \
      --input-file "$i" \
      --insert-db \
      --upsert \
      --logging

   echo "*********************"
done
