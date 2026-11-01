"""Development-only generator for the tiny GeoParquet test fixtures.

NOT part of the package and never run by it or by the tests: Python/pyarrow is a development
tool here. The committed outputs under
tests/testthat/fixtures/geoparquet/ are what the tests use. Regenerate with:

    python3 tools/make-geoparquet-fixtures.py tests/testthat/fixtures/geoparquet

Authority: pyarrow writes plain Parquet files whose `geo` key/value metadata follows the
GeoParquet 1.1.0 specification (https://github.com/opengeospatial/geoparquet, tag v1.1.0). The
three *.projjson CRS texts are produced by sf::st_as_text(<crs>, projjson = TRUE) and are only
read here. Parquet bytes embed the writer version, so tests compare decoded content, not
file hashes; MANIFEST.tsv records the hashes of the committed files for provenance.
"""
import hashlib, json, os, struct, sys
import pyarrow as pa
import pyarrow.parquet as pq

OUT = sys.argv[1]
N_SIDE = 4


def lattice():
    """4 x 4 node lattice, 100 m spacing: 24 endpoint-connected segments in a fixed shuffled
    order, every third one reversed. Integer-valued coordinates (exact in binary64)."""
    segs = []
    for j in range(N_SIDE):
        for i in range(N_SIDE):
            x, y = 500000 + 100 * i, 6000000 + 100 * j
            if i + 1 < N_SIDE:
                segs.append((x, y, x + 100, y))
            if j + 1 < N_SIDE:
                segs.append((x, y, x, y + 100))
    order = sorted(range(len(segs)), key=lambda k: (k * 7 + 3) % 31)  # deterministic shuffle
    out = []
    for position, k in enumerate(order):
        x1, y1, x2, y2 = segs[k]
        out.append((x2, y2, x1, y1) if position % 3 == 1 else (x1, y1, x2, y2))
    return out


def wkb(coords, endian="<", gtype=2, npoints=2):
    bo = b"\x01" if endian == "<" else b"\x00"
    return bo + struct.pack(endian + "II", gtype, npoints) + struct.pack(endian + "%dd" % len(coords), *coords)


def line(c, big):
    return wkb(c, ">" if big else "<")


def geometries(rows, phase):
    return [line(c, (k + phase) % 3 == 2) for k, c in enumerate(rows)]


def read(name):
    with open(os.path.join(OUT, name)) as f:
        return json.loads(f.read())


UTM = read("utm30n.projjson")
CRS84 = read("crs84.projjson")
EPSG4326 = read("epsg4326.projjson")
ROWS = lattice()
GEOM = geometries(ROWS, 0)
manifest = []


def geo(version="1.1.0", primary="geometry", columns=None, **extra):
    meta = {"version": version, "primary_column": primary,
            "columns": columns if columns is not None else {"geometry": {"encoding": "WKB", "geometry_types": ["LineString"]}}}
    meta.update(extra)
    return meta


def column(**kw):
    c = {"encoding": "WKB", "geometry_types": ["LineString"]}
    c.update(kw)
    return c


def write(name, geometry_arrays, metadata=None, raw_metadata=None, row_group=7, compression="snappy",
          names=("geometry",), large=False, rows=len(ROWS)):
    typ = pa.large_binary() if large else pa.binary()
    cols = [pa.array([(k * 40009) % 1009 + 10 ** 12 for k in range(rows)], pa.int64())]
    fields = [("feature_id", pa.int64())]
    for nm, values in zip(names, geometry_arrays):
        cols.append(pa.array(values, typ))
        fields.append((nm, typ))
    cols.append(pa.array(["name%d" % k for k in range(rows)]))
    fields.append(("name", pa.string()))
    md = {}
    if raw_metadata is not None:
        md["geo"] = raw_metadata
    elif metadata is not None:
        md["geo"] = json.dumps(metadata)
    table = pa.Table.from_arrays(cols, schema=pa.schema(fields, metadata=md or None))
    pq.write_table(table, os.path.join(OUT, name), row_group_size=row_group, compression=compression)
    with open(os.path.join(OUT, name), "rb") as f:
        manifest.append((name, hashlib.sha256(f.read()).hexdigest()))


