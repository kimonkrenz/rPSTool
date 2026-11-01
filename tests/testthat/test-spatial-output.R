# docs/spatial-io/spatial-output.md: spatial output. A NEW GeoParquet / FlatGeobuf file holding the ORIGINAL geometry and
# attributes plus the result columns, paired with the source features by position. Every output is read back with an
# independent reader (GDAL through sf for FlatGeobuf, R arrow for GeoParquet) and compared with the in-memory analysis and
# with the source file.

FORMATS <- c("flatgeobuf", "geoparquet")

skip_spatial <- function() {
  skip_if_not_installed("sf")
  skip_if_not_installed("arrow", "25.0.0")
  skip_if_not_installed("jsonlite")
}

test_that("file-built graphs carry lightweight source provenance; in-memory graphs carry none", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments()
  for (format in FORMATS) {
    path <- so_make_source(format, file.path(dir, paste0("s.", so_ext[[format]])), m)
    for (kind in c("segment", "axial")) {
      g <- so_graph(format, path, kind)
      src <- attr(g, "source")
      expect_named(src, c("path", "format", "rows", "size", "mtime", "device", "inode"))
      expect_identical(src$path, normalizePath(path)); expect_identical(src$format, format)
      expect_identical(src$rows, 30); expect_identical(src$size, as.double(file.size(path)))
      expect_false(any(c("geometry", "coords", "xy") %in% names(src)))   # never geometry
      expect_identical(attr(unserialize(serialize(g, NULL)), "source"), src)
    }
  }
  expect_null(attr(segment_graph(m), "source")); expect_null(attr(axial_graph(m), "source"))
  out <- file.path(dir, "o.fgb")
  expect_error(angular_choice(segment_graph(m), spatial_output_file = out), "built from a GeoParquet or FlatGeobuf file path")
  expect_false(file.exists(out))
})

test_that("spatial_output_file is appended after overwrite; output_file stays attribute-only and is mutually exclusive", {
  skip_spatial()
  fns <- list(angular_integration = c("graph", "steps", "radius", "weigh_by_length", "normalization", "angle_threshold", "angle_precision", "weight_outputs", "output_file", "overwrite"),
              angular_choice = c("graph", "radius", "weigh_by_length", "normalization", "angle_threshold", "angle_precision", "output_file", "overwrite"),
              network_integration = c("graph", "steps", "radius", "junctions", "junction_output", "output_file", "overwrite"),
              network_reach = c("graph", "radius", "origins", "output_file", "overwrite"),
              network_betweenness = c("graph", "radius", "distance", "normalization", "weights", "attraction_points", "output_file", "overwrite"),
              od_betweenness = c("graph", "origins", "radius", "distance", "destination_mode", "origin_weights", "destination_weights", "output_file", "overwrite"))
  for (name in names(fns)) expect_identical(names(formals(get(name))), c(fns[[name]], "spatial_output_file"), info = name)
  expect_identical(tail(names(formals(attraction_reach)), 3L), c("output_file", "overwrite", "spatial_output_file"))
  expect_identical(tail(names(formals(attraction_distance)), 3L), c("output_file", "overwrite", "spatial_output_file"))
  expect_null(formals(angular_choice)$spatial_output_file)
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  path <- so_write_fgb(file.path(dir, "s.fgb"), so_segments())
  g <- segment_graph(path)
  both <- file.path(dir, c("a.parquet", "b.fgb"))
  expect_error(angular_choice(g, output_file = both[1], spatial_output_file = both[2]), "mutually exclusive")
  expect_false(any(file.exists(both)))
  # output_file is unchanged for a file-built graph: attribute-only Parquet, no geometry
  out <- angular_choice(g, output_file = both[1])
  expect_identical(out$format, "parquet"); expect_null(out$spatial)
  expect_identical(names(rs_read_parquet(both[1], as_data_frame = FALSE)), c("segment_id", "choice", "node_count", "total_depth"))
})

test_that("ineligible modes are rejected before anything is computed or created", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  path <- so_write_fgb(file.path(dir, "s.fgb"), so_segments())
  g <- axial_graph(path); out <- file.path(dir, "o.fgb")
  expect_error(network_reach(g, origins = rbind(c(105, 205)), spatial_output_file = out), "not one-to-one")
  expect_error(network_integration(g, junctions = TRUE, spatial_output_file = out), "not one-to-one")
  expect_error(attraction_reach(g, rbind(c(105, 205)), origin = "points", spatial_output_file = out), "not one-to-one")
  expect_error(attraction_distance(g, rbind(c(105, 205)), origin = "junctions", spatial_output_file = out), "not one-to-one")
  expect_false(file.exists(out)); expect_length(so_leftovers(dir), 0L)
})

