#!/usr/bin/env Rscript
main <- function() {
  env <- new.env(parent=baseenv())
  sys.source("src/portability/harden-raster.R",envir=env)
  harden <- env$harden_raster
  read_bytes <- function(path) readBin(path,"raw",n=file.info(path)$size)
  dir.create("work",showWarnings=FALSE)
  tmp <- tempfile("raster-safety-",tmpdir="work")
  dir.create(tmp);on.exit(unlink(tmp,recursive=TRUE),add=TRUE)
  rejects <- function(expr,pattern) {
    err <- tryCatch({force(expr);NULL},error=identity)
    if (!inherits(err,"error") || !grepl(pattern,conditionMessage(err),fixed=TRUE)) stop("Expected ",pattern,"; got ",if(is.null(err)) "success" else conditionMessage(err))
  }
  for (key in c("CreateBufferPolygons.cpp","Raster.cpp","Blur.cpp","Arr2d.h")) {
    original <- file.path("inst/upstream/build-inputs",key)
    bytes <- read_bytes(original)
    output <- file.path(tmp,".rpst-build",key)
    harden(original,output);expected <- read_bytes(output)
    harden(original,output);stopifnot(identical(expected,read_bytes(output)))
    writeBin(charToRaw("corrupt generated state"),output)
    harden(original,output);stopifnot(identical(expected,read_bytes(output)))
    input <- file.path(tmp,key)
    for (mutation in list(c(bytes,charToRaw("\n")),expected,bytes[-1L])) {
      writeBin(mutation,input)
      rejects(harden(input,output),"pinned original checksum")
      stopifnot(identical(expected,read_bytes(output)),identical(bytes,read_bytes(original)))
    }
    unlink(output)
    rejects(harden(input,output),"pinned original checksum");stopifnot(!file.exists(output))
    # Bypass only the checksum in an owned clone to exercise pattern gates
    # independently, including the approved normalization operation.
    unchecked <- harden
    body(unchecked) <- parse(text=sub(
      "!identical(unname(tools::md5sum(source_file)), original_md5)", "FALSE",
      paste(deparse(body(harden),width.cutoff=500L),collapse="\n"),fixed=TRUE))[[1L]]
    pattern <- switch(key,
      "CreateBufferPolygons.cpp"="std::max(abs(min), abs(max))",
      "Raster.cpp"="\t\tm_Bits = malloc(m_Pitch * m_Height);",
      "Blur.cpp"="task.wait();", "Arr2d.h"="\t\t\tvoid* rowBuffer = malloc(strideBytes);")
    for (text in c(sub(pattern,"absent pattern",rawToChar(bytes),fixed=TRUE),
                   paste0(rawToChar(bytes),pattern))) {
      writeBin(charToRaw(text),input)
      rejects(unchecked(input,output),"Expected exactly one original pattern")
      stopifnot(!file.exists(output))
    }
    wrong <- harden
    body(wrong) <- parse(text=sub("hardened_md5 <- spec$hardened",
      'hardened_md5 <- "00000000000000000000000000000000"',
      paste(deparse(body(harden),width.cutoff=500L),collapse="\n"),fixed=TRUE))[[1L]]
    rejects(wrong(original,output),"Generated copy or original source failed verification")
    stopifnot(!file.exists(output),!length(list.files(dirname(output))))
    rejects(harden(original,original),"Output must be")
    forbidden <- file.path(tmp,"vendor","pstalgo",".rpst-build",key)
    rejects(harden(original,forbidden),"Refusing to write into the vendor tree")
    stopifnot(!dir.exists(file.path(tmp,"vendor")))
    if (.Platform$OS.type!="windows") {
      alias <- file.path(tmp,"alias",".rpst-build");dir.create(dirname(alias),showWarnings=FALSE)
      stopifnot(file.symlink(normalizePath("src/vendor/pstalgo"),alias))
      rejects(harden(original,file.path(alias,"forbidden-raster",key)),"Refusing to write into the vendor tree")
      stopifnot(!dir.exists("src/vendor/pstalgo/forbidden-raster"));unlink(alias)
    }
  }
  verifier <- new.env(parent=baseenv())
  sys.source("tools/verify-vendor.R",envir=verifier)
  with_mutation <- function(path,bytes,action) {
    existed <- file.exists(path)
    previous <- if(existed) read_bytes(path) else NULL
    on.exit(if(existed) writeBin(previous,path) else unlink(path),add=TRUE)
    dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
    writeBin(bytes,path);force(action)
  }
  copies <- c("src/.rpst-build/Raster.cpp","src/.rpst-build/gfx/Blur.cpp",
              "src/.rpst-build/analyses/CreateBufferPolygons.cpp",
              "src/.rpst-build/include/pstalgo/utils/Arr2d.h")
  for (path in copies) {
    with_mutation(path,charToRaw("generated drift"),{
      rejects(verifier$verify_raster_copies(),"Unexpected raster build-copy changes")
      stopifnot(identical(read_bytes(path),charToRaw("generated drift")))
    })
  }
  for (path in c("src/Makevars","src/Makevars.win")) {
    original <- rawToChar(read_bytes(path))
    for (pattern in c("-c .rpst-build/analyses/CreateBufferPolygons.cpp",
                      "-I.rpst-build/include $(ALL_CPPFLAGS)",
                      "CreateBufferPolygons.cpp .rpst-build/include/pstalgo/utils/Arr2d.h",
                      "portability/harden-raster.R ../inst/upstream/build-inputs/Raster.cpp .rpst-build/Raster.cpp")) {
      stopifnot(grepl(pattern,original,fixed=TRUE))
      mutated <- sub(pattern,"invalid recipe",original,fixed=TRUE)
      with_mutation(path,charToRaw(mutated),
                    rejects(verifier$verify_raster_copies(),"drift"))
    }
  }
  message("Raster safety transformations passed: exact/reversible checksums, deterministic regeneration, drift/path/symlink rejection")
}
main()
