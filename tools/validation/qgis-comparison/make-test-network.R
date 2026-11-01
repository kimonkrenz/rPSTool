#!/usr/bin/env Rscript
# DEVELOPMENT-ONLY. Deterministic small test networks for the QGIS-vs-rPSTool validation.
# Usage: Rscript make-test-network.R [out.gpkg]     (default: data/pst-qgis-test.gpkg)
#        Rscript make-test-network.R --update-manifest   (maintenance only: rewrites the tracked manifest)
# The generated content hashes are compared with the tracked data/pst-qgis-test.manifest.tsv; a mismatch is an error.
# Needs: sf. No network access, no RNG: every coordinate is plain arithmetic.
#
# Layers written (all EPSG:27700, metres; every layer has the integer id field named below):
#   axial      14 two-vertex lines, interior crossings (axial / HPSTAGraph-style)  id: seg_id
#   segment    endpoint-connected two-vertex segments (HPSTASegmentGraph-style)    id: seg_id
#   polylines  multi-vertex polylines (input for "Create Segment Map")             id: line_id
#   unlinks    1 point exactly on an axial crossing                                id: ul_id
#   origins    8 points   (+ numeric column `pop`, includes a 0)                   id: pt_id
#   destinations 7 points (+ `jobs` with a 0 and a NULL, `shops`>0, label `name`)  id: dest_id
#   regions    2 polygons (outer ring only, clockwise)  (+ `cap`)                  id: reg_id
#   obstacles  4 clockwise building polygons (isovist)                             id: obs_id
# Row order of each layer == fid order (fid is 1..N, written by GDAL). The id fields are
# deliberately NOT equal to fid, so a join on row order cannot accidentally pass.
suppressPackageStartupMessages(library(sf))
args <- commandArgs(trailingOnly = TRUE)
here <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))),
                 error = function(e) ".")
update_manifest <- "--update-manifest" %in% args
args <- setdiff(args, "--update-manifest")
out <- if (length(args)) args[1] else file.path(here, "data", "pst-qgis-test.gpkg")
manifest <- file.path(here, "data", "pst-qgis-test.manifest.tsv")
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
E0 <- 530000; N0 <- 180000   # British National Grid-like offset (float32 behaviour is realistic)
crs <- st_crs(27700)

line_sf <- function(m, df) {
  geom <- st_sfc(lapply(seq_len(nrow(m)), function(i)
    st_linestring(matrix(c(m[i, 1] + E0, m[i, 2] + N0, m[i, 3] + E0, m[i, 4] + N0), 2, byrow = TRUE))), crs = crs)
  st_sf(df, geometry = geom)
}
pts_sf <- function(m, df) st_sf(df, geometry = st_sfc(lapply(seq_len(nrow(m)), function(i)
  st_point(c(m[i, 1] + E0, m[i, 2] + N0))), crs = crs))

## ---- axial: 5 H, 5 V, 3 diagonals, 1 spur ---------------------------------------------
ax <- rbind(
  c(  0.00,   0.00, 480.25,  12.50),  # H1
  c(-30.00, 100.50, 500.00,  95.25),  # H2
  c( 10.00, 200.00, 350.75, 205.50),  # H3
  c(-15.50, 300.25, 520.00, 310.00),  # H4
  c( 60.00, 400.00, 440.00, 395.75),  # H5
  c( 20.50, -40.00,  15.00, 420.00),  # V1
  c(130.25, -20.00, 140.00, 330.50),  # V2
  c(250.00,  40.75, 245.50, 410.00),  # V3
  c(370.50, -25.00, 365.00, 300.00),  # V4
  c(480.00, -30.25, 475.50, 330.00),  # V5
  c(-10.00, -10.00, 300.00, 250.00),  # D1
  c(500.00,  50.00, 300.00, 420.00),  # D2
  c( 90.00, 150.00, 200.00, 380.50),  # D3
  c(240.00, 200.50, 300.75, 160.00))  # spur crossing V3
