#!/usr/bin/env Rscript
main <- function() {
  env <- new.env(parent=baseenv())
  sys.source("src/portability/harden-isovist.R",envir=env)
  harden <- env$harden_isovist
  read_bytes <- function(path) readBin(path,"raw",n=file.info(path)$size)
  dir.create(".local",showWarnings=FALSE)
  tmp <- tempfile("isovist-tests-",tmpdir=".local")
  dir.create(tmp);on.exit(unlink(tmp,recursive=TRUE),add=TRUE)
  rejects <- function(expr, message) {
    error <- tryCatch({force(expr);NULL},error=identity)
    stopifnot(inherits(error,"error"),grepl(message,conditionMessage(error),fixed=TRUE))
  }
  for (key in "CalculateIsovists") {
    source <- paste0("inst/upstream/build-inputs/",key,".cpp")
    original <- read_bytes(source)
    output <- file.path(tmp,".rpst-build","analyses",paste0(key,".cpp"))
    harden(source,output);expected <- read_bytes(output)
    harden(source,output);stopifnot(identical(read_bytes(output),expected))
    writeBin(charToRaw("corrupt build state"),output)
    harden(source,output);stopifnot(identical(read_bytes(output),expected))
    input <- file.path(tmp,paste0(key,".cpp"))
    mutations <- list(c(original,charToRaw("\n")),expected,
                      charToRaw(sub("isovist_points.back()","isovist_points.front()",rawToChar(original),fixed=TRUE)),
                      c(original,charToRaw("\n// unrelated drift\n")))
    for (bytes in mutations) {
      writeBin(bytes,input);rejects(harden(input,output),"pinned original checksum")
      stopifnot(identical(read_bytes(output),expected),identical(read_bytes(source),original))
    }
    unlink(output);rejects(harden(input,output),"pinned original checksum")
    stopifnot(!file.exists(output))
    for (pattern in c("if (!m_TempAttrEdgeQueue.empty())",
                      "if (!m_TempAttrPointCalc.empty())")) {
      wrong_pattern <- harden
      body(wrong_pattern) <- parse(text=sub(pattern,"// absent pattern",
        paste(deparse(body(harden)),collapse="\n"),fixed=TRUE))[[1L]]
      rejects(wrong_pattern(source,output),"Expected exactly one original pattern")
      stopifnot(!file.exists(output),identical(read_bytes(source),original))
    }
    wrong_output <- harden
    body(wrong_output) <- parse(text=sub(
      "fd1f956a159c1d136bae53acf75227bc",
      "00000000000000000000000000000000",paste(deparse(body(harden)),collapse="\n"),fixed=TRUE))[[1L]]
    rejects(wrong_output(source,output),"Generated copy or original source failed verification")
    stopifnot(!file.exists(output),!length(list.files(dirname(output))))
    rejects(harden(source,source),"Output must be")
    rejects(harden(source,file.path(tmp,"vendor","pstalgo",".rpst-build",paste0(key,".cpp"))),"Refusing to write into the vendor tree")
    stopifnot(!dir.exists(file.path(tmp,"vendor")))
    if (.Platform$OS.type!="windows") {
      alias <- file.path(tmp,"alias",".rpst-build");dir.create(dirname(alias),recursive=TRUE,showWarnings=FALSE)
      stopifnot(file.symlink(normalizePath("src/vendor/pstalgo"),alias))
      rejects(harden(source,file.path(alias,"forbidden-isovist",paste0(key,".cpp"))),"Refusing to write into the vendor tree")
      stopifnot(!dir.exists("src/vendor/pstalgo/forbidden-isovist"));unlink(alias)
    }
    copy <- paste0("src/.rpst-build/analyses/",key,".cpp")
    saved <- if(file.exists(copy))read_bytes(copy) else NULL
    harden(source,copy)
    sys.source("tools/verify-vendor.R",envir=new.env(parent=baseenv()))
    writeBin(c(expected,charToRaw("\n")),copy)
    rejects(sys.source("tools/verify-vendor.R",envir=new.env(parent=baseenv())),"Unexpected isovist build-copy changes")
    if(is.null(saved))unlink(copy) else writeBin(saved,copy)
  }
  message("Isovist transformations passed: deterministic, checksum/pattern/output/path/symlink/drift rejection; no partial publication")
}
main()
