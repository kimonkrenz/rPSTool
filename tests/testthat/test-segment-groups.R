group_native <- function(operation, ...) {
  .Call(get(paste0("C_rpst_segment_group_", operation), envir = asNamespace("rPSTool")), ...)
}
group_fixture <- function() dget(file.path("fixtures", "segment-groups-direct-v3.3.2.R"))
group_chain <- function(n = 5L) cbind(0:(n - 1L) * 3, 0, 1:n * 3, 0)

expect_group_values <- function(actual, expected) {
  expected <- as.double(expected)
  # Distinguish adopted NA from a genuinely written native NaN.
  expect_identical(is.na(actual) & !is.nan(actual), is.na(expected) & !is.nan(expected))
  expect_identical(is.nan(actual), is.nan(expected))
  expect_identical(is.infinite(actual), is.infinite(expected))
  expect_equal(actual, expected, tolerance = 1e-7)
}

test_that("grouping structures and integration values match direct pinned PST", {
  reference <- group_fixture()
  expect_identical(reference$pst_commit, "63df80a2cf3dd289be95ea3d91667c3490719b75")
  segments <- lapply(reference$networks, function(rows) segment_graph(do.call(rbind, rows)))
  for (case in rpst_cases(reference$groupings, every = 5L, by = list(rpst_case_signature), each = list(rpst_case_edges))) {
    result <- segment_grouping(segments[[case$network]], case$angle, case$split)
    expect_identical(names(result), c("segment_id", "group_id", "color"))
    expect_identical(result$segment_id, seq_along(case$ids))
    expect_identical(result$group_id, as.integer(case$ids))
    expect_identical(result$color, as.integer(case$colors))
    expect_identical(attr(result, "n_groups"), as.integer(case$n_groups))
    expect_identical(attr(result, "n_colors"), as.integer(case$n_colors))
  }
  for (case in rpst_cases(reference$integrations, every = 20L, by = list(rpst_case_signature), each = list(rpst_case_edges))) {
    g <- segment_group_graph(segments[[case$network]], case$ids)
    result <- segment_group_integration(g, do.call(analysis_radius, case$radius))
    expect_identical(names(result), c("group_id", "integration", "node_count", "total_depth"))
    expect_identical(result$group_id, seq_along(case$integration))
    expect_identical(result$node_count, as.integer(case$node_count))
    expect_group_values(result$integration, case$integration)
    expect_group_values(result$total_depth, case$total_depth)
    group_native("graph_release", g$ptr)
  }
})

test_that("whole no-node graphs return typed NA while mixed isolated groups retain writes", {
  networks <- list(group_chain(), rbind(c(0,0,1,0)),
                   rbind(c(0,0,1,0), c(5,0,6,0)),
                   rbind(c(0,0,1,0), c(1,0,1,1), c(1,1,0,1), c(0,1,0,0)))
  for (x in networks) {
    s <- segment_graph(x)
    for (split in c(FALSE, TRUE)) {
      grouping <- segment_grouping(s, 90, split)
      g <- segment_group_graph(s, grouping$group_id)
      for (radius in list(analysis_radius(), analysis_radius(steps=0), analysis_radius(walking=0))) {
        r <- segment_group_integration(g, radius)
        n <- g$n_groups
        expect_identical(r$integration, rep(NA_real_, n))
        expect_identical(r$node_count, rep(NA_integer_, n))
        expect_identical(r$total_depth, rep(NA_real_, n))
      }
    }
  }
  # Three connected singleton groups plus a group with no native nodes.
  s <- segment_graph(rbind(group_chain(3), c(10,0,11,0)))
  for (ids in list(1:4, 4:1)) {
    g <- segment_group_graph(s, ids)
    r <- segment_group_integration(g)
    isolated <- ids[[4L]]
    expect_identical(r$integration[[isolated]], -1)
    expect_identical(r$node_count[[isolated]], 0L)
    expect_identical(r$total_depth[[isolated]], 0)
    expect_false(anyNA(r))
  }
})

