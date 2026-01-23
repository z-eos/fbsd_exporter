#!/bin/sh
#
#
#

set -e

CONFIG_FILE="/usr/local/etc/fbsd_exporter.conf"

# default, mandatory for each scope
LIB_FILES="common.sh"

# Parse command line options
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

# Shift past the parsed options to get positional arguments
shift $((OPTIND - 1))

# Check metrics directory exists
if [ ! -e "$CONFIG_FILE" ]; then
    echo "# FATAL: Config file $CONFIG_FILE does not exist"
    exit 0
fi

. $CONFIG_FILE

touch "$DEBUG_LOG"
exec 2>"$DEBUG_LOG"

if [ "${OPT_METRICS_DIR:+x}" = x ] && [ -n "$OPT_METRICS_DIR" ]; then
    METRICS_DIR=$OPT_METRICS_DIR
fi
if [ "${OPT_DEBUG:+x}" ] && [ -n "$OPT_DEBUG" ]; then
    DEBUG=$OPT_DEBUG
fi

if [ -z $SCOPE ]; then
    SCOPE='fast'
    LIB_FILES="${LIB_FILES} cpu.sh memory.sh disk.sh filesystem.sh process.sh"
fi

# Load configuration and libraries
# SCRIPT_DIR=$(dirname "$(realpath "$0")")
for FILE in $LIB_FILES; do
    . "${SCRIPT_DIR}/lib/${FILE}"
done

OUTPUT="${METRICS_DIR}/${METRIC_NAME_PREFIX}_exporter_${SCOPE}.prom"

# Ensure metrics directory exists
mkdir -p "$METRICS_DIR"

#############
#   FAST    #
#############
collect_all_fast() {
    echo "# Fast metrics collected at $(date +%FT%T)"
    echo "# Hostname: ${HOSTNAME}"
    echo ""

    # CPU metrics
    if [ "$ENABLE_CPU" = "1" ]; then
	run_collector "cpu" collect_cpu
	echo ""
    fi

    # Memory metrics
    if [ "$ENABLE_MEMORY" = "1" ]; then
	run_collector "memory" collect_memory
	echo ""
    fi

    # Disk I/O metrics
    if [ "$ENABLE_DISK_IO" = "1" ]; then
	run_collector "disk" collect_disk
	echo ""
    fi

    # Filesystem metrics
    if [ "$ENABLE_FILESYSTEM" = "1" ]; then
	run_collector "filesystem" collect_filesystem
	echo ""
    fi

    # Process metrics
    if [ "$ENABLE_PROCESS" = "1" ]; then
	run_collector "process" collect_process
	echo ""
    fi
}

#############
#   SLOW    #
#############
collect_all_slow() {
    echo "# Slow metrics collected at $(now)"
    echo "# Hostname: ${HOSTNAME}"
    echo ""

    # ZPOOL metrics
    if [ "$ENABLE_ZPOOL" = "1" ]; then
	run_collector "zpool" collect_zpool
	echo ""
    fi

    # ZFS core metrics (ARC, basic pool stats)
    if [ "$ENABLE_ZFS_CORE" = "1" ]; then
	run_collector "zfs" collect_zfs
	echo ""
    fi

    # ZFS pool health and detailed status
    if [ "$ENABLE_ZFS_CORE" = "1" ] && has_zfs; then

	echo ""
    fi

}

#############
# USERSPACE #
#############
collect_all_userspace() {
    echo "# ZFS userspace metrics collected at $(now)"
    echo "# Hostname: ${HOSTNAME}"
    echo ""

    run_collector "zfs_userspace" collect_zfs_userspace
    echo ""
}

# Main execution
main() {
    TMP="${OUTPUT}.$$"
    trap 'rm -f "$TMP"' EXIT INT TERM

    case "$SCOPE" in
	fast)
	    # Loop mode for sub-minute collection
	    if [ "$1" = "--loop" ]; then
		iterations=${2:-6}
		interval=${3:-10}

		for i in $(seq 1 "$iterations"); do
		    collect_all_fast > "$TMP" 2>&1

		    if [ -s "$TMP" ]; then
			mv "$TMP" "$OUTPUT"
			chmod 644 "$OUTPUT"
		    else
			log_error "Fast collection produced no output"
		    fi

		    [ "$i" -lt "$iterations" ] && sleep "$interval"
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
