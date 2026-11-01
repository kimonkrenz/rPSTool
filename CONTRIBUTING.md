# Contributing to rPSTool

rPSTool is a thin native R interface to pinned PST v3.3.2. Start with the [documentation index](docs/README.md) and the
compatibility record for the relevant native family.

Create a focused branch from current `main`. Keep public API compatibility, source provenance and native ownership explicit.
Development reference tools live under [tools/reference](tools/reference/README.md); Python and upstream checkouts are development
resources, not installed package dependencies.

Run the complete validation entry point from the repository root:

```sh
Rscript tools/ci/check-local.R
git diff --check
```

R, its platform compiler toolchain and the package test dependencies (including `arrow`, `sf` and `jsonlite`) must be installed.
The [build guide](docs/build-and-platforms.md) and [CI policy](tools/ci/README.md) describe the gates, retained logs, warning
inventories and the manually launched cross-platform workflow. Document what actually ran, and any execution-platform limitation,
in the pull request.

Open a reviewable pull request against `main` with the concrete change and its validation. Do not launch the cross-platform
workflow or merge automatically.

The vendored PST source under `src/vendor/` is pristine pinned source and must not be edited; see [architecture](docs/architecture.md)
and [build and platforms](docs/build-and-platforms.md) for the engine, portability and numerical-fidelity rules.
