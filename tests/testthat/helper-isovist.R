rectangle <- function(x,y,size) rbind(c(x,y),c(x,y+size),c(x+size,y+size),c(x+size,y))
isovist_input <- function(kind) {
  empty <- matrix(numeric(),0,2)
  switch(kind,
    empty=list(),
    closed_polygon=list(obstacles=list(list(rbind(rectangle(2,-1,2),c(2,-1))))),
    reversed_polygon=list(obstacles=list(list(rectangle(2,-1,2)[4:1,]))),
    inside_attraction=list(attraction_polygons=list(list(rectangle(-1,-1,2)))),
    world_grouped=lapply(isovist_input("grouped"),function(groups) lapply(groups,function(g) if(is.matrix(g)) g+1e12 else lapply(g,function(x) x+1e12))),
    grouped=list(obstacles=list(list(rectangle(2,-1,2)),list(),list(rectangle(-4,1,1))),
      attraction_points=list(rbind(c(1,0),c(5,0),c(-1,0)),empty,rbind(c(0,2),c(20,20))),
      attraction_polygons=list(list(rectangle(0,3,1)),list(),list(rectangle(-2,-2,1)))),
    empty_groups=list(obstacles=list(list(),list()),attraction_points=list(empty,empty),attraction_polygons=list(list(),list())),
    inside_obstacle=list(obstacles=list(list(rectangle(-1,-1,2)))),
    near_point=list(attraction_points=list(matrix(c(0,0),1,2))),
    straddling_points=list(attraction_points=list(rbind(c(0,0),c(-1,-1),c(1,1)))),
    near_polygon=list(attraction_polygons=list(list(rectangle(.001,-.001,.002)))),
    many_points=list(attraction_points=list(cbind((0:79 %% 10)-5,(0:79 %/% 10)-5),empty,cbind((80:99 %% 10)-5,(80:99 %/% 10)-5))))
}
isovist_call <- function(context, case) isovist(context, (if(is.null(case$origin)) c(0,0) else unlist(case$origin)) + (if(case$geometry=="world_grouped") 1e12 else 0),
  case$distance,case$fov,case$direction,case$resolution)
isovist_life <- function() .Call(rPSTool:::C_rpst_isovist_lifecycle)

# Portability allowance for isovist polygon coordinates ONLY (decision log,
# "Deterministic floating-point evaluation policy"). Supported system `sinf`
# implementations can differ by one binary32 ULP even after FMA contraction and
# libm overload resolution are controlled, so finite polygon coordinates may
# differ from the direct-PST reference by at most one binary32 ULP, on either
# axis independently. Everything else stays exact: dimensions (vertex count),
# vertex order, and non-finite classes (NaN / +Inf / -Inf at the same cells).
# A finite value that is not exactly representable in binary32 gets no
# allowance. Area, visibility groups/indices, failures and lifecycle remain
# compared exactly by the callers.
isovist_f32_key <- function(x) {
  # Unsigned 32-bit pattern as an exact double, built from explicit big-endian
  # bytes. (readBin(..., "integer") is invalid here: -0.0f is 0x80000000, which
  # is R's NA_integer_.) Then the monotonic sign mapping: negative patterns
  # (sign bit set) map to -(pattern - 2^31), so -0.0f and +0.0f both give 0.
  vapply(x, function(v) {
    b <- as.numeric(as.integer(writeBin(v, raw(), size = 4L, endian = "big")))
    pattern <- ((b[1L] * 256 + b[2L]) * 256 + b[3L]) * 256 + b[4L]
    if (pattern >= 2147483648) -(pattern - 2147483648) else pattern
  }, 0)
}
isovist_f32_exact <- function(x) {
  back <- vapply(x, function(v) readBin(writeBin(v, raw(), size = 4L), "numeric", size = 4L), 0)
  back == x
}
isovist_polygon_difference <- function(actual, expected) {
  actual <- unname(actual); expected <- unname(expected)
  if (!is.matrix(actual) || !is.matrix(expected) || !is.double(actual) || !is.double(expected) ||
      !identical(dim(actual), dim(expected))) return("polygon storage or dimensions differ")
  nonfinite <- function(m) ifelse(is.nan(m), "NaN", ifelse(is.na(m), "NA", ifelse(is.infinite(m), ifelse(m > 0, "+Inf", "-Inf"), "")))
  if (!identical(nonfinite(actual), nonfinite(expected))) return("non-finite classes differ")
  fin <- is.finite(actual)
  a <- actual[fin]; e <- expected[fin]
  same <- a == e
  if (all(same)) return(NULL)
  a <- a[!same]; e <- e[!same]
  if (!all(isovist_f32_exact(a)) || !all(isovist_f32_exact(e))) return("finite coordinate differs and is not binary32-representable")
  ulp <- abs(isovist_f32_key(a) - isovist_f32_key(e))
  if (any(ulp > 1)) return(paste0("finite coordinate differs by ", max(ulp), " binary32 ULP (allowance: 1)"))
  NULL
}
expect_isovist_polygon <- function(actual, expected, info = NULL) {
  difference <- isovist_polygon_difference(actual, expected)
  testthat::expect_true(is.null(difference), info = paste(c(info, difference), collapse = ": "))
}
