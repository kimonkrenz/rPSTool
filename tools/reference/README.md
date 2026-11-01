# Direct PST reference tools

These development-only tools execute pinned PST exports and official ctypes
wrappers. They do not invoke rPSTool R analyses or implement replacement algorithms.
Installed tests consume frozen R fixtures offline; Python, a separate reference
checkout and native diagnostic modules are not runtime dependencies.

## Categories and naming

| Purpose | Naming and inputs | Outputs / role |
| --- | --- | --- |
| Native reference generation | `generate-reference.py PINNED_ROOT LIBR_PATH PST_DLL OUTPUT` | Source-verified direct-C-API fixture (R, except construction JSON) and unchanged upstream tests |
| Native case runners | `native-cases.py PINNED_ROOT LIBR_PATH PST_DLL [OUTPUT_JSON]` | Isovist emits JSON on stdout; raster writes JSON to its required fourth argument; child isolation contains unsafe original-source cases |
| Focused checks | `check-*.py`, signatures in each tool's docstring | Write-mask evidence, worker exceptions, allocation/bounds hazards, safety/overload comparisons; fail on an unexpected result |
| Diagnostic builds | `isovist/build-safety-variants.py BASELINE_DLL WORK_DIR` | Qualified pristine, assertion-enabled and adapted locally bound modules; source hashes on stdout |
| Fixture serialization | `write-r-fixture.{R,py} INPUT_JSON OUTPUT_R` | Deterministic checked-in R fixture representation; no recalculation |
| Source manifests | `source-blobs.json` | Frozen exact pin/blob authority, checked before native loading |
| Evidence payloads | `*-results.json` | Frozen observations recorded when the corresponding hazard or policy was established; some inventories are smaller than today's case runner |

Each domain keeps its related dependencies together:

| Domain | Tools and evidence |
| --- | --- |
| `core-network/` | Core analyses, 13 upstream tests and supplemental direct fixture |
| `reach-betweenness/` | Point Reach, weighted/attraction Betweenness; `check-output-writes.py` proves paired unwritten diagnostics; generator emits 147 cases |
| `segment-groups/` | Grouping/group Integration, write-mask checks and frozen output-write evidence; generator emits 28 grouping and 280 Integration cases |
| `axial/` | Indexed/unlink/point/polygon/junction fixtures; `axial-point-state.cpp` is a development structural accessor compiled by the generator |
| `attractions/` | Reach/Distance fixtures, unwritten group-distance evidence and worker safety checks |
| `angular/` | Angular settings/normalizers and worker safety checks; `generate-multi-radius-reference.py PINNED_ROOT LIBR_PATH PST_DLL OUTPUT` emits the multi-radius families fixture (`angular-multi-radius-direct-v3.3.2.R`, same blob verification as `generate-reference.py`, deterministic) |
| `od-betweenness/` | OD fixtures and native safety/failure checks |
| `network-construction/` | Junction/segment-map JSON generation, R serializer, native hazard and cycle-guard checks; source manifest, original/guarded evidence |
| `isovist/` | Context/result cases, module builds/comparison, full-circle bounds trace, R serializer; frozen initial/cardinality/full-circle evidence |
| `raster/` | Comparison/data/polygon cases, floating normalization proof, original abs-overload and native safety checks, R serializer; frozen reports and manifest |

## Reproduction setup

Run the complete [validation policy](../ci/README.md) first:

```sh
Rscript tools/ci/check-local.R
```

Set `PINNED_ROOT` to a read-only full checkout/archive of PST commit
`63df80a2cf3dd289be95ea3d91667c3490719b75`, including its Python wrappers and tests.
Set `LIBR_PATH` to the toolchain's `libR` library and `PST_DLL` to the freshly
validated rPSTool shared library. Native exports are loaded directly from that DLL.
Use a worker cap and ensure the dynamic loader can find libR. On GNU/Linux:

```sh
export RPST_NUM_THREADS=2
export PYTHONDONTWRITEBYTECODE=1
export PYTHONWARNINGS=ignore::SyntaxWarning
export LD_LIBRARY_PATH="$(dirname "$LIBR_PATH"):${LD_LIBRARY_PATH:-}"
mkdir -p work/reference
python3 tools/reference/core-network/generate-reference.py "$PINNED_ROOT" "$LIBR_PATH" "$PST_DLL" work/reference/core.R
Rscript -e 'stopifnot(identical(dget("tests/testthat/fixtures/core-network-direct-v3.3.2.R"), dget("work/reference/core.R")))'
```