# ---- correspondence, values, geometry, attributes, CRS -----------------------------------------------------------------
so_expected <- function(kind, g, m) {
  # the in-memory result, and an INDEPENDENT graph built from the source geometry matrix in physical order
  fresh <- if (kind == "segment") segment_graph(m) else axial_graph(m)
  list(
    angular_integration = if (kind == "segment") list(call = function(...) angular_integration(..., steps = 3), memory = angular_integration(g, steps = 3), fresh = angular_integration(fresh, steps = 3)),
    angular_choice = if (kind == "segment") list(call = function(...) angular_choice(..., radius = analysis_radius(steps = 3), normalization = "syntax"), memory = angular_choice(g, radius = analysis_radius(steps = 3), normalization = "syntax"), fresh = angular_choice(fresh, radius = analysis_radius(steps = 3), normalization = "syntax")),
    integration = if (kind == "axial") list(call = function(...) network_integration(..., steps = 2), memory = network_integration(g, steps = 2), fresh = network_integration(fresh, steps = 2)),
    reach = if (kind == "axial") list(call = function(...) network_reach(..., radius = analysis_radius(steps = 2)), memory = network_reach(g, analysis_radius(steps = 2)), fresh = network_reach(fresh, analysis_radius(steps = 2))),
    betweenness = if (kind == "axial") list(call = function(...) network_betweenness(..., radius = analysis_radius(steps = 3), normalization = "freeman"), memory = network_betweenness(g, analysis_radius(steps = 3), normalization = "freeman"), fresh = network_betweenness(fresh, analysis_radius(steps = 3), normalization = "freeman")),
    od = if (kind == "axial") list(call = function(...) od_betweenness(..., origins = rbind(c(105, 205), c(135, 215))), memory = od_betweenness(g, rbind(c(105, 205), c(135, 215))), fresh = od_betweenness(fresh, rbind(c(105, 205), c(135, 215)))),
    attraction_reach = if (kind == "axial") list(call = function(...) attraction_reach(..., attraction_points = rbind(c(112, 207)), radius = analysis_radius(steps = 2)), memory = attraction_reach(g, rbind(c(112, 207)), analysis_radius(steps = 2)), fresh = attraction_reach(fresh, rbind(c(112, 207)), analysis_radius(steps = 2))),
    attraction_distance = if (kind == "axial") list(call = function(...) attraction_distance(..., attraction_points = rbind(c(112, 207)), radius = analysis_radius(steps = 2)), memory = attraction_distance(g, rbind(c(112, 207)), analysis_radius(steps = 2)), fresh = attraction_distance(fresh, rbind(c(112, 207)), analysis_radius(steps = 2)))
  )
}

test_that("every eligible analysis writes the source geometry and attributes plus results, in source order, in both formats", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments(); attrs <- so_attributes(nrow(m))
  checked <- 0
  for (format in FORMATS) for (indexed in if (format == "flatgeobuf") c(FALSE, TRUE) else FALSE) {
    path <- so_make_source(format, file.path(dir, paste0("s", indexed, ".", so_ext[[format]])), m, attrs = attrs, index = indexed)
    src_md5 <- so_md5(path)
    src <- so_read(path, format)
    # PHYSICAL file order: an indexed FlatGeobuf is Hilbert-ordered on disk; the source reader below returns that order
    phys <- matrix(unlist(lapply(src$wkb, function(w) readBin(w[-(1:9)], "double", 4L))), ncol = 4, byrow = TRUE)
    if (indexed) expect_false(identical(unname(phys), unname(m)))   # the Hilbert-indexed file really is permuted on disk
    else expect_identical(unname(phys), unname(m))
    for (kind in c("segment", "axial")) {
      g <- so_graph(format, path, kind)
      for (name in names(Filter(Negate(is.null), so_expected(kind, g, phys)))) {
        exp <- so_expected(kind, g, phys)[[name]]
        out <- file.path(dir, paste0(name, indexed, ".", so_ext[[format]])); unlink(out)
        desc <- exp$call(g, spatial_output_file = out)
        expect_s3_class(desc, "pst_result_file"); expect_true(desc$spatial); expect_identical(desc$format, format)
        res <- so_read(out, format)
        mem <- exp$memory; mem <- mem[-1L]   # drop the positional id column
        # geometry: byte-identical to the source in the same (physical) order
        expect_identical(res$wkb, src$wkb, info = paste(format, indexed, kind, name))
        # source attributes unchanged (type and value, including NA)
        expect_identical(res$attrs[names(src$attrs)], src$attrs, info = paste(format, indexed, kind, name))
        # result columns equal the in-memory result, and equal an independent graph built from the geometry matrix
        expect_identical(names(res$attrs), c(names(src$attrs), names(mem)), info = paste(format, name))
        for (col in names(mem)) {
          expect_identical(unname(res$attrs[[col]]), unname(mem[[col]]), info = paste(format, indexed, kind, name, col))
          expect_identical(unname(res$attrs[[col]]), unname(exp$fresh[-1L][[col]]), info = paste(format, indexed, kind, name, col, "fresh"))
        }
        expect_identical(desc$rows, 30L); expect_identical(desc$appended, names(mem)); expect_identical(desc$replaced, character())
        checked <- checked + 1
      }
    }
    expect_identical(so_md5(path), src_md5)   # the source is never modified
  }
  expect_identical(checked, 24)   # 3 sources x (2 segment + 6 axial analyses)
})

test_that("CRS, header/layer metadata and the geo metadata are carried over unchanged", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments()
  fgb <- so_write_fgb(file.path(dir, "s.fgb"), m); gpq <- so_write_gpq(file.path(dir, "s.parquet"), m)
  angular_choice(segment_graph(fgb), spatial_output_file = file.path(dir, "o.fgb"))
  angular_choice(segment_graph(gpq), spatial_output_file = file.path(dir, "o.parquet"))
  a <- .Call(rPSTool:::C_rpst_fgb_inspect, fgb); b <- .Call(rPSTool:::C_rpst_fgb_inspect, file.path(dir, "o.fgb"))
  expect_identical(b$crs, a$crs); expect_identical(b$geometry_type, a$geometry_type); expect_identical(b$features_count, a$features_count)
  expect_identical(b$index_node_size, 0L)   # deliberately unindexed: an index would reorder the features
  expect_identical(sf::st_crs(sf::st_read(file.path(dir, "o.fgb"), quiet = TRUE)), sf::st_crs(sf::st_read(fgb, quiet = TRUE)))
  s <- rs_read_parquet(gpq, as_data_frame = FALSE); o <- rs_read_parquet(file.path(dir, "o.parquet"), as_data_frame = FALSE)
  expect_identical(o$metadata$geo, s$metadata$geo); expect_identical(o$metadata$other_key, "kept")
  expect_true(all(c("rpst:function", "rpst:parameters", "rpst:pst_commit") %in% names(o$metadata)))
  expect_identical(o$metadata[["rpst:function"]], "angular_choice")
})

