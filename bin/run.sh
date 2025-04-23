#!/bin/bash
source ./source-venv.sh

for i in ORSb0a732e6229e_2504191244 ORS80646fffb17e_2504191246 ORSb0a732e50022_2504191247 ORSb0a732e61eba_2504191248; do
   # output file written to dir: test_done
   echo "******** $i *********"
   python src/hcd.py --input-file "downloads/${i}.xlsx" --insert-db --upsert
   echo "*********************"
done
