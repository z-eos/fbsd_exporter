#!/bin/sh
# lib/common.sh
#
# Common functions for FreeBSD metrics collectors

# PERMISSION SAFETY CHECK:
# Ensure we can write to the debug log. Fallback to /dev/null if not.
# Uses explicit if-statements to prevent set -e short-circuit aborts.
: "${DEBUG_LOG:=/dev/null}"

if [ -e "$DEBUG_LOG" ]; then
    if [ ! -w "$DEBUG_LOG" ]; then
	DEBUG_LOG="/dev/null"
    fi
else
    LOG_DIR=$(dirname "$DEBUG_LOG" 2>/dev/null || echo "/var/log")
    if [ ! -w "$LOG_DIR" ]; then
	DEBUG_LOG="/dev/null"
    fi
fi

# Detect FreeBSD Version as pure integer (e.g., 1401000 for 14.1)
# This prevents shell arithmetic/comparison errors (Exit Code 2)
FREEBSD_VERSION_INT=$(uname -U 2>/dev/null || echo 0)
FREEBSD_VERSION_INT=$(echo "$FREEBSD_VERSION_INT" | tr -cd '0-9')
: "${FREEBSD_VERSION_INT:=0}"

# Set hostname
if [ -z "$HOSTNAME" ]; then
    HOSTNAME=$(hostname)
fi

METRIC_NAME_PREFIX='fbsd'

# Metric output helpers
metric_help() {
    echo "# HELP $1 $2"
}

metric_type() {
    echo "# TYPE $1 $2"
}

metric() {
    if [ -n "$2" ]; then
	echo "${1}{${2}} ${3}"
    else
	echo "${1} ${3}"
    fi
}

escape_label() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

has_zfs() {
    if has_command zfs && has_command zpool && kldstat -q -m zfs; then
	return 0
    else
	return 1
    fi
}

_awk() {
    command awk -v pfx="$METRIC_NAME_PREFIX" "$@"
}

now() {
    opt=${1:-s}
    # Check version for %N support (FreeBSD 14.1+ is >= 1401000)
    if [ "$opt" = "N" ] && [ "$FREEBSD_VERSION_INT" -lt 1401000 ]; then
	opt='s'
    fi
    date +%$opt
}

log_error() {
    logger -p user.err -t "${METRIC_NAME_PREFIX}_exporter" "$*"
}

log_warn() {
    logger -p user.warning -t "${METRIC_NAME_PREFIX}_exporter" "$*"
}

# SAFE WRAPPERS (Redirect stderr to DEBUG_LOG, prevent exit on failure)
_sysctl() {
    sysctl "$@" 2>>"${DEBUG_LOG}" || return 0
}

_zpool() {
    zpool "$@" 2>>"${DEBUG_LOG}" || return 0
}

_zfs() {
    zfs "$@" 2>>"${DEBUG_LOG}" || return 0
}
