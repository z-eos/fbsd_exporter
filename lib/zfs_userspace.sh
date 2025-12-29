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

    for dataset in $ZFS_USERSPACE_DATASETS; do
	# Check if dataset exists
	if ! zfs list -H -o name "$dataset" >/dev/null 2>&1; then
	    log_warn "Dataset $dataset not found, skipping"
	    continue
	fi

	# Collect userspace
	if echo "$ZFS_USERSPACE_TYPES" | grep -q user; then
	    collect_userspace_type "$dataset" "user" "zfs userspace"
	fi

	# Collect groupspace
	if echo "$ZFS_USERSPACE_TYPES" | grep -q group; then
	    collect_userspace_type "$dataset" "group" "zfs groupspace"
	fi

	# Collect projectspace
	if echo "$ZFS_USERSPACE_TYPES" | grep -q project; then
	    collect_userspace_type "$dataset" "project" "zfs projectspace"
	fi
    done
}

collect_userspace_type() {
    dataset="$1"
    type="$2"
    command="$3"

    metric_name="${METRIC_NAME_PREFIX}_zfs_${type}space_bytes"
    label_name="$type"

    metric_help "$metric_name" "ZFS ${type}space usage in bytes"
    metric_type "$metric_name" "gauge"

    # Run the command and filter by threshold
    $command -Hp -o used,name "$dataset" 2>/dev/null | \
    awk -v dataset="$dataset" \
	-v label="$label_name" \
	-v min_bytes="$ZFS_USERSPACE_MIN_BYTES" \
	-v max_entries="$ZFS_USERSPACE_MAX_ENTRIES" \
	-v metric="$metric_name" '
    BEGIN { total = 0 }
    {
	bytes = $1
	name = $2
	total += bytes

	# Escape quotes in name
	gsub(/"/, "\\\"", name)

	printf "%s{dataset=\"%s\",%s=\"%s\"} %s\n", metric, dataset, label, name, bytes

    }
    END {
	{
	    printf "%s_total{dataset=\"%s\"} %s\n", metric, dataset, total
	}
    }'
}
