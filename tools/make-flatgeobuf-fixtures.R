#!/usr/bin/env Rscript
# Development-only fixture generator (never run by the package or its tests).
# Writes tiny FlatGeobuf fixtures with GDAL's FlatGeobuf driver via sf (the authoritative,
# widely deployed writer) and reports which cases GDAL refuses to write. The committed
# tests/testthat/fixtures/flatgeobuf/*.fgb are copies of its output plus the byte-patched
# variants described in that directory's README.
# usage (from the repository root): Rscript tools/make-flatgeobuf-fixtures.R OUT_DIR
suppressMessages(library(sf))
out <- commandArgs(TRUE)[[1]]; dir.create(out, showWarnings = FALSE, recursive = TRUE)
lat <- as.matrix(read.csv("tests/testthat/fixtures/geoparquet/expected-lattice.csv"))
line <- function(...) st_linestring(rbind(...))
ls2 <- function(m) st_sfc(lapply(seq_len(nrow(m)), function(i) line(m[i, 1:2], m[i, 3:4])))
status <- character()
write <- function(geom, name, index = FALSE, crs = 32630) {
  geom <- st_set_crs(geom, crs)
  x <- st_sf(id = seq_along(geom), geometry = geom)
  f <- file.path(out, paste0(name, ".fgb")); unlink(f)
  r <- tryCatch({ suppressWarnings(suppressMessages(st_write(x, f, driver = "FlatGeobuf", quiet = TRUE,
        layer_options = paste0("SPATIAL_INDEX=", if (index) "YES" else "NO")))); "written" },
        error = function(e) paste("GDAL refused:", gsub("\n", " ", conditionMessage(e))))
  status[name] <<- r
}
g <- ls2(lat)
write(g, "lattice-utm-indexed", TRUE)
write(g, "lattice-utm-noindex", FALSE)
write(g, "lattice-unknown-crs", FALSE, NA)
write(g, "lattice-geographic-4326", FALSE, 4326)
write(st_sfc(line(c(0,0), c(1,1)), line(c(1,1), c(2,2), c(3,3))), "mixed-2pt-3pt")
write(st_sfc(st_multilinestring(list(rbind(c(0,0), c(1,1))))), "multilinestring-one-part")
write(st_sfc(st_point(c(1, 2))), "point")
write(st_sfc(st_polygon(list(rbind(c(0,0), c(1,0), c(1,1), c(0,0))))), "polygon")
write(st_sfc(st_linestring(rbind(c(0,0,5), c(1,1,6)), dim = "XYM")), "linestring-m")
write(st_sfc(st_linestring(rbind(c(0,0,5,7), c(1,1,6,8)), dim = "XYZM")), "linestring-zm")
write(st_sfc(st_linestring()), "linestring-empty")
write(st_sfc(line(c(0,0), c(1,1)), st_point(c(2, 2))), "heterogeneous")
write(st_sfc(line(c(0,0), c(1,1)), line(c(1,1), c(2,2)), line(c(2,2), c(3,3))), "three-segments-noindex")
write(st_sfc(line(c(0,0), c(1,1)), line(c(1,1), c(2,2)), line(c(2,2), c(3,3))), "three-segments-indexed", TRUE)
# NULL geometry and zero features go through GeoJSON -> ogr2ogr (sf cannot express them directly).
writeLines('{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"id":1},"geometry":{"type":"LineString","coordinates":[[0,0],[1,1]]}},{"type":"Feature","properties":{"id":2},"geometry":null}]}',
           file.path(out, "null-geometry.geojson"))
writeLines('{"type":"FeatureCollection","features":[]}', file.path(out, "zero.geojson"))
writeLines('{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"id":1},"geometry":{"type":"LineString","coordinates":[[0,0,5],[1,1,6]]}}]}',
           file.path(out, "linestring-z.geojson"))
for (n in c("null-geometry", "zero", "linestring-z")) {
  o <- file.path(out, paste0(n, ".fgb")); unlink(o)
  r <- system2("ogr2ogr", c("-f", "FlatGeobuf", "-lco", "SPATIAL_INDEX=NO", "-a_srs", "EPSG:32630", shQuote(o),
                            shQuote(file.path(out, paste0(n, ".geojson")))), stdout = TRUE, stderr = TRUE)
  status[n] <- if (file.exists(o)) "written" else paste("GDAL refused:", paste(r, collapse = " "))
  unlink(file.path(out, paste0(n, ".geojson")))
}
print(data.frame(status = status))
