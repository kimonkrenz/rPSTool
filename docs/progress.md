# Progress display

`options(rPSTool.progress = TRUE | FALSE)` is the only control. Unset (the default) means on in interactive sessions that are
not capturing output (`sink()`, knitr) and off everywhere else, including scripts, CI and package checks. The option is read
once per top-level call.

Nothing is printed until two seconds after the call began (monotonic clock, measured for the whole call, not per radius). The
display is one line redrawn in place with `\r` and erased when the call ends, fails or is interrupted:

```
ac_a_rw400_n  ██████████████░░░░░░   70%  Analysis 2/6      (UTF-8 session)
ac_a_rw400_n  [##############------]   70%  Analysis 2/6     (otherwise)
```

* The label is the first result variable of the running analysis, taken from the central naming layer (`R/naming.R`).
* The percentage is the progress PST reports for the current analysis; it starts again at 0% for each radius. Nothing is
  estimated or averaged. `Analysis k/n` appears only for several analyses (several radii).
* Covered: `network_integration()`, `network_reach()`, `network_betweenness()`, `angular_choice()`, `angular_integration()`,
  `attraction_reach()`, `attraction_distance()`, `od_betweenness()`, `segment_group_integration()`, and the construction functions `create_junctions()` (label
  `junctions`) and `create_segment_map()` (label `segments`). Graph construction, segment grouping, isovists and raster
  functions show no progress.
* `attraction_distance()`: PST first builds its multi-distance graph and reports nothing until that is done (roughly 3 to 5 s
  in the benchmarked workloads). The line therefore first appears, at 0%, when PST sends its first report, which can be later
  than two seconds. Showing it earlier would need a timer or a second thread, and any figure shown during the build would be
  invented, so this is documented rather than worked around.
* PST calls the callback on the thread that called the analysis (the R main thread) about every 100 ms, so the line can appear up
  to about 100 ms after the two-second mark. The callback does no work before then, and when progress is off PST gets no
  callback at all. PST ignores the callback's return value, so progress cannot cancel an analysis.
