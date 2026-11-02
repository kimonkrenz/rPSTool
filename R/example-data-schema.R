#' Hillier-Iida example data: schema of the components
#'
#' The structure returned by [load_example_data()]: a list of three `sf` objects. This page documents
#' the components; the data are supplied as stored and are not recalculated, segmented, aggregated or repaired.
#'
#' @section Contents:
#' The Barnsbury network: 1915 `axial` lines, 2 `unlinks` and 109 `gates` observations (gate `area` label `barnsbury`).
#'
#' @section Conventions common to all components:
#' All geometries are two-dimensional `sf` geometries in British National Grid, EPSG:27700 (OSGB36 / British National Grid), in
#' metres. They were georeferenced and spatially transformed after the original dataset was distributed, so they are not the original,
#' unmodified coordinates; the original local drawing coordinates are not included. Axial-line identifiers are the original identifiers: they are
#' unique but are not row numbers and need not be consecutive. Every `axial_id` in `unlinks` and `gates` refers to a
#' parent axial line in the `axial` object, not to a segment generated later from the network. Unavailable
#' observations are `NA`, never zero. Text categories are lower-case snake case. The list returned by
#' [load_example_data()] carries the full description of origin and conventions in its `metadata` attribute.
#'
#' @section `axial`:
#' An `sf` data frame with one `LINESTRING` per axial line.
#' \describe{
#'   \item{`axial_id`}{integer, the original axial-line identifier.}
#'   \item{`source_connectivity`}{integer, the supplied historical connectivity of the line.}
#'   \item{`source_control`}{numeric, the supplied historical control value.}
#'   \item{`source_integration`}{numeric, the supplied historical integration value.}
#'   \item{`source_local_integration`}{numeric, the supplied historical local integration value.}
#'   \item{`geometry`}{`LINESTRING`, EPSG:27700.}
#' }
#' The four `source_` columns are historical values retained unchanged and without recalculation. They are not rPSTool or PST results,
#' and no rPSTool function reads them.
#'
#' @section `unlinks`:
#' An `sf` data frame with one row per unlink: a place where two axial lines cross without being connected.
#' \describe{
#'   \item{`axial_id_1`, `axial_id_2`}{integer, the identifiers of the two axial lines that cross without connecting.}
#'   \item{`geometry`}{`POINT`, EPSG:27700, the location of the unlink.}
#' }
#' The unlink points lie on both lines, so they can be passed as the `unlinks` argument of [axial_graph()] together with the axial lines.
#'
#' @section `gates`:
#' An `sf` data frame with one row per observation of movement at a gate, with the reported physical attributes of the street at the
#' gate (network-aligned georeferenced placement). Pedestrian and vehicle observations are combined by observation area, gate number
#' and parent axial-line identifier. Movement rates, building heights and widths are preserved as supplied.
#' \describe{
#'   \item{`gate_id`}{integer, the gate number within the observation area. A gate may lie on more than one axial line:
#'   Barnsbury gate 42 is recorded twice, once for `axial_id` 16 and once for `axial_id` 20, and both rows are kept.}
#'   \item{`axial_id`}{integer, the parent axial line.}
#'   \item{`area`}{character, the observation area (always `barnsbury`: only the Barnsbury network is included).}
#'   \item{`pedestrians_per_hour`}{numeric, observed pedestrian movement rate per hour.}
#'   \item{`vehicles_per_hour`}{numeric, observed vehicle movement rate per hour; `NA` where unavailable (27 rows).}
#'   \item{`land_use`}{character, reported land use (for example `residential`, `retail`, `mixed`, `school`).}
#'   \item{`traffic_management`}{character, one of `one_way`, `two_way`, `pedestrian`, `restricted`, `vehicular_cul_de_sac`
#'   (not every value necessarily occurs).}
#'   \item{`street_type`}{character, one of `primary`, `secondary`, `local`.}
#'   \item{`mean_building_height_storeys`, `max_building_height_storeys`}{numeric, building heights in storeys.}
#'   \item{`street_width_m`, `pavement_width_m`, `vehicle_road_width_m`, `parking_width_m`, `effective_road_width_m`}{numeric,
#'   the reported widths in metres.}
#'   \item{`geometry`}{`POINT`, EPSG:27700, the gate location.}
#' }
#' The gate observations are not aggregated: several rows can refer to the same axial line.
#'
#' @name hillier_iida
#' @docType data
#' @keywords datasets
#' @seealso [load_example_data()]
#' @section Source:
#' The Barnsbury example data are derived from Hillier and Iida (2005) and include the axial network, unlinks and observed movement gate counts. The geometries were georeferenced and spatially transformed by Kimon Krenz. The data are included and redistributed with permission from the authors. The original research and data remain attributable to their respective authors.
#' The movement gate counts were originally reported by Penn et al. (1998). See also the section "Source of the data" in [load_example_data()].
#'
#' @references Hillier, B. and Iida, S. (2005). Network and Psychological Effects in Urban Movement. In *Spatial Information Theory*,
#'   LNCS 3693, pp. 475-490. \doi{10.1007/11556114_30}.
#'
#'   Penn, A., Hillier, B., Banister, D. and Xu, J. (1998). Configurational modelling of urban movement networks. *Environment and Planning B: Planning and Design*, 25(1), 59-84. \doi{10.1068/b250059}.
NULL