# ---- column replacement ------------------------------------------------------------------------------------------------
test_that("a result column with a source column's name replaces it in place; repeated analyses never duplicate columns", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments(); attrs <- so_attributes(nrow(m))
  attrs$choice <- as.character(seq_len(nrow(m))); attrs$node_count <- seq_len(nrow(m)) * 100L   # same names as results
  attrs$tail <- seq_len(nrow(m)) / 3
  for (format in FORMATS) {
    path <- so_make_source(format, file.path(dir, paste0("s.", so_ext[[format]])), m, attrs = attrs)
    g <- segment_graph(path)
    out1 <- file.path(dir, paste0("o1.", so_ext[[format]]))
    d1 <- angular_choice(g, radius = analysis_radius(steps = 2), spatial_output_file = out1)
    expect_identical(d1$replaced, c("choice", "node_count")); expect_identical(d1$appended, "total_depth")
    r1 <- so_read(out1, format)
    expect_identical(names(r1$attrs), c(names(attrs), "total_depth"))        # in-place replacement, one appended, no duplicates
    mem <- angular_choice(g, radius = analysis_radius(steps = 2))
    expect_identical(unname(r1$attrs$choice), mem$choice); expect_identical(unname(r1$attrs$node_count), mem$node_count)
    expect_identical(r1$attrs$tail, attrs$tail); expect_identical(r1$attrs$osm_id, attrs$osm_id)   # unrelated columns untouched
    # run again on the output with different parameters -> replaced again
    g2 <- segment_graph(out1)
    out2 <- file.path(dir, paste0("o2.", so_ext[[format]]))
    d2 <- angular_choice(g2, radius = analysis_radius(steps = 3), spatial_output_file = out2)
    expect_identical(d2$replaced, c("choice", "node_count", "total_depth")); expect_identical(d2$appended, character())
    r2 <- so_read(out2, format)
    expect_identical(names(r2$attrs), names(r1$attrs)); expect_false(anyDuplicated(names(r2$attrs)) > 0)
    expect_identical(unname(r2$attrs$choice), angular_choice(g, radius = analysis_radius(steps = 3))$choice)
  }
})

test_that("ambiguous or duplicate names are rejected, and no file or temporary is left", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments(); attrs <- so_attributes(nrow(m))
  # FlatGeobuf looks fields up case-insensitively: a source column "Choice" is ambiguous with the result "choice"
  a2 <- attrs; a2$Choice <- 1
  fgb <- so_write_fgb(file.path(dir, "ci.fgb"), m, attrs = a2); out <- file.path(dir, "o.fgb")
  expect_error(angular_choice(segment_graph(fgb), spatial_output_file = out), "only by letter case")
  expect_false(file.exists(out)); expect_length(so_leftovers(dir), 0L)
  # GeoParquet: the geometry column's name collides with a result column
  gpq <- so_write_gpq(file.path(dir, "geom.parquet"), m, attrs = attrs, primary = "choice"); out2 <- file.path(dir, "o.parquet")
  expect_error(angular_choice(segment_graph(gpq), spatial_output_file = out2), "name of the geometry column")
  expect_false(file.exists(out2)); expect_length(so_leftovers(dir), 0L)
  # duplicate source column names never reach the writer: arrow cannot even open such a dataset at graph construction
  dup <- file.path(dir, "dup.parquet")
  tab <- arrow::arrow_table(a = 1:30, a = 31:60, geometry = arrow::Array$create(so_wkb(m), type = arrow::binary()))
  arrow::write_parquet(tab$ReplaceSchemaMetadata(list(geo = so_geo_json())), dup)
  expect_error(segment_graph(dup), "duplicate field names")
})

# ---- GeoParquet specifics --------------------------------------------------------------------------------------------
test_that("GeoParquet: source row-group layout, column types and metadata survive; results are sliced across row groups", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments(); n <- nrow(m)
  extra <- list(code = arrow::Array$create(as.numeric(seq_len(n)) * 1e15, type = arrow::uint64()),
                kind = arrow::Array$create(factor(rep(c("a", "b", "c"), length.out = n))),
                score = arrow::Array$create(seq_len(n) / 7, type = arrow::float32()))
  path <- so_write_gpq(file.path(dir, "s.parquet"), m, chunk = 7L, extra = extra)
  out <- file.path(dir, "o.parquet")
  g <- segment_graph(path); d <- angular_integration(g, steps = 3, spatial_output_file = out)
  s <- rs_pq(path); o <- rs_pq(out)
  expect_identical(o$num_row_groups, s$num_row_groups); expect_identical(s$num_row_groups, 5L)
  ss <- s$GetSchema(); os <- o$GetSchema()
  for (nm in ss$names) expect_true(ss$GetFieldByName(nm)$type == os$GetFieldByName(nm)$type, info = nm)
  expect_true(os$GetFieldByName("integration")$type == arrow::float32()); expect_false(os$GetFieldByName("integration")$nullable)
  expect_identical(os$names, c(ss$names, "integration", "node_count", "total_depth"))
  src <- rs_read_parquet(path, as_data_frame = FALSE); res <- rs_read_parquet(out, as_data_frame = FALSE)
  for (nm in ss$names) expect_true(src$GetColumnByName(nm)$Equals(res$GetColumnByName(nm)), info = nm)
  mem <- angular_integration(g, steps = 3)
  expect_identical(as.vector(res$GetColumnByName("integration")), mem$integration)
  # a batch size that does not divide the source row groups
  md <- rPSTool:::.pst_result_metadata("x", list(), "segment", 30, g)
  desc <- rPSTool:::.pst_write_result_file(NULL, FALSE, export = function(stream, batch_rows)
      .Call(rPSTool:::C_rpst_angular_integration_stream, g$ptr, analysis_radius(steps = 3), FALSE, "turner", 0, 1, FALSE, stream,
            c("segment_id", "integration", "node_count", "total_depth"), names(md), unname(md), batch_rows),
    columns = c("segment_id", "integration", "node_count", "total_depth"), expected_rows = 30, batch_rows = 4,
    spatial_output_file = file.path(dir, "b4.parquet"), graph = g, metadata = md)
  expect_identical(as.vector(rs_read_parquet(file.path(dir, "b4.parquet"), as_data_frame = FALSE)$GetColumnByName("integration")), mem$integration)
})

