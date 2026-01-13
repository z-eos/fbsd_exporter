#!/bin/sh
#

# EXAMPLE: sudo ./collect-test.sh <zfs_userspace> [./freebsd-metrics.conf]

CONFIG_FILE="${2:-./fbsd_exporter.conf}"

. $CONFIG_FILE
. lib/common.sh
. lib/${1}.sh

collect_$1
