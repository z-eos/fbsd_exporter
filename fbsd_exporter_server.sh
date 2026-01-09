#!/bin/sh
#
# FreeBSD Prometheus metrics HTTP server for inetd
# Serves pre-collected metrics with atomic merging
#

set -e

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

if [ "${OPT_METRICS_DIR:+x}" = x ] && [ -n "$OPT_METRICS_DIR" ]; then
    METRICS_DIR=$OPT_METRICS_DIR
fi
if [ "${OPT_DEBUG:+x}" ] && [ -n "$OPT_DEBUG" ]; then
    DEBUG=$OPT_DEBUG
fi

# Staleness thresholds (seconds)
FAST_MAX_AGE=120      # 2 minutes
SLOW_MAX_AGE=600      # 10 minutes
USERSPACE_MAX_AGE=1800  # 30 minutes

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
    case s in
	fast)
	    max_age=$FAST_MAX_AGE
	    required="required"
	    ;;
	slow)
	    max_age=$SLOW_MAX_AGE
	    required="required"
	    ;;
	userspace)
	    max_age=$USERSPACE_MAX_AGE
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
	    echo "freebsd_metrics_file_status{file=\"${name}\",status=\"missing\"} 1"
	fi
	return 1
    fi

    # File unreadable
    if [ ! -r "$file" ]; then
	echo "# ERROR: File ${name} not readable"
	echo "freebsd_metrics_file_status{file=\"${name}\",status=\"unreadable\"} 1"
	return 1
    fi

    # File empty
    if [ ! -s "$file" ]; then
	echo "# WARNING: File ${name} is empty"
	echo "freebsd_metrics_file_status{file=\"${name}\",status=\"empty\"} 1"
	return 1
    fi

    # File stale
    if [ "$age" -gt "$max_age" ]; then
	echo "# WARNING: File ${name} is stale (${age}s old, max ${max_age}s)"
	echo "freebsd_metrics_file_age_seconds{file=\"${name}\"} $age"
    fi

    # Try to cat the file
    if cat "$file" 2>/dev/null; then
	echo ""
	echo "# File ${name} served successfully"
	echo "freebsd_metrics_file_status{file=\"${name}\",status=\"ok\"} 1"
	echo "freebsd_metrics_file_age_seconds{file=\"${name}\"} $age"
	return 0
    else
	echo "# ERROR: Failed to read ${name}"
	echo "freebsd_metrics_file_status{file=\"${name}\",status=\"read_error\"} 1"
	return 1
    fi
}

# Check metrics directory exists
if [ ! -d "$METRICS_DIR" ]; then
    echo "# FATAL: Metrics directory $METRICS_DIR does not exist"
    echo "freebsd_metrics_directory_missing 1"
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

# Server metadata
echo "# HELP freebsd_metrics_server_info Metrics server information"
echo "# TYPE freebsd_metrics_server_info gauge"
echo "freebsd_metrics_server_info{version=\"1.0\",hostname=\"$(hostname)\"} 1"
echo ""

echo "# HELP freebsd_metrics_server_scrape_timestamp_seconds Timestamp of this scrape"
echo "# TYPE freebsd_metrics_server_scrape_timestamp_seconds gauge"
echo "freebsd_metrics_server_scrape_timestamp_seconds $(date +%s)"
echo ""

# OpenMetrics EOF marker
echo "# EOF"