# ---- nulls and non-finite values, driven by the synthetic native producer ---------------------------------------------------
test_that("native NaN, infinities, -0, boundaries and nulls are stored exactly; a null is never a sentinel", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  rows <- 13; m <- so_segments(rows)
  f <- rs_bits(rs_special_bits)                              # +0 -0 1 -1 +Inf -Inf NaN NaN(payload) -NaN tiny.. max
  ints <- c(0L, -1L, 2147483647L, 5L, 0L, 1L, -2147483647L, 7L, 8L, 9L, 10L, 11L, 12L)
  valid_f <- c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, FALSE)
  valid_i <- !valid_f
  for (format in FORMATS) {
    path <- so_make_source(format, file.path(dir, paste0("s.", so_ext[[format]])), m)
    g <- so_graph(format, path, "segment"); src <- attr(g, "source")
    stream <- rs_synth(rows, floats = list(score = f), signed = list(delta = ints), id = "segment_id", valid = list(score = valid_f, delta = valid_i), batch = 5)
    out <- file.path(dir, paste0("o.", so_ext[[format]])); tmp <- file.path(dir, paste0(".tmp.", so_ext[[format]])); file.create(tmp)
    writer <- if (format == "flatgeobuf") rPSTool:::.pst_spatial_write_flatgeobuf else rPSTool:::.pst_spatial_write_geoparquet
    w <- writer(src, stream, tmp, c("score", "delta"), c(`rpst:function` = "test"), rows)
    expect_identical(w$rows, if (format == "flatgeobuf") 13 else 13)
    file.rename(tmp, out)
    r <- so_read(out, format)$attrs
    expect_identical(is.na(r$score) & !is.nan(r$score), !valid_f)            # nulls only where the mask says
    expect_identical(is.na(r$delta), !valid_i)
    got <- r$score[valid_f]; want <- readBin(f, "numeric", n = rows, size = 4L)[valid_f]
    expect_identical(is.nan(got), is.nan(want)); expect_identical(got[!is.nan(got)], want[!is.nan(want)])
    expect_identical(1 / got[1:2], 1 / want[1:2])                            # +0 and -0 keep their sign
    expect_true(is.infinite(r$score[5]) && r$score[5] > 0 && is.infinite(r$score[6]) && r$score[6] < 0)
    expect_identical(r$delta[valid_i], ints[valid_i])                       # -1, 0 and INT32 boundaries are ordinary values
  }
})

# ---- publication, protection and failure -------------------------------------------------------------------------------
test_that("destinations: no-clobber, explicit overwrite, atomic replacement, and invalid locations", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments()
  for (format in FORMATS) {
    path <- so_make_source(format, file.path(dir, paste0("s.", so_ext[[format]])), m)
    g <- segment_graph(path)
    out <- file.path(dir, paste0("o.", so_ext[[format]]))
    angular_choice(g, spatial_output_file = out)
    first <- so_md5(out)
    expect_error(angular_choice(g, spatial_output_file = out), "already exists")
    expect_identical(so_md5(out), first)
    angular_choice(g, radius = analysis_radius(steps = 1), spatial_output_file = out, overwrite = TRUE)
    expect_false(identical(so_md5(out), first))
    expect_error(angular_choice(g, spatial_output_file = file.path(dir, "no-such-dir", "o")), "directory of spatial_output_file does not exist")
    expect_error(angular_choice(g, spatial_output_file = dir), "is a directory")
    expect_error(angular_choice(g, spatial_output_file = c("a", "b")), "one non-empty")
    expect_error(angular_choice(g, spatial_output_file = out, overwrite = NA), "TRUE or FALSE")
    expect_length(so_leftovers(dir), 0L)
  }
})

