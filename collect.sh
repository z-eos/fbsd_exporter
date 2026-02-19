#!/bin/sh
#
#
#

set -e

CONFIG_FILE="/usr/local/etc/fbsd_exporter.conf"

# default, mandatory for each scope
LIB_FILES="common.sh"

while getopts "c:M:s:d" opt; do
    case "$opt" in
	c) CONFIG_FILE="$OPTARG" ;;
	d) OPT_DEBUG=1 ;;
	s)
	    case "$OPTARG" in
		fast)
		    SCOPE=$OPTARG
		    LIB_FILES="${LIB_FILES} cpu.sh memory.sh disk.sh process.sh"
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
		    echo "Invalid scope option: $OPTARG, " >&2
		    echo "Usage: scope one of: fast (default), slow or userspace" >&2
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

shift $((OPTIND - 1))

# Check config file exists
if [ ! -e "$CONFIG_FILE" ]; then
    echo "# FATAL: Config file $CONFIG_FILE does not exist" >&2
    exit 1
fi

. $CONFIG_FILE

: "${DEBUG_LOG:=/var/log/fbsd_exporter-debug.log}"

if touch "$DEBUG_LOG" >> "$DEBUG_LOG" 2>&1; then
    exec 2>>"$DEBUG_LOG"
else
    echo "WARNING: Cannot write to $DEBUG_LOG, logging to stderr" >&2
fi

: ${DEBUG:=0}

if [ "${OPT_DEBUG:+x}" ] && [ -n "$OPT_DEBUG" ]; then
    DEBUG=$OPT_DEBUG
fi

if [ "${DEBUG}" -gt 0 ]; then
    echo "$(date +%FT%T) --- $0: $*" >> "$DEBUG_LOG"
    env | sort >> "$DEBUG_LOG"
    echo >> "$DEBUG_LOG"
fi

if [ "${OPT_METRICS_DIR:+x}" = x ] && [ -n "$OPT_METRICS_DIR" ]; then
    METRICS_DIR=$OPT_METRICS_DIR
fi

: "${METRICS_DIR:=/var/spool/fbsd_exporter}"

if [ -z "$SCOPE" ]; then
    SCOPE='fast'
    LIB_FILES="${LIB_FILES} cpu.sh memory.sh disk.sh filesystem.sh process.sh"
fi

# Load configuration and libraries
for FILE in $LIB_FILES; do
    . "${SCRIPT_DIR}/lib/${FILE}"
done

OUTPUT="${METRICS_DIR}/${METRIC_NAME_PREFIX}_exporter_${SCOPE}.prom"

mkdir -p "$METRICS_DIR"

######################
#   COLLECT: FAST    #
######################
collect_all_fast() {
    echo "# Fast metrics collected on $(date +%FT%T) / $(now)"
    echo "# Hostname: ${HOSTNAME}"
    echo ""

    # CPU metrics
    if [ "$ENABLE_CPU" = "1" ]; then
	echo "### >>> ENABLE_CPU = 1"
	run_collector "cpu" collect_cpu
	echo ""
    fi

    # Memory metrics
    if [ "$ENABLE_MEMORY" = "1" ]; then
	echo "### >>> ENABLE_MEMORY = 1"
	run_collector "memory" collect_memory
	echo ""
    fi

    # Disk I/O metrics
    if [ "$ENABLE_DISK_IO" = "1" ]; then
	echo "### >>> ENABLE_DISK_IO = 1"
	run_collector "disk" collect_disk
	echo ""
    fi

    # Filesystem metrics
    if [ "$ENABLE_FILESYSTEM" = "1" ]; then
	echo "### >>> ENABLE_FILESYSTEM = 1"
	run_collector "filesystem" collect_filesystem
	echo ""
    fi

    # Process metrics
    if [ "$ENABLE_PROCESS" = "1" ]; then
	echo "### >>> ENABLE_PROCESS = 1"
	run_collector "process" collect_process
	echo ""
    fi
}

######################
#   COLLECT: SLOW    #
######################
collect_all_slow() {
    echo "# Slow metrics collected on $(date +%FT%T) / $(now)"
    echo "# Hostname: ${HOSTNAME}"
    echo ""

    # ZPOOL metrics
    if [ "$ENABLE_ZPOOL" = "1" ]; then
	echo "### >>> ENABLE_ZPOOL = 1"
	run_collector "zpool" collect_zpool
	echo ""
    fi

    # ZFS core metrics (ARC, basic pool stats)
    if [ "$ENABLE_ZFS_CORE" = "1" ]; then
	echo "### >>> ENABLE_ZFS_CORE = 1"
	run_collector "zfs" collect_zfs
	echo ""
    fi

    # ZFS pool health and detailed status
    # if [ "$ENABLE_ZFS_CORE" = "1" ] && has_zfs; then
    # fi

}

######################
# COLLECT: USERSPACE #
######################
collect_all_userspace() {
    echo "# ZFS userspace metrics collected on $(date +%FT%T) / $(now)"
    echo "# Hostname: ${HOSTNAME}"
    echo ""

    run_collector "zfs_userspace" collect_zfs_userspace
    echo ""
}

# Main execution
main() {
    TMP="${OUTPUT}.$$"

    # Captures the exit status. If non-zero (crash/error), logs it to the debug log.
    trap 'ret=$?; [ $ret -ne 0 ] && echo "FATAL: Script aborted with exit code $ret" >&2; rm -f "$TMP"' EXIT INT TERM

    case "$SCOPE" in
	fast)
	    # Loop mode for sub-minute collection
	    if [ "$1" = "--loop" ]; then
		iterations=${2:-6}
		interval=${3:-10}

		# POSIX shell "seq" replacement: while loop
		i=1
		while [ "$i" -le "$iterations" ]; do
		    collect_all_fast > "$TMP" 2>&1

		    if [ -s "$TMP" ]; then
			mv "$TMP" "$OUTPUT"
			chmod 644 "$OUTPUT"
		    else
			log_error "Fast collection produced no output"
		    fi

		    if [ "$i" -lt "$iterations" ]; then
			sleep "$interval"
		    fi
		    i=$((i + 1))
		done
	    elif [ "$1" = "--daemon" ]; then
		# Daemon mode - continuous loop
		interval=${2:-10}
		while true; do
		    collect_all_fast > "$TMP" 2>&1

		    if [ -s "$TMP" ]; then
			mv "$TMP" "$OUTPUT"
			chmod 644 "$OUTPUT"
		    else
			log_error "Fast collection produced no output"
		    fi

		    sleep "$interval"
		done
	    else
		# Single run
		collect_all_fast > "$TMP" 2>&1

		if [ -s "$TMP" ]; then
		    mv "$TMP" "$OUTPUT"
		    chmod 644 "$OUTPUT"
		else
		    log_error "Fast collection produced no output"
		    exit 1
		fi
	    fi
	    ;;

	slow)
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
