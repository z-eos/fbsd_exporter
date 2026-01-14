#!/bin/sh
# lib/zfs.sh
#
# ZFS metrics collector

collect_zfs() {
    [ "$ENABLE_ZFS_CORE" != "1" ] && return 0

    if ! has_zfs; then
	log_warn "ZFS not available, skipping ZFS metrics"
	return 0
    fi

    # ZFS ARC statistics
    if [ "$ZFS_INCLUDE_ARC" = "1" ]; then
	collect_zfs_arc
    fi

}

collect_zfs_arc() {
    metric_help "${METRIC_NAME_PREFIX}_zfs_arc_size_bytes" "ARC size in bytes"
    metric_type "${METRIC_NAME_PREFIX}_zfs_arc_size_bytes" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_zfs_arc_target_bytes" "ARC target size in bytes"
    metric_type "${METRIC_NAME_PREFIX}_zfs_arc_target_bytes" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_zfs_arc_max_bytes" "ARC maximum size in bytes"
    metric_type "${METRIC_NAME_PREFIX}_zfs_arc_max_bytes" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_zfs_arc_hits_total" "ARC hits"
    metric_type "${METRIC_NAME_PREFIX}_zfs_arc_hits_total" "counter"

    metric_help "${METRIC_NAME_PREFIX}_zfs_arc_misses_total" "ARC misses"
    metric_type "${METRIC_NAME_PREFIX}_zfs_arc_misses_total" "counter"

    # Read ARC stats from sysctl
    arc_size=$(sysctl -n kstat.zfs.misc.arcstats.size 2>/dev/null || echo 0)
    arc_target=$(sysctl -n kstat.zfs.misc.arcstats.c 2>/dev/null || echo 0)
    arc_max=$(sysctl -n kstat.zfs.misc.arcstats.c_max 2>/dev/null || echo 0)
    arc_hits=$(sysctl -n kstat.zfs.misc.arcstats.hits 2>/dev/null || echo 0)
    arc_misses=$(sysctl -n kstat.zfs.misc.arcstats.misses 2>/dev/null || echo 0)

    metric "${METRIC_NAME_PREFIX}_zfs_arc_size_bytes" "" "$arc_size"
    metric "${METRIC_NAME_PREFIX}_zfs_arc_target_bytes" "" "$arc_target"
    metric "${METRIC_NAME_PREFIX}_zfs_arc_max_bytes" "" "$arc_max"
    metric "${METRIC_NAME_PREFIX}_zfs_arc_hits_total" "" "$arc_hits"
    metric "${METRIC_NAME_PREFIX}_zfs_arc_misses_total" "" "$arc_misses"

    # Calculate hit rate
    if [ "$arc_hits" -gt 0 ] || [ "$arc_misses" -gt 0 ]; then
	total=$((arc_hits + arc_misses))
	if [ "$total" -gt 0 ]; then
	    hit_rate=$(_awk "BEGIN {printf \"%.4f\", $arc_hits / $total}")
	    metric_help "${METRIC_NAME_PREFIX}_zfs_arc_hit_ratio" "ARC hit ratio"
	    metric_type "${METRIC_NAME_PREFIX}_zfs_arc_hit_ratio" "gauge"
	    metric "${METRIC_NAME_PREFIX}_zfs_arc_hit_ratio" "" "$hit_rate"
	fi
    fi

    # L2ARC stats if available
    l2arc_hits=$(sysctl -n kstat.zfs.misc.arcstats.l2_hits 2>/dev/null || echo 0)
    if [ "$l2arc_hits" != "0" ]; then
	metric_help "${METRIC_NAME_PREFIX}_zfs_l2arc_hits_total" "L2ARC hits"
	metric_type "${METRIC_NAME_PREFIX}_zfs_l2arc_hits_total" "counter"

	metric_help "${METRIC_NAME_PREFIX}_zfs_l2arc_misses_total" "L2ARC misses"
	metric_type "${METRIC_NAME_PREFIX}_zfs_l2arc_misses_total" "counter"

	metric_help "${METRIC_NAME_PREFIX}_zfs_l2arc_size_bytes" "L2ARC size in bytes"
	metric_type "${METRIC_NAME_PREFIX}_zfs_l2arc_size_bytes" "gauge"

	l2arc_misses=$(sysctl -n kstat.zfs.misc.arcstats.l2_misses 2>/dev/null || echo 0)
	l2arc_size=$(sysctl -n kstat.zfs.misc.arcstats.l2_size 2>/dev/null || echo 0)

	metric "${METRIC_NAME_PREFIX}_zfs_l2arc_hits_total" "" "$l2arc_hits"
	metric "${METRIC_NAME_PREFIX}_zfs_l2arc_misses_total" "" "$l2arc_misses"
	metric "${METRIC_NAME_PREFIX}_zfs_l2arc_size_bytes" "" "$l2arc_size"
    fi
}
