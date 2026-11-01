test_that("the engine pin records the pinned PST release", {
  x <- rPSTool:::.pst_engine_pin()
  expect_identical(unname(x[["pst_version"]]), "3.3.2")
  expect_identical(
    unname(x[["pst_commit"]]),
    "63df80a2cf3dd289be95ea3d91667c3490719b75"
  )
})

test_that("installed provenance agrees with the engine pin", {
  pin <- readLines(system.file("upstream", "PST_VERSION", package = "rPSTool"))
  x <- rPSTool:::.pst_engine_pin()
  expect_true(paste0("PST_VERSION=", x[["pst_version"]]) %in% pin)
  expect_true(paste0("PST_COMMIT=", x[["pst_commit"]]) %in% pin)
  expect_true("PST_TAG=v3.3.2" %in% pin)
  license <- system.file("upstream", "PST_LICENSE", package = "rPSTool")
  expect_true(file.exists(license))
  expect_match(paste(readLines(license), collapse = "\n"),
               "GNU LESSER GENERAL PUBLIC LICENSE")
})
