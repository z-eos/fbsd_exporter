#!/bin/sh
# lib/cpu.sh
#
# CPU metrics collector

collect_cpu() {
    [ "$ENABLE_CPU" != "1" ] && return 0

    ncpu=$(sysctl -n hw.ncpu || echo 1)
    hz=$(sysctl -n kern.clockrate | sed -n 's/.*[,{][[:space:]]*hz[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' || echo 128)

    ################
    # per-CPU time #
    ################
    if [ "$ENABLE_CPU_PERCPU_TIME" = "1" ]; then
	metric_help "${METRIC_NAME_PREFIX}_cpu_percpu_time_seconds_total" "per-CPU time in seconds"
	metric_type "${METRIC_NAME_PREFIX}_cpu_percpu_time_seconds_total" "counter"
	# kern.cp_times: user, nice, system, interrupt, idle per CPU
	sysctl -n kern.cp_times | _awk -v ncpu="$ncpu" -v hz="$hz" '
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
	metric_help "${METRIC_NAME_PREFIX}_cpu_percpu_temperature_total" "per-CPU time in seconds"
	metric_type "${METRIC_NAME_PREFIX}_cpu_percpu_temperature_total" "gauge"

	# Get per-CPU temperature
	for i in `seq 0 $((ncpu-1))`; do
	    t=$(sysctl -n dev.cpu.$i.temperature)
	    metric "${METRIC_NAME_PREFIX}_cpu_percpu_temperature_total" "cpu=\"$i\"" "${t%?}"
	done
    fi

    metric_help "${METRIC_NAME_PREFIX}_cpu_time_total" "CPU time in percents"
    metric_type "${METRIC_NAME_PREFIX}_cpu_time_total" "gauge"

    sysctl -n kern.cp_time | _awk '
    BEGIN {
	split("user nice system interrupt idle", states)
    }
    {
	total = $1 + $2 + $3 + $4 + $5
	printf "%s_cpu_time_total{mode=\"user\"} %.2f\n", pfx, $1 / total * 100
	printf "%s_cpu_time_total{mode=\"nice\"} %.2f\n", pfx, $2 / total * 100
	printf "%s_cpu_time_total{mode=\"system\"} %.2f\n", pfx, $3 / total * 100
	printf "%s_cpu_time_total{mode=\"interrupt\"} %.2f\n", pfx, $4 / total * 100
	printf "%s_cpu_time_total{mode=\"idle\"} %.2f\n", pfx, $5 / total * 100
    }'

    #################
    # Load averages #
    #################
    metric_help "${METRIC_NAME_PREFIX}_sys_loadavg" "System load average"
    metric_type "${METRIC_NAME_PREFIX}_sys_loadavg" "gauge"

    sysctl -n vm.loadavg | _awk '{
	printf "%s_sys_loadavg{period=\"1m\"} %s\n", pfx, $2
	printf "%s_sys_loadavg{period=\"5m\"} %s\n", pfx, $3
	printf "%s_sys_loadavg{period=\"15m\"} %s\n", pfx, $4
    }'

    ###################################
    # Context switches and interrupts #
    ###################################
    metric_help "${METRIC_NAME_PREFIX}_sys_context_switches_total" "Total context switches"
    metric_type "${METRIC_NAME_PREFIX}_sys_context_switches_total" "counter"
    vm_swtch=$(sysctl -n vm.stats.sys.v_swtch || echo 0)
    metric "${METRIC_NAME_PREFIX}_sys_context_switches_total" "" "$vm_swtch"

    metric_help "${METRIC_NAME_PREFIX}_sys_traps_total" "Total traps"
    metric_type "${METRIC_NAME_PREFIX}_sys_traps_total" "counter"
    vm_trap=$(sysctl -n vm.stats.sys.v_trap || echo 0)
    metric "${METRIC_NAME_PREFIX}_sys_traps_total" "" "$vm_trap"

    metric_help "${METRIC_NAME_PREFIX}_sys_syscalls_total" "Total syscalls"
    metric_type "${METRIC_NAME_PREFIX}_sys_syscalls_total" "counter"
    vm_syscall=$(sysctl -n vm.stats.sys.v_syscall || echo 0)
    metric "${METRIC_NAME_PREFIX}_sys_syscalls_total" "" "$vm_syscall"

    metric_help "${METRIC_NAME_PREFIX}_sys_interrupts_dev_total" "Total device interrupts"
    metric_type "${METRIC_NAME_PREFIX}_sys_interrupts_dev_total" "counter"
    vm_intr=$(sysctl -n vm.stats.sys.v_intr || echo 0)
    metric "${METRIC_NAME_PREFIX}_sys_interrupts_dev_total" "" "$vm_intr"

    metric_help "${METRIC_NAME_PREFIX}_sys_interrupts_soft_total" "Total softwaree interrupts"
    metric_type "${METRIC_NAME_PREFIX}_sys_interrupts_soft_total" "counter"
    vm_soft=$(sysctl -n vm.stats.sys.v_soft || echo 0)
    metric "${METRIC_NAME_PREFIX}_sys_interrupts_soft_total" "" "$vm_soft"

    #############
    # CPU count #
    #############
    metric_help "${METRIC_NAME_PREFIX}_sys_cpu_count" "Number of CPUs"
    metric_type "${METRIC_NAME_PREFIX}_sys_cpu_count" "gauge"
    metric "${METRIC_NAME_PREFIX}_sys_cpu_count" "" "$ncpu"
}
