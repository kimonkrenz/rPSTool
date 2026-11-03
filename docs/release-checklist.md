# Release checklist (rPSTool 0.1.0)

Test environments and check results for CRAN are in `cran-comments.md`.

## Outstanding before submission

* **Linux validation at the current tree.** Run the full development gate (`Rscript tools/ci/check-local.R`) on Linux at the
  commit to be released.
* **CRAN incoming checks.** Run `R CMD check --as-cran` with `_R_CHECK_CRAN_INCOMING_`, `_R_CHECK_CRAN_INCOMING_REMOTE_` and
  `_R_CHECK_FORCE_SUGGESTS_` enabled, on each platform. The expected NOTEs are "New submission" and, with Debian-style `-g`
  toolchains, the installed-size NOTE ([build and platforms](build-and-platforms.md)).
* **Spelling, URLs, version.** `spelling::spell_check_package()` (needs aspell), `urlchecker::url_check()`, and the final
  `Version` and `Date`.
* **Frozen tarball.** Build the tarball with `R CMD build` from the release commit and re-check that exact tarball.
* **`cran-comments.md`.** Complete the test-environment list and check results; list every remaining NOTE with its explanation.
* **`arrow >= 25.0.0`.** Re-verify at submission that it resolves from CRAN. Tests and examples skip when it is absent; the
  development gate requires it.
* **README.** `README.md` is excluded from the tarball (`.Rbuildignore`) because it links to repository files that are not
  shipped. Keep the exclusion or ship a CRAN-facing README.
