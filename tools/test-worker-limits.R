#!/usr/bin/env Rscript
main <- function() {
  env <- new.env(parent=baseenv())
  sys.source("src/portability/limit-workers.R",envir=env)
  transform <- env$limit_workers
  bytes <- function(path) readBin(path,"raw",n=file.info(path)$size)
  dir.create(".local",showWarnings=FALSE)
  tmp <- tempfile("worker-transform-",tmpdir=".local")
  dir.create(tmp)
  on.exit(unlink(tmp,recursive=TRUE))
  rejects <- function(expr,pattern) {
    e <- tryCatch({force(expr);NULL},error=identity)
    stopifnot(inherits(e,"error"),grepl(pattern,conditionMessage(e),fixed=TRUE))
  }
  for (name in c("AngularChoiceAlgo","SegmentBetweenness","SegmentGroupIntegration","AttractionReach","AttractionDistance","ODBetweenness")) {
    worker_pattern <- if (name == "SegmentGroupIntegration") "thread::hardware_concurrency()" else "std::thread::hardware_concurrency()"
    if (name == "ODBetweenness") worker_pattern <- "workers.resize(1);"
    input <- paste0("inst/upstream/build-inputs/",name,".cpp")
    original <- bytes(input)
    output <- file.path(tmp,".rpst-build",paste0(name,".cpp"))
    transform(input,output);expected <- bytes(output)
    transform(input,output);stopifnot(identical(bytes(output),expected))
    writeBin(charToRaw("corrupt output"),output)
    transform(input,output);stopifnot(identical(bytes(output),expected))
    mutant <- file.path(tmp,paste0(name,".cpp"))
    for (mutation in list(c(original,charToRaw("\n// drift")),expected,
        charToRaw(gsub(worker_pattern,"1u",rawToChar(original),fixed=TRUE)))) {
      writeBin(mutation,mutant)
      rejects(transform(mutant,output),"pinned original checksum")
      stopifnot(identical(bytes(output),expected))
    }
    rejects(transform(input,input),"Output must be")
    rejects(transform(input,file.path(tmp,"vendor","pstalgo",".rpst-build",paste0(name,".cpp"))),"Refusing to write into the vendor tree")
    stopifnot(!dir.exists(file.path(tmp,"vendor")),identical(bytes(input),original))
    missing <- transform
    body(missing) <- parse(text=sub('old <- worker_calls[[key]]', 'old <- "missing_call()"',paste(deparse(body(transform)),collapse="\n"),fixed=TRUE))[[1L]]
    rejects(missing(input,output),"Expected exactly one original pattern")
    wrong <- transform
    checksum <- unname(tools::md5sum(output))
    body(wrong) <- parse(text=sub(checksum,"00000000000000000000000000000000",paste(deparse(body(transform)),collapse="\n"),fixed=TRUE))[[1L]]
    rejects(wrong(input,output),"Generated copy or original source failed verification")
    stopifnot(identical(bytes(output),expected))
    unlink(output);transform(input,output);stopifnot(identical(bytes(output),expected))
    # Verify existing generated drift without repairing it.
    copy <- paste0("src/.rpst-build/analyses/",name,".cpp")
    saved <- if (file.exists(copy)) bytes(copy) else NULL
    local({
      on.exit(if (is.null(saved)) unlink(copy) else writeBin(saved,copy))
      transform(input,copy)
      sys.source("tools/verify-vendor.R",envir=new.env(parent=baseenv()))
      writeBin(c(expected,charToRaw("\n// corrupted generated copy")),copy)
      rejects(sys.source("tools/verify-vendor.R",envir=new.env(parent=baseenv())),"Unexpected worker build-copy changes")
      stopifnot(identical(bytes(copy),c(expected,charToRaw("\n// corrupted generated copy"))))
    })
    if (.Platform$OS.type!="windows") {
      alias <- file.path(tmp,".rpst-build")
      unlink(alias,recursive=TRUE)
      stopifnot(file.symlink(normalizePath("src/vendor/pstalgo"),alias))
      rejects(transform(input,file.path(alias,"forbidden-worker-dir",paste0(name,".cpp"))),"Refusing to write into the vendor tree")
      stopifnot(!dir.exists("src/vendor/pstalgo/forbidden-worker-dir"))
      unlink(alias)
    }
  }
  message("Worker transformations passed: deterministic output, drift/checksum/pattern rejection, safe publication, path/symlink rejection")
}
main()
