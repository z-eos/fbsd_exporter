# FreeBSD Prometheus Metrics Collector

A lightweight, modular Prometheus metrics exporter for FreeBSD systems, designed to provide comprehensive system monitoring with minimal overhead.

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
┌─────────────────────────────┐
│ freebsd-metrics-server.sh   │
│  reads and merges:          │
│  - fast.prom                │
│  - slow.prom                │
│  - userspace.prom           │
└─────────────────────────────┘
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

Edit `/usr/local/etc/freebsd-metrics.conf`:

```bash
# Enable/disable modules
ENABLE_CPU=1
ENABLE_MEMORY=1
ENABLE_DISK_IO=1
ENABLE_FILESYSTEM=1
ENABLE_ZFS_CORE=1
ENABLE_ZFS_USERSPACE=0  # Enable for quota tracking
ENABLE_PROCESS=0        # Enable for process monitoring

# ZFS userspace settings (if enabled)
ZFS_USERSPACE_DATASETS="tank/mails tank/home"
ZFS_USERSPACE_TYPES="user group"

# Process monitoring (if enabled)
PROCESS_NAMES="nginx postgres sshd"
```

## Setup

### 1. Configure Cron

```bash
# Edit crontab for prometheus user
crontab -u prometheus -e

# Add these lines:
* * * * * /usr/local/lib/freebsd-metrics/collect-fast.sh --loop 6 10
*/5 * * * * /usr/local/lib/freebsd-metrics/collect-slow.sh
*/15 * * * * /usr/local/lib/freebsd-metrics/collect-userspace.sh
```

The `--loop 6 10` runs fast collector 6 times with 10-second intervals (every minute, collects every 10s).

### 2. Configure inetd

Add to `/etc/inetd.conf`:

```
9101 stream tcp nowait nobody /usr/local/libexec/freebsd-metrics-server.sh freebsd-metrics-server.sh
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
ls -lh /var/lib/freebsd-metrics/

# Check cron logs
grep freebsd-metrics /var/log/cron
```

## Prometheus Configuration

Add to `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'freebsd-hosts'
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

## Troubleshooting

### No metrics appearing

```bash
# Check if collectors are running
ps aux | grep collect

# Check cron logs
tail -f /var/log/cron

# Manually run collectors
su -m prometheus -c '/usr/local/lib/freebsd-metrics/collect-fast.sh'

# Check output files
cat /var/lib/freebsd-metrics/fast.prom
```

### inetd not responding

```bash
# Check inetd is running
service inetd status

# Test with telnet
telnet localhost 9101

# Check inetd logs
tail -f /var/log/messages | grep inetd

# Verify inetd.conf syntax
inetd -d  # Debug mode
```

### Metrics stale

```bash
# Check file timestamps
ls -lh /var/lib/freebsd-metrics/

# Check for collector errors
grep ERROR /var/log/cron

# Verify permissions
ls -la /var/lib/freebsd-metrics/
```

### High cardinality (userspace)

```bash
# Increase threshold in config
ZFS_USERSPACE_MIN_BYTES=10737418240  # 10GB

# Reduce max entries
ZFS_USERSPACE_MAX_ENTRIES=100

# Limit to specific datasets
ZFS_USERSPACE_DATASETS="tank/important"
```

## Performance Considerations

- **Fast collector**: ~0.5-2s execution time
- **Slow collector**: ~1-5s execution time
- **Userspace collector**: ~5-30s depending on user count
- **inetd overhead**: <10ms per request
- **Memory usage**: <10MB per collector
- **Disk I/O**: Minimal (atomic file writes)

## SNMP Integration

This collector is designed to complement SNMP monitoring:

**Disable network metrics if using SNMP**:
```bash
ENABLE_NETWORK=0  # Not implemented yet, placeholder
```

**SNMP typically covers**:
- Interface statistics
- Protocol counters
- Routing table

**This collector adds**:
- Deep ZFS metrics
- Process monitoring
- System-level details
- Native FreeBSD integration

## License

BSD-2-Clause (FreeBSD-style)

## Contributing

Contributions welcome! Areas for improvement:
- Additional metric collectors
- Performance optimizations
- Better error handling
- Unit tests

## Author

Community project for FreeBSD monitoring
