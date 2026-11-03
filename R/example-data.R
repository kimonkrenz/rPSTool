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
#' The Barnsbury example data are derived from Hillier and Iida (2005) and include the axial network, unlinks and observed movement gate counts. The geometries were georeferenced and spatially transformed by Kimon Krenz. The data are included and redistributed with permission from the authors. The original research and data remain attributable to their respective authors.
#' The movement gate counts were originally reported by Penn et al. (1998).
#'
#' The original data were not supplied in British National Grid. The coordinates in this package are the transformed coordinates in
#' EPSG:27700 (metres); they are not the original coordinates. The LGPL (>= 3) licence applies to rPSTool's software. The Barnsbury data are included with the authors' permission and remain attributable to them.
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
