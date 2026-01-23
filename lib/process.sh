#!/bin/sh
# /usr/local/lib/freebsd-metrics/lib/process.sh
#
# Process metrics collector

collect_process() {
    [ "$ENABLE_PROCESS" != "1" ] && return 0

    if [ -z "$PROCESS_NAMES" ] && [ -z "$PROCESS_PATTERNS" ]; then
	return 0
    fi

    metric_help "${METRIC_NAME_PREFIX}_process_cpu_percent" "Process CPU usage percentage"
    metric_type "${METRIC_NAME_PREFIX}_process_cpu_percent" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_process_memory_percent" "Process memory usage percentage"
    metric_type "${METRIC_NAME_PREFIX}_process_memory_percent" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_process_memory_bytes" "Process memory in bytes"
    metric_type "${METRIC_NAME_PREFIX}_process_memory_bytes" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_process_count" "Number of processes by name"
    metric_type "${METRIC_NAME_PREFIX}_process_count" "gauge"

    # Build pattern for matching
    if [ -n "$PROCESS_NAMES" ]; then
	names_pattern=$(echo "$PROCESS_NAMES" | sed 's/ /|/g')
	# Pass expected names to awk
	expected_names="$PROCESS_NAMES"
    else
	expected_names=""
    fi

    # Get process list and generate metrics
    ps auxww 2>/dev/null | \
    _awk -v names="$names_pattern" \
	-v patterns="$PROCESS_PATTERNS" \
	-v aggregate="$PROCESS_INCLUDE_AGGREGATE" \
	-v expected="$expected_names" '
    BEGIN {
	count = 0
	# Parse expected process names into array
	if (expected) {
	    split(expected, exp_array)
	    for (i in exp_array) {
		expected_procs[exp_array[i]] = 1
	    }
	}
    }
    NR > 1 {
	user = $1
	pid = $2
	cpu = $3
	mem = $4
	vsz = $5 * 1024  # Convert KB to bytes
	rss = $6 * 1024
	state = $8
	command = $11

	# Extract process name from command
	gsub(/^.*\//, "", command)  # Remove path
	gsub(/:.*/, "", command)    # Remove after colon

	# Check if matches
	matched = 0
	if ((names && command ~ "^(" names ")$") || (patterns && $0 ~ patterns)) matched = 1

	if (!matched) next

	count++

	# Mark this process as found
	if (expected_procs[command]) found_procs[command] = 1

	# Escape quotes
	gsub(/"/, "\\\"", user)
	gsub(/"/, "\\\"", command)

	# Per-process metrics
	printf "%s_process_cpu_percent{pid=\"%s\",name=\"%s\",user=\"%s\"} %s\n", pfx, pid, command, user, cpu
	printf "%s_process_memory_percent{pid=\"%s\",name=\"%s\",user=\"%s\"} %s\n", pfx, pid, command, user, mem
	printf "%s_process_memory_bytes{pid=\"%s\",name=\"%s\",user=\"%s\",type=\"vsz\"} %s\n", pfx, pid, command, user, vsz
	printf "%s_process_memory_bytes{pid=\"%s\",name=\"%s\",user=\"%s\",type=\"rss\"} %s\n", pfx, pid, command, user, rss

	# Aggregate by name
	if (aggregate == "1") {
	    proc_count[command]++
	    proc_cpu[command] += cpu
	    proc_mem[command] += rss
	}
    }
    END {
	# Output aggregated metrics for found processes
	if (aggregate == "1") {
	    for (name in proc_count) {
		printf "%s_process_count{name=\"%s\"} %d\n", pfx, name, proc_count[name]
		printf "%s_process_total_cpu_percent{name=\"%s\"} %.2f\n", pfx, name, proc_cpu[name]
		printf "%s_process_total_memory_bytes{name=\"%s\"} %.0f\n", pfx, name, proc_mem[name]
	    }
	}

	# Output zeros for expected processes that were NOT found
	for (name in expected_procs) {
	    if (!found_procs[name]) {
		printf "%s_process_count{name=\"%s\"} 0\n", pfx, name
		if (aggregate == "1") {
		    printf "%s_process_total_cpu_percent{name=\"%s\"} 0\n", pfx, name
		    printf "%s_process_total_memory_bytes{name=\"%s\"} 0\n", pfx, name
		}
	    }
	}
    }'

    for process in `echo $PROCESS_NAMES`;do
	case "$process" in
	    openvpn)
		if [ -n "$PROCESS_NAME_OPENVPN_CONFIGS" ]; then
		    metric_help "${METRIC_NAME_PREFIX}_process_clients" "Number of OpenVPN clients connected"
		    metric_type "${METRIC_NAME_PREFIX}_process_clients" "gauge"
		    metric "${METRIC_NAME_PREFIX}_process_clients_number" "name=\"$process\"" $(grep '^status ' $PROCESS_NAME_OPENVPN_CONFIGS | cut -d' ' -f2 | xargs grep '^CLIENT_LIST' | wc -l)
		fi
		;;
	esac
    done

}