ax_df <- data.frame(seg_id = 100L + seq_len(nrow(ax)) * 3L,
                    w = 1 + (seq_len(nrow(ax)) %% 4) * 0.5,
                    cost = 1 + ((seq_len(nrow(ax)) * 13) %% 7) / 2,
                    name = sprintf("ax%02d", seq_len(nrow(ax))))
axial <- line_sf(ax, ax_df)

## unlink: exact crossing of H2 (row 2) and V3 (row 8)
cross <- function(a, b) {  # intersection of segments a, b (4-vectors)
  d <- (a[1]-a[3])*(b[2]-b[4]) - (a[2]-a[4])*(b[1]-b[3])
  t <- ((a[1]-b[1])*(b[2]-b[4]) - (a[2]-b[2])*(b[1]-b[3])) / d
  c(a[1] + t*(a[3]-a[1]), a[2] + t*(a[4]-a[2]))
}
ul <- cross(ax[2, ], ax[8, ])
unlinks <- pts_sf(matrix(ul, 1), data.frame(ul_id = 9001L))

## ---- segment map: jittered 6x5 node lattice -------------------------------------------
nx <- c(0, 98.5, 203.25, 297.75, 404, 501.5); ny <- c(0, 105.25, 197.5, 303, 402.75)
node <- function(i, j) c(round(nx[i] + (((i*7 + j*13) %% 11) - 5) * 2.7, 3),
                         round(ny[j] + (((i*5 + j*3) %% 9) - 4) * 3.1, 3))
drop <- list(c(2,3,"h"), c(4,2,"v"), c(5,4,"h"))   # removed lattice edges
edges <- list()
for (j in seq_along(ny)) for (i in seq_along(nx)) {
  if (i < length(nx) && !any(vapply(drop, function(d) all(d == c(i, j, "h")), TRUE))) edges[[length(edges)+1]] <- c(i, j, i+1, j)
  if (j < length(ny) && !any(vapply(drop, function(d) all(d == c(i, j, "v")), TRUE))) edges[[length(edges)+1]] <- c(i, j, i, j+1)
}
edges <- c(edges, list(c(1,1,2,2), c(3,2,4,3), c(4,1,5,2), c(2,4,3,5)))
sg <- t(vapply(seq_along(edges), function(k) {
  e <- edges[[k]]; a <- node(e[1], e[2]); b <- node(e[3], e[4])
  if ((e[1] + e[2]) %% 3 == 0) c(b, a) else c(a, b)        # some reversed on purpose
}, numeric(4)))
ord <- order((seq_len(nrow(sg)) * 7919) %% 10007)         # deterministic non-spatial feature order
sg <- sg[ord, , drop = FALSE]
sg_df <- data.frame(seg_id = 2000L + (seq_len(nrow(sg)) - 1L) * 3L,
                    w = 1 + (seq_len(nrow(sg)) %% 5) * 0.5,
                    cost = 1 + ((seq_len(nrow(sg)) * 13) %% 7) / 2,
                    name = sprintf("sg%02d", seq_len(nrow(sg))))
segment <- line_sf(sg, sg_df)

## ---- polylines for Create Segment Map -------------------------------------------------
pl <- list(
  rbind(c(0, 0), c(100, 5), c(200, 0), c(300, 10)),
  rbind(c(50, -50), c(55, 40), c(48, 120)),
  rbind(c(150, 150), c(160, 60), c(250, 20), c(260, -40)),
  rbind(c(0, 100), c(120, 90), c(240, 110), c(330, 95), c(400, 100)),
  rbind(c(300, 200), c(280, 100), c(290, 0)))
polylines <- st_sf(line_id = 7000L + seq_along(pl) * 2L, grp = LETTERS[seq_along(pl)],
  geometry = st_sfc(lapply(pl, function(m) st_linestring(cbind(m[, 1] + E0, m[, 2] + N0))), crs = crs))