test_that("connected controls retain PST finite, NaN, Inf and small-neighbourhood values", {
  s <- segment_graph(group_chain(3))
  g <- segment_group_graph(s, 1:3)
  unlimited <- segment_group_integration(g)
  expect_identical(unlimited$node_count, rep(3L, 3))
  expect_identical(unlimited$total_depth, c(3, 2, 3))
  expect_true(all(is.finite(unlimited$integration[c(1,3)])))
  expect_identical(unlimited$integration[[2L]], Inf)
  restricted <- segment_group_integration(g, analysis_radius(steps=1))
  expect_identical(is.nan(restricted$integration), c(TRUE, FALSE, TRUE))
  expect_identical(restricted$integration[[2L]], Inf)
  expect_false(any(is.na(restricted$integration) & !is.nan(restricted$integration)))
  zero <- segment_group_integration(g, analysis_radius(steps=0))
  expect_identical(zero$integration, rep(-1, 3))
  expect_identical(zero$node_count, rep(1L, 3))
  expect_identical(zero$total_depth, rep(0, 3))
  # Transcribe the pinned five-singleton-group chain's diagnostic expectations.
  g <- segment_group_graph(segment_graph(group_chain()), 1:5)
  r <- segment_group_integration(g)
  expect_identical(r$node_count, rep(5L, 5))
  expect_identical(r$total_depth, c(10, 7, 6, 7, 10))
})

test_that("production conversion uses diagnostic masks, never an integration sentinel", {
  convert <- function(score, count, depth) group_native("output_test", score, count, depth)
  for (seed in c(17, 29, -Inf, Inf, NaN, NA_real_)) {
    r <- convert(c(seed, -1, 0, NaN, Inf), c(NA_integer_, 0L, 1L, 2L, 3L), c(-Inf,0,0,1,2))
    expect_identical(r[[1L]], c(NA_real_, -1, 0, NaN, Inf))
    expect_identical(r[[2L]], c(NA_integer_, 0L, 1L, 2L, 3L))
    expect_identical(r[[3L]], c(NA_real_,0,0,1,2))
  }
  expect_error(convert(c(1,2), c(1L,NA_integer_), c(0,0)), "write masks are inconsistent")
  expect_error(convert(c(1,2), c(1L,0L), c(0,-Inf)), "write masks are inconsistent")
  expect_error(convert(1, 2L, 0), "invalid group node count")
  expect_error(convert(1L, 1L, 0), "double/integer/double")
  expect_error(convert(1e308, 1L, 0), "native float range")
  expect_error(convert(1, 1L, -1e308), "native float range")
})

test_that("grouping and group IDs validate native storage before PST access", {
  s <- segment_graph(group_chain(3))
  for (x in list(NULL, numeric(), c(1,2), TRUE, "1", 1+1i, NA_real_,
                 NaN, Inf, -Inf, -1, 1e100, 1e-100)) {
    expect_error(segment_grouping(s, x), "angle_threshold")
    expect_error(.Call(rPSTool:::C_rpst_segment_grouping,s$ptr,x,FALSE), "angle_threshold")
  }
  for (x in list(NULL, 0, 1L, NA, c(TRUE,FALSE), "TRUE")) {
    expect_error(segment_grouping(s, split_at_junctions=x), "split_at_junctions")
    expect_error(.Call(rPSTool:::C_rpst_segment_grouping,s$ptr,1,x), "split_at_junctions")
  }
  expect_identical(segment_grouping(s,180)$group_id, segment_grouping(s,181)$group_id)
  expect_identical(segment_grouping(s,1L)$group_id, rep(1L,3))
  for (x in list(NULL, numeric(), c(1,2), c(TRUE,FALSE,TRUE), rep("1",3),
                 rep(1+1i,3), c(1,NA,2), c(1,NA_integer_,2), c(1,NaN,2),
                 c(1,Inf,2), c(1,-Inf,2), c(0,1,2), c(-1,1,2),
                 c(1,1.5,2), c(1,2,4), c(1,2,2147483648),
                 matrix(1:3,1), array(1:3,c(1,1,3)))) {
    expect_error(segment_group_graph(s,x), "group_id")
    expect_error(group_native("graph_create",s$ptr,x), "group_id")
  }
  # ALTREP IDs, names, integer/double input and caller labels remain unchanged.
  g <- segment_group_graph(s, setNames(as.double(3:1), letters[1:3]))
  expect_identical(g$n_groups,3L)
  g$n_groups <- 999L; g$type <- "axial"; g$pst_version <- "wrong"
  expect_output(print(g), "3 groups")
  expect_identical(segment_group_integration(g)$group_id,1:3)
  expect_identical(segment_group_graph(s,1:3)$n_groups,3L)
  gap <- segment_group_graph(s,c(1,3,3))
  gap_result <- segment_group_integration(gap)
  expect_identical(gap_result$integration[[2L]],-1)
  expect_identical(gap_result$node_count[[2L]],0L)
  expect_identical(gap_result$total_depth[[2L]],0)
  s$n_segments <- 999L
  expect_identical(segment_group_graph(s,1:3)$n_groups,3L)
  gap <- segment_group_graph(s,c(1,3,3))
  gap_result <- segment_group_integration(gap)
  expect_identical(gap_result$integration[[2L]],-1)
  expect_identical(gap_result$node_count[[2L]],0L)
  expect_identical(gap_result$total_depth[[2L]],0)
  expect_error(segment_group_graph(s,rep(1L,999)),"native segment")
})

