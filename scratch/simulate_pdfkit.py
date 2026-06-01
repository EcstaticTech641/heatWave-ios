import sys
import os
import pdfplumber

pdf_path = r"R:\aaron\programs\heatWave\heatWaveIOS\test\2026.04.28 - updated psych sheets.pdf"

with pdfplumber.open(pdf_path) as pdf:
    page = pdf.pages[2]
    width = page.width
    height = page.height
    
    left_bbox = (0, 0, width / 2, height)
    left_page = page.crop(left_bbox)
    words = left_page.extract_words()
    
    # 1. Sort words strictly by Y descending (in pdfplumber, top is ascending, so we sort by top ascending)
    rough_sorted = sorted(words, key=lambda w: (w['top'], w['x0']))
    
    # Let's simulate selections: suppose words close to each other are grouped by pdfplumber or PDFKit
    # Here we can just group words directly by visual line (top within 5 points)
    rows = []
    for w in words:
        # Find if there is an existing row with similar top
        matched = False
        for row in rows:
            if abs(row[0]['top'] - w['top']) < 5:
                row.append(w)
                matched = True
                break
        if not matched:
            rows.append([w])
            
    # Sort the rows by their average top (top-to-bottom)
    rows_sorted = sorted(rows, key=lambda row: sum(w['top'] for w in row)/len(row))
    
    # Sort each row left-to-right (by x0)
    final_lines = []
    for row in rows_sorted:
        row_sorted = sorted(row, key=lambda w: w['x0'])
        line_text = " ".join([w['text'] for w in row_sorted])
        final_lines.append(line_text)
        
    print("--- Corrected Grouping & Sorting Output ---")
    for line in final_lines[:25]:
        print(f"LINE: {line}")
