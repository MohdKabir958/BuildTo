#!/usr/bin/env python3
"""Static hygiene checker only; real Prisma + PG validation runs in Actions."""
import re, pathlib, sys
s = (pathlib.Path(__file__).parents[1]/'prisma/schema.prisma').read_text()
models = dict((name, body) for name, body in re.findall(r'^model\s+(\w+)\s*\{(.*?)^\}', s, re.M | re.S))
enums = set(re.findall(r'^enum\s+(\w+)\s*\{', s,re.M))
primitives={'String','Boolean','Int','BigInt','Float','Decimal','DateTime','Json','Bytes','Unsupported'}
errors=[]; rows={}
for m,body in models.items():
    fields=[]
    for line in body.splitlines():
        line=line.strip()
        if not line or line.startswith('//') or line.startswith('@@'):continue
        match=re.match(r'^(\w+)\s+([\w?\[\]]+)',line)
        if not match:continue
        fields.append((match.group(1),match.group(2),line))
        typ=match.group(2).removesuffix('?').removesuffix('[]')
        if typ not in models and typ not in enums and typ not in primitives:
            errors.append(f'{m}.{match.group(1)} has unknown type {typ}')
    rows[m]=fields
for name,fields in rows.items():
    for field,typ,source in fields:
        t=typ.removesuffix('?').removesuffix('[]')
        if t not in models: continue
        if not any(x.removesuffix('?').removesuffix('[]')==name for _,x,_ in rows[t]):
            errors.append(f'{name}.{field}: missing opposite relationship on {t}')
for name,fields in rows.items():
    fieldnames={x[0] for x in fields}
    for field,typ,source in fields:
        m=re.search(r'@relation\(fields:\s*\[([^\]]+)\],\s*references:',source)
        if m:
            for f in m.group(1).split(','):
                if f.strip() not in fieldnames:errors.append(f'{name}.{field}: field in relation not defined: {f}')
print(f'{len(models)} models; {len(enums)} enums; {sum(len(v) for v in rows.values())} fields; {len(errors)} static errors')
for e in errors:print('ERROR',e)
sys.exit(1 if errors else 0)
