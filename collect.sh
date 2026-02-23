#!/bin/sh
#

set -e

# CRON SAFETY: Ensure standard paths are available
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

CONFIG_FILE="/usr/local/etc/fbsd_exporter.conf"
LIB_FILES="common.sh"

while getopts "c:M:s:d" opt; do
    case "$opt" in
	c) CONFIG_FILE="$OPTARG" ;;
	d) OPT_DEBUG=1 ;;
	s)
	    case "$OPTARG" in
		fast)
		    SCOPE=$OPTARG
		    LIB_FILES="${LIB_FILES} cpu.sh memory.sh disk.sh filesystem.sh process.sh"
		    ;;
		slow)
		    SCOPE=$OPTARG
		    LIB_FILES="${LIB_FILES} filesystem.sh zfs.sh zpool.sh"
		    ;;
		userspace)
		    SCOPE=$OPTARG
		    LIB_FILES="${LIB_FILES} zfs_userspace.sh"
		    ;;
		*)
		    echo "Invalid scope option: $OPTARG" >&2
		    exit 1
		    ;;
	    esac
	    ;;
	M) OPT_METRICS_DIR="$OPTARG" ;;
	*)
	    echo "Usage: $0 [-c configfile] [-M metrics-dir] [-s metrics scope (fast, slow, userspace)]" >&2
	    exit 1
	    ;;
    esac
done

# --- CONCURRENCY PROTECTION ---
if [ "${LOCKED_EXECUTION}" != "1" ]; then
    LOCKFILE="/tmp/fbsd_exporter_${SCOPE:-fast}.lock"
    export LOCKED_EXECUTION=1
    exec lockf -t 0 "$LOCKFILE" "$0" "$@" || exit 0
fi

if [ -n "$OPTIND" ] && [ "$OPTIND" -gt 1 ]; then
    shift $((OPTIND - 1))
fi

if [ ! -e "$CONFIG_FILE" ]; then
    echo "# FATAL: Config file $CONFIG_FILE does not exist" >&2
    exit 1
fi

set +e
. "$CONFIG_FILE"
config_ret=$?
set -e
if [ "$config_ret" -ne 0 ]; then
    echo "FATAL: Syntax error or failure while loading config file $CONFIG_FILE" >&2
    exit 1
fi

if [ -z "$DEBUG_LOG" ]; then
    DEBUG_LOG="/var/log/fbsd_exporter-debug.log"
fi

if touch "$DEBUG_LOG" >> "$DEBUG_LOG" 2>&1; then
    exec 2>>"$DEBUG_LOG"
else
    echo "WARNING: Cannot write to $DEBUG_LOG, logging to stderr" >&2
fi

if [ -n "$OPT_DEBUG" ]; then
    DEBUG_RAW="$OPT_DEBUG"
elif [ -n "$DEBUG" ]; then
    DEBUG_RAW="$DEBUG"
else
    DEBUG_RAW="0"
fi

DEBUG_INT=$(echo "$DEBUG_RAW" | tr -cd '0-9')
if [ -z "$DEBUG_INT" ]; then
    DEBUG=0
else
    DEBUG=$DEBUG_INT
fi

if [ "$DEBUG" -gt 0 ]; then
    echo "$(date +%FT%T) --- $0: $*" >> "$DEBUG_LOG"
    set | sort >> "$DEBUG_LOG"
    echo >> "$DEBUG_LOG"
fi

if [ -n "$OPT_METRICS_DIR" ]; then
    METRICS_DIR=$OPT_METRICS_DIR
fi

if [ -z "$METRICS_DIR" ]; then
    METRICS_DIR="/var/spool/fbsd_exporter"
fi

if [ -z "$SCOPE" ]; then
    SCOPE='fast'
    LIB_FILES="${LIB_FILES} cpu.sh memory.sh disk.sh filesystem.sh process.sh"
fi

SCRIPT_DIR=$(dirname "$(realpath "$0")")

for FILE in $LIB_FILES; do
    set +e
    . "${SCRIPT_DIR}/lib/${FILE}"
    lib_ret=$?
    set -e
    if [ "$lib_ret" -ne 0 ]; then
	echo "FATAL: Syntax error or missing library file: ${SCRIPT_DIR}/lib/${FILE}" >&2
	exit 1
    fi
done

OUTPUT="${METRICS_DIR}/${METRIC_NAME_PREFIX}_exporter_${SCOPE}.prom"

mkdir -p "$METRICS_DIR" 2>/dev/null || true
if [ ! -w "$METRICS_DIR" ]; then
    log_error "FATAL: Metrics directory $METRICS_DIR is not writable by user $(id -un). Cannot write metrics."
    echo "FATAL: Metrics directory $METRICS_DIR is not writable." >&2
    exit 1
fi

######################################
# Collector Execution & Timing Logic #
######################################

collector_status() {
    collector="$1"
    exit_code="$2"
    duration="$3"
    timestamp="$4"

    metric "${METRIC_NAME_PREFIX}_metrics_collector_status" "collector=\"${collector}\"" "$exit_code"
    metric "${METRIC_NAME_PREFIX}_metrics_collector_duration_nanoseconds" "collector=\"${collector}\"" "$duration"
    metric "${METRIC_NAME_PREFIX}_metrics_collector_last_run_timestamp" "collector=\"${collector}\"" "$timestamp"
}

