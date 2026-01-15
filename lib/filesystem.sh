#!/bin/sh
# lib/filesystem.sh
#
# Filesystem metrics collector

collect_filesystem() {
    [ "$ENABLE_FILESYSTEM" != "1" ] && return 0

    metric_help "${METRIC_NAME_PREFIX}_filesystem_size_bytes" "Filesystem size in bytes"
    metric_type "${METRIC_NAME_PREFIX}_filesystem_size_bytes" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_filesystem_used_bytes" "Filesystem used space in bytes"
    metric_type "${METRIC_NAME_PREFIX}_filesystem_used_bytes" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_filesystem_avail_bytes" "Filesystem available space in bytes"
    metric_type "${METRIC_NAME_PREFIX}_filesystem_avail_bytes" "gauge"

    # Build _awk script to filter exclusions
    exclude_types_pattern=$(echo "$FILESYSTEM_EXCLUDE_TYPES" | sed 's/ /|/g')
    exclude_paths_pattern=$(echo "$FILESYSTEM_EXCLUDE_PATHS" | sed 's/ /|/g')

    # Collect ZFS datasets if available
    if has_zfs; then

	echo ${ZFS_LIST_DEPTH:+"-d $ZFS_LIST_DEPTH"}
	# here we deal with type=filesystem only, movin `-t TYPE' to config file hasn't been considered yet
	zfs list -Hp -o name,used,avail,refer,mountpoint -t fs ${ZFS_LIST_DEPTH:+-d $ZFS_LIST_DEPTH} 2>/dev/null | \
	_awk -v exclude_paths="$exclude_paths_pattern" '
	$5 != "-" && $5 != "none" && $5 != "legacy" {
	    dataset = $1
	    used = $2
	    avail = $3
	    refer = $4
	    mountpoint = $5

	    # Skip excluded paths
	    if (exclude_paths && mountpoint ~ "^(" exclude_paths ")") next

	    size = used + avail

	    # Escape quotes in labels
	    gsub(/"/, "\\\"", dataset)
	    gsub(/"/, "\\\"", mountpoint)

	    printf "%s_filesystem_size_bytes{mountpoint=\"%s\",fstype=\"zfs\",dataset=\"%s\"}  %s\n", pfx, mountpoint, dataset, size
	    printf "%s_filesystem_used_bytes{mountpoint=\"%s\",fstype=\"zfs\",dataset=\"%s\"}  %s\n", pfx, mountpoint, dataset, used
	    printf "%s_filesystem_avail_bytes{mountpoint=\"%s\",fstype=\"zfs\",dataset=\"%s\"} %s\n", pfx, mountpoint, dataset, avail
	}'

    else

	# Collect non-ZFS filesystems from df
	df -kT 2>/dev/null | \
	    _awk -v exclude_types="$exclude_types_pattern" -v exclude_paths="$exclude_paths_pattern" '
    NR > 1 && $2 != "zfs" {
	device = $1
	fstype = $2
	size = $3 * 1024
	used = $4 * 1024
	avail = $5 * 1024
	mountpoint = $7

	# Skip excluded types
	if (exclude_types && fstype ~ "^(" exclude_types ")$") next

	# Skip excluded paths
	if (exclude_paths && mountpoint ~ "^(" exclude_paths ")") next

	# Escape quotes
	gsub(/"/, "\\\"", device)
	gsub(/"/, "\\\"", mountpoint)
	gsub(/"/, "\\\"", fstype)

	printf "%s_filesystem_size_bytes{mountpoint=\"%s\",fstype=\"%s\",device=\"%s\"} %s\n", pfx, mountpoint, fstype, device, size
	printf "%s_filesystem_used_bytes{mountpoint=\"%s\",fstype=\"%s\",device=\"%s\"} %s\n", pfx, mountpoint, fstype, device, used
	printf "%s_filesystem_avail_bytes{mountpoint=\"%s\",fstype=\"%s\",device=\"%s\"} %s\n", pfx, mountpoint, fstype, device, avail
    }'
    fi

}
