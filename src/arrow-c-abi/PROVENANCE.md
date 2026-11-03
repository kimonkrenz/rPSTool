# Provenance of `arrow_c_abi.h`

`arrow_c_abi.h` carries the Arrow C data/stream interface **declarations** needed by the
GeoParquet decoder (`src/pst-geoparquet.cpp`) to consume an `ArrowArrayStream` produced by
the optional R `arrow` package. rPSTool does not link libarrow and does not include any Arrow
implementation, runtime, device, async or statistics code (see
[GeoParquet input](../../docs/spatial-io/geoparquet-input.md)).

- Upstream repository: `apache/arrow`
- Release tag: `apache-arrow-25.0.0`
- Source path: `cpp/src/arrow/c/abi.h`
- Source SHA-256: `1828f1ce60368cd590d19595910fa19db09b30728f8a43b5f89933623f7a7276` (20 318 bytes; the same bytes as at the `apache-arrow-25.0.1` tag)
- Licence of the source: Apache-2.0 (the file's original licence header is kept verbatim as the first sixteen lines of the wrapper)
- Wrapper header SHA-256: `427ed4eedbefab6991528ccdf876d94b34dca05138e3a27b37596aac741a23c6`
- Wrapper header MD5: `096a3e41b2f3b93fa73479b9ce9a2456`

## Extraction method

The wrapper is an **extraction of selected verbatim declarations** from the fixed upstream
release, not a byte-identical copy of the complete upstream `abi.h`. It consists of, in
order, these upstream line ranges: 1-16 (licence header), 33-35 (`#pragma once`,
`<stdint.h>`), 38-45 (`extern "C"` opening and the `ARROW_C_DATA_INTERFACE` guard), 49-81
(`struct ArrowSchema`, `struct ArrowArray`), 100-101 (guard close), 158-197 (the
`ARROW_C_STREAM_INTERFACE` guard and `struct ArrowArrayStream`) and 458-460 (`extern "C"`
close), with an rPSTool explanatory comment block inserted before `#pragma once`.

Deliberately omitted: the `ARROW_FLAG_*` constants (the decoder never reads `flags`), the
`ARROW_STATISTICS_KEY_*` macros, the device data/stream interfaces and the async interface.
The canonical guards `ARROW_C_DATA_INTERFACE` and `ARROW_C_STREAM_INTERFACE` are preserved
exactly.

## Attribution and notices

The declarations are © The Apache Software Foundation, licensed under the Apache License,
Version 2.0 (<http://www.apache.org/licenses/LICENSE-2.0>). Apache Arrow's `NOTICE.txt`
("Apache Arrow, Copyright 2016-2026 The Apache Software Foundation") lists third-party notices
that concern Arrow's implementation, none of which is carried here. Component licence
matrix: [licensing](../../docs/licensing.md).

## Verification

`Rscript tools/verify-arrow-abi.R` (part of `tools/ci/check-local.R`) checks, offline and
fail-closed: the licence header; that exactly the three structs and the two canonical guards
are present with no other macro, include or type; and the wrapper's SHA-256 and MD5 above.
`tools/test-arrow-abi.R` proves the verifier rejects each kind of drift. With
`RPST_ARROW_ABI_UPSTREAM=<path to the pristine abi.h>` the verifier additionally checks the
source SHA-256 above and that every declaration line of the wrapper occurs, in order, in that
file.
