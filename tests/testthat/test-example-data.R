# The Hillier-Iida example data: installed files, loader, structure and fidelity to the supplied RDS objects.
skip_if_not_installed("sf")

extdata <- function() system.file("extdata", "hillier_iida", package = "rPSTool")
# MD5 sum of the installed RDS file (saved with compress = "xz", version = 2, readable by every supported R). The metadata attribute
# describes the Barnsbury-only dataset, its georeferenced and spatially transformed geometry and the Penn et al. (1998) source.
# The fingerprints of the axial, unlinks and gates components below pin the supplied data themselves and are independent of the
# metadata text and the compression.
supplied_md5 <- "b889d36955c7892db1c773da86471ee8"
# Fingerprint of an sf component: MD5 of a canonical byte stream holding the column names, the attribute table, the CRS WKT,
# the geometry type and the well-known binary of every geometry. The attribute values are written as bytes, never as text:
# integers as little-endian 32-bit, doubles as the little-endian IEEE 754 bytes (exact, so one changed bit is detected),
# strings as UTF-8, with an explicit flag per value for NA (NA payloads are not compared). A text rendering such as dput()
# depends on the platform's floating-point formatting and is not a stable fingerprint of the values.
canonical_column <- function(values) {
  missing <- is.na(values)
  flags <- writeBin(as.integer(missing), raw(), size = 4L, endian = "little")
  if (is.double(values)) {
    nan <- is.nan(values)
    values[missing] <- 0
    c(charToRaw("double"), flags, writeBin(as.integer(nan), raw(), size = 4L, endian = "little"),
      writeBin(values, raw(), size = 8L, endian = "little"))
  } else if (is.integer(values)) {
    values[missing] <- 0L
    c(charToRaw("integer"), flags, writeBin(values, raw(), size = 4L, endian = "little"))
  } else if (is.character(values)) {
    bytes <- lapply(enc2utf8(values[!missing]), charToRaw)
    c(charToRaw("character"), flags, unlist(lapply(bytes, function(b)
      c(writeBin(length(b), raw(), size = 4L, endian = "little"), b))))
  } else stop("unsupported attribute type: ", class(values)[[1L]])
}
fingerprint <- function(x) {
  file <- tempfile()
  on.exit(unlink(file))
  table <- sf::st_drop_geometry(x)
  connection <- file(file, "wb")
  writeLines(c(names(table), sf::st_crs(x)$wkt, as.character(sf::st_geometry_type(x, by_geometry = FALSE))), connection, useBytes = TRUE)
  for (column in table) writeBin(canonical_column(column), connection)
  for (geometry in sf::st_as_binary(sf::st_geometry(x))) writeBin(geometry, connection)
  close(connection)
  unname(tools::md5sum(file))
}
component_fingerprints <- c(axial = "ab7fb65747b5daa068a5af29a5e27b95", unlinks = "e9de3cd6cc17c467a372d3ea1cca02d5",
                            gates = "03e31b3659d2be9b94d0ea39d2918e6c")

test_that("the installed package carries exactly the approved RDS file and no other data files", {
  expect_true(nzchar(extdata()))
  connection <- xzfile(file.path(extdata(), "barnsbury.rds"), "rb")   # xz-compressed serialization version 2: no R >= 3.5.0 requirement
  header <- readBin(connection, "raw", 6L)
  close(connection)
  expect_identical(header, as.raw(c(0x58, 0x0a, 0x00, 0x00, 0x00, 0x02)))
  expect_identical(list.files(extdata(), all.files = TRUE, no.. = TRUE), "barnsbury.rds")
  root <- dirname(extdata())
  expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), "hillier_iida")
  expect_identical(list.dirs(root, full.names = FALSE), c("", "hillier_iida"))
  package <- system.file(package = "rPSTool")
  expect_false(any(grepl("\\.(gpkg|zip|csv|tar|gz|shp|geojson|parquet|fgb)$", list.files(package, recursive = TRUE))))
  expect_false(dir.exists(file.path(package, "data")))
  expect_identical(unname(tools::md5sum(file.path(extdata(), "barnsbury.rds"))), supplied_md5)
})