The core generator uses a different final closing-line layout from the committed
fixture; the parsed R reference is identical.

The pinned ctypes wrapper contains a Python invalid-escape SyntaxWarning. The
reference-only warning filter above prevents that interpreter diagnostic from
entering captured evidence/fixture stderr; it changes no native result or R
validation gate. It also keeps the read-only reference checkout free of bytecode.

Repeat the same signature for the other `generate-reference.py` tools and compare
their outputs with the corresponding frozen fixture under `tests/testthat/fixtures/`.
Construction writes JSON first, then
`Rscript tools/reference/network-construction/write-r-fixture.R INPUT_JSON OUTPUT_R`.
The Reach/Betweenness and segment-group generators run their output-write checks
internally. Attraction's unwritten-output check has the generator
signature and writes its result to `OUTPUT`.

Worker/safety checks in attractions, angular and OD use
`PINNED_ROOT LIBR_PATH PST_DLL`; their locally bound modules go under domain-specific
`work/` directories. GNU/Linux diagnostic builders require GCC and Linux linking
flags; portable generated-source checks remain part of the full R validation
suite on all supported platforms. Never build inside the upstream checkout.

## Geometry and numerical-policy reproduction

For network hazards, build a locally bound pristine `CreateSegmentMap.cpp` module
against the validated DLL, using the package compatibility headers and
`-Wl,-Bsymbolic`. Pass it to `check-native-hazards.py`; expected crashes run only
in child processes. Build the guarded variant (the verified build copy of patch 0008) separately
and pass it to `check-cycle-guard.py`. This preserves successful native controls
and confirms controlled failure for the three original cycle hazards. Empty
junction-layer unwritten outputs are original native evidence; R rejects that
combination before calling PST.

For isovists, keep `BASELINE_DLL` and `WORK_DIR` inside this repository:

```sh
python3 tools/reference/isovist/build-safety-variants.py "$PST_DLL" work/reference/isovist
python3 tools/reference/isovist/native-cases.py "$PINNED_ROOT" "$LIBR_PATH" work/reference/isovist/baseline.so > work/reference/isovist/baseline.json
python3 tools/reference/isovist/native-cases.py "$PINNED_ROOT" "$LIBR_PATH" work/reference/isovist/checked.so > work/reference/isovist/checked.json
python3 tools/reference/isovist/native-cases.py "$PINNED_ROOT" "$LIBR_PATH" work/reference/isovist/guarded.so > work/reference/isovist/guarded.json
python3 tools/reference/isovist/check-safety-variants.py work/reference/isovist/baseline.json work/reference/isovist/checked.json work/reference/isovist/guarded.json
Rscript tools/reference/isovist/write-r-fixture.R work/reference/isovist/baseline.json work/reference/isovist/fixture.R
python3 tools/reference/isovist/check-full-circle-bounds.py "$PINNED_ROOT" "$LIBR_PATH" "$PST_DLL" work/reference/isovist-bounds
```

The full-circle trace intentionally demonstrates a pinned out-of-bounds access;
use the baseline/guarded comparison for the current safe contract. The R fixture
serializer uses hexadecimal numbers to retain exact native double bits.

Raster numerical policy selects floating absolute values only for normalized
extrema. Genuine zero denominators remain native floating arithmetic; Relative
Percent is unchanged. `BASELINE_DLL` provides pinned dependencies, not R scoring:

```sh
python3 tools/reference/raster/check-floating-normalization.py "$PINNED_ROOT" "$LIBR_PATH" "$BASELINE_DLL" "$PST_DLL" work/reference/raster
python3 tools/reference/raster/write-r-fixture.py work/reference/raster/approved.json work/reference/raster/fixture.R
python3 tools/reference/raster/check-abs-overloads.py "$PINNED_ROOT" "$LIBR_PATH" "$BASELINE_DLL" work/reference/raster-overloads
python3 tools/reference/raster/check-native-safety.py "$PINNED_ROOT" "$LIBR_PATH" "$PST_DLL" work/reference/raster-safety
```

The floating proof compares 79 exact cases across independent math-header,
narrow `std::abs`, sanitizer and package-export builds; all 41 Relative Percent
controls remain identical. The abs-overload check uses the original 75-case
inventory and retains unsafe integer-conversion evidence. `raster/native-cases.py`
can also run a supplied DLL independently.

## Exact numeric serialization of direct fixtures