test_that("the source network can never be the destination, even with overwrite, and is never modified", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments()
  for (format in FORMATS) {
    path <- so_make_source(format, file.path(dir, paste0("s.", so_ext[[format]])), m)
    before <- so_md5(path); mtime <- file.info(path)$mtime
    g <- segment_graph(path)
    soft <- file.path(dir, paste0("soft.", so_ext[[format]])); hard <- file.path(dir, paste0("hard.", so_ext[[format]]))
    # aliases of the source: its own path, another spelling of it, a hard link and (where permitted) a symbolic link;
    # on Windows also the same path in another letter case and with backslashes
    aliases <- list(path, file.path(dir, ".", basename(path)))
    if (isTRUE(suppressWarnings(file.link(path, hard)))) aliases <- c(aliases, list(hard))
    else if (.Platform$OS.type == "unix") fail("hard links must be available on POSIX")
    has_soft <- rs_symlink(path, soft)
    if (has_soft) aliases <- c(aliases, list(soft))
    if (.Platform$OS.type == "windows")
      aliases <- c(aliases, list(file.path(dir, toupper(basename(path))), gsub("/", "\\", path, fixed = TRUE)))
    for (dest in aliases)
      for (ow in c(FALSE, TRUE))
        expect_error(angular_choice(g, spatial_output_file = dest, overwrite = ow), "source network itself|already exists")
    for (dest in setdiff(aliases, aliases[2L]))
      expect_error(angular_choice(g, spatial_output_file = dest, overwrite = TRUE), "source network itself")
    expect_identical(so_md5(path), before); expect_identical(file.info(path)$mtime, mtime)
    if (has_soft && .Platform$OS.type == "unix") expect_true(nzchar(Sys.readlink(soft)))
    expect_length(so_leftovers(dir), 0L)
    # a successful write also leaves the source byte-identical
    angular_choice(g, spatial_output_file = file.path(dir, paste0("ok.", so_ext[[format]])))
    expect_identical(so_md5(path), before)
  }
})

test_that("an obviously changed source is detected before and after the analysis, and nothing is published", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments()
  for (format in FORMATS) {
    path <- so_make_source(format, file.path(dir, paste0("s.", so_ext[[format]])), m)
    g <- segment_graph(path); out <- file.path(dir, paste0("o.", so_ext[[format]]))
    angular_choice(g, spatial_output_file = out); keep <- so_md5(out)
    # (1) modified (same size, new mtime)
    before_time <- file.info(path)$mtime
    set_time <- Sys.setFileTime(path, Sys.time() + 5)
    # Sys.setFileTime() returns FALSE (silently) when it cannot open the file, which on Windows it cannot while ANY handle to it
    # is open (R requests exclusive access); the assertions below say which part failed instead of a misleading missing error.
    expect_true(set_time, info = paste(format, ": Sys.setFileTime() failed; is a handle to the source still open?"))
    expect_gt(as.numeric(file.info(path)$mtime), as.numeric(before_time), label = paste(format, "source mtime after Sys.setFileTime()"))
    expect_error(angular_choice(g, spatial_output_file = out, overwrite = TRUE), "source file changed")
    expect_identical(so_md5(out), keep)   # a previous valid output is untouched by the failed write
    # (2) replaced by a different network (different size)
    path2 <- so_make_source(format, file.path(dir, paste0("s2.", so_ext[[format]])), so_segments(20))
    g2 <- segment_graph(path2); file.copy(path, path2, overwrite = TRUE)
    x <- file.path(dir, paste0("x.", so_ext[[format]]))
    expect_error(angular_choice(g2, spatial_output_file = x, overwrite = TRUE), "source file changed")
    expect_false(file.exists(x)); expect_length(so_leftovers(dir), 0L)
    # (3) deleted
    g3 <- segment_graph(path2); file.remove(path2)
    expect_error(angular_choice(g3, spatial_output_file = x), "source file changed")
  }
})

test_that("a corrupt source record with unchanged size and time fails the writer cleanly: no output, no temporary", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments()
  path <- so_write_fgb(file.path(dir, "s.fgb"), m)
  g <- segment_graph(path)
  bytes <- readBin(path, "raw", file.size(path)); mt <- file.info(path)$mtime
  bytes[length(bytes) - 10:5] <- as.raw(0xFF); writeBin(bytes, path); Sys.setFileTime(path, mt)
  out <- file.path(dir, "o.fgb")
  expect_error(angular_choice(g, spatial_output_file = out), "Feature|source file changed")
  expect_false(file.exists(out)); expect_length(so_leftovers(dir), 0L)
  # truncated mid-file: the size differs
  bytes <- readBin(path, "raw", file.size(path))
  writeBin(bytes[seq_len(length(bytes) - 40)], path)
  expect_error(angular_choice(g, spatial_output_file = out), "source file changed")
  expect_false(file.exists(out)); expect_length(so_leftovers(dir), 0L)
})

