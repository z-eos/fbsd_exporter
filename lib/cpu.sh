#!/bin/sh
# lib/cpu.sh
#
# CPU metrics collector

collect_cpu() {
    [ "$ENABLE_CPU" != "1" ] && return 0

    # _sysctl returns 0 on fail, so use defaults
    ncpu=$(_sysctl -n hw.ncpu)
    ncpu=${ncpu:-1}

    # Optimized: Use shell parameter expansion instead of a complex 'sed' regex
    hz_raw=$(_sysctl -n kern.clockrate)
    hz="${hz_raw#*hz = }"
    hz="${hz%%,*}"
    hz=${hz:-128}

    ################
    # per-CPU time #
    ################
    if [ "$ENABLE_CPU_PERCPU_TIME" = "1" ]; then
	metric_help "${METRIC_NAME_PREFIX}_cpu_percpu_time_seconds_total" "per-CPU time in seconds"
	metric_type "${METRIC_NAME_PREFIX}_cpu_percpu_time_seconds_total" "counter"
	# kern.cp_times: user, nice, system, interrupt, idle per CPU
	_sysctl -n kern.cp_times | _awk -v ncpu="$ncpu" -v hz="$hz" '
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
		printf "%s_cpu_percpu_time_seconds_total{cpu=\"%d\",mode=\"%s\"} %.2f\n", pfx, cpu, state, seconds
	    }
	}
    }'
    fi

    #######################
    # per-CPU temperature #
    #######################
    if [ "$ENABLE_CPU_PERCPU_TEMPERATURE" = "1" ]; then
	metric_help "${METRIC_NAME_PREFIX}_cpu_percpu_temperature_celsius" "per-CPU temperature in Celsius"
	metric_type "${METRIC_NAME_PREFIX}_cpu_percpu_temperature_celsius" "gauge"

	# Output format example: dev.cpu.0.temperature: 40.0C
	_sysctl dev.cpu | _awk '
	/^dev\.cpu\.[0-9]+\.temperature:/ {
	    split($1, parts, ".")
	    cpu_idx = parts[3]
	    val = $2
	    gsub(/C$/, "", val)
	    printf "%s_cpu_percpu_temperature_celsius{cpu=\"%s\"} %s\n", pfx, cpu_idx, val
	}'
    fi

    ####################
    # Global CPU Stats #
    ####################

    # 1. Standard Prometheus Counter (Raw Seconds)
    metric_help "${METRIC_NAME_PREFIX}_cpu_seconds_total" "Total aggregated CPU time in seconds"
    metric_type "${METRIC_NAME_PREFIX}_cpu_seconds_total" "counter"

    # 2. Legacy/Convenience Percentage (Gauge)
    metric_help "${METRIC_NAME_PREFIX}_cpu_usage_percent" "Aggregated CPU usage in percent"
    metric_type "${METRIC_NAME_PREFIX}_cpu_usage_percent" "gauge"

    _sysctl -n kern.cp_time | _awk -v hz="$hz" '
    BEGIN {
	split("user nice system interrupt idle", states)
    }
    {
	total_ticks = $1 + $2 + $3 + $4 + $5

	for (i = 1; i <= 5; i++) {
	    # Output Raw Seconds (Counter)
	    ticks = $i
	    seconds = ticks / hz
	    printf "%s_cpu_seconds_total{mode=\"%s\"} %.2f\n", pfx, states[i], seconds

	    # Output Percentages (Gauge)
	    pct = (ticks / total_ticks) * 100
	    printf "%s_cpu_usage_percent{mode=\"%s\"} %.2f\n", pfx, states[i], pct
	}
    }'

    #################
    # Load averages #
    #################
    metric_help "${METRIC_NAME_PREFIX}_sys_loadavg" "System load average"
    metric_type "${METRIC_NAME_PREFIX}_sys_loadavg" "gauge"

    _sysctl -n vm.loadavg | _awk '{
	printf "%s_sys_loadavg{period=\"1m\"} %s\n", pfx, $2
	printf "%s_sys_loadavg{period=\"5m\"} %s\n", pfx, $3
	printf "%s_sys_loadavg{period=\"15m\"} %s\n", pfx, $4
    }'

    ###################################
    # Context switches and interrupts #
    ###################################
    metric_help "${METRIC_NAME_PREFIX}_sys_context_switches_total" "Total context switches"
    metric_type "${METRIC_NAME_PREFIX}_sys_context_switches_total" "counter"

    metric_help "${METRIC_NAME_PREFIX}_sys_traps_total" "Total traps"
    metric_type "${METRIC_NAME_PREFIX}_sys_traps_total" "counter"

    metric_help "${METRIC_NAME_PREFIX}_sys_syscalls_total" "Total syscalls"
    metric_type "${METRIC_NAME_PREFIX}_sys_syscalls_total" "counter"

    metric_help "${METRIC_NAME_PREFIX}_sys_interrupts_dev_total" "Total device interrupts"
    metric_type "${METRIC_NAME_PREFIX}_sys_interrupts_dev_total" "counter"

    metric_help "${METRIC_NAME_PREFIX}_sys_interrupts_soft_total" "Total softwaree interrupts"
    metric_type "${METRIC_NAME_PREFIX}_sys_interrupts_soft_total" "counter"

    _sysctl vm.stats.sys | _awk '
	/^vm.stats.sys.v_swtch:/ { printf "%s_sys_context_switches_total %s\n", pfx, $2 }
	/^vm.stats.sys.v_trap:/  { printf "%s_sys_traps_total %s\n", pfx, $2 }
	/^vm.stats.sys.v_syscall:/ { printf "%s_sys_syscalls_total %s\n", pfx, $2 }
	/^vm.stats.sys.v_intr:/  { printf "%s_sys_interrupts_dev_total %s\n", pfx, $2 }
	/^vm.stats.sys.v_soft:/  { printf "%s_sys_interrupts_soft_total %s\n", pfx, $2 }
    '

    #############
    # CPU count #
    #############
    metric_help "${METRIC_NAME_PREFIX}_sys_cpu_count" "Number of CPUs"
    metric_type "${METRIC_NAME_PREFIX}_sys_cpu_count" "gauge"
    metric "${METRIC_NAME_PREFIX}_sys_cpu_count" "" "$ncpu"
}
