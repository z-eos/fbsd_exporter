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
# EXTREMELY IMPORTANT: This must run BEFORE the `shift` command below,
# otherwise the arguments (-s slow) are lost when lockf re-executes the script!
if [ "${LOCKED_EXECUTION}" != "1" ]; then
    LOCKFILE="/tmp/fbsd_exporter_${SCOPE:-fast}.lock"
    export LOCKED_EXECUTION=1
    exec lockf -t 0 "$LOCKFILE" "$0" "$@" || exit 0
fi

# Now it is safe to shift the parsed options away
if [ -n "$OPTIND" ] && [ "$OPTIND" -gt 1 ]; then
    shift $((OPTIND - 1))
fi

if [ ! -e "$CONFIG_FILE" ]; then
    echo "# FATAL: Config file $CONFIG_FILE does not exist" >&2
    exit 1
fi

# SAFETY: Protect sourcing the config file.
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

# Robust DEBUG handling decoupled from the config to prevent Exit 2 crashes
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

# Dynamically find script directory regardless of what the config says
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# SAFETY: Protect sourcing library files.
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

    # CRITICAL FIX: Use Epoch seconds (`date +%s`).
    # This prevents `%N` nanoseconds from triggering shell Octal Parsing crashes
    # and prevents negative duration wrap-arounds.
    start_time=$(date +%s)

    if "$@"; then
	exit_code=0
    else
	exit_code=$?
	log_error "Collector ${collector_name} failed with exit code ${exit_code}"
    fi

    end_time=$(date +%s)

    # CRITICAL FIX: Use awk for duration math.
    # Immune to Octal issues, immune to 32-bit integer limits.
    duration=$(awk -v st="$start_time" -v et="$end_time" 'BEGIN { printf "%.0f\n", (et - st) * 1000000000 }')

    collector_status "$collector_name" "$exit_code" "$duration" "$end_time"

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

# Main execution
main() {
    TMP="${OUTPUT}.$$"

    # ULTIMATE TRAP: If it crashes, DUMP the exact error message from the TMP file into DEBUG_LOG
    trap 'ret=$?; if [ $ret -ne 0 ]; then echo "FATAL: Script (PPID: ${PPID:-unknown}; $(ps -p ${PPID:-1} -o command= 2>/dev/null || echo unknown)) aborted with exit code $ret" >&2; if [ -f "$TMP" ] && [ -s "$TMP" ]; then echo "--- CRASH DUMP FROM $TMP ---" >> "$DEBUG_LOG"; cat "$TMP" >> "$DEBUG_LOG"; echo "--- END DUMP ---" >> "$DEBUG_LOG"; fi; fi; rm -f "$TMP"' EXIT INT TERM

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
