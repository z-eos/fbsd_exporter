# FreeBSD Openmetrics Generator And Collector

A lightweight, modular openmetrics exporter for FreeBSD systems, designed to provide comprehensive system monitoring with minimal overhead.

The main idea is to use tools natively available in OS.

## Features

- **Modular Architecture**: Enable/disable metric groups as needed
- **Multi-tier Collection**: Fast (10s), slow (5m), and userspace (15m) collectors
- **ZFS-First Design**: Deep ZFS integration with pool, dataset, and userspace metrics
- **inetd Integration**: Serves metrics via HTTP without persistent daemon
- **Atomic Updates**: Lock-free file operations prevent partial data
- **Low Overhead**: POSIX-shell-based collectors with minimal resource usage

## Metrics Collected

### Core Metrics (Always Enabled)
- **CPU**: Per-CPU time, load averages, context switches, interrupts
- **Memory**: Physical memory breakdown, page statistics, swap usage
- **System**: Uptime, kernel version, architecture

### Optional Modules

#### Disk I/O
- **ZFS Pools**: Operations, bandwidth, allocation per pool and vdev
- **GEOM Devices**: I/O statistics via gstat

#### Filesystem
- **ZFS Datasets**: Usage, available space, compression ratio
- **UFS/Others**: Standard filesystem metrics

#### ZFS Core
- **ARC**: Size, hit rate, L2ARC statistics
- **Pool Health**: Status, errors, scrub information
- **Fragmentation**: Per-pool fragmentation ratio

#### ZFS Userspace
- **User/Group/Project**: Space usage per entity per dataset
- **Configurable Thresholds**: Limit cardinality with minimum size filters

#### Process Monitoring
- **Per-Process**: CPU, memory, state for configured processes
- **Aggregated**: Total resources by process name

## Architecture

```
┌─────────────────┐
│   Prometheus    │
└────────┬────────┘
		 │ scrape :9101/metrics
		 ▼
┌─────────────────┐
│  inetd :9101    │
└────────┬────────┘
		 │ spawn
		 ▼
┌─────────────────────────────────┐
│ fbsd_exporter_server.sh         │
│  reads and merges:              │
│  - fbsd_exporter_fast.prom      │
│  - fbsd_exporter_slow.prom      │
│  - fbsd_exporter_userspace.prom │
└─────────────────────────────────┘
		 ▲
		 │ atomic writes
	┌────┴────┬─────────┐
	│         │         │
┌───┴────┐ ┌──┴─────┐ ┌─┴─────────┐
│ Fast   │ │ Slow   │ │ Userspace │
│ (10s)  │ │ (5m)   │ │ (15m)     │
└────────┘ └────────┘ └───────────┘
   cron       cron        cron
```

## Configuration

Edit `/usr/local/etc/fbsd_exporter.conf`:

## Setup

### 1. Configure Cron

create file in /usr/local/etc/cron.d with something like this

```bash
#
# minute hour mday month wday who command
#

*/1  * * * * root /usr/local/libexec/fbsd_exporter/collect.sh
*/5  * * * * root /usr/local/libexec/fbsd_exporter/collect.sh -s slow
*/15 * * * * root /usr/local/libexec/fbsd_exporter/collect.sh -s userspace

#
```

### 2. Configure inetd

Add to `/etc/inetd.conf`:

```
9101 stream tcp nowait nobody /usr/local/libexec/fbsd_exporter_server.sh fbsd_exporter_server.sh
```

Enable inetd in `/etc/rc.conf`:

```bash
inetd_enable="YES"
inetd_flags="-wW -C 60"  # Rate limiting
```

Restart inetd:

```bash
service inetd restart
```

### 3. Firewall Configuration (Optional)

For PF, add to `/etc/pf.conf`:

```
prometheus_server = "192.168.1.10"
pass in proto tcp from $prometheus_server to any port 9101
```

### 4. Verify Installation

```bash
# Test locally
curl http://localhost:9101/metrics

# Check if metrics are being collected
ls -lh /var/spool/fbsd_exporter/

# Check cron logs
grep fbsd_exporter /var/log/cron
```

## Prometheus Configuration

Add to `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'fbsd'
	static_configs:
	  - targets:
		  - 'freebsd-host1.example.com:9101'
		  - 'freebsd-host2.example.com:9101'
	scrape_interval: 30s
	scrape_timeout: 10s
```

## Example Metrics

```
# CPU time
freebsd_cpu_time_seconds_total{cpu="0",mode="user"} 12345.67
freebsd_cpu_time_seconds_total{cpu="0",mode="system"} 2345.67

# Memory
freebsd_memory_bytes{type="active"} 8589934592
freebsd_memory_bytes{type="free"} 4294967296

# ZFS Pool
freebsd_zfs_pool_allocated_bytes{pool="tank"} 5497558138880
freebsd_zfs_pool_free_bytes{pool="tank"} 4939212029952

# ZFS ARC
freebsd_zfs_arc_size_bytes 4294967296
freebsd_zfs_arc_hit_ratio 0.9523

# Filesystem
freebsd_filesystem_used_bytes{mountpoint="/home",fstype="zfs",dataset="tank/home"} 1234567890

# ZFS Userspace (if enabled)
freebsd_zfs_userspace_bytes{dataset="tank/mails",user="john.doe"} 5314053350
freebsd_zfs_groupspace_bytes{dataset="tank/data",group="developers"} 10737418240
```
