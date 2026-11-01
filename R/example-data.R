#' Load the Hillier-Iida example data
#'
#' Reads the bundled spatial example data: the Barnsbury (London) axial map of Hillier and Iida (2005) together with its unlinks
#' and the pedestrian and vehicle movement observed at gates. The data are returned as stored; nothing is segmented, recalculated,
#' aggregated or repaired, and nothing is assigned into the global environment. The objects are `sf` objects, so the 'sf' package
#' is needed. Their layout is described in [hillier_iida].
#'
#' @return A list with the `sf` objects `axial`, `unlinks` and `gates` and a `metadata` attribute (a character string describing
#'   the data, its origin and its conventions).
#' @section Source of the data:
#' The axial map is that distributed with Hillier and Iida (2005) through UCL Discovery. The pedestrian and vehicular movement
#' observations were originally used in Penn et al. (1998), as documented in the README of the original dataset. That attribution
#' concerns the movement observations only: it does not imply that every axial map, network metric or other attribute originated in the
#' 1998 study. The Barnsbury geometry was subsequently georeferenced to British National Grid and spatially transformed (a best-fit
#' transformation supplied by Kimon Krenz). The coordinates in this package are therefore transformed coordinates and must not be
#' taken to be the original, unmodified coordinates of the source data. No explicit redistribution licence was located in the supplied
#' material and the attribution does not establish one; see the package's installed `COPYRIGHTS` file for provenance.
#'
#' @references Hillier, B. and Iida, S. (2005). Network and Psychological Effects in Urban Movement. In Cohn, A.G. and Mark, D.M.
#'   (eds), *Spatial Information Theory*, Lecture Notes in Computer Science 3693, pp. 475-490. Springer.
#'   \doi{10.1007/11556114_30}. The original axial map and movement observations were obtained from
#'   <https://discovery.ucl.ac.uk/id/eprint/1232/>.
#'
#'   Penn, A., Hillier, B., Banister, D. and Xu, J. (1998). Configurational modelling of urban movement networks. *Environment and Planning B: Planning and Design*, 25(1), 59-84. \doi{10.1068/b250059}.
#' @seealso [hillier_iida] for the schema of the components.
#' @export
#' @examples
#' if (requireNamespace("sf", quietly = TRUE)) {
#'   example <- load_example_data()
#'   names(example)
#'   example$axial
#'   table(example$gates$area)
#'
#'   # An axial map and its unlinks are the input of an axial graph.
#'   # Coordinates are transformed to metres (EPSG:27700).
#'   graph <- axial_graph(
#'     example$axial,
#'     unlinks = example$unlinks
#'   )
#' }
load_example_data <- function() {
  if (!requireNamespace("sf", quietly = TRUE)) stop("Loading these spatial examples requires the 'sf' package", call. = FALSE)
  path <- system.file("extdata", "hillier_iida", "barnsbury.rds", package = "rPSTool")
  if (!nzchar(path)) stop("The Barnsbury example data file is unavailable in the installed package", call. = FALSE)
  readRDS(path)
}