# Valid files.
write("lattice-binary.parquet", [GEOM], geo(columns={"geometry": column(crs=UTM, edges="planar")}))
write("lattice-large-binary.parquet", [geometries(ROWS, 1)], geo(columns={"geometry": column(crs=None)}),
      large=True, row_group=len(ROWS), compression="zstd")
write("lattice-two-geoms.parquet",
      [[line([c[0] + 1e6, c[1], c[2] + 1e6, c[3]], False) for c in ROWS], geometries(ROWS, 2)],
      geo(primary="network", columns={"decoy": column(crs=None), "network": column(crs=None)}),
      names=("decoy", "network"))
write("lattice-planar-null-crs.parquet", [GEOM], geo(version="1.0.0", columns={"geometry": column(crs=None, edges="planar")}))
write("lattice-multi-batch.parquet", [GEOM], geo(columns={"geometry": column(crs=None)}), row_group=5)
# Metadata the route must reject.
write("lattice-crs-absent.parquet", [GEOM], geo(columns={"geometry": column()}))
write("lattice-geographic-crs84.parquet", [GEOM], geo(columns={"geometry": column(crs=CRS84)}))
write("lattice-geographic-4326.parquet", [GEOM], geo(columns={"geometry": column(crs=EPSG4326)}))
write("lattice-invalid-crs.parquet", [GEOM], geo(columns={"geometry": column(crs={"type": "NotACrs"})}))
write("lattice-spherical.parquet", [GEOM], geo(columns={"geometry": column(crs=None, edges="spherical")}))
write("lattice-no-geo.parquet", [GEOM])
write("lattice-bad-json.parquet", [GEOM], raw_metadata="{not json")
write("lattice-missing-primary.parquet", [GEOM], {"version": "1.1.0", "columns": {"geometry": column(crs=None)}})
write("lattice-bad-primary.parquet", [GEOM], geo(primary="nope", columns={"geometry": column(crs=None)}))
write("lattice-primary-not-in-file.parquet", [GEOM], geo(primary="ghost", columns={"ghost": column(crs=None)}))
write("lattice-encoding-point.parquet", [GEOM], geo(columns={"geometry": {"encoding": "point", "geometry_types": ["Point"], "crs": None}}))
write("lattice-version-2.parquet", [GEOM], geo(version="2.0.0", columns={"geometry": column(crs=None)}))
write("empty.parquet", [[]], geo(columns={"geometry": column(crs=None)}), rows=0)
# Geometry the decoder must reject, each naming its one-based row.
def with_row(k, value):
    g = list(GEOM)
    g[k] = value
    return g
write("bad-multilinestring.parquet", [with_row(4, b"\x01" + struct.pack("<II", 5, 1) + line(ROWS[4], False))],
      geo(columns={"geometry": column(crs=None)}))
write("bad-null-geometry.parquet", [with_row(2, None)], geo(columns={"geometry": column(crs=None)}))
write("bad-polyline.parquet", [with_row(3, wkb(list(ROWS[3]) + [0.0, 0.0], npoints=3))], geo(columns={"geometry": column(crs=None)}))
write("bad-iso-z.parquet", [with_row(1, wkb(list(ROWS[1][:2]) + [0.0] + list(ROWS[1][2:]) + [0.0], gtype=1002))],
      geo(columns={"geometry": column(crs=None)}))
write("bad-nan.parquet", [with_row(5, wkb([float("nan"), 1.0, 2.0, 3.0]))], geo(columns={"geometry": column(crs=None)}))

with open(os.path.join(OUT, "expected-lattice.csv"), "w") as f:
    f.write("x1,y1,x2,y2\n")
    for r in ROWS:
        f.write("%d,%d,%d,%d\n" % r)
with open(os.path.join(OUT, "MANIFEST.tsv"), "w") as f:
    f.write("# pyarrow %s; GeoParquet metadata per v1.1.0; regenerate with tools/make-geoparquet-fixtures.py\n" % pa.__version__)
    f.write("file\tsha256\n")
    for name, digest in sorted(manifest):
        f.write("%s\t%s\n" % (name, digest))
print("wrote", len(manifest), "fixtures")
