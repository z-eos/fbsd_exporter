#!/bin/sh
# lib/userspace.sh
#
# ZFS userspace/groupspace/projectspace collector

collect_zfs_userspace() {
    [ "$ENABLE_ZFS_USERSPACE" != "1" ] && return 0

    if ! has_zfs; then
	log_warn "ZFS not available, skipping userspace metrics"
	return 0
    fi

    if [ -z "$ZFS_USERSPACE_DATASETS" ]; then
	log_warn "ZFS_USERSPACE_DATASETS not configured, skipping userspace metrics"
	return 0
    fi

    # Optimized: Pad spaces around variable and use shell substring removal instead of echo | grep
    types_padded=" $ZFS_USERSPACE_TYPES "

    if [ "${types_padded#* user }" != "$types_padded" ]; then
	metric_name_bytes="${METRIC_NAME_PREFIX}_zfs_userspace_bytes"
	metric_help "$metric_name_bytes" "ZFS userspace usage in bytes"
	metric_type "$metric_name_bytes" "gauge"

	metric_name_objects="${METRIC_NAME_PREFIX}_zfs_userspace_objects"
	metric_help "$metric_name_objects" "ZFS userspace usage in objects"
	metric_type "$metric_name_objects" "gauge"
    fi

    if [ "${types_padded#* group }" != "$types_padded" ]; then
	metric_name_bytes="${METRIC_NAME_PREFIX}_zfs_groupspace_bytes"
	metric_help "$metric_name_bytes" "ZFS groupspace usage in bytes"
	metric_type "$metric_name_bytes" "gauge"

	metric_name_objects="${METRIC_NAME_PREFIX}_zfs_groupspace_objects"
	metric_help "$metric_name_objects" "ZFS groupspace usage in objects"
	metric_type "$metric_name_objects" "gauge"
    fi

    if [ "${types_padded#* project }" != "$types_padded" ]; then
	metric_name_bytes="${METRIC_NAME_PREFIX}_zfs_projectspace_bytes"
	metric_help "$metric_name_bytes" "ZFS projectspace usage in bytes"
	metric_type "$metric_name_bytes" "gauge"

	metric_name_objects="${METRIC_NAME_PREFIX}_zfs_projectspace_objects"
	metric_help "$metric_name_objects" "ZFS projectspace usage in objects"
	metric_type "$metric_name_objects" "gauge"
    fi


    for dataset in $ZFS_USERSPACE_DATASETS; do
	# Check if dataset exists
	if ! zfs list -H -o name "$dataset" >/dev/null 2>&1; then
	    log_warn "Dataset $dataset not found, skipping"
	    continue
	fi

	# Collect userspace
	if [ "${types_padded#* user }" != "$types_padded" ]; then
	    # Use _zfs wrapper for subcommand
	    collect_userspace_type "$dataset" "user" "_zfs userspace"
	fi

	# Collect groupspace
	if [ "${types_padded#* group }" != "$types_padded" ]; then
	    collect_userspace_type "$dataset" "group" "_zfs groupspace"
	fi

	# Collect projectspace
	if [ "${types_padded#* project }" != "$types_padded" ]; then
	    collect_userspace_type "$dataset" "project" "_zfs projectspace"
	fi
    done
}

collect_userspace_type() {
    dataset="$1"
    space_type="$2"
    command="$3"

    label_name="$space_type"

    metric_name_bytes="${METRIC_NAME_PREFIX}_zfs_${space_type}space_bytes"
    metric_name_objects="${METRIC_NAME_PREFIX}_zfs_${space_type}space_objects"

    # Run the command
    $command -Hpo used,name,objused "$dataset" | \
    awk -v dataset="$dataset" \
	-v label="$label_name" \
	-v metricb="$metric_name_bytes" \
	-v metrico="$metric_name_objects" '
    BEGIN {
	FS = "\t"
	totalb = 0
	totalo = 0
    }

    # Skip header
    $1 == "USED" { next }

    {
	# Capture values, defaulting to 0/unknown if missing
	used = $1
	name = $2
	objused = $3

	if (name == "") name = "unknown"
	if (used == "") used = 0
	if (objused == "") objused = 0

	totalb += used
	totalo += objused

	# Escape quotes in name
	gsub(/"/, "\\\"", name)

	printf "%s{dataset=\"%s\",%s=\"%s\"} %s\n", metricb, dataset, label, name, used
	printf "%s{dataset=\"%s\",%s=\"%s\"} %s\n", metrico, dataset, label, name, objused
    }
    END {
	# Renamed _total suffix to _sum for Gauges
	printf "%s_sum{dataset=\"%s\"} %s\n", metricb, dataset, totalb
	printf "%s_sum{dataset=\"%s\"} %s\n", metrico, dataset, totalo
    }'
}
