# Contributing to rPSTool

rPSTool is a thin native R interface to pinned PST v3.3.2. Start with the [documentation index](docs/README.md) and the
compatibility record for the relevant native family.

Create a focused branch from current `main`.
Development reference tools live under [tools/reference](tools/reference/README.md); Python and upstream checkouts are development
resources, not installed package dependencies.

Run the complete validation entry point from the repository root:

```sh
Rscript tools/ci/check-local.R
git diff --check
```

R, its platform compiler toolchain and the package test dependencies (including `arrow`, `sf` and `jsonlite`) must be installed.
The [build guide](docs/build-and-platforms.md) and [CI policy](tools/ci/README.md) describe the gates, retained logs, warning
inventories and the cross-platform workflow.

Open a pull request against `main` describing the change and its validation.

The vendored PST source under `src/vendor/` is pristine pinned source and must not be edited; see [architecture](docs/architecture.md)
and [build and platforms](docs/build-and-platforms.md) for the engine, portability and numerical-fidelity rules.