test_that("graph families, radii, dead and deserialised pointers are enforced", {
  s <- segment_graph(group_chain(3)); a <- axial_graph(group_chain(3))
  g <- segment_group_graph(s,1:3)
  for (ptr in list(NULL,1,new("externalptr"),s$ptr,a$ptr)) {
    expect_error(group_native("graph_info",ptr),"Invalid pst_segment_group_graph")
    expect_error(group_native("graph_release",ptr),"Invalid pst_segment_group_graph")
    expect_error(group_native("integration",ptr,analysis_radius()),"Invalid pst_segment_group_graph")
  }
  for (ptr in list(NULL,1,new("externalptr"),a$ptr,g$ptr)) {
    expect_error(.Call(rPSTool:::C_rpst_segment_grouping,ptr,1,FALSE),"Invalid pst_segment_graph")
    expect_error(group_native("graph_create",ptr,1:3),"Invalid pst_segment_graph")
  }
  expect_error(segment_grouping(g),"pst_segment_graph")
  expect_error(segment_group_graph(a,1:3),"pst_segment_graph")
  expect_error(segment_group_integration(s),"pst_segment_group_graph")
  expect_error(segment_group_integration(list()),"pst_segment_group_graph")
  for (field in c("straight","angular","axmeter")) {
    radius <- do.call(analysis_radius,setNames(list(1),field))
    expect_error(segment_group_integration(g,radius),"only walking and steps")
    expect_error(group_native("integration",g$ptr,radius),"only walking and steps")
  }
  expect_error(group_native("integration",g$ptr,list()),"analysis_radius")
  bad <- analysis_radius(); bad$steps <- 1.5
  expect_error(group_native("integration",g$ptr,bad),"whole number")
  restored <- unserialize(serialize(g,NULL))
  expect_error(print(restored),"no longer live")
  expect_error(segment_group_integration(restored),"no longer live")
  group_native("graph_release",restored$ptr)
  group_native("graph_release",restored$ptr)
  expect_output(print(g),"3 groups")
  group_native("graph_release",g$ptr); group_native("graph_release",g$ptr)
  expect_error(segment_group_integration(g),"no longer live")
  .Call(rPSTool:::C_rpst_segment_graph_release,s$ptr)
  expect_error(segment_grouping(s),"no longer live")
  expect_error(segment_group_graph(s,1:3),"no longer live")
})

