# The Hillier-Iida example data: installed files, loader, structure and fidelity to the supplied RDS objects.
skip_if_not_installed("sf")

extdata <- function() system.file("extdata", "hillier_iida", package = "rPSTool")
# MD5 sum of the installed RDS file. The file as first supplied had ad53f36e...; the authorised changes since are the added Penn et al.
# (1998) sentence and the later rewording of the metadata attribute for the Barnsbury-only dataset (georeferenced and spatially
# transformed geometry), and saving with compress = "xz", version = 2 (readable by every supported R; objects verified identical).
# The fingerprints of the axial, unlinks and gates components below (computed on the file as first supplied) are unchanged.
supplied_md5 <- "b889d36955c7892db1c773da86471ee8"
# Fingerprint of an sf component: MD5 of its attribute table (dput, 17 digits, NA kept), column names, CRS WKT, geometry type and the
# well-known binary of every geometry.
fingerprint <- function(x) {
  file <- tempfile()
  on.exit(unlink(file))
  table <- sf::st_drop_geometry(x)
  text <- c(utils::capture.output(dput(as.list(table), control = c("keepNA", "keepInteger", "digits17"))),
            names(table), sf::st_crs(x)$wkt, as.character(sf::st_geometry_type(x, by_geometry = FALSE)))
  connection <- file(file, "wb")
  writeLines(text, connection, useBytes = TRUE)
  for (geometry in sf::st_as_binary(sf::st_geometry(x))) writeBin(geometry, connection)
  close(connection)
  unname(tools::md5sum(file))
}
component_fingerprints <- c(axial = "0bceafe50acbd1436934a00a008ca949", unlinks = "e741eb7f1e74b67db234858a68ff1373",
                            gates = "695947c9176a8b3b8b3a81820ed6d7f1")

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
  # Source attribution of the movement observations (verified by the maintainer against the supplied README and Hillier and Iida
  # 2005, Section 5): one sentence directly after the opening Hillier-Iida reference, and no more than the observations.
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
