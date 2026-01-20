#!/bin/sh
#
# FreeBSD Prometheus metrics HTTP server for inetd
# Serves pre-collected metrics with atomic merging
#

set -e

VERSION="0.6.0"

CONFIG_FILE="/usr/local/etc/fbsd_exporter.conf"

# Parse command line options
while getopts "c:M:d" opt; do
    case "$opt" in
	c) CONFIG_FILE="$OPTARG" ;;
	d) OPT_DEBUG=1 ;;
	M) OPT_METRICS_DIR="$OPTARG" ;;
	*)
	    echo "Usage: $0 [-c configfile] [-M metrics-dir]" >&2
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
. ${SCRIPT_DIR}/lib/common.sh

if [ "${OPT_METRICS_DIR:+x}" = x ] && [ -n "$OPT_METRICS_DIR" ]; then
    METRICS_DIR=$OPT_METRICS_DIR
fi
if [ "${OPT_DEBUG:+x}" ] && [ -n "$OPT_DEBUG" ]; then
    DEBUG=$OPT_DEBUG
fi

# Read and discard HTTP request
while IFS= read -r line; do
    line=$(printf '%s' "$line" | tr -d '\r')
    [ -z "$line" ] && break
done

# HTTP response headers
printf "HTTP/1.0 200 OK\r\n"
printf "Content-Type: text/plain; version=0.0.4; charset=utf-8\r\n"
printf "Connection: close\r\n"
printf "\r\n"

# Helper: check if file is stale
is_stale() {
    file="$1"
    max_age="$2"

    [ ! -f "$file" ] && return 0  # Missing = stale

    file_time=$(stat -f %m "$file" 2>/dev/null || echo 0)
    current_time=$(date +%s)
    age=$((current_time - file_time))

    [ "$age" -gt "$max_age" ]
}

# Helper: get file age in seconds
get_age() {
    file="$1"
    [ ! -f "$file" ] && echo "999999" && return
    file_time=$(stat -f %m "$file" 2>/dev/null || echo 0)
    current_time=$(date +%s)
    echo $((current_time - file_time))
}

# Helper: safely cat file with error handling
safe_cat() {
    scope=$1
    case $scope in
	fast)
	    max_age="$MAX_AGE_FAST"
	    required="required"
	    ;;
	slow)
	    max_age="$MAX_AGE_SLOW"
	    required="required"
	    ;;
	userspace)
	    max_age="$MAX_AGE_USERSPACE"
	    required="optional"
	    ;;
    esac
    file="${METRICS_DIR}/${METRIC_NAME_PREFIX}_exporter_${scope}.prom"
    name="$(basename $1)"

    age=$(get_age "$file")

    # File missing
    if [ ! -f "$file" ]; then
	if [ "$required" = "required" ]; then
	    echo "# ERROR: Required file ${name} not found"
	    echo "${METRIC_NAME_PREFIX}_metrics_file_status{file=\"${name}\",status=\"missing\"} 1"
	fi
	return 1
    fi

    # File unreadable
    if [ ! -r "$file" ]; then
	echo "# ERROR: File ${name} not readable"
	echo "${METRIC_NAME_PREFIX}_metrics_file_status{file=\"${name}\",status=\"unreadable\"} 1"
	return 1
    fi

    # File empty
    if [ ! -s "$file" ]; then
	echo "# WARNING: File ${name} is empty"
	echo "${METRIC_NAME_PREFIX}_metrics_file_status{file=\"${name}\",status=\"empty\"} 1"
	return 1
    fi

    # File stale
    if [ "$age" -gt "$max_age" ]; then
	echo "# WARNING: File ${name} is stale (${age}s old, max ${max_age}s)"
	echo "${METRIC_NAME_PREFIX}_metrics_file_age_seconds{file=\"${name}\"} $age"
    fi

    # Try to cat the file
    if cat "$file" 2>/dev/null; then
	echo ""
	echo "# File ${name} served successfully"
	echo "${METRIC_NAME_PREFIX}_metrics_file_status{file=\"${name}\",status=\"ok\"} 1"
	echo "${METRIC_NAME_PREFIX}_metrics_file_age_seconds{file=\"${name}\"} $age"
	return 0
    else
	echo "# ERROR: Failed to read ${name}"
	echo "${METRIC_NAME_PREFIX}_metrics_file_status{file=\"${name}\",status=\"read_error\"} 1"
	return 1
    fi
}

# Check metrics directory exists
if [ ! -d "$METRICS_DIR" ]; then
    echo "# FATAL: Metrics directory $METRICS_DIR does not exist"
    echo "${METRIC_NAME_PREFIX}_metrics_directory_missing 1"
    echo "# EOF"
    exit 0
fi

# Serve all metric files
echo "# FreeBSD Prometheus Metrics"
echo "# Metrics collected from multiple files"
echo ""

for scope in fast slow userspace; do
    safe_cat $scope
    echo ""
done

# System uptime
metric_help "${METRIC_NAME_PREFIX}_system_uptime_seconds" "System uptime in seconds"
metric_type "${METRIC_NAME_PREFIX}_system_uptime_seconds" "gauge"
uptime_seconds=$(sysctl -n kern.boottime 2>/dev/null | awk '{print $4}' | tr -d ',')
if [ -n "$uptime_seconds" ]; then
    current=$(now)
    uptime=$((current - uptime_seconds))
    metric "${METRIC_NAME_PREFIX}_system_uptime_seconds" "" "$uptime"
fi
echo ""

# System info (/etc/os-release)
metric_help "${METRIC_NAME_PREFIX}_system_info" "System information"
metric_type "${METRIC_NAME_PREFIX}_system_info" "gauge"
if [ -f /etc/os-release ]; then
    _awk -F= '{
		    # Remove any surrounding quotes from the value first
		    gsub(/^"/, "", $2);
		    gsub(/"$/, "", $2);
		    # Escape any quotes inside the value
		    gsub(/"/, "\\\"", $2);
		    pairs = pairs (NR==1 ? "" : ",") $1 "=\"" $2 "\""
		  } END {
		    printf "%s_system_info{%s} 1\n", pfx, pairs
		  }' /etc/os-release
else
    OS_VERSION=$(uname -r)
    metric "${METRIC_NAME_PREFIX}_system_info" "NAME=\"FreeBSD\",VERSION=\"$OS_VERSION\",VERSION_ID=\"$(echo ${OS_VERSION%%-*} | tr -d '.')\"" "1"
fi

echo ""

# Server metadata
echo "# HELP ${METRIC_NAME_PREFIX}_metrics_server_info Metrics server information"
echo "# TYPE ${METRIC_NAME_PREFIX}_metrics_server_info gauge"
echo "${METRIC_NAME_PREFIX}_metrics_server_info{version=\"${VERSION}\",hostname=\"$(hostname)\"} 1"
echo ""

echo "# HELP ${METRIC_NAME_PREFIX}_metrics_server_scrape_timestamp_seconds Timestamp of this scrape"
echo "# TYPE ${METRIC_NAME_PREFIX}_metrics_server_scrape_timestamp_seconds gauge"
echo "${METRIC_NAME_PREFIX}_metrics_server_scrape_timestamp_seconds $(date +%s)"
echo ""

# OpenMetrics EOF marker
echo "# EOF"
