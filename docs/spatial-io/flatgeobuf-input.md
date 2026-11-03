# FlatGeobuf path input

`segment_graph(<FlatGeobuf path>)` builds a segment graph directly from a FlatGeobuf file, using the same graph builder as
GeoParquet input. The axial route is described in [axial file input](axial-file-input.md).

## 1. Public API and format detection

```r
segment_graph(x)    # x: numeric matrix | sf/sfc | ONE character path to a GeoParquet OR FlatGeobuf file
```

The file format is identified from the file content only, never from the extension:

1. The first four bytes are `PAR1`: GeoParquet (the trailing `PAR1` is then required; see [GeoParquet input](geoparquet-input.md)).
2. Otherwise the first seven bytes are `66 67 62 03 66 67 62` (any eighth, patch-level byte): FlatGeobuf major version 3.
3. Otherwise the FlatGeobuf marker with another major version gives an "unsupported major version" error.
4. Otherwise the error is "unsupported file format".

A FlatGeobuf file whose last bytes happen to be `PAR1` is still read as FlatGeobuf. The path must be a single non-empty string
naming an existing, readable, regular local file. The returned object is the ordinary `pst_segment_graph`. `sf` is required (for
CRS parsing); `arrow` and `jsonlite` are not needed. No identifiers or attributes are read or retained.

## 2. File contract

| Item | Behaviour |
| --- | --- |
| Geometry | header `geometry_type` Unknown or LineString; every feature a non-null, single-part LineString with exactly two finite XY vertices; Z, M, T or TM in the header or a feature is rejected. Polylines are never split |
| Row order | physical file order; an indexed FlatGeobuf is Hilbert-ordered and the order of the writer is not recoverable |
| `features_count` | 0 means unknown; otherwise it must equal the decoded count exactly |
| Index | `index_node_size` 16 (default) or 0 (none); the index must fit inside the file |
| Empty file | rejected (0 features) |
| Big-endian host | rejected |

## 3. Parser and bounds

The file is parsed with the FlatBuffers 24.12.23 verifier and the FlatGeobuf-generated headers, vendored unmodified (see
`src/vendor/flatbuffers/PROVENANCE.md` and `src/vendor/flatgeobuf/PROVENANCE.md`). The file is treated as untrusted. It is read
record by record, one record in memory at a time. The header and each feature record are limited to 64 MiB, and each size prefix
must fit in the remaining bytes. Malformed or truncated input fails with an error and publishes no graph. The header is
checked again between inspection and decoding.

## 4. CRS

Only GDAL's exact representation of an unknown CRS maps to `sf::st_crs(NA)`: no organisation, code absent or 0, name
`Undefined Cartesian SRS with unknown unit`, GDAL's engineering-CRS WKT, and no description or code string. An absent `Crs` table
also gives `NA`. Anything else is interpreted by `sf` (the EPSG code first, as GDAL does, then the WKT). A projected CRS is
retained unchanged; a geographic or uninterpretable CRS is rejected.

## 5. Memory

PST retains the constructed graph in memory. FlatGeobuf records are decoded individually rather than loading the entire source file into an R object.

## 6. Not supported

External identifiers or attributes, spatial filtering, Z/M coordinates, multi-part geometry or splitting, directories, remote
paths, big-endian hosts, `format=` or `geometry=` arguments, snapping, reprojection and CRS override.
