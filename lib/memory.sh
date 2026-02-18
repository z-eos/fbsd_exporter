#!/bin/sh
# lib/memory.sh
#
# Memory metrics collector

collect_memory() {
    [ "$ENABLE_MEMORY" != "1" ] && return 0

    pagesize=$(sysctl -n hw.pagesize || echo 4096)

    # Physical memory
    metric_help "${METRIC_NAME_PREFIX}_memory_size_bytes" "Total physical memory"
    metric_type "${METRIC_NAME_PREFIX}_memory_size_bytes" "gauge"
    physmem=$(sysctl -n hw.physmem || echo 0)
    metric "${METRIC_NAME_PREFIX}_memory_size_bytes" "" "$physmem"

    # Memory stats from vm.stats.vm
    metric_help "${METRIC_NAME_PREFIX}_memory_pages" "Memory pages by type"
    metric_type "${METRIC_NAME_PREFIX}_memory_pages" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_memory_bytes" "Memory in bytes by type"
    metric_type "${METRIC_NAME_PREFIX}_memory_bytes" "gauge"

    # Page faults
    metric_help "${METRIC_NAME_PREFIX}_memory_page_faults_total" "Page faults"
    metric_type "${METRIC_NAME_PREFIX}_memory_page_faults_total" "counter"

    # OPTIMIZATION: Single sysctl call for all vm stats
    sysctl vm.stats.vm | _awk -v pagesize="$pagesize" '
    BEGIN {
	# Map sysctl names to metric types
	map["v_free_count"] = "free"
	map["v_active_count"] = "active"
	map["v_inactive_count"] = "inactive"
	map["v_wire_count"] = "wire"
	map["v_cache_count"] = "cache"
    }

    # Match lines like vm.stats.vm.v_free_count: 12345
    /^vm\.stats\.vm\.v_[a-z]+_count:/ {
	split($1, parts, ".")
	stat_name = parts[4]
	sub(/:$/, "", stat_name) # remove trailing colon

	if (stat_name in map) {
	    count = $2
	    type = map[stat_name]
	    bytes = count * pagesize

	    printf "%s_memory_pages{type=\"%s\"} %s\n", pfx, type, count
	    printf "%s_memory_bytes{type=\"%s\"} %s\n", pfx, type, bytes
	}
    }

    /^vm\.stats\.vm\.v_vm_faults:/ {
	printf "%s_memory_page_faults_total{type=\"total\"} %s\n", pfx, $2
    }
    '

    # Swap information
    metric_help "${METRIC_NAME_PREFIX}_swap_size_bytes" "Total swap space"
    metric_type "${METRIC_NAME_PREFIX}_swap_size_bytes" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_swap_used_bytes" "Used swap space"
    metric_type "${METRIC_NAME_PREFIX}_swap_used_bytes" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_swap_used_ratio" "Ratio of used swap"
    metric_type "${METRIC_NAME_PREFIX}_swap_used_ratio" "gauge"

    swapinfo -k | _awk 'NR > 1 && $1 != "Total" {
	total += $2 * 1024
	used += $3 * 1024
    }
    END {
	if (NR > 1) {
	    printf "%s_swap_size_bytes %d\n", pfx, total
	    printf "%s_swap_used_bytes %d\n", pfx, used
	    if (total > 0) {
		printf "%s_swap_used_ratio %.4f\n", pfx, used / total
	    }
	}
    }'
}
