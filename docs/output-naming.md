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
| Weight | none when unweighted; `wl` length weighting; `w<name>` custom weights, whose name is mandatory (`weight_name`); `wo<name>`/`wd<name>` origin and destination weights of `od_betweenness()` |
| Normalisation | `t` Turner, `a` NAIN (Angular Integration `syntax`), `c` NACH (Angular Choice `syntax`), `h` Hillier, `s` standard, `f` Freeman, `y` Network Betweenness `syntax`, `n` raw. Only where normalisation is a dimension of the analysis (`ac`, `ai`, `nb`/`at`) |
| Diagnostic | `nc` node count, `td` total depth, `tw` total weight, `tdw` total depth weight, `rc` reached count, `rln` reached length, `rca` reached area, `di` destination index; `anc`, `atd` node count and total depth of Attraction Betweenness |

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

Custom weights must be named. `weights = pop, weight_name = "population"` gives `..._wpopulation_...`; supplying weights without a
name, or a name without weights, is an error raised before any calculation (`Custom weights require weight_name. Supply a
descriptive identifier, for example weight_name = "population".`). `attraction_reach()` (`attraction_values`) and
`attraction_distance()` (`line_weights`) use `weight_name`; `od_betweenness()` uses `origin_weight_name` and
`destination_weight_name`, each required only for its own vector. There is no fallback label, hash or inferred name.

The name is normalised automatically: lower-cased, every run of characters outside `a-z`, `0-9` and `_` becomes a single `_`, and
leading and trailing underscores are removed. Only a name that is empty or has no letter or digit left is an error, as is a name
that normalises to `l` (it would read as length weighting). Names are never truncated, and the original name is kept in the
metadata. `Jobs 2021`, `Jobs-2021`, `Jobs/2021` and `jobs_2021` all give `jobs_2021` (`wjobs_2021` in the column name);
`Population (%)` gives `population`. The `w` prefix is automatic, so `wjobs` gives `wwjobs`. Different names that normalise alike
produce the same column name, so the collision checks treat them as the same field (a clash needs `overwrite = TRUE`). A name is a label
only: reusing it for different values is not detected, and the collision rules apply when extending a spatial dataset.

## Examples

| Call | Columns |
|---|---|
| `angular_integration(g, radius = analysis_radius(walking = 3000))` | `ai_a_rw3000_t`, `nc_a_rw3000`, `td_a_rw3000` |
| `angular_integration(g, steps = 3, weigh_by_length = TRUE, normalization = "syntax")` | `ai_a_rs3_wl_a`, `nc_a_rs3`, `td_a_rs3`, `tw_a_rs3_wl`, `tdw_a_rs3_wl` |
| `angular_integration(g, steps = 3, weight_outputs = TRUE)` (unweighted) | `ai_a_rs3_t`, `nc_a_rs3`, `td_a_rs3`, `tw_a_rs3`, `tdw_a_rs3` |
| `angular_choice(g, analysis_radius(walking = 3000), normalization = "syntax", angle_threshold = 12)` | `ac_a_rw3000_n_at12`, `nc_a_rw3000_at12`, `td_a_rw3000_at12`, `ac_a_rw3000_c_at12` |
| `angular_choice(g, analysis_radius(walking = 3000, steps = 3))` | `ac_a_rw3000_rs3_n`, … |
| `network_integration(a, steps = 3)` | `ni_s_rs3`, `nc_s_rs3`, `td_s_rs3` |
| `network_reach(a, analysis_radius(walking = 400))` | `rc_rw400`, `rln_rw400`, `rca_rw400` |
| `network_betweenness(a, distance = "walking", radius = analysis_radius(walking = 800), weights = pop, weight_name = "population", normalization = "freeman")` | `nb_w_rw800_wpopulation_n`, `nc_w_rw800_wpopulation`, `td_w_rw800_wpopulation`, `nb_w_rw800_wpopulation_f` |
| the same with `attraction_points = pts` | `at_w_rw800_wpopulation_n`, `anc_w_rw800_wpopulation`, `atd_w_rw800_wpopulation`, … |
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

## Diagnostics that look alike: Network Betweenness and Attraction Betweenness

Network Betweenness (`nb`) and Attraction Betweenness (`at`) both return a node count and a total depth for the same distance
and radius, so unqualified `nc_w_rw800` / `td_w_rw800` could have meant two things. They were compared on the actual
calculations, not assumed:

* Without weights, and with positive line weights, `nb`'s node count and total depth equal those of the unweighted run: the
  origin set is every line, and the values do not depend on the weights. Every weighted origin whose effective weight is
  zero or negative is skipped by PST, which gives `NA` for those origins, so under such weights the diagnostics differ from
  the unweighted run. The weight-tagged names (`nc_w_rw800_wpopulation`) therefore keep a weighted run's diagnostics apart
  from the unweighted run's.
* Attraction runs use the attraction points to decide which origins take part, so their node count and total depth differ
  from `nb`'s for the same distance and radius. They are named `anc` and `atd` (`anc_w_rw800`, `atd_w_rw800`), with the
  `_w<name>` tag when attraction weights are supplied.

Everything else that shares a diagnostic code is the same quantity: `nc` and `td` of Angular Integration, Angular Choice,
Network Integration and segment-group integration differ by their distance and radius components, which are always part of
the name.
