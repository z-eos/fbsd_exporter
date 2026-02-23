#!/bin/sh
# lib/zfs_userspace.sh
#
# ZFS userspace metrics collector

# Safe, POSIX-compliant substring check
has_zfs_type() {
    case " $ZFS_USERSPACE_TYPES " in
	*" $1 "*) return 0 ;;
	*) return 1 ;;
    esac
}

collect_zfs_userspace() {
    [ "$ENABLE_ZFS_USERSPACE" != "1" ] && return 0
    [ -z "$ZFS_USERSPACE_DATASETS" ] && { log_warn "ZFS_USERSPACE_DATASETS not configured, skipping userspace metrics"; return 0; }

    if has_zfs_type "user"; then
	metric_name_bytes="${METRIC_NAME_PREFIX}_zfs_userspace_bytes"
	metric_help "$metric_name_bytes" "ZFS userspace usage in bytes"
	metric_type "$metric_name_bytes" "gauge"

	metric_name_objects="${METRIC_NAME_PREFIX}_zfs_userspace_objects"
	metric_help "$metric_name_objects" "ZFS userspace usage in objects"
	metric_type "$metric_name_objects" "gauge"
    fi

    if has_zfs_type "group"; then
	metric_name_bytes="${METRIC_NAME_PREFIX}_zfs_groupspace_bytes"
	metric_help "$metric_name_bytes" "ZFS groupspace usage in bytes"
	metric_type "$metric_name_bytes" "gauge"

	metric_name_objects="${METRIC_NAME_PREFIX}_zfs_groupspace_objects"
	metric_help "$metric_name_objects" "ZFS groupspace usage in objects"
	metric_type "$metric_name_objects" "gauge"
    fi

    if has_zfs_type "project"; then
	metric_name_bytes="${METRIC_NAME_PREFIX}_zfs_projectspace_bytes"
	metric_help "$metric_name_bytes" "ZFS projectspace usage in bytes"
	metric_type "$metric_name_bytes" "gauge"

	metric_name_objects="${METRIC_NAME_PREFIX}_zfs_projectspace_objects"
	metric_help "$metric_name_objects" "ZFS projectspace usage in objects"
	metric_type "$metric_name_objects" "gauge"
    fi

    for dataset in $ZFS_USERSPACE_DATASETS; do
	# Check if dataset exists, warn and skip if it doesn't
	zfs list -H -o name "$dataset" >/dev/null 2>&1 || { log_warn "Dataset $dataset not found, skipping"; continue; }

	# Execute collection natively inline
	has_zfs_type "user" && collect_userspace_type "$dataset" "user" "zfs userspace"
	has_zfs_type "group" && collect_userspace_type "$dataset" "group" "zfs groupspace"
	has_zfs_type "project" && collect_userspace_type "$dataset" "project" "zfs projectspace"
    done

    return 0
}

collect_userspace_type() {
    dataset="$1"
    space_type="$2"
    cmd="$3"

    has_command zfs || return 0

    metric_name_bytes="${METRIC_NAME_PREFIX}_zfs_${space_type}space_bytes"
    metric_name_objects="${METRIC_NAME_PREFIX}_zfs_${space_type}space_objects"

    # Call zfs directly with explicitly separated flags, safely pipe to awk
    $cmd -H -p -o used,name,objused "$dataset" 2>/dev/null | \
    _awk -v ds="$dataset" \
	 -v label="$space_type" \
	 -v m_bytes="$metric_name_bytes" \
	 -v m_objs="$metric_name_objects" '
    BEGIN {
	FS = "\t"
	totalb = 0
	totalo = 0
    }

    # Skip header if accidentally printed
    $1 == "USED" { next }

    {
	# Skip entirely blank lines safely
	if ($0 == "") next

	# Capture values
	used = $1
	name = $2
	objused = $3

	# Default to 0/unknown if missing or if ZFS returns "-"
	if (name == "" || name == "-") name = "unknown"
	if (used == "" || used == "-") used = 0
	if (objused == "" || objused == "-") objused = 0

	totalb += used
	totalo += objused

	# Escape quotes and backslashes in name
	gsub(/\\/, "\\\\", name)
	gsub(/"/, "\\\"", name)

	# Dynamic label injection (%s="%s")
	printf "%s{dataset=\"%s\",%s=\"%s\"} %s\n", m_bytes, ds, label, name, used
	printf "%s{dataset=\"%s\",%s=\"%s\"} %s\n", m_objs, ds, label, name, objused
    }
    END {
	# Sum aggregations (using %.0f prevents scientific notation e+ breaking Prometheus)
	printf "%s_sum{dataset=\"%s\"} %.0f\n", m_bytes, ds, totalb
	printf "%s_sum{dataset=\"%s\"} %.0f\n", m_objs, ds, totalo
    }'
}
