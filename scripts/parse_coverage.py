#!/usr/bin/env python3
"""Parse lcov.info and calculate coverage statistics."""

import re
import sys

def parse_lcov(filepath):
    """Parse lcov.info file and return coverage statistics."""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    files = []
    total_lines = 0
    hit_lines = 0
    
    # Split by end_of_record
    records = re.split(r'^end_of_record', content, flags=re.MULTILINE)
    
    for record in records:
        sf_match = re.search(r'^SF:(.+)$', record, re.MULTILINE)
        lf_match = re.search(r'^LF:(\d+)$', record, re.MULTILINE)
        lh_match = re.search(r'^LH:(\d+)$', record, re.MULTILINE)
        
        if sf_match and lf_match and lh_match:
            filepath = sf_match.group(1)
            total = int(lf_match.group(1))
            hit = int(lh_match.group(1))
            coverage = round((hit / total * 100), 1) if total > 0 else 0
            
            files.append({
                'file': filepath,
                'total': total,
                'hit': hit,
                'coverage': coverage
            })
            
            total_lines += total
            hit_lines += hit
    
    overall_coverage = round((hit_lines / total_lines * 100), 1) if total_lines > 0 else 0
    
    return {
        'files': sorted(files, key=lambda x: x['coverage']),
        'overall': {
            'total': total_lines,
            'hit': hit_lines,
            'coverage': overall_coverage
        }
    }

if __name__ == '__main__':
    stats = parse_lcov('coverage/lcov.info')
    
    print(f"Overall Coverage: {stats['overall']['coverage']}%")
    print(f"Total Lines: {stats['overall']['total']}")
    print(f"Hit Lines: {stats['overall']['hit']}")
    print("\nFile Coverage:")
    for file in stats['files']:
        print(f"  {file['file']}: {file['coverage']}% ({file['hit']}/{file['total']} lines)")