test_that("load_example_data takes no arguments and returns the Barnsbury data with the supplied structure", {
  expect_length(formals(load_example_data), 0L)
  expect_error(load_example_data("barnsbury"), "unused argument")
  before <- ls(globalenv(), all.names = TRUE)
  example <- load_example_data()
  expect_identical(ls(globalenv(), all.names = TRUE), before)
  expect_type(example, "list")
  expect_identical(names(example), c("axial", "unlinks", "gates"))
  expect_identical(example, readRDS(file.path(extdata(), "barnsbury.rds")))
  for (component in names(example)) {
    expect_s3_class(example[[component]], "sf")
    expect_identical(sf::st_crs(example[[component]])$epsg, 27700L, info = component)
  }
  expect_identical(c(nrow(example$axial), nrow(example$unlinks), nrow(example$gates)), c(1915L, 2L, 109L))
  expect_identical(as.character(sf::st_geometry_type(example$axial, by_geometry = FALSE)), "LINESTRING")
})

test_that("the axial, unlinks and gates components are identical to the files as first supplied", {
  expect_identical(vapply(load_example_data()[c("axial", "unlinks", "gates")], fingerprint, ""), component_fingerprints)
})

test_that("the fingerprint detects any change to attribute values, geometry, names and NA positions", {
  data <- load_example_data()
  base <- vapply(data[c("axial", "unlinks", "gates")], fingerprint, "")
  expect_identical(base, component_fingerprints)
  expect_identical(fingerprint(unserialize(serialize(data$axial, NULL))), base[["axial"]])   # a copy is unchanged
  changed <- function(x) !identical(fingerprint(x), fingerprint(data[[attr(x, "component")]]))
  mutate <- function(component, edit) { x <- data[[component]]; x <- edit(x); attr(x, "component") <- component; x }
  nudge <- function(v) { v[[1L]] <- v[[1L]] + abs(v[[1L]]) * .Machine$double.eps * 2; v }   # a one-ulp-scale change in a double
  expect_true(changed(mutate("axial", function(x) { x$source_control <- nudge(x$source_control); x })))
  expect_true(changed(mutate("axial", function(x) { x$source_integration[10L] <- x$source_integration[10L] + 1e-9; x })))
  expect_true(changed(mutate("axial", function(x) { x$axial_id[3L] <- x$axial_id[3L] + 1L; x })))
  expect_true(changed(mutate("gates", function(x) { x$vehicles_per_hour[1L] <- NA_real_; x })))                # value -> NA
  first_na <- which(is.na(data$gates$vehicles_per_hour))[[1L]]
  expect_true(changed(mutate("gates", function(x) { x$vehicles_per_hour[first_na] <- 0; x })))                 # NA -> value
  expect_true(changed(mutate("gates", function(x) { x$land_use[1L] <- paste0(x$land_use[1L], "x"); x })))
  expect_true(changed(mutate("gates", function(x) { x$effective_road_width_m <- nudge(x$effective_road_width_m); x })))
  expect_true(changed(mutate("unlinks", function(x) { x$axial_id_1[1L] <- x$axial_id_1[1L] + 1L; x })))
  expect_true(changed(mutate("axial", function(x) { names(x)[2L] <- "renamed"; x })))
  expect_true(changed(mutate("axial", function(x) { sf::st_geometry(x)[[1L]] <- sf::st_geometry(x)[[1L]] + c(1e-6, 0); x })))
  expect_true(changed(mutate("axial", function(x) x[rev(seq_len(nrow(x))), ])))                                # row order
})

