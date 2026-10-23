import os
import re

lib_dir = r"D:\BuildDo\Buildto\apps\customer_app\lib"
all_dart_files = []
for root, dirs, files in os.walk(lib_dir):
    for f in files:
        if f.endswith('.dart'):
            all_dart_files.append(os.path.join(root, f))

print(f"Auditing all {len(all_dart_files)} Dart files...")

issues = []
for p in all_dart_files:
    with open(p, 'r', encoding='utf-8') as fp:
        c = fp.read()
    
    # Check delimiter balance
    curlies = c.count('{') - c.count('}')
    parens = c.count('(') - c.count(')')
    brackets = c.count('[') - c.count(']')
    
    if curlies != 0 or parens != 0 or brackets != 0:
        issues.append((os.path.relpath(p, lib_dir), f"Delimiter imbalance ({{}}: {curlies}, (): {parens}, []: {brackets})"))

print(f"Delimiter check completed. Issues found: {len(issues)}")
for f, iss in issues:
    print(f"  [ISSUE] {f}: {iss}")
