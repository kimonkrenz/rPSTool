#!/usr/bin/env python3
"""Convert independently generated native JSON to an offline R fixture."""
import json, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'common'))
from rnumeric import r_number  # exact R numeric literals (development-only helper)
def value(x):
    if isinstance(x,str) and x in ['NaN','Inf','-Inf']:return x
    if isinstance(x,str):return json.dumps(x)
    return r_number(float(x))
def vec(x):return 'c('+','.join(value(v) for v in x)+')' if x else 'numeric()'
def matrix(x,columns):
    return 'structure('+vec([row[c] for c in range(columns) for row in x])+',dim=c('+str(len(x))+'L,'+str(columns)+'L))'
def nested(groups):
    return 'list('+','.join('list('+','.join('list('+','.join(matrix(ring,2) for ring in poly)+')' for poly in group)+')' for group in groups)+')'
cases=json.loads(pathlib.Path(sys.argv[1]).read_text())
lines=['# Direct pinned PST v3.3.2 exported C API. Do not edit expected values.',
       '# Authority: pinned formula with explicitly authorised std::abs(float) only.',
       '# Regenerate with tools/reference/raster/native-cases.py and tools/reference/raster/write-r-fixture.py.',
       'raster_direct_fixture <- list(']
for case in cases:
    args=[]
    for k,v in case['args'].items():
        args.append(k+'='+ (matrix(v,4) if k in ['x','y'] else vec(v) if isinstance(v,list) else value(v)))
    e=case['expected']
    fields=['bbox='+vec(e['bbox']),'dimensions='+vec([e['width'],e['height']]),
            'pitch='+value(e['pitch']),'format='+value(e['format']),
            'min='+value(e['min']),'max='+value(e['max']),
            'values='+matrix(e['values'],e['width'])]
    lines.append('list(name='+value(case['name'])+',args=list('+','.join(args)+'),ranges='+matrix(case['ranges'],2)+
                 ',expected=list('+','.join(fields)+'),polygons='+nested(e['polygons'])+'),')
lines[-1]=lines[-1].rstrip(',')
lines.append(')')
pathlib.Path(sys.argv[2]).write_text('\n'.join(lines)+'\n')
