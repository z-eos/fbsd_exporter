#!/bin/sh
# lib/disk.sh
#
# Disk I/O metrics collector

collect_disk() {
    [ "$ENABLE_DISK_IO" != "1" ] && return 0

    # Prefer zpool iostat for ZFS systems
    if [ "$DISK_PREFER_ZPOOL" = "1" ] && has_zfs; then
	collect_zpool_iostat
    fi

    if has_command gstat; then
	collect_gstat
    else
	collect_iostat
    fi
}

collect_zpool_iostat() {
    metric_help "${METRIC_NAME_PREFIX}_zpool_iostat_allocated_bytes" "Allocated space in pool"
    metric_type "${METRIC_NAME_PREFIX}_zpool_iostat_allocated_bytes" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_zpool_iostat_free_bytes" "Free space in pool"
    metric_type "${METRIC_NAME_PREFIX}_zpool_iostat_free_bytes" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_zpool_iostat_operations_total" "Total I/O operations"
    metric_type "${METRIC_NAME_PREFIX}_zpool_iostat_operations_total" "counter"

    metric_help "${METRIC_NAME_PREFIX}_zpool_iostat_bytes_total" "Total I/O bytes"
    metric_type "${METRIC_NAME_PREFIX}_zpool_iostat_bytes_total" "counter"

    # Get pool-level stats
    zpool iostat -Hp 2>/dev/null | _awk 'NR > 1 && NF >= 7 {
	pool = $1
	alloc = $2
	free = $3
	read_ops = $4
	write_ops = $5
	read_bw = $6
	write_bw = $7

	printf "%s_zpool_iostat_allocated_bytes{pool=\"%s\"} %s\n", pfx, pool, alloc
	printf "%s_zpool_iostat_free_bytes{pool=\"%s\"} %s\n", pfx, pool, free
	printf "%s_zpool_iostat_operations_total{pool=\"%s\",operation=\"read\"} %s\n", pfx, pool, read_ops
	printf "%s_zpool_iostat_operations_total{pool=\"%s\",operation=\"write\"} %s\n", pfx, pool, write_ops
	printf "%s_zpool_iostat_bytes_total{pool=\"%s\",operation=\"read\"} %s\n", pfx, pool, read_bw
	printf "%s_zpool_iostat_bytes_total{pool=\"%s\",operation=\"write\"} %s\n", pfx, pool, write_bw
    }'

    # Per-vdev stats if enabled
    if [ "$DISK_INCLUDE_VDEV" = "1" ]; then
	metric_help "${METRIC_NAME_PREFIX}_zpool_iostat_vdev_operations_total" "Total I/O operations per vdev"
	metric_type "${METRIC_NAME_PREFIX}_zpool_iostat_vdev_operations_total" "counter"

	metric_help "${METRIC_NAME_PREFIX}_zpool_iostat_vdev_bytes_total" "Total I/O bytes per vdev"
	metric_type "${METRIC_NAME_PREFIX}_zpool_iostat_vdev_bytes_total" "counter"

	zpool list -H -o name 2>/dev/null | while read pool; do
	    zpool iostat -Hpv "$pool" 2>/dev/null | _awk -v pool="$pool" 'NR > 1 && $1 != pool && NF >= 7 {
		vdev = $1
		gsub(/^  */, "", vdev)  # Remove leading spaces
		read_ops = $4
		write_ops = $5
		read_bw = $6
		write_bw = $7

		printf "%s_zpool_iostat_vdev_operations_total{pool=\"%s\",vdev=\"%s\",operation=\"read\"} %s\n", pfx, pool, vdev, read_ops
		printf "%s_zpool_iostat_vdev_operations_total{pool=\"%s\",vdev=\"%s\",operation=\"write\"} %s\n", pfx, pool, vdev, write_ops
		printf "%s_zpool_iostat_vdev_bytes_total{pool=\"%s\",vdev=\"%s\",operation=\"read\"} %s\n", pfx, pool, vdev, read_bw
		printf "%s_zpool_iostat_vdev_bytes_total{pool=\"%s\",vdev=\"%s\",operation=\"write\"} %s\n", pfx, pool, vdev, write_bw
	    }'
	done
    fi
}

