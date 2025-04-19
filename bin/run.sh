#!/bin/bash
source ./source-venv.sh
# input file comes from dir: test
# output file written to dir: test_done
#python src/hcd.py Butterfly\ MCD\ 8167\ D2\ ORS80646fffb17e_2504141146.xlsx 
python src/hcd.py --input-file test/Butterfly\ MCD\ 8167\ P1\ ORSb0a732e61eba_2504141148.xlsx
