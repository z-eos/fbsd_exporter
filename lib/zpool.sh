#!/bin/sh
# lib/zpool.sh
# Zpool metrics collector

collect_zpool() {
    [ "$ENABLE_ZPOOL" != "1" ] && return 0
    if has_zfs; then

	metric_help "${METRIC_NAME_PREFIX}_zpool_size_bytes" "Total size of the storage pool in bytes"
	metric_type "${METRIC_NAME_PREFIX}_zpool_size_bytes" "gauge"

	metric_help "${METRIC_NAME_PREFIX}_zpool_alloc_bytes" "Amount of storage used within the pool in bytes"
	metric_type "${METRIC_NAME_PREFIX}_zpool_alloc_bytes" "gauge"

	metric_help "${METRIC_NAME_PREFIX}_zpool_free_bytes" "The amount of free space available in the pool in bytes"
	metric_type "${METRIC_NAME_PREFIX}_zpool_free_bytes" "gauge"

	metric_help "${METRIC_NAME_PREFIX}_zpool_frag" "The percent of fragmentation in the pool"
	metric_type "${METRIC_NAME_PREFIX}_zpool_frag" "gauge"

	metric_help "${METRIC_NAME_PREFIX}_zpool_dedup" "Zpool deduplication coefficient"
	metric_type "${METRIC_NAME_PREFIX}_zpool_dedup" "gauge"

	metric_help "${METRIC_NAME_PREFIX}_zpool_health" "The current health of the pool, one of ONLINE, DEGRADED, FAULTED, OFFLINE, REMOVED, UNAVAIL."
	metric_type "${METRIC_NAME_PREFIX}_zpool_health" "gauge"

	zpool list -Hp -o name,size,alloc,free,frag,dedup,health 2>/dev/null | tr -d '%' | tr -d 'x' | _awk '
	BEGIN {
	      split("STUB ONLINE DEGRADED FAULTED OFFLINE REMOVED UNAVAIL", states)
	}
	{
	    name = $1
	    size = $2
	    alloc = $3
	    free = $4
	    frag = $5
	    dedup = $6
	    health = 0

	    for (i = 1; i <= 6; i++) {
		if ($7 == states[i]) {
		    health = i
		    break
		}
	    }

	    printf "%s_zpool_size_bytes{name=\"%s\"} %s\n", pfx, name, size
	    printf "%s_zpool_alloc_bytes{name=\"%s\"} %s\n", pfx, name, alloc
	    printf "%s_zpool_free_bytes{name=\"%s\"} %s\n", pfx, name, free
	    printf "%s_zpool_frag{name=\"%s\"} %s\n", pfx, name, frag
	    printf "%s_zpool_dedup{name=\"%s\"} %s\n", pfx, name, dedup
	    printf "%s_zpool_health{name=\"%s\"} %s\n", pfx, name, health

	}'
    fi

}
