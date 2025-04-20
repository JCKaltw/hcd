#!/bin/sh
python3 -m venv env
source env/bin/activate
pip install --upgrade pip
pip install pandas openpyxl matplotlib numpy psycopg2-binary
