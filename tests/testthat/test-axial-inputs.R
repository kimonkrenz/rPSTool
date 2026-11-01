axial_native <- function(name, ...) .Call(get(paste0("C_rpst_", name), asNamespace("rPSTool")), ...)
axial_rows <- function(rows, width = 2L) matrix(as.double(unlist(rows)), ncol = width, byrow = TRUE)
axial_vector <- function(values) as.double(unlist(values))
axial_case_graph <- function(case) {
  args <- case[intersect(names(case), c("x", "line_indices", "unlinks", "points",
                                      "points_per_polygon", "polygon_point_interval"))]
  args$x <- axial_rows(args$x, if (is.null(args$line_indices)) 4L else 2L)
  for (field in c("line_indices", "unlinks", "points"))
    if (field %in% names(args)) args[[field]] <- axial_rows(args[[field]])
  if ("points_per_polygon" %in% names(args))
    args$points_per_polygon <- axial_vector(args$points_per_polygon)
  do.call(axial_graph, args)
}
axial_exact_classes <- function(actual, expected) {
  expect_identical(is.na(actual), is.na(expected))
  expect_identical(is.nan(actual), is.nan(expected))
  expect_identical(is.infinite(actual), is.infinite(expected))
  expect_identical(actual[!is.finite(expected)], expected[!is.finite(expected)])
  # Finite native floats can differ by a rounding unit across compilers.
  expect_equal(actual[is.finite(expected)], expected[is.finite(expected)], tolerance = 1e-7)
}