collect_gstat() {
    metric_help "${METRIC_NAME_PREFIX}_disk_gstat_operations_per_second" "Disk operations per second"
    metric_type "${METRIC_NAME_PREFIX}_disk_gstat_operations_per_second" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_disk_gstat_bytes_per_second" "Disk bytes per second"
    metric_type "${METRIC_NAME_PREFIX}_disk_gstat_bytes_per_second" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_disk_gstat_busy_percent" "Disk busy percentage"
    metric_type "${METRIC_NAME_PREFIX}_disk_gstat_busy_percent" "gauge"

    # Run gstat for the configured interval
    interval=${DISK_GSTAT_INTERVAL:-1s}

    # gstat output format:
    # dT: 1.033s  w: 1.000s
    #  L(q)  ops/s    r/s   kBps   ms/r    w/s   kBps   ms/w    d/s   kBps   ms/d   %busy Name
    #     0      0      0      0    0.0      0      0    0.0      0      0    0.0    0.0  da0

    gstat -bdp -I "${interval}" 2>/dev/null | _awk -v interval="$interval" '
    # Skip header lines
    /^dT:/ { next }
    /L\(q\)/ { next }
    /^[[:space:]]*$/ { next }

    # Process device lines
    NF >= 13 && $1 ~ /^[0-9]+$/ {
	queue = $1
	ops = $2
	read_ops = $3
	read_kbps = $4
	read_ms = $5
	write_ops = $6
	write_kbps = $7
	write_ms = $8
	d_ops = $9
	d_kbps = $10
	d_ms = $11
	busy = $12
	device = $13

	# Skip special devices
	if (device ~ /^(cd|pass|md)/) next

	# Convert kBps to bytes/s
	read_bps = read_kbps * 1024
	write_bps = write_kbps * 1024

	printf "%s_disk_gstat_operations_per_second{device=\"%s\",operation=\"read\"} %s\n", pfx, device, read_ops
	printf "%s_disk_gstat_operations_per_second{device=\"%s\",operation=\"write\"} %s\n", pfx, device, write_ops
	printf "%s_disk_gstat_bytes_per_second{device=\"%s\",operation=\"read\"} %.0f\n", pfx, device, read_bps
	printf "%s_disk_gstat_bytes_per_second{device=\"%s\",operation=\"write\"} %.0f\n", pfx, device, write_bps
	printf "%s_disk_gstat_busy_percent{device=\"%s\"} %s\n", pfx, device, busy
	printf "%s_disk_gstat_queue_length{device=\"%s\"} %s\n", pfx, device, queue
    }'
}

collect_iostat() {
    if ! has_command iostat; then
	return 0
    fi

    metric_help "${METRIC_NAME_PREFIX}_disk_iostat_operations_per_second" "Disk operations per second"
    metric_type "${METRIC_NAME_PREFIX}_disk_iostat_operations_per_second" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_disk_iostat_bytes_per_second" "Disk bytes per second"
    metric_type "${METRIC_NAME_PREFIX}_disk_iostat_bytes_per_second" "gauge"

    metric_help "${METRIC_NAME_PREFIX}_disk_iostat_busy_percent" "Disk busy percentage"
    metric_type "${METRIC_NAME_PREFIX}_disk_iostat_busy_percent" "gauge"

    # iostat output (extended format):
    # device     r/s   w/s    kr/s    kw/s qlen  svc_t  %b

    iostat -x -w 1 -c 2 2>/dev/null | _awk '
    # Skip until we see the second iteration (to get rates, not totals)
    /^device/ { header_count++; next }

    # Only process lines from second iteration
    header_count == 2 && NF >= 7 {
	device = $1
	read_ops = $2
	write_ops = $3
	read_kbps = $4
	write_kbps = $5
	queue = $6
	svc_time = $7
	busy = $8

	# Skip special devices
	if (device ~ /^(cd|pass|md)/) next

	# Convert kBps to bytes/s
	read_bps = read_kbps * 1024
	write_bps = write_kbps * 1024

	printf "%s_disk_iostat_operations_per_second{device=\"%s\",operation=\"read\"} %s\n", pfx, device, read_ops
	printf "%s_disk_iostat_operations_per_second{device=\"%s\",operation=\"write\"} %s\n", pfx, device, write_ops
	printf "%s_disk_iostat_bytes_per_second{device=\"%s\",operation=\"read\"} %.0f\n", pfx, device, read_bps
	printf "%s_disk_iostat_bytes_per_second{device=\"%s\",operation=\"write\"} %.0f\n", pfx, device, write_bps
	printf "%s_disk_iostat_busy_percent{device=\"%s\"} %s\n", pfx, device, busy
	printf "%s_disk_iostat_queue_length{device=\"%s\"} %s\n", pfx, device, queue
	printf "%s_disk_iostat_service_time_ms{device=\"%s\"} %s\n", pfx, device, svc_time
    }'
}