test_that("writer failures leave no output, no temporary and a previous valid output intact", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments()
  for (format in FORMATS) {
    path <- so_make_source(format, file.path(dir, paste0("s.", so_ext[[format]])), m)
    g <- segment_graph(path)
    out <- file.path(dir, paste0("o.", so_ext[[format]]))
    angular_choice(g, spatial_output_file = out); keep <- so_md5(out)
    src <- attr(g, "source")
    cols <- c("segment_id", "choice")
    md <- rPSTool:::.pst_result_metadata("x", list(), "segment", 30, g)
    run <- function(rows = 30, faults = c(0L, -1L, 0L, -1L), overwrite = TRUE, batch = 4)
      rPSTool:::.pst_write_result_file(NULL, overwrite, columns = cols, expected_rows = rows, batch_rows = batch,
        export = function(stream, batch_rows) rs_native("result_test_export", stream, "segment_id", "choice", 0L, list(rs_bits(rep_len(rs_special_bits, rows))),
                                                         character(), character(), as.double(rows), as.double(batch_rows), as.integer(faults)),
        spatial_output_file = out, graph = g, metadata = md)
    # a stream error in the middle of the result
    expect_error(run(faults = c(0L, 3L, 5L, -1L)))
    expect_identical(so_md5(out), keep); expect_length(so_leftovers(dir), 0L)
    # a schema error, an allocation failure
    expect_error(run(faults = c(5L, -1L, 0L, -1L)))
    expect_error(run(faults = c(0L, -1L, 0L, 2L)))
    expect_identical(so_md5(out), keep); expect_length(so_leftovers(dir), 0L)
    # too few / too many result rows for the source
    expect_error(run(rows = 29), "one-to-one|fewer|source")
    expect_error(run(rows = 31), "one-to-one|more|source")
    expect_identical(so_md5(out), keep); expect_length(so_leftovers(dir), 0L)
    # a failing destination directory (no write permission) when not running as root
    if (rs_can_deny_directory()) {   # POSIX non-root only: Sys.chmod() cannot deny file creation in a Windows directory
      ro <- file.path(dir, paste0("ro-", format)); dir.create(ro)
      on.exit(Sys.chmod(ro, "755"), add = TRUE, after = FALSE)   # restored first, even if an assertion below fails
      Sys.chmod(ro, "555")
      expect_error(angular_choice(g, spatial_output_file = file.path(ro, paste0("o.", so_ext[[format]]))))
      Sys.chmod(ro, "755")
      expect_length(list.files(ro, all.files = TRUE, no.. = TRUE), 0L)
    }
  }
})

test_that("the graph is reusable after spatial output and native result owners stay balanced", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments()
  before <- rs_baseline()
  for (format in FORMATS) {
    path <- so_make_source(format, file.path(dir, paste0("s.", so_ext[[format]])), m)
    g <- segment_graph(path)
    ref <- angular_choice(g)
    for (k in 1:3) angular_choice(g, spatial_output_file = file.path(dir, paste0("o", k, ".", so_ext[[format]])))
    expect_identical(angular_choice(g), ref)
    rs_native("segment_graph_release", g$ptr)
    dead <- file.path(dir, paste0("dead.", so_ext[[format]]))
    expect_error(angular_choice(g, spatial_output_file = dead), "released|freed|invalid|dead")
    expect_false(file.exists(dead))
  }
  expect_true(rs_balanced(before))
})

test_that("an interrupt during the write removes the temporary file and publishes nothing", {
  skip_spatial()
  skip_if_not(exists("local_mocked_bindings", asNamespace("testthat")))
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments()
  for (format in FORMATS) {
    path <- so_make_source(format, file.path(dir, paste0("s.", so_ext[[format]])), m)
    g <- segment_graph(path); out <- file.path(dir, paste0("o.", so_ext[[format]]))
    angular_choice(g, spatial_output_file = out); keep <- so_md5(out)
    writer <- if (format == "flatgeobuf") ".pst_spatial_write_flatgeobuf" else ".pst_spatial_write_geoparquet"
    mocked <- list(function(src, stream, temp, ...) {
      writeBin(as.raw(1:100), temp)                          # a partial output exists at the moment of the interrupt
      stop(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
    })
    names(mocked) <- writer
    testthat::local_mocked_bindings(.package = "rPSTool", .env = environment(), !!!mocked)
    res <- tryCatch(angular_choice(g, spatial_output_file = out, overwrite = TRUE), interrupt = function(e) "interrupted")
    expect_identical(res, "interrupted")
    expect_identical(so_md5(out), keep); expect_length(so_leftovers(dir), 0L)
    expect_false(file.exists(file.path(dir, "never")))
  }
})

test_that("the file-size-limit subprocess helper reports status without warnings and the limit is really enforced", {
  skip_spatial()
  skip_on_os("windows")   # `ulimit -f` (RLIMIT_FSIZE) has no Windows equivalent for a single process; see tools/validation/windows
  skip_if(Sys.which("sh") == "")
  expect_no_warning(failing <- so_subprocess("quit(save = 'no', status = 3L)"))   # a non-zero exit status is data, not a warning
  expect_identical(failing$status, 3L)
  ok <- so_subprocess("cat('hello\\n')")
  expect_identical(ok$status, 0L); expect_identical(ok$stdout, "hello")
  # positive evidence that the mechanism works on this platform: a 4 MiB write under a 512 KiB limit is cut short
  target <- tempfile(); on.exit(unlink(target), add = TRUE)
  limited <- so_subprocess(c(sprintf("f <- '%s'", target), "r <- tryCatch(writeBin(raw(4 * 2^20), f), error = function(e) 'error', warning = function(w) 'warning')",
                             "cat('DONE\\n')"), limit_blocks = 1024L)
  expect_identical(limited$status, 0L, info = so_describe(limited))
  expect_true(file.exists(target) && file.size(target) <= 2^20 && file.size(target) < 4 * 2^20, info = so_describe(limited))
  expect_true("DONE" %in% limited$stdout, info = so_describe(limited))
})

test_that("a full disk fails the write cleanly: error, no output, no temporary, previous output intact", {
  skip_spatial()
  skip_on_os("windows")   # needs RLIMIT_FSIZE; the Windows full-disk path is the mocked-writer test in test-result-publication.R
  skip_if(Sys.which("sh") == "")
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  n <- 40000L; m <- so_big_segments(n); attrs <- so_noise_attributes(n)
  # The limit (1024 x 512 B = 512 KiB; 1 MiB where `ulimit -f` counts 1024-byte blocks) is generous for anything R, sf, arrow or
  # PROJ write while starting up, but far below the several-MiB output, so the failure is the WRITER's own.
  limit <- 1024L
  expected <- c(flatgeobuf = "is the disk full", geoparquet = "errno 27|File too large|No space")   # the writer's own message
  for (format in FORMATS) {
    path <- so_make_source(format, file.path(dir, paste0("s.", so_ext[[format]])), m, attrs = attrs)
    kept <- file.path(dir, paste0("keep.", so_ext[[format]])); fresh <- file.path(dir, paste0("fresh.", so_ext[[format]]))
    script <- function(dest, overwrite) c("suppressMessages(library(rPSTool))", sprintf("g <- segment_graph('%s')", path),
      sprintf("r <- tryCatch({ angular_choice(g, spatial_output_file = '%s', overwrite = %s); 'WROTE' }, error = function(e) conditionMessage(e))", dest, overwrite),
      "cat('RESULT:', r, '\\n')")
    # positive control, no limit: the very same subprocess succeeds and writes an output larger than the limit
    control <- so_subprocess(script(kept, "FALSE"))
    expect_identical(control$status, 0L, info = so_describe(control))
    expect_true(any(grepl("RESULT: WROTE", control$stdout, fixed = TRUE)), info = so_describe(control))
    expect_true(file.exists(kept) && file.size(kept) > 4 * limit * 512, info = format)
    before <- so_md5(kept)
    # (a) replacing a previous valid output (overwrite = TRUE): the writer fails, the previous file is untouched
    run <- so_subprocess(script(kept, "TRUE"), limit_blocks = limit)
    expect_identical(run$status, 0L, info = so_describe(run))                      # the script itself ran to completion
    result <- grep("^RESULT:", run$stdout, value = TRUE)
    expect_length(result, 1L)
    expect_match(result, expected[[format]], info = so_describe(run))             # positive evidence: the intended write failure
    expect_identical(so_md5(kept), before)
    # (b) a new destination: nothing is published
    run <- so_subprocess(script(fresh, "FALSE"), limit_blocks = limit)
    expect_identical(run$status, 0L, info = so_describe(run))
    expect_match(grep("^RESULT:", run$stdout, value = TRUE), expected[[format]], info = so_describe(run))
    expect_false(file.exists(fresh)); expect_length(so_leftovers(dir), 0L)
  }
})

test_that("format-specific rejections happen before the analysis runs", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments(); attrs <- so_attributes(nrow(m)); attrs$Choice <- 1
  fgb <- so_write_fgb(file.path(dir, "ci.fgb"), m, attrs = attrs)
  gpq <- so_write_gpq(file.path(dir, "geom.parquet"), m, primary = "choice")
  for (path in c(fgb, gpq)) {
    g <- segment_graph(path); called <- FALSE
    expect_error(rPSTool:::.pst_write_result_file(NULL, FALSE, columns = c("segment_id", "choice"), expected_rows = 30,
                   export = function(stream, batch_rows) { called <<- TRUE }, spatial_output_file = file.path(dir, paste0("o.", tools::file_ext(path))),
                   graph = g, metadata = character()), "letter case|name of the geometry column")
    expect_false(called)
  }
  expect_length(so_leftovers(dir), 0L)
})