Every generated direct fixture (`tests/testthat/fixtures/*-direct-v3.3.2.R`) stores its numbers
exactly. R's decimal parser is not correctly rounded where `long double` is only binary64 (for
example Apple Silicon): `-9.536743128535363e-08` parses one ULP away and `3.4028234663852886e+38`
parses above `FLT_MAX`, which corrupts both expected outputs and inputs. Fixtures therefore use
hexadecimal numeric literals, never non-integer decimals.

* `common/rnumeric.py` is the shared development-only helper used by the Python generators and the
  raster serializer: finite floats are `float.hex()`, non-finites are `NaN`/`Inf`/`-Inf`, integers up
  to 2**53 are decimal digits, larger integers must be exactly representable (hex) or are rejected.
  The construction and isovist R serializers use `dput(..., control = c(..., "hexNumeric"))`.
* `common/test_rnumeric.py` round-trips Python values through `Rscript` and compares raw binary64
  bits (known Mac parser failures, signed zero, non-finites, `DBL_MAX`, subnormals, 8000 random
  values). Run `python3 tools/reference/common/test_rnumeric.py` on every platform whose R parser
  matters; it is not part of the installed package.
* `common/hexify-fixture.py INPUT_R OUTPUT_R` converts an existing generated fixture's decimal
  numerics to hex without changing any value (each token verified). It is not an R parser: it
  accepts only what the generators emit (`#` comments and double-quoted strings are skipped) and
  raises `ValueError` on single-quoted strings, backtick names, raw strings and unterminated strings;
  `common/test_hexify_fixture.py` covers this, including every current direct fixture. It was used to convert the committed `core-network` and `angular-controls` values before the
  floating-point policy; those fixtures (and the other float-sensitive ones) have since been
  regenerated under [the policy](../../docs/compatibility/floating-point-policy.md).
* `tests/testthat/test-fixture-serialization.R` fails if a generated direct fixture contains a
  non-integer decimal literal or a digit-only integer above 2**53 (integers up to and including 2**53
  are exact, matching `rnumeric.py`; the boundary is covered by mutation tests). Hand-written test numerics and the hand-transcribed
  `network-integration`/`angular-integration` upstream constants are out of its scope.

Because layout is otherwise unchanged, regeneration of the other fixtures reproduces the committed
files byte-for-byte; the committed `network-construction` fixture previously used `dput`'s default
15 significant digits, so four native values there are now stored with their exact binary64 value.

## Evidence payloads

The frozen `*-results.json` files are the recorded outputs of the focused checks; each backs a policy or guard documented in
`docs/compatibility/` and `inst/upstream/PATCHES.md`:

| File | Produced by | Backs |
| --- | --- | --- |
| `attractions/unwritten-group-distance-results.json` | `check-unwritten-group-distance.py` | rejection of straight-only Attraction Distance with point-group origins |
| `segment-groups/output-write-results.json` | `check-output-writes.py` | paired write mask and typed-NA policy for Group Integration |
| `network-construction/native-hazard-results.json`, `cycle-guard-results.json` | `check-native-hazards.py`, `check-cycle-guard.py` | empty-layer rejection and the cycle guard (patch 0008) |
| `isovist/baseline-results.json`, `cardinality-results.json`, `full-circle-results.json`, `guard-results.json` | `native-cases.py`, `check-full-circle-bounds.py`, `check-safety-variants.py` | the state-dependent cardinality guards (patch 0009) |
| `raster/abs-overload-results.json`, `floating-normalization-results.json` | `check-abs-overloads.py`, `check-floating-normalization.py` | the floating absolute-value contract (patch 0010) |

## Fixture provenance

Every generated fixture records, in its header comment, the generator that wrote it and the pinned PST source blobs it was verified
against. Frozen `*-results.json` observations keep their original inventories and diagnostic payloads. Numbered adopted patches, build
inputs, warning inventories, upstream pins and vendor bytes are recorded in `inst/upstream/`.

## Regenerating under the floating-point policy

Generators load the freshly built package library, so run them against a library installed from the
current tree (`-ffp-contract=off` and `rpst-float-overloads.h` apply automatically). The isovist
baseline/diagnostic modules built by `isovist/build-safety-variants.py` pass `-ffp-contract=off` and
include `src/rpst-compat.h` (which pulls in the float-overload header). Fixtures record
"pinned PST v3.3.2 under the adopted deterministic rPSTool floating-point evaluation policy"; see
[../../docs/compatibility/floating-point-policy.md](../../docs/compatibility/floating-point-policy.md).
