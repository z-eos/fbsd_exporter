#!/bin/sh
# lib/cpu.sh
#
# CPU metrics collector

collect_cpu() {
    [ "$ENABLE_CPU" != "1" ] && return 0

    metric_help "${METRIC_NAME_PREFIX}_cpu_time_seconds_total" "CPU time in seconds"
    metric_type "${METRIC_NAME_PREFIX}_cpu_time_seconds_total" "counter"

    # Get per-CPU stats using sysctl
    # kern.cp_times: user, nice, system, interrupt, idle per CPU
    ncpu=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
    hz=$(sysctl -n kern.clockrate 2>/dev/null | sed -n 's/.*[,{][[:space:]]*hz[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' || echo 128)

    sysctl -n kern.cp_times 2>/dev/null | _awk -v ncpu="$ncpu" -v hz="$hz" '
    BEGIN {
	split("user nice system interrupt idle", states)
    }
    {
	# Each CPU has 5 values
	for (cpu = 0; cpu < ncpu; cpu++) {
	    for (i = 1; i <= 5; i++) {
		idx = cpu * 5 + i
		state = states[i]
		ticks = $idx
		# Convert ticks to seconds
		seconds = ticks / hz
		printf "%s_cpu_time_seconds_total{cpu=\"%d\",mode=\"%s\"} %.2f\n", pfx, cpu, state, seconds
	    }
	}
    }'

    # Load averages
    metric_help "${METRIC_NAME_PREFIX}_loadavg" "System load average"
    metric_type "${METRIC_NAME_PREFIX}_loadavg" "gauge"

    sysctl -n vm.loadavg 2>/dev/null | _awk '{
	printf "%s_loadavg{period=\"1m\"} %s\n", pfx, $2
	printf "%s_loadavg{period=\"5m\"} %s\n", pfx, $3
	printf "%s_loadavg{period=\"15m\"} %s\n", pfx, $4
    }'

    # Context switches and interrupts
    metric_help "${METRIC_NAME_PREFIX}_context_switches_total" "Total context switches"
    metric_type "${METRIC_NAME_PREFIX}_context_switches_total" "counter"
    vm_swtch=$(sysctl -n vm.stats.sys.v_swtch 2>/dev/null || echo 0)
    metric "${METRIC_NAME_PREFIX}_context_switches_total" "" "$vm_swtch"

    metric_help "${METRIC_NAME_PREFIX}_interrupts_total" "Total interrupts"
    metric_type "${METRIC_NAME_PREFIX}_interrupts_total" "counter"
    vm_intr=$(sysctl -n vm.stats.sys.v_intr 2>/dev/null || echo 0)
    metric "${METRIC_NAME_PREFIX}_interrupts_total" "" "$vm_intr"

    # CPU count
    metric_help "${METRIC_NAME_PREFIX}_cpu_count" "Number of CPUs"
    metric_type "${METRIC_NAME_PREFIX}_cpu_count" "gauge"
    metric "${METRIC_NAME_PREFIX}_cpu_count" "" "$ncpu"
}
