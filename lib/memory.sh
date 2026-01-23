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

    # Get various page counts
    for stat in v_free_count v_active_count v_inactive_count v_wire_count v_cache_count; do
	count=$(sysctl -n vm.stats.vm.$stat || echo 0)
	type=$(echo "$stat" | sed 's/v_//; s/_count//')
	bytes=$((count * pagesize))
	metric "${METRIC_NAME_PREFIX}_memory_pages" "type=\"${type}\"" "$count"
	metric "${METRIC_NAME_PREFIX}_memory_bytes" "type=\"${type}\"" "$bytes"
    done

    # Page faults
    metric_help "${METRIC_NAME_PREFIX}_memory_page_faults_total" "Page faults"
    metric_type "${METRIC_NAME_PREFIX}_memory_page_faults_total" "counter"

    vm_faults=$(sysctl -n vm.stats.vm.v_vm_faults || echo 0)
    metric "${METRIC_NAME_PREFIX}_memory_page_faults_total" "type=\"total\"" "$vm_faults"

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
