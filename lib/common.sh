#!/bin/sh
# lib/common.sh
#
# Common functions for FreeBSD metrics collectors

# Load configuration
if [ ! -e "$CONFIG_FILE" ]; then
    echo "# FATAL: Config file $CONFIG_FILE does not exist"
    exit 0
fi

. $CONFIG_FILE
. /etc/os-release

VERSION_ID_DOTLESS=$(echo $VERSION_ID | tr -d '.')

# if [ -f /usr/local/etc/freebsd-metrics.conf ]; then
#     . /usr/local/etc/freebsd-metrics.conf
# fi

# Set hostname
if [ -z "$HOSTNAME" ]; then
    HOSTNAME=$(hostname)
fi

METRIC_NAME_PREFIX='fbsd'

# Metric output helpers
metric_help() {
    name="$1"
    help_text="$2"
    echo "# HELP ${name} ${help_text}"
}

metric_type() {
    name="$1"
    type="$2"  # counter, gauge, histogram, summary
    echo "# TYPE ${name} ${type}"
}

metric() {
    name="$1"
    labels="$2"
    value="$3"

    if [ -n "$labels" ]; then
	echo "${name}{${labels}} ${value}"
    else
	echo "${name} ${value}"
    fi
}

# Escape label value for Prometheus format
escape_label() {
    # Escape backslashes and quotes
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# ?? # # Convert bytes with suffix to plain bytes
# ?? # parse_bytes() {
# ?? #     value="$1"
# ?? #     # Handle K, M, G, T, P suffixes
# ?? #     case "$value" in
# ?? #	*K) echo "$value" | sed 's/K$//' | awk '{printf "%.0f", $1 * 1024}' ;;
# ?? #	*M) echo "$value" | sed 's/M$//' | awk '{printf "%.0f", $1 * 1024 * 1024}' ;;
# ?? #	*G) echo "$value" | sed 's/G$//' | awk '{printf "%.0f", $1 * 1024 * 1024 * 1024}' ;;
# ?? #	*T) echo "$value" | sed 's/T$//' | awk '{printf "%.0f", $1 * 1024 * 1024 * 1024 * 1024}' ;;
# ?? #	*P) echo "$value" | sed 's/P$//' | awk '{printf "%.0f", $1 * 1024 * 1024 * 1024 * 1024 * 1024}' ;;
# ?? #	*) echo "$value" ;;
# ?? #     esac
# ?? # }

# Check if command exists
has_command() {
    command -v "$1" >/dev/null 2>&1
}

# Check if ZFS is available
has_zfs() {
    has_command zfs && has_command zpool && kldstat -q -m zfs
}

# AWK alias to promote var `pfx'
_awk() {
    command awk -v pfx="$METRIC_NAME_PREFIX" "$@"
}

# Get current timestamp
now() {
    opt=${1:-s} # or `N' for nanosecunds
    test "$opt" = "N" && test "$VERSION_ID_DOTLESS" -lt "141" && opt='s'
    date +%$opt
}

# Log error to stderr
log_error() {
    # echo "ERROR: $*" >&2
    logger -p user.err -t "${METRIC_NAME_PREFIX}_exporter" "$*"
}

# Log warning to stderr
log_warn() {
    # echo "WARNING: $*" >&2
    logger -p user.warning -t "${METRIC_NAME_PREFIX}_exporter" "$*"
}

# Collector status tracking
collector_status() {
    collector="$1"
    exit_code="$2"
    duration="$3"
    timestamp="$4"

    metric "${METRIC_NAME_PREFIX}_metrics_collector_status" "collector=\"${collector}\"" "$exit_code"
    metric "${METRIC_NAME_PREFIX}_metrics_collector_duration_nanoseconds" "collector=\"${collector}\"" "$duration"
    metric "${METRIC_NAME_PREFIX}_metrics_collector_last_run_timestamp" "collector=\"${collector}\"" "$timestamp"
}

# Run collector with status tracking
run_collector() {
    collector_name="$1"
    shift

    start_time=$(now N) # nanoseconds
    if "$@"; then
	exit_code=0
    else
	exit_code=$?
	log_error "Collector ${collector_name} failed with exit code ${exit_code}"
    fi
    end_time=$(now N) # nanoseconds
    duration=$((end_time - start_time))

    collector_status "$collector_name" "$exit_code" "$duration" "$end_time"
}