test_that("values, identifiers, observations, NA values and gate-42 assignments are preserved as supplied", {
  data <- load_example_data()
  axial <- data$axial
  expect_identical(names(axial), c("axial_id", "source_connectivity", "source_control", "source_integration",
                                   "source_local_integration", "geometry"))
  expect_false(anyDuplicated(axial$axial_id) > 0L)
  expect_true(all(data$gates$axial_id %in% axial$axial_id))
  expect_true(all(unlist(sf::st_drop_geometry(data$unlinks)) %in% axial$axial_id))
  expect_identical(names(data$unlinks), c("axial_id_1", "axial_id_2", "geometry"))
  expect_identical(names(data$gates)[c(1:3, 15:16)], c("gate_id", "axial_id", "area", "effective_road_width_m", "geometry"))
  gates <- sf::st_drop_geometry(data$gates)
  expect_identical(gates[gates$gate_id == 42L, "axial_id"], c(16L, 20L))                # both Barnsbury gate-42 assignments
  expect_identical(sum(duplicated(gates$gate_id)), 1L)
  expect_identical(sum(is.na(data$gates$vehicles_per_hour)), 27L)
  expect_false(any(is.na(data$gates$pedestrians_per_hour)))
  expect_identical(unique(data$gates$area), "barnsbury")
  expect_equal(unlist(sf::st_drop_geometry(data$axial)[1, ]),
               c(axial_id = 1, source_connectivity = 14, source_control = 3.29336, source_integration = 1.59014,
                 source_local_integration = 4.59585), tolerance = 1e-6)
})

test_that("the descriptive metadata is stored with the loaded list", {
  metadata <- attr(load_example_data(), "metadata")
  expect_type(metadata, "character")
  expect_length(metadata, 1L)
  expect_match(metadata, "Hillier, B. and Iida, S. (2005)", fixed = TRUE)
  expect_match(metadata, "EPSG:27700", fixed = TRUE)
  expect_match(metadata, "without recalculation", fixed = TRUE)
  # The geometry is transformed and the metadata says so; only the Barnsbury dataset is described.
  expect_match(metadata, "georeferenced to British National Grid (EPSG:27700) using a best-fit spatial transformation", fixed = TRUE)
  expect_match(metadata, "not the original, unmodified coordinates", fixed = TRUE)
  expect_false(grepl("Clerkenwell|Kensington|Calthorpe|Brompton|SKMuseum|Knightsbridge", metadata))
  # Source attribution of the movement observations (the supplied README and Hillier and Iida 2005, Section 5): one sentence
  # directly after the opening Hillier-Iida reference, and no more than the observations.
  penn <- paste0("The pedestrian and vehicular movement observations were originally used in Penn, A., Hillier, B., Banister, D. ",
                 "and Xu, J. (1998), Configurational modelling of urban movement networks, Environment and Planning B: Planning ",
                 "and Design, 25(1), pp. 59")
  expect_match(metadata, paste0("DOI: 10.1007/11556114_30. ", penn), fixed = TRUE)
  expect_match(metadata, "DOI: 10.1068/b250059. The original axial maps and movement observations were obtained from UCL Discovery",
               fixed = TRUE)
  expect_identical(lengths(regmatches(metadata, gregexpr("Penn", metadata, fixed = TRUE))), 1L)
  expect_match(metadata, "unavailable vehicle observations represented as NA rather than zero", fixed = TRUE)
  expect_match(metadata, "parent axial lines, not subsequently generated network segments", fixed = TRUE)
  file <- tempfile(fileext = ".txt")
  on.exit(unlink(file), add = TRUE)
  writeBin(charToRaw(enc2utf8(metadata)), file)                                         # the UTF-8 bytes of the supplied text
  expect_identical(unname(tools::md5sum(file)), "502f7ef94fd48707484b3426e86f3222")
})

test_that("the example axial maps build axial graphs unchanged", {
  barnsbury <- load_example_data()
  graph <- axial_graph(barnsbury$axial, unlinks = barnsbury$unlinks)
  expect_s3_class(graph, "pst_graph")
  expect_identical(graph$n_lines, nrow(barnsbury$axial))
  # The two unlinks remove two of the 4493 crossings of the unlinked map (as supplied; no recalculation of the source values).
  expect_identical(c(graph$n_crossings, axial_graph(barnsbury$axial)$n_crossings), c(4491L, 4493L))
})