run_collector() {
    collector_name="$1"
    shift

    if [ "$DEBUG" -gt 0 ]; then
	echo "# +++> collector start: ${collector_name}"
    fi

    # High-resolution timestamp extraction (Seconds and Nanoseconds)
    if [ "${FREEBSD_VERSION_INT:-0}" -ge 1401000 ]; then
	start_time=$(date "+%s %N")
    else
	start_time=$(date "+%s 0")
    fi

    if "$@"; then
	exit_code=0
    else
	exit_code=$?
	log_error "Collector ${collector_name} failed with exit code ${exit_code}"
    fi

    if [ "${FREEBSD_VERSION_INT:-0}" -ge 1401000 ]; then
	end_time=$(date "+%s %N")
    else
	end_time=$(date "+%s 0")
    fi

    # Calculate exact duration bypassing shell math limits
    duration=$(awk -v st="$start_time" -v et="$end_time" 'BEGIN {
	split(st, s)
	split(et, e)
	sec_diff = e[1] - s[1]
	ns_diff = e[2] - s[2]
	printf "%.0f\n", (sec_diff * 1000000000) + ns_diff
    }')

    # Grab the pure epoch timestamp for the status metric
    end_stamp=$(echo "$end_time" | awk '{print $1}')

    collector_status "$collector_name" "$exit_code" "$duration" "$end_stamp"

    if [ "$DEBUG" -gt 0 ]; then
	echo "# ---> collector stop: ${collector_name}"
	echo
    fi
}

#######################
# COLLECTOR: FAST     #
#######################
collect_all_fast() {
    echo "# Fast metrics collected at $(date +%FT%T)"
    echo "# Hostname: ${HOSTNAME}"
    echo ""

    if [ "$ENABLE_CPU" = "1" ]; then run_collector "cpu" collect_cpu; fi
    if [ "$ENABLE_MEMORY" = "1" ]; then run_collector "memory" collect_memory; fi
    if [ "$ENABLE_DISK_IO" = "1" ]; then run_collector "disk" collect_disk; fi
    if [ "$ENABLE_FILESYSTEM" = "1" ]; then run_collector "filesystem" collect_filesystem; fi
    if [ "$ENABLE_PROCESS" = "1" ]; then run_collector "process" collect_process; fi

    return 0
}

#######################
# COLLECTOR: SLOW     #
#######################
collect_all_slow() {
    echo "# Slow metrics collected at $(now)"
    echo "# Hostname: ${HOSTNAME}"
    echo ""

    if [ "$ENABLE_ZPOOL" = "1" ]; then run_collector "zpool" collect_zpool; fi
    if [ "$ENABLE_ZFS_CORE" = "1" ]; then run_collector "zfs" collect_zfs; fi

    return 0
}

########################
# COLLECTOR: USERSPACE #
########################
collect_all_userspace() {
    echo "# ZFS userspace metrics collected at $(now)"
    echo "# Hostname: ${HOSTNAME}"
    echo ""

    run_collector "zfs_userspace" collect_zfs_userspace

    return 0
}

# Cleanup and Error Reporting Function
cleanup_on_exit() {
    ret=$?
    if [ $ret -ne 0 ]; then
	parent_cmd=$(ps -p "${PPID:-1}" -o command= 2>/dev/null || echo "unknown")
	echo "FATAL: Script (PPID: ${PPID:-unknown}; ${parent_cmd}) aborted with exit code $ret" >&2

	if [ -f "$TMP" ] && [ -s "$TMP" ]; then
	    echo "--- CRASH DUMP FROM $TMP ---" >> "$DEBUG_LOG"
	    cat "$TMP" >> "$DEBUG_LOG"
	    echo "--- END DUMP ---" >> "$DEBUG_LOG"
	fi
    fi
    rm -f "$TMP"
}

# Main execution
main() {
    TMP="${OUTPUT}.$$"

    trap cleanup_on_exit EXIT INT TERM

    case "$SCOPE" in
	fast)
		touch "$TMP" || { log_error "FATAL: Cannot create temporary file $TMP"; exit 1; }
		collect_all_fast > "$TMP" 2>&1

		if [ -s "$TMP" ]; then
		    mv "$TMP" "$OUTPUT"
		    chmod 644 "$OUTPUT"
		else
		    log_error "Fast collection produced no output"
		    exit 1
		fi
	    ;;

	slow)
	    touch "$TMP" || { log_error "FATAL: Cannot create temporary file $TMP"; exit 1; }
	    collect_all_slow > "$TMP" 2>&1

	    if [ -s "$TMP" ]; then
		mv "$TMP" "$OUTPUT"
		chmod 644 "$OUTPUT"
	    else
		log_error "Slow collection produced no output"
		exit 1
	    fi
	    ;;

	userspace)
	    touch "$TMP" || { log_error "FATAL: Cannot create temporary file $TMP"; exit 1; }
	    collect_all_userspace > "$TMP" 2>&1

	    if [ -s "$TMP" ]; then
		mv "$TMP" "$OUTPUT"
		chmod 644 "$OUTPUT"
	    else
		log_error "Userspace collection produced no output"
		exit 1
	    fi
	    ;;
    esac
}

main "$@"
