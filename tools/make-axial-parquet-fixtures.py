"""Development-only generator (never run by the package or its tests) for the tiny GeoParquet fixtures behind
axial_graph(<path>). Regenerate with (pyarrow 26.0.0):

    python3 tools/make-axial-parquet-fixtures.py tests/testthat/fixtures/axial-files

Reads tests/testthat/fixtures/axial-files/lines.csv (written by tools/make-axial-file-fixtures.R from the direct
pinned-PST axial reference cases) and writes one GeoParquet 1.1.0 file per case with a WKB `geometry` column in the
CSV row order and the UTM 30N PROJJSON CRS of the segment-graph GeoParquet fixtures. Parquet bytes embed the writer version, so the
tests compare decoded content; MANIFEST.tsv records the committed hashes for provenance only.
"""
import csv, hashlib, json, os, struct, sys
import pyarrow as pa
import pyarrow.parquet as pq

OUT = sys.argv[1]
with open("tests/testthat/fixtures/geoparquet/utm30n.projjson") as f:
    UTM = json.loads(f.read())
cases = {}
with open(os.path.join(OUT, "lines.csv"), newline="") as f:
    for r in csv.DictReader(f):
        cases.setdefault(r["case"], []).append([float(r[k]) for k in ("x1", "y1", "x2", "y2")])

def wkb(c):
    return b"\x01" + struct.pack("<II", 2, 2) + struct.pack("<4d", *c)

manifest = []
for name, rows in cases.items():
    if name == "order-indexed":
        continue  # a spatial-index property of the FlatGeobuf file only
    meta = {"version": "1.1.0", "primary_column": "geometry",
            "columns": {"geometry": {"encoding": "WKB", "geometry_types": ["LineString"], "crs": UTM, "edges": "planar"}}}
    schema = pa.schema([("id", pa.int64()), ("geometry", pa.binary())], metadata={"geo": json.dumps(meta)})
    table = pa.Table.from_arrays([pa.array(range(1, len(rows) + 1), pa.int64()), pa.array([wkb(c) for c in rows], pa.binary())], schema=schema)
    path = os.path.join(OUT, name + ".parquet")
    pq.write_table(table, path, compression="snappy")
    with open(path, "rb") as g:
        manifest.append((os.path.basename(path), hashlib.sha256(g.read()).hexdigest()))
for name in sorted(os.listdir(OUT)):
    if name.endswith(".fgb"):
        with open(os.path.join(OUT, name), "rb") as g:
            manifest.append((name, hashlib.sha256(g.read()).hexdigest()))
manifest.append(("lines.csv", hashlib.sha256(open(os.path.join(OUT, "lines.csv"), "rb").read()).hexdigest()))
with open(os.path.join(OUT, "MANIFEST.tsv"), "w") as f:
    f.write("file\tsha256\n")
    for n, h in sorted(manifest):
        f.write("%s\t%s\n" % (n, h))
