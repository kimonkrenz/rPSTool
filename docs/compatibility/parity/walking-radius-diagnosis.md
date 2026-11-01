# Walking-radius diagnosis for network_integration() on axial graphs

> **Status (PR #71 follow-up).** This is a record of an investigation. rPST is an interface to the supported PST software; **no native
> BFS correction is planned, approved or implemented**, `src/vendor` and `src/portability` are untouched, and the prototype patch is not part of
> the repository. The upstream motive for the steps-only Network Integration restriction is not documented, and this report does not
> claim that the pruning behaviour caused it. rPST now follows the official restriction (steps radius or none) in `network_integration()`.
> Statements below about "recommended" or "candidate" solutions are historical.

Date 2026-10-31. The package repository was NOT modified; upstream clone was NOT modified. All
builds/edits are under `scratchpad/audit/W/` (pkg = scratch copy of the repo, `lib_instr` = instrumented install, `proto`/`proto_instr` = prototype
installs, `p/lib` = stock install used as the reference build).

## 0. Diagnosis (short)

**Native algorithmic defect (inefficient pruning in the vendored, unmodified upstream `CPSTBFS`), results are correct; not a wrapper error;
not a native prohibition; the upstream QGIS/Python restriction to steps is a Python/UI-only restriction with no recorded explanation.**
Confidence: high on mechanism and on correctness of results (instrumented counts + independent exact reference + bit-identical prototype);
medium on the reason upstream hid walking radii (no explanation found; performance is a plausible but unproven motive).

* Mechanism (BFS.cpp:348-399 + :158/:236/:276): one checkpoint per line crossing, overwritten only by a state that dominates it (`!bHasWorse`).
  An arrival that is better in one compared metric and worse in another (walking vs turns) is accepted and queued again but the checkpoint stays at the FIRST
  arrival. Any later path with less walking than that first arrival is accepted, however many turns it has and even if an already-accepted
  state dominates it. With only a walking limit there is no turn limit, so paths can circle through short cycles of a dense local cluster of
  lines (line changes cost walking only through the short edges). The number of queued states per origin is then the number of feasible
  paths, not a function of line count. Evidence: >99.9% of all accepted revisits are weakly dominated by an earlier accepted state at the same
  line crossing (`acc_redund` vs `acc_dom` below); one line is dequeued 8-18 million times from one origin; max turns seen in a queued
  state is 1,384 within 300 m of walking on Barnsbury.
* Specific to combinations of >= 2 independently compared metrics where at least one is not bounded: NetworkIntegration is always DIST_LINES
  (turns always compared), so any walking (or angular/axmeter) radius triggers it; steps-only, unrestricted and network_reach with walking only (DIST_NONE, one compared metric) do not.
  Also triggered: network_reach with walking + axmeter (bad_alloc at 2.9 GB on a 100-line graph).
* A walking limit combined with a steps limit is cheap (turns bounded): Barnsbury w=2000,n=3: 0.036 s.

## 1. Official interface (task 1)

| item | evidence | finding |
|---|---|---|
| Wizard | `pstqgis/src/pst/ui/wizards/networkintegrationwiz.py:34` `RadiusPage(radius_types=[RadiusType.STEPS], ...)` (v3.3.2) | UI-only: only the steps radius is offered |
| Python analysis | `pstqgis/src/pst/analyses/networkintegrationanalysis.py:45-48` (v3.3.2) `radii_list = [pstalgo.Radii(steps = props['rad_steps'] if props.get('rad_steps_enabled') else None)]`; old line `RadiiFromSettings(pstalgo, self._props).split()` commented out (:45) | Python-side hard-coding: even a stored walking property would be ignored. Only a `steps` radius is passed to `PSTANetworkIntegration` (m_Radius = Radii with only MASK_STEPS). No distance TYPE field exists in `SPSTANetworkIntegration` (pstalgo/python/pstalgo/networkintegration.py:27-51): fields are version, graph, radius, callback, junction/line outputs. |
| Python wrapper | `pstalgo/python/pstalgo/common.py:92-133` `Radii(straight, walking, steps, angular, axmeter)`; `pstalgo/test/tests/testnetworkintegration.py` (chain graph) tests `Radii(walking=0/1/3)`, `Radii(straight=...)`, `Radii(angular=1)` | native API accepts walking (tiny graph only; does not exercise the blow-up) |
| Introduced | commit `5f3f70f` 2024-10-17 martin-fitger "pstqgis: networkintegration: Only allow axial network and only support step radius." (changes networkintegrationwiz.py, networkintegrationanalysis.py, radiuspage.py, networkinputpage.py and 7 other wizards, same day as `44bc53a` "Disable isovist tool", `a4b9550` Disable "Split polylines"). Before it: `RadiusPage()` (all five radius types) and `RadiiFromSettings(...).split()` since the file's first version (`a808c54` 2019-11-18; unchanged by `d6ec025` license change). | |
| Follow-up | `dac509f` 2024-11-01 "pstqgis: network integration:: Changed text for step radius." (label "Axial (topological) steps") | text only |
| Present at v3.3.2 | `git tag --contains 5f3f70f` = v3.3.1, v3.3.2; v3.3.2 wizard line 34 verified with `git grep` | yes |
| Performance link | `git log --grep='perform|slow|walking|memory'` finds nothing about this; BFS.cpp history is only `866cf3a` (2019-11-20, added) and `d6ec025` (license); no comment, issue reference or README text | **no explanation found** |
| Other upstream wizards at v3.3.2 | Reach, Network Betweenness, Angular Integration/Choice, Attraction* all use `RadiusPage()` (all radius types) | only NI is restricted |

Classification of the upstream restriction: **Python-validation / UI-only** (class C). Native accepts walking (the native API has no restriction;
`LimitsFromSPSTARadii` Limits.cpp:~30-50 maps the mask bits).

## 2. rPST parameter passing (task 2)

* R: `network_integration(graph, steps = NULL, radius = NULL, ...)` R/integration.R:64 -> `.pst_resolve_radius(steps, radius, FALSE)` (R/radius.R:142-148) ->
  `.pst_validate_radius` (R/radius.R:77-107: finite, non-negative, <= FLT_MAX, whole steps; then `.Call(C_rpst_radius_validate)`). The (validated) `pst_radius`
  object is passed as the C argument called `steps` (legacy name).
* C++: `analysis_radii()` src/pst-graph.cpp:158-205 (field index 1 -> `radii.SetWalking(f)` :199 with `float f = static_cast<float>(v)`; checks for overflow/underflow); `network_integration()` :680-780 sets `desc.m_Radius = radii` (:741) with a value-initialised descriptor (`SPSTANetworkIntegrationDesc desc{}`, :737-748). `SetWalking` sets `m_Walking` and mask bit `EPSTADistanceTypeMask_Walking` (vendor Common.h:96).
* Distance type: the descriptor has no distance-type/start-distance field. `DIST_LINES` is hard-coded inside the engine (`NetworkIntegration.cpp:69`); `LimitsFromSPSTARadii` (Limits.cpp) translates the mask to `LIMITS::MASK_WALKING` + `walking`. The Python request is identical (a `Radii` struct). **Verdict: the mapping is correct and equals the Python request construction; no wrapper error (G).**
* rPST sets no progress callback (`m_ProgressCallback` is never assigned in pst-graph.cpp), so `m_bCancel`/`getCancel()` can never become true: a runaway native run cannot be interrupted from R (usability/safety risk; consistent with the observed need for timeout/RLIMIT).
* Unit: coordinate units (R/radius.R docs), not a problem.

## 3. Native semantics (task 3)

* Graph: lines, "crossings" (junction points), "line crossings" (LC = a (line, crossing) pair, i.e. an entry/exit point on a line; `lc.iOpposite` is the same crossing on the other line).
* **State** (BFS.h:`STATE`): `{iLineCrossing, DIST{walking,turns,angle,axmeter}, lastAngle}` = "standing on the line of LC `iLineCrossing`, at that crossing, having walked `walking` and changed line `turns` times (the change onto this line included)". Origin: midpoint of the origin line (`doBFSFromLine` :83-96), `iLineCrossing = -1`.
* **Expansion** (`doBFS` :113-296): dequeue state; (target = lines) compute the walking to the midpoint of the line and, if `testLimit`, call `visitBFS(line, dist)`; then for every other LC on the line compute walking/axmeter/angle to it, test limits, run the checkpoint test at that LC (:228-246), and (unless it is the same crossing) enqueue the opposite LC with `turns+1` (:276).
* `testLimit` (:300): compares each masked metric (`walking`, `turns`, `angle`, `axmeter`) against the limit. Straight is tested on crossings only (`testStraightLineLimit`).
* **Checkpoint** (BFS.h:`CHECKPOINT`, one per LC, valid only if the LC visited-bit is set; bits are cleared per origin by `clrVisitedLineCrossings`): `{walking, turns, fwAngle, bkAngle, axmeter}`.
* **Acceptance rule** (`updateCheckPoint`, :348-399): the metrics compared are those of `m_distType` (DIST_WALKING: walking; DIST_LINES: turns; DIST_ANGULAR: angle; DIST_AXMETER: walking, turns, axmeter) PLUS every metric present in the limit mask. Accept (return true) iff the arrival is strictly better than the checkpoint in at least one compared metric; overwrite the checkpoint only if it is not worse in any compared metric. First arrival at an LC is accepted and stored unconditionally (:150-160, :236-246).
  Hence: reject <=> dominated by (or equal to) the single stored point; with one compared metric this is exact Dijkstra-like pruning; with two or more it is not (the stored point is not the frontier, and incomparable arrivals never tighten it).
* **Result** for NetworkIntegration: `visitBFS` (NetworkIntegration.cpp:122-129) records the turns of the FIRST visit of each target line (bitvector dedupe), `N = visited+1`, `TD = sum(turns)`. The FIFO queue is layered by `turns` (initial 0, every enqueue +1), so the first visit is at the minimum number of turns among all paths that satisfy the walking limit (and the other limits). **Native semantics under walking+turns: depth = minimum turns over walking-feasible paths (reach set = lines reachable within the walking limit measured to the line midpoint), NOT turns along the walking-shortest path.** Verified (section 5): in 232/806 (random N=100, r=300) and 1358/4164 (N=200, r=500) origin-target pairs the walking-shortest path has more turns than the reported depth.
* **Why Reach (DIST_NONE) is cheap** (Reach.cpp:65): with `DIST_NONE` the only compared metrics are those in the mask; for a walking limit that is a single metric, so an arrival is accepted only if it strictly lowers walking (the stored value always equals the best so far): measured `acc_incomp = 0` and 4,672 states total for the 100-line graph at 300 m (vs >30 M for network_integration, which adds turns via DIST_LINES). Reach with walking + steps/angular also has two metrics but the second is bounded (6 steps: 5,919 states) - except walking+axmeter (unbounded second metric): bad_alloc.

## 4. Instrumented scratch build (task 4)

* Patch: `scratchpad/audit/W/instr.patch` (generated by `mkinstr.py` from the pristine `src/vendor/pstalgo/src/BFS.cpp`, applied ONLY to `W/pkg/src/vendor/pstalgo/src/BFS.cpp`; header untouched). `Makevars` compiles `.rpst-build/BFS.o` straight from `vendor/pstalgo/src/BFS.cpp` (src/Makevars: rule `.rpst-build/BFS.o`), so no generated copy and no hash bypass was needed (install-time does not verify vendor hashes; the `tools/test-*.R` hash tests were not run). Counters are `thread_local` and appended per origin to the CSV named by env `RPST_BFS_STATS` (no R/.Call change); env `RPST_BFS_CAP=n` aborts one origin after n dequeues (diagnostic only; results then wrong, counts valid).
* Counters per origin (columns of the CSVs in `W/logs/`): origin, enq, deq, rej_deq (rejected at dequeue), rej_exit (rejected at expansion), first (first arrival at an LC), acc_dom (accepted, improves without being worse anywhere), acc_incomp (accepted although worse in some compared metric), acc_redundant (accepted but weakly dominated by an earlier accepted state at the same LC; history capped at 4,096 per LC), maxq, maxlinedeq (max dequeues of one line = repeated expansions), nlines_expanded, nlines_visited, ms, capped, maxturns. `enq == deq` whenever no cap triggered.
* Experiment harness: `tm.py` (fresh process, RLIMIT_AS 3.4 GB, `timeout`), `run.R`, `sweep.py`. Barnsbury 400 m was NOT run on the stock/instrumented build. All stock runs ran under `timeout 40-60` and RLIMIT_AS <= 3.5 GB. One direct `Rscript` call without limits (reference check on random:200:3 at 500 m) was killed by the OOM killer before I switched everything to the wrapper: no persistent effect.

### 4a. Barnsbury (1,915 lines, with unlinks), network_integration, stock logic, instrumented build (times about 1.5-2x the uninstrumented 0.03 / 1.4 / 2.5 / 9.3 s)

| radius | analysis s (instr.) | states dequeued (all origins) | median / p99 / max per origin | share of states in top 1% origins | max queue | max repeats of one line | accepted incomparable | of which redundant | acc non-dominated | lines expanded vs visited (mean) |
|---|---|---|---|---|---|---|---|---|---|---|
| w=100 | 0.01 | 14,004 | 5 / 33 / 101 | 0.06 | 26 | 22 | 2,579 | 570 | 364 | 4.9 / 2.1 |
| w=150 | 0.02 | 27,869 | 11 / 63 / 221 | 0.07 | 63 | 54 | 7,910 | 2,474 | 1,430 | 7.8 / 3.6 |
| w=200 | 0.02 | 72,809 | 19 / 152 / 18,654 | 0.37 | 91 | 6,194 | 63,361 | 51,971 | 3,980 | 11.4 / 5.8 |
| w=250 | 0.09 | 388,542 | 31 / 303 / 293,683 | 0.81 | 617 | 91,413 | 614,235 | 593,531 | 8,428 | 15.6 / 8.7 |
| w=275 | 2.7 | 21,848,882 | 39 / 480 / 20,490,102 | 1.00 | 1,536,074 | 8,058,946 | 32,651,596 | 32,624,417 | 11,705 | 17.9 / 10.4 |
| w=300 | 4.0 | 31,122,351 | 48 / 1,432 / 20,490,112 | 1.00 | 1,536,074 | 8,058,946 | 50,985,192 | 50,950,202 | 15,628 | 20.5 / 12.2 |
| w=325 | 15.6 | 109,032,072 | 58 / 2,798 / 73,481,613 | 1.00 | 8,553,888 | 18,446,621 | 175,647,222 | 175,602,820 | 20,465 | 23.3 / 14.2 |
| w=350 | 18.5 | 135,413,256 | 70 / 4,206 / 73,481,624 | 1.00 | 8,553,888 | 18,446,621 | 227,033,405 | 226,977,869 | 26,234 | 26.1 / 16.5 |
| steps=3 | 0.06 | 269,977 | 112 / 492 / 866 | 0.04 | 660 | 19 | 0 | 0 | 0 | 74.2 / 74.2 |
| steps=5 | 0.18 | 1,590,444 | 757 / 2,204 / 3,359 | 0.03 | 1,559 | 20 | 0 | 0 | 0 | 320 / 320 |
| steps=7 | 0.41 | 4,381,764 | 2,219 / 4,639 / 5,343 | 0.02 | 1,694 | 24 | 0 | 0 | 0 | 755 / 755 |
| unrestricted | 1.10 | 13,537,135 | 7,069 / 7,069 / 7,069 | 0.01 | 1,731 | 24 | 0 | 0 | 0 | 1915 / 1915 |

(Only the 400 m run was withheld.) Per-origin distribution: it is a handful of pathological origins, not a uniform cost. At w=275 three origins carry
>1e5 states (1210: 20.49 M, 125: 0.95 M, 1810: 0.28 M) and at w=350 seven; the median origin needs 70 states (steps=3 needs 112). The pathological
origins are lines adjacent to hub lines with 17-31 crossings (line 1210, length 418 m, 8 crossings, its neighbours have 26/17/16/13 crossings; max
degree in Barnsbury is 31, median 4); they reach only 10-28 lines. The cost therefore tracks (number of walking-feasible paths in a dense cluster), not line count or reach size.
`maxturns` (max `turns` of a dequeued state) is 1,384 at w=300 although at most 30 lines are reachable: the search keeps circling cycles.

### 4b. Synthetic random line networks (oblique crossings), stock logic vs prototype

Generator `run.R gen_random` (N segments, centres uniform in a square of side 110*sqrt(N) m, length ~ lognormal(250 m), uniform angle); orthogonal "stagger" grids
(`gen_stagger`) do NOT blow up (mean 8 -> 17 reached lines at 400-600 m, <=4 states per expanded line) - the defect needs oblique geometry with many alternative short cycles.
Times for stock are from the instrumented build and, for the first rows, under CPU contention with other jobs. "NOT FINISHED" = 40 s timeout or 3.4 GB cap;
radii above the first failure for the same N were not attempted for stock. Proto columns = prototype (section 7) instrumented build.

| graph (lines) | walking m | reached lines mean/max | stock states (dequeued) | stock max single-origin | stock top-1% origins share | stock s | proto states | proto max single-origin | proto s | stock/proto states |
|---|---|---|---|---|---|---|---|---|---|---|
| random N=200 | 100 | 2.29/6 | 1,635 | 70 | 0.07 | 0.003 | 1568 | 61 | 0.003 | 1x |
| random N=200 | 200 | 5.07/14 | 5,071 | 172 | 0.07 | 0.006 | 4442 | 138 | 0.004 | 1x |
| random N=200 | 250 | 7.23/21 | 22,650 | 12,618 | 0.65 | 0.006 | 6611 | 174 | 0.005 | 3x |
| random N=200 | 300 | 9.44/24 | 1,845,488 | 909,917 | 0.97 | 0.254 | 8919 | 216 | 0.005 | 207x |
| random N=200 | 350 | 11.88/27 | 3,727,871 | 2,072,392 | 0.93 | 0.444 | 11608 | 284 | 0.006 | 321x |
| random N=200 | 400 | 14.66/36 | 94,903,787 | 79,699,428 | 0.94 | 13.821 | 15006 | 376 | 0.007 | 6324x |
| random N=200 | 450 | 17.63/43 | 155,266,138 | 137,049,888 | 0.94 | 19.383 | 19005 | 490 | 0.008 | 8170x |
| random N=200 | 500 | 21.20/51 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 23909 | 614 | 0.008 | - |
| random N=200 | 600 | 28.92/64 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 35332 | 760 | 0.012 | - |
| random N=200 | 700 | 37.22/75 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 47340 | 834 | 0.013 | - |
| random N=500 | 100 | 2.32/6 | 4,475 | 68 | 0.06 | 0.005 | 4282 | 45 | 0.005 | 1x |
| random N=500 | 200 | 5.82/18 | 15,321 | 387 | 0.08 | 0.007 | 12864 | 121 | 0.007 | 1x |
| random N=500 | 250 | 7.96/20 | 25,668 | 695 | 0.10 | 0.009 | 18848 | 165 | 0.011 | 1x |
| random N=500 | 300 | 10.50/26 | 44,347 | 3,592 | 0.17 | 0.017 | 25977 | 201 | 0.011 | 2x |
| random N=500 | 350 | 13.20/32 | 1,076,304 | 991,584 | 0.94 | 0.153 | 34264 | 272 | 0.012 | 31x |
| random N=500 | 400 | 16.19/39 | 2,632,272 | 2,419,994 | 0.96 | 0.498 | 43554 | 331 | 0.020 | 60x |
| random N=500 | 450 | 19.27/49 | 7,170,746 | 6,476,230 | 0.97 | 0.991 | 54325 | 383 | 0.016 | 132x |
| random N=500 | 500 | 22.63/51 | 11,306,158 | 9,967,131 | 0.96 | 1.573 | 66421 | 446 | 0.018 | 170x |
| random N=500 | 600 | 30.07/65 | 20,346,634 | 10,056,245 | 0.84 | 2.683 | 95802 | 610 | 0.025 | 212x |
| random N=500 | 700 | 38.18/77 | 125,337,948 | 77,790,345 | 0.88 | 18.434 | 131791 | 831 | 0.031 | 951x |
| random N=1000 | 100 | 2.33/9 | 11,476 | 301 | 0.13 | 0.011 | 10331 | 116 | 0.010 | 1x |
| random N=1000 | 200 | 5.87/19 | 50,309 | 7,215 | 0.25 | 0.016 | 31044 | 180 | 0.015 | 2x |
| random N=1000 | 250 | 8.24/22 | 28,722,478 | 22,132,394 | 1.00 | 4.092 | 45900 | 275 | 0.018 | 626x |
| random N=1000 | 300 | 10.88/30 | 72,034,731 | 32,120,591 | 1.00 | 10.102 | 63879 | 379 | 0.022 | 1128x |
| random N=1000 | 350 | 13.96/37 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 84841 | 465 | 0.036 | - |
| random N=1000 | 400 | 17.37/46 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 109486 | 564 | 0.049 | - |
| random N=1000 | 450 | 21.16/54 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 138505 | 753 | 0.054 | - |
| random N=1000 | 500 | 25.32/60 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 171526 | 893 | 0.048 | - |
| random N=1000 | 600 | 34.66/78 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 249343 | 1131 | 0.063 | - |
| random N=1000 | 700 | 44.99/92 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 341686 | 1376 | 0.082 | - |
| random N=1500 | 100 | 2.24/7 | 13,935 | 489 | 0.11 | 0.012 | 12850 | 106 | 0.012 | 1x |
| random N=1500 | 200 | 5.54/16 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 37658 | 216 | 0.019 | - |
| random N=1500 | 250 | 7.68/18 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 55261 | 249 | 0.025 | - |
| random N=1500 | 300 | 10.15/23 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 76740 | 278 | 0.030 | - |
| random N=1500 | 350 | 13.02/29 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 102445 | 303 | 0.041 | - |
| random N=1500 | 400 | 16.15/38 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 132792 | 373 | 0.039 | - |
| random N=1500 | 450 | 19.70/45 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 168037 | 494 | 0.050 | - |
| random N=1500 | 500 | 23.51/54 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 209590 | 597 | 0.087 | - |
| random N=1500 | 600 | 32.14/68 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 311099 | 817 | 0.086 | - |
| random N=1500 | 700 | 42.05/95 | NOT FINISHED (40 s / 3.4 GB cap) | - | - | >40 | 440020 | 1049 | 0.146 | - |


Smaller probes: random:100 (seed 5), 100 lines: stock w=275 -> one origin (49) exceeds 30,000,000 dequeues (cap) while expanding 11 lines, maxq 27 M, one line dequeued 7.6 M times; at w=300/350/400 respectively 1/2/3 origins hit the cap; stock w=300 without cap died at 3.26 GB (rc=1) after ~27 s. The same case: prototype 4,672 states, 0.002 s. random:1500 stock w=150 died at 3.1 GB / 40 s.
So states per origin are unbounded by line count: 100 lines, > 3e7 queued states for one origin.

## 5. Correctness despite the blow-up (task 5)

* Independent reference `W/ref.py` (pure Python, own segment-intersection graph build, layered exact DP over turns with best walking per (line, entry crossing), reports N and TD per origin). Semantics: origin = midpoint, walking to a crossing accumulates along lines, each line change costs 1 turn, a target is reached if walking-to-crossing + |pos - midpoint| <= r (and turns <= steps limit), depth = fewest turns of a feasible path.
* Stock native vs reference (`node_count`, `total_depth` exact): random N=100 seeds 3 (r=150/300/500), 4 (400), N=200 (150/300), steps+walking (400/n2, 500/n3, 500/n1): **0 mismatches in all 10 cases that finished**. (random:100:5 at 400 did not finish on stock.) So the native result IS correct (it computes the minimum-turn walking-feasible depth); the blow-up is only wasted work.
* Prototype native vs reference (cases where stock cannot finish): random:200:3 at 350/500/800, random:300:9 at 500 and 800/n=5, random:100:5 at 300/600/1500, random:150:11 at 1200: **0 mismatches**.
* Stock vs prototype (section 7) bit-identical.

## 6. Which other analyses share the logic (task 6)

`CPSTBFS` (BFS.h/BFS.cpp) is used by exactly: `NetworkIntegration.cpp:69` (DIST_LINES), `Reach.cpp:65` (DIST_NONE), `AttractionReach.cpp:215` (distance type from the request: straight/walking/steps/angular/axmeter/none). Not used by `network_betweenness`, `od_betweenness`
(priority queue, ODBetweenness.cpp:191), `attraction_distance`, segment analyses, angular analyses (no BFS rows were produced when run with the instrumented build; their code uses other engines). Instrumented probes on random:100:5 (the graph where NI explodes):

| call | states | note |
|---|---|---|
| network_reach w=300 | 4,672, acc_incomp 0 | one compared metric: cheap |
| network_reach w=300,s=250 | 4,401 | straight is not a compared metric |
| network_reach w=300,n=6 | 5,919 (acc_incomp 4,432, 2,296 redundant) | incomparable but turns bounded |
| network_reach w=300,a=720 | 7,233 | angle second metric, bounded |
| network_reach w=300,x=5000 | **>30 M for one origin (cap), stock without cap: std::bad_alloc after 14.6 s / 2.9 GB** | walking+axmeter blows up; prototype 0.003 s |
| attraction_reach (30 point origins) distance steps + walking 300 / walking dist / none | 762 / 618 / 618 | same acceptance logic (acc_incomp 426 in the steps case) but only 30 origins and none of them in the hub region: blow-up not shown, NOT proven absent |

So the blow-up is not specific to NetworkIntegration: it is a property of the shared acceptance rule whenever two or more independently compared metrics exist and one is not bounded (NI always has turns as DIST_LINES; for Reach the user must combine walking with an unbounded second metric or an attraction analysis with steps distance + walking limit).

## 7. Candidate solutions (task 7)

| candidate | correctness argument vs existing semantics | complexity | evidence needed |
|---|---|---|---|
| **A. Pareto frontier per line crossing** (prototype below) | reject an arrival iff some earlier ACCEPTED arrival at the same LC is no worse in every metric the original rule compares; a rejected state is dominated, all its continuations (walking additive, turns +1 per step, float addition monotone) are dominated by the continuations of the dominating state, and the dominating state has <= turns so is expanded earlier/in the same FIFO layer; therefore the first-visit turns (NI), the visited set (Reach) and best scores (Attraction) are unchanged; with a single compared metric it reduces exactly to the current rule | frontier size <= number of distinct turn values with strictly decreasing walking (small in practice, <= tens); per arrival O(frontier); memory O(LC x frontier) | numerical equivalence on all cases where stock finishes (done, below); reference comparison where stock cannot finish (done) |
| B. Update the single checkpoint on every accepted incomparable arrival | NOT correct: overwriting loses the other frontier point and can drop states that were not dominated | - | rejected |
| C. Dedup of queued states (hash set of (LC,walking,turns)) | exact duplicates only; does not remove dominated states, no bound | no | insufficient |
| D. Dijkstra/priority queue by walking per turn layer | helps ordering (fewer accepts) but still needs the frontier; changes processing order (float ties in attraction scores) | O(E log) | extra |
| E. Separate bounded search for walking (min-turn feasible depth by layered DP, as in ref.py) | exact semantics but a second implementation that must be validated bit-for-bit incl. float32 tie behaviour | O(turns x LC x frontier) | large |
| F. R-side restriction (reject walking/axmeter on network_integration, or require steps with walking) | no change in semantics, loses valid functionality (class F) and a steps cap is a different quantity; steps+walking is already cheap | trivial | docs + tests; stop-gap only |
| G. Allow cancellation (progress callback / interrupt) | independent safety measure | small | needs R-side checkUserInterrupt design |

Original recommendation, SUPERSEDED by the maintainer's scope decision (no native change): A as an rPST build-time portability patch of the generated BFS copy (like `src/portability/*.R` + `inst/upstream/build-inputs/`), with a documented class-D classification only after the numerical-equivalence suite below; until then document walking on network_integration as E (performance-unsafe), optionally refuse walking-only radii above a documented threshold or require an accompanying steps limit (stop-gap F), and add cancellation (G). Multi-km radii: with A, Barnsbury w=1000: 0.29 s, 2000: 2.06 s, 5000: 16.5 s (uninstrumented prototype), w=1e5 (everything reachable): 23.8 s versus 0.6 s for the unrestricted run - still polynomial and memory flat (<150 MB); a per-layer ordering by walking (D) would be the next improvement.

### Prototype measurements (research record only)

A scratch prototype of candidate A was built outside the repository to test the mechanism. Its diff is deliberately not kept here: no native modification is planned or approved (see the status note at the top).

Measured effects (uninstrumented prototype vs stock; `W/logs/equiv_*.txt`):

* **Bit-identical results** (`identical()` on the whole result data.frame/vectors, saveRDS comparison) in every case where stock finishes: network_integration 75/75 on random N=100,200,300,500,1000, stagger 500/1500 (w=100..500, w+steps, steps, none) + 11/11 on Barnsbury (w=100,200,250,275,300,350; w=500,n=4; w=2000,n=3; n=3; n=7; none) and Barnsbury w=1e5 identical to unrestricted; network_reach + attraction_reach (steps, walking, none distances; w, w+n, w+a, w+s, w+x, n, none): 68/68. Total 154 identical, 0 different; 5 integration cases where stock failed (3 memory cap, 2 timeout) were checked against the Python reference instead.
* Barnsbury w=300: 31,122,351 -> 104,052 states, analysis 2.5 s -> 0.023 s; w=350: 135,413,256 -> 148,185 states, 9.3 s -> 0.024 s; w=400: 202,686 states, 0.034 s (stock 400 m was not run). maxturns 1,384 -> 8-9.
* Synthetic: random N=200 w=450: 155,266,138 -> 19,005 states (19.4 s -> 0.008 s); N=1500 w=700 (stock never finishes): 0.146 s. network_reach w=300,x=5000: stock bad_alloc 2.9 GB -> prototype 0.003 s.
* Overhead where stock is already cheap: none visible (equal within noise; steps=7 0.248 vs 0.233 s).

Required before any adoption (not planned): full existing testthat suite and native fixtures on a real patched build; angle/axmeter/straight metric combinations beyond the Reach/NI cases above (axmeter dominance assumes monotone accumulation; the NI/Reach cases tested were identical but no independent reference exists for axmeter/angular); multi-threaded AttractionReach (each worker owns its frontier, not stress-tested); Windows/other compilers; segment-graph engines unaffected (do not use CPSTBFS).

## 8. Answer summary for classification

* Walking on `network_integration`: rPST wrapper = G (correct mapping). Upstream restriction = C (Python/UI only, since 5f3f70f, in v3.3.1/v3.3.2, reason not documented). Performance of the exposed combination = E (accepted by native, correct, but pathologically slow/memory-hungry on dense oblique networks; root cause is the vendored acceptance rule, fixable by the Pareto-frontier prototype above). Suggested row note: recommendation = investigate (apply patch A via portability layer after approval) / until then document + keep.
* Same defect class affects `network_reach` with walking + axmeter (and potentially `attraction_reach` with steps distance + walking limit, untested at scale): E.

## 9. What was NOT tested

Barnsbury 400 m on the stock/instrumented build (rule); stock native at radii above the first failure for each synthetic N; junctions = TRUE; output_file/stream paths (same native call); segment graphs; attraction_reach on hub-adjacent origins at scale and with multiple workers under stress; angular/axmeter/straight reference semantics (no independent reference; only stock-vs-prototype equality); real-world networks other than Barnsbury; Windows/macOS; the repo test-suite and vendor-hash tests against a patched vendor tree; R-interrupt behaviour (only inferred from the absent callback); order-of-magnitude of QGIS-plugin behaviour (the PST QGIS plugin was not run; upstream native test only covers a 5-line chain with walking); upstream issue tracker (offline) for rationale; per-layer walking ordering (candidate D) and a faster multi-km variant.

## 10. Files

All under `<scratch>/audit/W/`: `instr.patch`, `mkinstr.py`, `mkproto.py`, `run.R`, `tm.py`, `ref.py`, `ref_alt.py`, `sweep.py`, `sweep_proto.py`, `equiv.sh`, `summ.py`, `cmp.R`, build logs, and `logs/` (per-origin CSVs, `sweep_random.txt`, `sweep_random_proto.txt`, `sweep_table.md`, `equiv_ni.txt`, `equiv_barn.txt`, `equiv_other.txt`, `barn.txt`).
