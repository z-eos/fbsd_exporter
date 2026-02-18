#!/bin/sh
#

# EXAMPLE: sudo ./collect-test.sh <zfs_userspace> [./freebsd-metrics.conf]

CONFIG_FILE="${2:-./fbsd_exporter.conf}"

. $CONFIG_FILE
. lib/common.sh

case $1 in
    cpu|disk|filesystem|memory|process|zfs_userspace|zfs|zpool)
	. lib/${1}.sh
	collect_$1
	;;

    all)
	for mod in lib/*.sh
	do
	    test "$mod" = "lib/common.sh" && continue
	    . $mod
	done

	for file in lib/*.sh
	do
	    mod=$(basename $file)
	    collect_${mod%%.*}
	done

	;;

    *)
	echo "there is no such module: $1"
	exit 1
esac
