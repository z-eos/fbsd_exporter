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

    # Pool health and capacity (in slow collector, but include basic here)
    collect_zfs_pools_basic
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

collect_zfs_pools_basic() {
    metric_help "${METRIC_NAME_PREFIX}_zfs_pool_capacity_bytes" "ZFS pool capacity"
    metric_type "${METRIC_NAME_PREFIX}_zfs_pool_capacity_bytes" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_zfs_pool_allocated_bytes" "ZFS pool allocated space"
    metric_type "${METRIC_NAME_PREFIX}_zfs_pool_allocated_bytes" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_zfs_pool_free_bytes" "ZFS pool free space"
    metric_type "${METRIC_NAME_PREFIX}_zfs_pool_free_bytes" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_zfs_pool_fragmentation_ratio" "ZFS pool fragmentation"
    metric_type "${METRIC_NAME_PREFIX}_zfs_pool_fragmentation_ratio" "gauge"

    zpool list -Hp -o name,size,alloc,free,frag 2>/dev/null | \
    _awk '{
	pool = $1
	size = $2
	alloc = $3
	free = $4
	frag = $5

	# Remove % from fragmentation
	gsub(/%/, "", frag)
	frag_ratio = frag / 100

	printf "%s_zfs_pool_capacity_bytes{pool=\"%s\"} %s\n", pfx, pool, size
	printf "%s_zfs_pool_allocated_bytes{pool=\"%s\"} %s\n", pfx, pool, alloc
	printf "%s_zfs_pool_free_bytes{pool=\"%s\"} %s\n", pfx, pool, free
	printf "%s_zfs_pool_fragmentation_ratio{pool=\"%s\"} %.4f\n", pfx, pool, frag_ratio
    }'
}

# Pool health status - for slow collector
collect_zfs_pool_health() {
    [ "$ZFS_POOL_HEALTH_CHECK" != "1" ] && return 0

    metric_help "${METRIC_NAME_PREFIX}_zfs_pool_health" "ZFS pool health status (0=online, 1=degraded, 2=faulted, 3=unavail)"
    metric_type "${METRIC_NAME_PREFIX}_zfs_pool_health" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_zfs_pool_error_count" "ZFS pool error counts"
    metric_type "${METRIC_NAME_PREFIX}_zfs_pool_error_count" "gauge"

    zpool status 2>/dev/null | _awk '
    /^  pool:/ { pool = $2 }
    /^ state:/ {
	state = $2
	status = 3  # unavail
	if (state == "ONLINE") status = 0
	else if (state == "DEGRADED") status = 1
	else if (state == "FAULTED") status = 2
	printf "%s_zfs_pool_health{pool=\"%s\",state=\"%s\"} %d\n", pfx, pool, state, status
    }
    /^errors:/ {
	# errors: No known data errors
	# or: errors: 5 data errors, use '\'''-v'\'' for a list
	if ($0 ~ /No known data errors/) {
	    printf "%s_zfs_pool_error_count{pool=\"%s\",type=\"data\"} 0\n", pfx, pool
	} else if ($2 ~ /^[0-9]+$/) {
	    printf "%s_zfs_pool_error_count{pool=\"%s\",type=\"data\"} %d\n", pfx, pool, $2
	}
    }'
}
