test_that("one central fail-closed policy controls all exposed worker engines", {
  variables <- c("RPST_NUM_THREADS","_R_CHECK_LIMIT_CORES_")
  original <- Sys.getenv(variables,unset=NA_character_)
  on.exit(for (v in variables) {
    if (is.na(original[[v]])) Sys.unsetenv(v)
    else do.call(Sys.setenv,setNames(list(original[[v]]),v))
  })
  Sys.unsetenv(variables)
  hardware <- .Call(rPSTool:::C_rpst_workers)
  expect_gte(hardware,1)
  Sys.setenv("_R_CHECK_LIMIT_CORES_"="true")
  expect_identical(.Call(rPSTool:::C_rpst_workers),min(2,hardware))
  # Check-cap policy (R's convention: unset/empty/"false" in any case = inactive; any other value, e.g. "TRUE"
  # or "warn", = active). When active it is a ceiling of two: a stricter explicit cap still applies, a larger
  # one cannot lift it. Without it an explicit cap and the hardware fallback are unchanged.
  active <- c("true","TRUE","True","warn","WARN","1","yes","falsey","fals"," false","false ")
  inactive <- c("false","FALSE","False","fAlSe")
  explicit <- c(NA,"1","2","3","64","4294967295")
  for (check in c(active,inactive,NA,if (.Platform$OS.type != "windows") "")) {
    for (cap in explicit) {
      Sys.unsetenv(variables)
      if (!is.na(check)) Sys.setenv("_R_CHECK_LIMIT_CORES_"=check)
      if (!is.na(cap)) Sys.setenv(RPST_NUM_THREADS=cap)
      limit <- if (is.na(cap)) hardware else min(as.double(cap),hardware)
      is_active <- !is.na(check) && check %in% active
      expected <- if (is_active) min(limit,2) else limit
      expect_identical(.Call(rPSTool:::C_rpst_workers),expected,info=paste(check,cap))
    }
  }
  # malformed explicit limits stay fail-closed even when the check cap is active
  Sys.setenv("_R_CHECK_LIMIT_CORES_"="TRUE",RPST_NUM_THREADS="0")
  expect_error(.Call(rPSTool:::C_rpst_workers),"RPST_NUM_THREADS")
  Sys.unsetenv(variables)
  Sys.setenv("_R_CHECK_LIMIT_CORES_"="true")
  Sys.setenv(RPST_NUM_THREADS="3")
  expect_identical(.Call(rPSTool:::C_rpst_workers),min(2,hardware))
  a <- axial_graph(cbind(0:4*3,0,1:5*3,0));s <- segment_graph(cbind(0:4*3,0,1:5*3,0))
  base <- list(network_betweenness(a),angular_choice(s),angular_integration(s))
  for (cap in c("1","2","4294967295")) {
    Sys.setenv(RPST_NUM_THREADS=cap)
    expect_identical(.Call(rPSTool:::C_rpst_workers),min(as.double(cap),hardware,2))
    result <- list(network_betweenness(a),angular_choice(s),angular_integration(s))
    expect_identical(result,base)
  }
  # Windows R's Sys.setenv(name="") removes the variable via _putenv;
  # POSIX retains a present empty string. Test the actual platform contract.
  Sys.setenv(RPST_NUM_THREADS="")
  if (.Platform$OS.type == "windows")
    expect_identical(.Call(rPSTool:::C_rpst_workers),min(2,hardware))
  else expect_error(.Call(rPSTool:::C_rpst_workers),"RPST_NUM_THREADS")
  bad_limits <- c("0","-1","1.5","2x"," 2","4294967296")
  if (.Platform$OS.type != "windows") bad_limits <- c("",bad_limits)
  for (bad in bad_limits) {
    Sys.setenv(RPST_NUM_THREADS=bad)
    expect_error(.Call(rPSTool:::C_rpst_workers),"RPST_NUM_THREADS")
    expect_error(network_betweenness(a),"RPST_NUM_THREADS")
    expect_error(angular_choice(s),"RPST_NUM_THREADS")
    expect_error(angular_integration(s),"RPST_NUM_THREADS")
    expect_identical(network_reach(a)$reached_count,rep(5L,5))
    expect_identical(network_integration(a)$node_count,rep(5L,5))
  }
})