## ---- point layers ----------------------------------------------------------------------
org <- cbind(c(15, 100, 180, 260, 330, 410, 60, 450), c(20, 60, 150, 220, 310, 60, 350, 200))
origins <- pts_sf(org, data.frame(pt_id = 500L + seq_len(nrow(org)) * 2L, pop = c(10, 0, 25.5, 40, 5, 12, 8.25, 30)))
dst <- cbind(c(40, 220, 330, 120, 410, 270, 90), c(80, 30, 120, 260, 280, 340, 360))
destinations <- pts_sf(dst, data.frame(dest_id = 800L + seq_len(nrow(dst)) * 5L,
  jobs = c(5, 0, 12, NA, 7, 20, 3), shops = c(1, 2, 3, 1, 2, 1, 4),
  name = c("alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta")))

## ---- polygons (clockwise outer rings) --------------------------------------------------
sq <- function(x, y, s) rbind(c(x, y), c(x, y + s), c(x + s, y + s), c(x + s, y), c(x, y))  # clockwise
poly_sf <- function(rings, df) st_sf(df, geometry = st_sfc(lapply(rings, function(m)
  st_polygon(list(cbind(m[, 1] + E0, m[, 2] + N0)))), crs = crs))
regions <- poly_sf(list(sq(380, 150, 40), sq(60, 250, 30)), data.frame(reg_id = 600L + 1:2 * 7L, cap = c(100, 50)))
obstacles <- poly_sf(list(sq(100, 120, 40), sq(200, 250, 30), sq(300, 60, 50), sq(150, 340, 25)),
                     data.frame(obs_id = 400L + 1:4 * 11L))

layers <- list(axial = axial, segment = segment, polylines = polylines, unlinks = unlinks,
               origins = origins, destinations = destinations, regions = regions, obstacles = obstacles)
if (file.exists(out)) unlink(out)
for (nm in names(layers)) st_write(layers[[nm]], out, layer = nm, driver = "GPKG", quiet = TRUE, append = TRUE)

## ---- fingerprint (content, not file bytes: GPKG headers carry timestamps) ---------------
fp <- vapply(names(layers), function(nm) {
  x <- layers[[nm]]
  tf <- tempfile(fileext = ".txt")
  writeLines(c(vapply(seq_len(nrow(x)), function(i) paste(
    paste(vapply(st_drop_geometry(x)[i, , drop = FALSE], function(v) format(v, digits = 17), ""), collapse = ","),
    st_as_text(st_geometry(x)[[i]], digits = 17)), ""), as.character(st_crs(x)$epsg)), tf)
  unname(tools::md5sum(tf))
}, "")
observed <- data.frame(layer = names(layers), features = vapply(layers, nrow, 1L),
                       id_field = c("seg_id","seg_id","line_id","ul_id","pt_id","dest_id","reg_id","obs_id"), content_md5 = fp)
rownames(observed) <- NULL
if (update_manifest) {   # explicit maintenance action only; never part of normal generation
  write.table(observed, manifest, sep = "\t", quote = FALSE, row.names = FALSE)
  cat("Wrote", out, "and UPDATED the tracked manifest", manifest, "\n")
} else {
  expected <- read.delim(manifest, stringsAsFactors = FALSE, colClasses = "character")
  obs <- data.frame(lapply(observed, as.character), stringsAsFactors = FALSE)
  if (!isTRUE(all.equal(expected, obs, check.attributes = FALSE))) {
    unlink(out)
    m <- merge(expected, obs, by = "layer", all = TRUE, suffixes = c(".expected", ".generated"))
    print(m[!(m$features.expected == m$features.generated & m$content_md5.expected == m$content_md5.generated) | is.na(m$content_md5.expected) | is.na(m$content_md5.generated), ], row.names = FALSE)
    stop("Generated network does not match the tracked manifest ", manifest, ". The output file was removed. ",
         "If the change is intentional, rerun with --update-manifest and commit the new manifest.", call. = FALSE)
  }
  cat("Wrote", out, "- content hashes match the tracked manifest\n"); print(observed, row.names = FALSE)
}
