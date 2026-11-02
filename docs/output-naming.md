# Output column names

Every analysis names its result columns with one compact, PST-inspired scheme, built in one place (`R/naming.R`). The names are
labels: the `rpst:columns` manifest in result-file metadata (and the `rpst_manifest` attribute of multi-radius data frames) is the
authoritative description of each column. Positional identifiers (`segment_id`, `line_id`, `origin_id`, `group_id`,
`junction_id`) keep their names and are not part of the scheme.

```
measure:     <analysis>_<distance>_<radius>[_<weight>][_<normalisation>][_<parameters>]
diagnostic:  <diagnostic>_<distance>_<radius>[_<weight>][_<parameters>]
```

All names are lower case with `_` separators. A component that does not apply to an analysis is omitted. A scalar call and a
multi-radius call name the same calculation identically (`ai_a_rw3000_t` either way).

## Codes

| Component | Codes |
|---|---|
| Analysis | `nr` Network Reach (no measure column; see diagnostics), `ni` Network Integration, `nj` junction score, `nb` Network Betweenness, `at` Attraction Betweenness (`network_betweenness()` with `attraction_points`), `ai` Angular Integration, `ac` Angular Choice (PST's Angular Betweenness), `ar` Attraction Reach, `ad` Attraction Distance, `od` Origin-Destination Betweenness, `gi` segment-group integration |
| Distance | `a` angular, `w` walking, `s` steps, `l` straight line, `am` axmeter, `d` custom per-line cost (`attraction_distance(distance = "weights")`). Omitted for Network Reach, segment groups and `attraction_reach(distance = "none")` (zero cost) |
| Radius | `rl`, `rw`, `rs`, `ra`, `ram` followed by the full value (`rw3000`, `rs3`, `rw0p5`); every active restriction in the order straight, walking, steps, angular, axmeter (`rl500_rw400_ra90`); `rg` when unrestricted. A decimal point is `p`; thousands are never abbreviated. Values use the shortest decimal that reads back as the same single-precision number PST uses |
| Weight | `wl` length weighting; `wu` unit weights where weight totals are reported for an unweighted run (`weight_outputs = TRUE`); `w<name>` user weights named with `weight_name`; `wv` user weights without a name; `wo<name>`/`wd<name>` (`wov`/`wdv`) origin and destination weights of `od_betweenness()` |
| Normalisation | `t` Turner, `a` NAIN (Angular Integration `syntax`), `c` NACH (Angular Choice `syntax`), `h` Hillier, `s` standard, `f` Freeman, `y` Network Betweenness `syntax`, `n` raw. Only where normalisation is a dimension of the analysis (`ac`, `ai`, `nb`/`at`) |
| Diagnostic | `nc` node count, `td` total depth, `tw` total weight, `tdw` total depth weight, `rc` reached count, `rln` reached length, `rca` reached area, `di` destination index |

Network Betweenness `syntax` is `log10(score + 1) / log10(2 + total_depth)` (`PSTABetweennessSyntaxNormalize`,
`SegmentBetweenness.cpp`). It is the same transformation as Angular Choice's NACH but is applied to an axial measure, so it has its own code.

## Non-default parameters

A parameter appears as a suffix only when its value differs from the default, including when the default is passed explicitly.
Suffixes follow this order; values are encoded as radius values (`p` decimal point, `m` minus sign):

| Suffix | Parameter (default) | Analyses |
|---|---|---|
| `at<v>` | `angle_threshold` (0) | `ac`, `ai` |
| `ap<v>` | `angle_precision` (1) | `ac`, `ai` |
| `or<x>` | `origin` (`lines`): `j` junctions, `p` points, `g` point groups | `ar`, `ad` |
| `dc<x>` | `decay` (`constant`): `p` power, `v` curve, `d` divide | `ar` |
| `dk<v>` | `decay_constant` (0 for constant decay, 1 for the others) | `ar` |
| `ds<x>` | `distribution` (`divide`): `c` copy | `ar` |
| `cl<x>` | `collection` (`mean`): `s` sum, `n` min, `x` max | `ar` |
| `pe<v>` | `point_edge_weight` (0) | `ad` |
| `pi<v>` | `polygon_point_interval` (none) | `ar`, `ad` |
| `dm<x>` | `destination_mode` (`all`): `c` closest | `od` |

Options that only shape the output (`destination_indices`, `weight_outputs`, files, `junction_output`) never add suffixes. The
attraction points, `points_per_polygon` and weight values themselves are inputs, not parameters; they are recorded by size and
(for weights) by name in the metadata.

## Weight names

`weight_name` (and `origin_weight_name`, `destination_weight_name`) labels a user weight vector: `weights = pop, weight_name = "population"` gives `..._wpopulation_...`.
The name is lower-cased, every run of characters other than letters, digits and `_` becomes one `_`, and leading and trailing `_`
are dropped. It is never truncated. A name with no letters or digits, or one that would produce the reserved codes `wl`, `wu` or
`wv`, is an error. The original name is kept in the metadata. Without a name the weights are labelled `wv`. A name is a label
only: reusing it for different values is not detected, and the result-column collision rules apply (see `?pst_result_file`).
Underscores inside a name stay, so names are not meant to be parsed; use the manifest.

## Examples

| Call | Columns |
|---|---|
| `angular_integration(g, radius = analysis_radius(walking = 3000))` | `ai_a_rw3000_t`, `nc_a_rw3000`, `td_a_rw3000` |
| `angular_integration(g, steps = 3, weigh_by_length = TRUE, normalization = "syntax")` | `ai_a_rs3_wl_a`, `nc_a_rs3`, `td_a_rs3`, `tw_a_rs3_wl`, `tdw_a_rs3_wl` |
| `angular_choice(g, analysis_radius(walking = 3000), normalization = "syntax", angle_threshold = 12)` | `ac_a_rw3000_n_at12`, `nc_a_rw3000_at12`, `td_a_rw3000_at12`, `ac_a_rw3000_c_at12` |
| `angular_choice(g, analysis_radius(walking = 3000, steps = 3))` | `ac_a_rw3000_rs3_n`, … |
| `network_integration(a, steps = 3)` | `ni_s_rs3`, `nc_s_rs3`, `td_s_rs3` |
| `network_reach(a, analysis_radius(walking = 400))` | `rc_rw400`, `rln_rw400`, `rca_rw400` |
| `network_betweenness(a, distance = "walking", radius = analysis_radius(walking = 800), weights = pop, weight_name = "population", normalization = "freeman")` | `nb_w_rw800_wpopulation_n`, `nc_w_rw800`, `td_w_rw800`, `nb_w_rw800_wpopulation_f` |
| `attraction_reach(a, pts, distance = "walking", radius = analysis_radius(walking = 800))` | `ar_w_rw800` |
| `attraction_distance(a, pts, distance = "weights", line_weights = cost, weight_name = "cost")` | `ad_d_rg_wcost`, `di_d_rg_wcost` |
| `od_betweenness(a, origins, radius = analysis_radius(walking = 800))` | `od_w_rw800` |
| `segment_group_integration(gg, analysis_radius(walking = 1000))` | `gi_rw1000`, `nc_rw1000`, `td_rw1000` |

Successive analyses can be accumulated in one spatial dataset because their names differ: write the first result with
`spatial_output_file`, then analyse the new file with another radius or measure and write it to a further file; the earlier
result columns are carried along as ordinary attributes. Re-running the same analysis on its own output uses the same names.

## Schema change

These names replace the earlier generic ones (`integration`, `choice`, `node_count`, `total_depth`, `normalized`, `betweenness`,
`reached_count`, …). Files written before this change keep their old names and are not reinterpreted.