test_that("the destination extension must match the source format; rejected requests compute and create nothing", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments()
  # the extension is NOT used to detect the input: a GeoParquet source named .fgb is still read as GeoParquet
  fgb <- so_write_fgb(file.path(dir, "s.fgb"), m); gpq <- so_write_gpq(file.path(dir, "s.parquet"), m)
  disguised <- file.path(dir, "disguised.fgb"); file.copy(gpq, disguised)
  expect_identical(attr(segment_graph(disguised), "source")$format, "geoparquet")
  for (case in list(list(src = fgb, ok = c("o.fgb", "O.FGB", "o.Fgb", "a.b.fgb"), bad = c("o.parquet", "o.fgb.parquet", "o", "o.", "o.gpkg", "fgb", ".fgb.tmp")),
                    list(src = gpq, ok = c("o.parquet", "O.PARQUET", "o.Parquet"), bad = c("o.fgb", "o.parquet.fgb", "o", "o.geoparquet", "o.pq")))) {
    g <- segment_graph(case$src)
    for (bad in case$bad) {
      called <- FALSE
      expect_error(rPSTool:::.pst_write_result_file(NULL, FALSE, columns = c("segment_id", "choice"), expected_rows = 30,
                     export = function(stream, batch_rows) { called <<- TRUE }, spatial_output_file = file.path(dir, bad),
                     graph = g, metadata = character()), "must end in", info = bad)
      expect_false(called, info = bad)
      expect_false(file.exists(file.path(dir, bad)), info = bad)
      expect_error(angular_choice(g, spatial_output_file = file.path(dir, bad), overwrite = TRUE), "must end in", info = bad)
    }
    expect_length(so_leftovers(dir), 0L)
    for (ok in case$ok) {   # accepted spellings still work, case-insensitively, and nothing is renamed
      out <- file.path(dir, ok)
      d <- angular_choice(g, spatial_output_file = out)
      expect_identical(basename(d$path), ok); expect_true(file.exists(out)); unlink(out)
    }
  }
  # the extension check does not weaken the source/destination protection
  expect_error(angular_choice(segment_graph(fgb), spatial_output_file = fgb, overwrite = TRUE), "source network itself")
  expect_error(angular_choice(segment_graph(gpq), spatial_output_file = gpq, overwrite = TRUE), "source network itself")
  # a message that names the problem and promises no rename
  err <- tryCatch(angular_choice(segment_graph(fgb), spatial_output_file = file.path(dir, "r.parquet")), error = conditionMessage)
  expect_match(err, "'\\.fgb'"); expect_match(err, "never renamed")
  expect_false(file.exists(file.path(dir, "r.parquet"))); expect_length(so_leftovers(dir), 0L)
})

