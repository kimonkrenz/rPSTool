# FlatGeobuf test fixtures

Tiny files written by GDAL's FlatGeobuf driver (GDAL 3.13.3 via sf / ogr2ogr) by
`tools/make-flatgeobuf-fixtures.R`, plus `patched-*` byte patches of `lattice-utm-noindex.fgb` (declared
count; non-finite first coordinate) and `no-crs-table.fgb` (written from a CSV with no SRS). `SHA256SUMS` records their
hashes. The tests also derive malformed variants in memory by byte patching; no fixture contains third-party data.
