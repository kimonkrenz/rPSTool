# Generated direct-PST reference fixtures (tests/testthat/fixtures/*-direct-v3.3.2.R) must carry exact
# numeric literals. R's decimal parser is not correctly rounded on builds where `long double` is only
# binary64 (for example Apple Silicon), so a non-integer decimal literal can parse to a neighbouring
# double. Hexadecimal literals are exact everywhere. The scope is deliberately limited to generated
# direct-reference fixtures; hand-written test numerics and hand-transcribed upstream constants
# (network-integration-v3.3.2.R, angular-integration-v3.3.2.R) are not covered.
fixture_nonexact_numerics <- function(path) {
  text <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  text <- gsub('"([^"\\\\]|\\\\.)*"', '""', text, perl = TRUE)     # string literals are not numerics
  text <- gsub("(?m)#[^\n]*$", "", text, perl = TRUE)                    # neither are comments
  # Non-exact: any decimal with a fraction or an exponent, or a digit-only token above 2^53.
  # Digit-only tokens up to 2^53 (9007199254740992) are exact on every R build, matching the
  # rnumeric.py contract; larger integers must be written as hexadecimal. Hexadecimal literals are
  # skipped by the (?<![\w.]) guard because their digits follow "0x".
  decimal <- "(?<![\\w.])(?:[0-9]+\\.[0-9]*|\\.[0-9]+|[0-9]+(?=[eE][-+]?[0-9]))(?:[eE][-+]?[0-9]+)?(?![\\w.])"
  digits_only <- "(?<![\\w.])[0-9]{16,}(?![\\w.])"                    # shorter tokens are always below 2^53
  found <- regmatches(text, gregexpr(paste0(decimal, "|", digits_only), text, perl = TRUE))[[1L]]
  is_digits <- grepl("^[0-9]+$", found)
  exact_integer <- is_digits
  exact_integer[is_digits] <- digits_within_2_53(found[is_digits])
  found[!exact_integer]
}

# TRUE when a digit-only token is <= 2^53 = 9007199254740992 (string comparison; no parser involved).
digits_within_2_53 <- function(tokens) {
  tokens <- sub("^0+(?=[0-9])", "", tokens, perl = TRUE)
  limit <- "9007199254740992"
  nchar(tokens) < nchar(limit) | (nchar(tokens) == nchar(limit) & tokens <= limit)
}

test_that("generated direct-reference fixtures contain only exact numeric literals", {
  files <- list.files(test_path("fixtures"), "-direct-v3\\.3\\.2\\.R$", full.names = TRUE)
  expect_gte(length(files), 10L)                      # every generated direct fixture is in scope
  for (path in files) {
    bad <- fixture_nonexact_numerics(path)
    expect_identical(head(bad, 5L), character(), info = basename(path))
  }
})

test_that("the serialization gate rejects non-exact decimal literals", {
  probe <- function(code) {
    path <- tempfile(fileext = ".R"); on.exit(unlink(path))
    writeLines(code, path)
    fixture_nonexact_numerics(path)
  }
  expect_identical(probe("list(a = 0.1, b = 1e-05, c = -9.536743128535363e-08, d = 3.4028234663852886e+38)"),
                   c("0.1", "1e-05", "9.536743128535363e-08", "3.4028234663852886e+38"))
  expect_identical(probe("list(a = 5, b = 7L, c = 0x1.8p+1, d = 0x0p+0, e = NaN, f = Inf, g = NA_real_, h = TRUE)"),
                   character())
  expect_identical(probe("x <- 1234567890123456789"), "1234567890123456789")   # beyond exact integer digits
  # Boundary of the rnumeric.py integer contract: digit-only tokens are exact up to and including 2^53.
  expect_identical(probe("c(1000000000000000, 9007199254740991, 9007199254740992, 0009007199254740992)"),
                   character())                                                  # 16 digits but exact
  expect_identical(probe("c(9007199254740993, 9007199254740994, 9999999999999999, 10000000000000000)"),
                   c("9007199254740993", "9007199254740994", "9999999999999999", "10000000000000000"))
  expect_identical(probe("c(-9007199254740992, -9007199254740993)"), "9007199254740993")   # sign is not part of the token
  expect_identical(probe("c(0x1.0000000000001p+53, 0x1p+60)"), character())               # larger integers belong in hex
  expect_identical(probe("# 0.5 in a comment\nlist(s = \"0.25\", n = 2)"), character())
})
