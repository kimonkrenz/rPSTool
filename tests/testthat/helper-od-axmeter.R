# The direct OD fixture still contains the pinned engine's axmeter cases (native evidence that the limit is ignored).
# od_betweenness() rejects axmeter limits, so wrapper-level loops use only the supported cases.
od_supported_cases <- function(cases) Filter(function(c) is.null(c$args$radius$axmeter), cases)