# ---- FlatGeobuf header metadata on repeated analyses ------------------------------------------------------------------------
so_fgb_meta <- function(path) {
  raw <- .Call(rPSTool:::C_rpst_fgb_columns, path)$metadata
  if (is.null(raw)) NULL else rawToChar(raw)
}
so_prov <- function(meta, key) {
  m <- regmatches(meta, regexec(paste0('"', key, '":"((?:[^"\\\\]|\\\\.)*)"'), meta, perl = TRUE))[[1L]]
  if (length(m) < 2L) NA_character_ else m[[2L]]
}
test_that("FlatGeobuf provenance always describes the latest calculation; unrelated source metadata is preserved", {
  skip_spatial()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments()
  src <- so_write_fgb(file.path(dir, "s.fgb"), m)
  expect_null(so_fgb_meta(src))   # a plain GDAL-written source has no header metadata
  o1 <- file.path(dir, "o1.fgb"); o2 <- file.path(dir, "o2.fgb"); o3 <- file.path(dir, "o3.fgb")
  angular_choice(segment_graph(src), radius = analysis_radius(steps = 2), spatial_output_file = o1)
  angular_integration(segment_graph(o1), steps = 5, spatial_output_file = o2)
  angular_choice(segment_graph(o2), radius = analysis_radius(steps = 9), spatial_output_file = o3)   # replaces `choice` again
  m1 <- so_fgb_meta(o1); m2 <- so_fgb_meta(o2); m3 <- so_fgb_meta(o3)
  expect_identical(so_prov(m1, "rpst:function"), "angular_choice")
  expect_identical(so_prov(m2, "rpst:function"), "angular_integration")
  expect_identical(so_prov(m3, "rpst:function"), "angular_choice")
  expect_match(so_prov(m1, "rpst:parameters"), '"steps\\":2', fixed = TRUE)
  expect_match(so_prov(m3, "rpst:parameters"), '"steps\\":9', fixed = TRUE)
  expect_false(grepl('"steps\\":2', m3, fixed = TRUE))   # nothing of the first calculation survives
  for (mm in list(m1, m2, m3)) expect_identical(lengths(regmatches(mm, gregexpr('"rpst:function"', mm, fixed = TRUE))), 1L)   # no duplicate keys
  # the data are also the latest (replacement, not duplication)
  expect_identical(names(so_read(o3, "flatgeobuf")$attrs), c(names(so_read(src, "flatgeobuf")$attrs), "choice", "node_count", "total_depth", "integration"))
  expect_identical(so_read(o3, "flatgeobuf")$attrs$choice, angular_choice(segment_graph(o2), radius = analysis_radius(steps = 9))$choice)

  # an rPSTool object that ALSO holds an unrelated pair: the unrelated pair survives byte for byte, rPSTool's pairs are refreshed
  patch <- function(from, to, pattern, replacement) {
    b <- readBin(from, "raw", file.size(from)); at <- grepRaw(charToRaw(pattern), b, fixed = TRUE)
    stopifnot(length(at) == 1L, nchar(pattern) == nchar(replacement))
    b[at + seq_len(nchar(pattern)) - 1L] <- charToRaw(replacement); writeBin(b, to); to
  }
  mixed <- patch(o1, file.path(dir, "mixed.fgb"), '"rpst:id_base"', '"note:id_base"')
  expect_match(so_fgb_meta(mixed), '"note:id_base":"1"', fixed = TRUE)
  o4 <- file.path(dir, "o4.fgb")
  angular_integration(segment_graph(mixed), steps = 4, spatial_output_file = o4)
  m4 <- so_fgb_meta(o4)
  expect_match(m4, '"note:id_base":"1"', fixed = TRUE)                                     # unrelated pair preserved verbatim
  expect_identical(so_prov(m4, "rpst:function"), "angular_integration")
  expect_identical(lengths(regmatches(m4, gregexpr('"rpst:id_base"', m4, fixed = TRUE))), 1L)   # re-added once, by the new provenance
  expect_match(so_prov(m4, "rpst:parameters"), '"steps\\":4', fixed = TRUE)

  # opaque metadata (not a flat string object, or no rPSTool keys) is preserved faithfully and never extended or corrupted
  patch_all <- function(from, to, pattern, replacement) {
    b <- readBin(from, "raw", file.size(from)); at <- grepRaw(charToRaw(pattern), b, fixed = TRUE, all = TRUE)
    stopifnot(length(at) > 1L, nchar(pattern) == nchar(replacement))
    for (a in at) b[a + seq_len(nchar(pattern)) - 1L] <- charToRaw(replacement); writeBin(b, to); to
  }
  opaque <- c(patch(o1, file.path(dir, "opaque-array.fgb"), '{"rpst:schema"', '["rpst:schema"'),              # not an object
              patch_all(o1, file.path(dir, "not-rpst.fgb"), '"rpst:', '"xpst:'))                                # a flat object with no rPSTool key
  for (op in opaque) {
    before <- so_fgb_meta(op); oo <- file.path(dir, paste0("oo-", basename(op)))
    angular_integration(segment_graph(op), steps = 3, spatial_output_file = oo)
    expect_identical(so_fgb_meta(oo), before, info = basename(op))   # preserved byte for byte, never extended or corrupted
    expect_identical(so_read(oo, "flatgeobuf")$wkb, so_read(op, "flatgeobuf")$wkb)
    expect_true("integration" %in% so_read(oo, "flatgeobuf")$names)
  }
  expect_length(so_leftovers(dir), 0L)
})