test_that("axial inputs and native inspection match pinned structural oracles", {
  ref <- dget(test_path("fixtures", "axial-inputs-direct-v3.3.2.R"))
  expect_identical(ref$pst_commit, unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  for (case in ref$cases) {
    g <- axial_case_graph(case)
    info <- as.integer(unlist(case$native_info))
    # The exported C API hardcodes zero groups; pinned native storage retains them.
    expect_identical(info[[4L]], 0L)
    info[[4L]] <- length(case$group_sizes)
    expect_identical(axial_native("graph_info", g$ptr), info)
    expect_identical(g$n_point_groups, info[[4L]])
    expect_identical(axial_line_lengths(g), axial_vector(case$lengths))
    expect_identical(unname(axial_crossing_coords(g)), axial_rows(case$crossings))
    expect_identical(colnames(axial_crossing_coords(g)), c("x", "y"))
    state <- axial_native("graph_point_state", g$ptr)
    expect_equal(state[[1L]], axial_rows(case$point_state, 5L), tolerance = 1e-7)
    expect_identical(state[[2L]], as.integer(unlist(case$group_sizes)))
    expect_identical(sum(state[[2L]]), if (length(state[[2L]])) info[[3L]] else 0L)
    # Mutable metadata cannot resize native outputs or reinterpret graph storage.
    g$n_lines <- g$n_points <- g$n_crossings <- g$n_point_groups <- 999L
    expect_identical(axial_line_lengths(g), axial_vector(case$lengths))
    expect_identical(unname(axial_crossing_coords(g)), axial_rows(case$crossings))
    axial_native("graph_release", g$ptr)
  }
})

test_that("junction integration matches direct PST and retains existing line results", {
  ref <- dget(test_path("fixtures", "axial-inputs-direct-v3.3.2.R"))
  for (case in rpst_thin_items(ref$cases, "integrations", every = 4L, by = list(rpst_radius_class))) {
    g <- axial_case_graph(case)
    for (expected in case$integrations) {
      radius <- do.call(analysis_radius, expected$radius)
      result <- rPSTool:::.pst_network_integration_run(g, radius = radius, junctions = TRUE)
      expect_identical(names(result), c("lines", "junctions"))
      expect_identical(result$lines, rPSTool:::.pst_network_integration_run(g, radius = radius))
      expect_identical(result$lines$line_id, seq_along(expected$scores))
      expect_identical(result$lines$node_count, as.integer(unlist(expected$counts)))
      axial_exact_classes(result$lines$integration, axial_vector(expected$scores))
      expect_identical(result$lines$total_depth, axial_vector(expected$depths))
      expect_identical(result$junctions$junction_id, seq_along(expected$junction_scores))
      expect_type(result$junctions$x, "double")
      expect_type(result$junctions$y, "double")
      actual_coords <- matrix(c(result$junctions$x, result$junctions$y), ncol=2L)
      expect_identical(actual_coords, axial_rows(expected$junction_coords))
      axial_exact_classes(result$junctions$integration, axial_vector(expected$junction_scores))
      expect_identical(result, rPSTool:::.pst_network_integration_run(g, radius = radius, junctions = TRUE))
    }
    axial_native("graph_release", g$ptr)
  }
})

test_that("fresh junction seeds preserve native small-neighbourhood and multiplicity semantics", {
  chain <- cbind(0:4*3, 0, 1:5*3, 0)
  g <- axial_graph(chain)
  # nLines is the number of pairwise crossing records in this constructor.
  # At a two-line join it is 1; PST adds both -1 scores divided by 1.
  expect_identical(network_integration(g, steps=0, junctions=TRUE)$junctions$integration, rep(-2,4))
  out <- network_integration(g, steps=1, junctions=TRUE)
  expect_true(all(is.nan(out$junctions$integration[c(1,4)])))
  expect_identical(out$junctions$integration[2:3], c(Inf,Inf))
  before <- network_integration(g, junctions=TRUE)
  for (i in 1:10) {
    network_integration(g, steps=0, junctions=TRUE)
    expect_identical(network_integration(g, junctions=TRUE), before)
  }
  s <- axial_graph(matrix(c(0,0,1,0),1))
  empty <- network_integration(s, junctions=TRUE)$junctions
  expect_identical(nrow(empty),0L)
  expect_identical(vapply(empty,typeof,""), c(junction_id="integer",x="double",y="double",integration="double"))
  expect_identical(dim(axial_crossing_coords(s)),c(0L,2L))
})

test_that("all constructor inputs validate storage and shape at the native boundary", {
  lines <- rbind(c(0,0,2,0),c(1,-1,1,1))
  create <- function(x=lines,line_indices=NULL,unlinks=NULL,points=NULL,
                     points_per_polygon=NULL,polygon_point_interval=NULL)
    axial_native("graph_create_inputs",x,line_indices,unlinks,points,points_per_polygon,polygon_point_interval)
  for (value in list(TRUE,"a",1+1i,list(0),new("externalptr"),1:2,matrix(1,1,3))) {
    for (field in c("unlinks","points","line_indices")) {
      args <- setNames(list(value),field)
      expect_error(do.call(axial_graph,c(list(x=lines),args)), "matrix|columns")
      expect_error(do.call(create,args), "matrix|columns")
    }
  }
  coords <- rbind(c(0,0),c(2,0),c(1,-1),c(1,1))
  ids <- rbind(c(1,2),c(3,4))
  for (v in c(0,-1,1.5,5,NA_real_,NaN,Inf,-Inf,2147483648)) {
    bad <- ids; bad[1,1] <- v
    expect_error(axial_graph(coords,bad), "indices|finite")
    expect_error(create(coords,bad), "indices|finite")
  }
  expect_error(create(coords,matrix(numeric(),0,2)), "at least one")
  for (v in c(NA_real_,NaN,Inf,-Inf)) {
    bad <- matrix(c(v,0),1)
    for (field in c("unlinks","points")) {
      args <- setNames(list(bad),field)
      expect_error(do.call(create,args), "finite")
      expect_error(do.call(axial_graph,c(list(x=lines),args)), "finite")
    }
  }
  for (field in c("unlinks","points")) {
    for (bad in list(matrix(c(1e100,0),1),matrix(c(1e20,0),1)))
      expect_error(do.call(create,setNames(list(bad),field)), "overflows PST")
  }
  expect_error(create(rbind(c(0,0),c(2,0),c(-4e38,0)),
                      matrix(c(1,2),1)), "overflows PST")
  # Opposite supplied points share the constructor's network bbox (unlike Reach origins).
  expect_error(create(points=rbind(c(-1e19,0),c(1e19,0))),"overflows PST")
  for (storage in list(coords, matrix(as.integer(coords),ncol=2),
                       structure(as.double(1:8),dim=c(4L,2L)))) {
    g <- axial_graph(storage, matrix(as.double(1:4),ncol=2),
                   unlinks=matrix(numeric(),0,2),points=matrix(numeric(),0,2))
    expect_identical(g$n_lines,2L)
    axial_native("graph_release",g$ptr)
  }
})

test_that("polygon layouts and sampling are bounded before entering native generation", {
  x <- matrix(c(0,0,3,0),1)
  points <- rbind(c(0,1),c(2,1),c(2,2),c(0,2))
  construct <- function(sizes=4,interval=1,p=points)
    axial_native("graph_create_inputs",x,NULL,NULL,p,sizes,interval)
  for (sizes in list(NULL,TRUE,"4",4+1i,numeric(),c(1,2),5,-1,1.5,NA_real_,Inf,NaN,
                     c(0,Inf),matrix(4,1),array(4,c(1,1,1)),new("externalptr")))
    expect_error(construct(sizes), "points_per_polygon|sum|requires")
  for (interval in list(NULL,TRUE,"1",1+1i,numeric(),c(1,2),0,-1,NA_real_,NaN,Inf,-Inf,1e100,1e-100)) {
    expect_error(construct(interval=interval),"polygon_point_interval")
    expect_error(axial_graph(x,points=points,points_per_polygon=4,polygon_point_interval=interval),"polygon_point_interval")
  }
  expect_error(construct(interval=1e-12),"signed point-count")
  expect_error(construct(p=rbind(c(NA_real_,NA_real_),c(1,1),c(1,2),c(0,2))),"finite")
  expect_error(construct(p=rbind(c(NaN,0),c(1,1),c(1,2),c(0,2))),"finite")
  g <- axial_graph(x,points=points,points_per_polygon=c(0L,4L,0L),polygon_point_interval=1L)
  expect_identical(g$n_point_groups,3L)
  expect_identical(axial_native("graph_point_state",g$ptr)[[2L]],c(0L,6L,0L))
  expect_error(axial_graph(x,polygon_point_interval=1),"requires")
})

test_that("owners keep no construction inputs and inspection outputs survive graph disposal", {
  gc(); before <- axial_native("graph_lifecycle")
  build <- function() {
    coords <- rbind(c(0,0),c(2,0),c(1,-1),c(1,1))
    indices <- rbind(c(1,2),c(3,4))
    points <- rbind(c(0.3,1),c(1.7,0.2))
    g <- axial_graph(coords,indices,points=points,points_per_polygon=c(1,1),polygon_point_interval=1)
    coords[] <- 99; indices[] <- 1; points[] <- -99
    g
  }
  g <- build(); alias <- g
  state <- axial_native("graph_point_state",g$ptr)
  expect_equal(state[[1L]][,1:2],rbind(c(0.3,1),c(1.7,0.2)),tolerance=1e-7)
  expect_identical(sort(names(g)),sort(c("ptr","type","n_lines","n_crossings","n_points","n_point_groups","pst_version")))
  lengths <- axial_line_lengths(g); coords <- axial_crossing_coords(g)
  result <- network_integration(g,junctions=TRUE)
  rm(g); gc()
  expect_identical(network_integration(alias,junctions=TRUE),result)
  expect_identical(axial_native("graph_lifecycle")-before,c(1,0,1))
  axial_native("graph_release",alias$ptr); axial_native("graph_release",alias$ptr)
  rm(alias); gc()
  expect_identical(axial_native("graph_lifecycle")-before,c(1,1,0))
  expect_identical(lengths,c(2,2))
  expect_identical(unname(coords),matrix(c(1,0),1))
  expect_identical(result$lines$node_count,c(2L,2L))
  expect_identical(state[[2L]],c(1L,1L))
  before <- axial_native("graph_lifecycle")
  for (i in 1:40) {
    g <- build()
    if (i %% 2L) axial_native("graph_release",g$ptr)
    rm(g)
  }
  gc(); expect_identical(axial_native("graph_lifecycle")-before,c(40,40,0))
  expect_error((function() { g <- build(); stop("after acquisition") })(),"after acquisition")
  gc(); expect_identical(axial_native("graph_lifecycle")-before,c(41,41,0))
  before <- axial_native("graph_lifecycle")
  for (i in 1:10) expect_error(axial_graph(matrix(c(0,0,1,0),1),points=matrix(c(1e100,0),1)),"overflows")
  gc(); expect_identical(axial_native("graph_lifecycle"),before)
})

test_that("graph outputs enforce exact tags, liveness and junction flag storage", {
  g <- axial_graph(rbind(c(0,0,2,0),c(1,-1,1,1)))
  s <- segment_graph(matrix(c(0,0,1,0),1))
  group <- segment_group_graph(s,1L)
  for (ptr in list(NULL,1,new("externalptr"),s$ptr,group$ptr)) {
    for (name in c("graph_line_lengths","graph_crossing_coords","graph_point_state"))
      expect_error(axial_native(name,ptr),"Invalid pst_graph")
    expect_error(axial_native("network_integration_outputs",ptr,NULL,TRUE),"Invalid pst_graph")
  }
  for (obj in list(s,group,list(),NULL)) {
    expect_error(axial_line_lengths(obj),"live axial")
    expect_error(axial_crossing_coords(obj),"live axial")
  }
  for (flag in list(NULL,1L,0,"TRUE",NA,c(TRUE,FALSE),logical(),1+1i)) {
    expect_error(network_integration(g,junctions=flag),"junctions")
    expect_error(axial_native("network_integration_outputs",g$ptr,NULL,flag),"junctions")
  }
  restored <- unserialize(serialize(g,NULL))
  for (obj in list(restored,g)) {
    if (identical(obj,g)) axial_native("graph_release",g$ptr)
    expect_error(axial_line_lengths(obj),"no longer live")
    expect_error(axial_crossing_coords(obj),"no longer live")
    expect_error(network_integration(obj,junctions=TRUE),"no longer live")
    expect_error(axial_native("graph_point_state",obj$ptr),"no longer live")
  }
})