test_that("group owner outlives source graph/input and is freed exactly once", {
  gc(); before <- group_native("graph_lifecycle")
  s <- segment_graph(group_chain()); ids <- 1:5
  g <- segment_group_graph(s,ids); alias <- g
  expected <- segment_group_integration(g)
  .Call(rPSTool:::C_rpst_segment_graph_release,s$ptr)
  ids[] <- 1L; rm(s,ids,g); gc()
  expect_identical(segment_group_integration(alias),expected)
  expect_identical(group_native("graph_lifecycle")-before,c(1,0,1))
  expect_output(print(alias),"5 groups")
  rm(alias); gc()
  expect_identical(group_native("graph_lifecycle")-before,c(1,1,0))
  expect_identical(expected$node_count,rep(5L,5))
  for (i in seq_len(80L)) {
    s <- segment_graph(group_chain(3)); ids <- 1:3
    g <- segment_group_graph(s,ids)
    .Call(rPSTool:::C_rpst_segment_graph_release,s$ptr)
    expect_identical(segment_group_integration(g)$node_count,rep(3L,3))
    if (i %% 2L == 0L) {
      group_native("graph_release",g$ptr); group_native("graph_release",g$ptr)
    }
    rm(g,s,ids)
    if (i %% 10L == 0L) gc()
  }
  gc(); expect_identical(group_native("graph_lifecycle")-before,c(81,81,0))
  s <- segment_graph(group_chain(3))
  for (i in seq_len(20L)) expect_error(segment_group_graph(s,c(1,4,4)),"1..n_segments")
  gc(); expect_identical(group_native("graph_lifecycle")-before,c(81,81,0))
  fail_after_create <- function() {
    ptr <- group_native("graph_create",s$ptr,1:3)
    stop("deliberate error after group acquisition")
  }
  expect_error(fail_after_create(),"after group acquisition")
  gc(); expect_identical(group_native("graph_lifecycle")-before,c(82,82,0))
})

test_that("central worker policy controls connected and no-node group integration", {
  original <- Sys.getenv("RPST_NUM_THREADS",unset=NA_character_)
  on.exit(if (is.na(original)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS=original))
  s <- segment_graph(group_chain())
  connected <- segment_group_graph(s,1:5); no_nodes <- segment_group_graph(s,rep(1L,5))
  Sys.setenv(RPST_NUM_THREADS="1")
  base <- segment_group_integration(connected)
  for (cap in c("1","2","4294967295")) {
    Sys.setenv(RPST_NUM_THREADS=cap)
    expect_identical(segment_group_integration(connected),base)
    expect_identical(segment_group_integration(no_nodes)$node_count,NA_integer_)
  }
  for (bad in c("0","-1","1.5","2x"," 2","4294967296")) {
    Sys.setenv(RPST_NUM_THREADS=bad)
    expect_error(segment_group_integration(connected),"RPST_NUM_THREADS")
    expect_error(segment_group_integration(no_nodes),"RPST_NUM_THREADS")
    expect_identical(segment_grouping(s)$group_id,rep(1L,5))
  }
})

test_that("a segment graph with a zero-length segment is rejected before the native group-graph construction", {
  # PST's CSegmentGroupGraph::Create does not terminate on a zero-length segment that shares a coordinate (SegmentGroupGraph.cpp:203-254).
  s <- segment_graph(rbind(c(0, 0, 0, 0), c(0, 0, 1, 0)))
  expect_s3_class(s, "pst_segment_graph")                       # construction and the other analyses stay supported
  expect_error(segment_group_graph(s, 1:2), "zero-length segments \\(1 found")
  expect_error(segment_group_graph(s, segment_grouping(s)$group_id), "zero-length")
  expect_error(group_native("graph_create", s$ptr, 1:2), "zero-length")
  expect_s3_class(angular_choice(s), "data.frame")
  ok <- segment_graph(rbind(c(0, 0, 1, 0), c(1, 0, 2, 0)))       # non-degenerate graphs are unaffected
  expect_s3_class(segment_group_graph(ok, 1:2), "pst_segment_group_graph")
  expect_error(segment_grouping(list()), "created by segment_graph\\(\\)")
  expect_error(segment_group_integration(list()), "created by segment_group_graph\\(\\)")
})
