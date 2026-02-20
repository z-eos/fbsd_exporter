# **fbsd\_exporter(8) \- FreeBSD System Manager's Manual**

## **NAME**

**fbsd\_exporter** \- Native shell-based Prometheus metrics exporter for FreeBSD

## **SYNOPSIS**

collect.sh \[-d\] \[-c config\_file\] \[-M metrics\_dir\] \[-s scope\]

fbsd\_exporter\_server.sh

## **DESCRIPTION**

The **fbsd\_exporter** suite provides a native, dependency-free mechanism for extracting system metrics from a FreeBSD host and exposing them in the Prometheus text-based exposition format. Unlike traditional exporters written in Go, **fbsd\_exporter** relies exclusively on the POSIX shell (/bin/sh) and standard FreeBSD base utilities (sysctl, zfs, zpool, awk).  
The system is architecturally split into two distinct phases to ensure system stability and prevent blocking:

1. **Collection:** The collect.sh script is invoked periodically (typically via cron(8)) to gather metrics and atomically write them to a spool directory.  
2. **Exposition:** The fbsd\_exporter\_server.sh script serves the pre-calculated metrics over HTTP. It is designed to be invoked by inetd(8) or a similar super-server.

Metrics are grouped into "scopes", allowing expensive operations (like querying ZFS user/group quotas) to be executed less frequently than lightweight operations (like reading CPU state).

## **OPTIONS**

The following options are available for the collect.sh utility:

* **\-c** *config\_file*  
  Specify an alternate configuration file. If not specified, the default is /usr/local/etc/fbsd\_exporter.conf.  
* **\-d**  
  Enable debug logging. Execution traces, environments, and verbose module outputs will be appended to the debug log (see *FILES*).  
* **\-M** *metrics\_dir*  
  Specify the spool directory where output .prom files are written. Overrides the METRICS\_DIR variable in the configuration file. Default is /var/spool/fbsd\_exporter.  
* **\-s** *scope*  
  Define the scope of metrics to collect during this execution. The *scope* argument dictates which library files are sourced. Valid scopes are:  
  * **fast**: Lightweight metrics suitable for sub-minute polling (CPU, memory, disk I/O, filesystem usage, process counts). This is the default if \-s is omitted.  
  * **slow**: Heavier metrics that may require disk access or subsystem locks (Zpool health, ZFS core statistics).  
  * **userspace**: Highly intensive metrics requiring deep dataset traversal (ZFS userspace, groupspace, and projectspace quotas).

## **CONFIGURATION**

The configuration file (fbsd\_exporter.conf) is sourced directly by the shell and must conform to POSIX shell syntax. It defines which modules are enabled and configures module-specific parameters.  
Key configuration variables include:

* ENABLE\_CPU, ENABLE\_MEMORY, ENABLE\_ZFS\_CORE, etc.: Set to 1 to enable the respective collector, or 0 to disable.  
* MAX\_AGE\_FAST, MAX\_AGE\_SLOW, MAX\_AGE\_USERSPACE: Defines the maximum age (in seconds) of a spool file before the HTTP server considers it stale and drops the metrics.  
* ZFS\_USERSPACE\_DATASETS: A space-separated list of ZFS datasets to query when the **userspace** scope is executed (e.g., "zroot/ROOT tank/home").  
* PROCESS\_NAMES: A space-separated list of process names to monitor for CPU/memory consumption.

## **IMPLEMENTATION NOTES**

* collect.sh utilizes lockf(1) to prevent concurrent executions of the same scope. If a cron job fires while a previous execution of the same scope is still running, the new process will exit immediately with status 0\.  
* To ensure atomic metric updates, collect.sh writes all metrics to a temporary file (\*.prom.PID) within the *metrics\_dir*. Upon successful completion, the temporary file is moved to the final destination file using mv(1).  
* Arithmetic and float conversions are strictly delegated to awk(1) to bypass the 32-bit integer limits and octal-parsing quirks inherent to standard /bin/sh.

## **MODULE ARCHITECTURE**

The metric collection logic is highly modular. Each collector resides in a standalone POSIX shell script within the lib/ directory. Modules are dynamically sourced by collect.sh based on the requested *scope*.  
To standardize output and ensure execution safety, modules rely on helper functions defined in lib/common.sh:

* metric\_help "metric\_name" "Description": Generates the \# HELP metadata line.  
* metric\_type "metric\_name" "gauge|counter": Generates the \# TYPE metadata line.  
* metric "metric\_name" "labels" "value": Emits the actual metric. If labels are provided (e.g., device="ada0"), they are automatically enclosed in braces.  
* \_awk: A wrapper for awk(1) that automatically injects the \-v pfx="$METRIC\_NAME\_PREFIX" variable, allowing awk scripts to seamlessly prefix metric names (using %s\_metric\_name, pfx).  
* \_sysctl, \_zfs, \_zpool: Safe execution wrappers that redirect standard error to the debug log and prevent the strict set \-e shell environment from aborting the entire collection run if a system binary fails or returns a non-zero exit code.

## **CREATING NEW MODULES**

To introduce a new metric collector (e.g., for pf firewall stats), follow this procedure:

1. **Create the Library File:**  
   Create a new file lib/pf.sh.  
2. **Define the Collector Function:**  
   Implement a function named collect\_pf(). The function must first verify if it is enabled via a configuration toggle:  
   collect\_pf() {  
       \[ "$ENABLE\_PF" \!= "1" \] && return 0  
       \# Metric collection logic goes here  
   }

3. **Format and Emit Metrics:**  
   Utilize the helper functions to output data to standard output.  
   metric\_help "${METRIC\_NAME\_PREFIX}\_pf\_states" "Number of active pf states"  
   metric\_type "${METRIC\_NAME\_PREFIX}\_pf\_states" "gauge"

   states=$(pfctl \-si 2\>/dev/null | awk '/current entries/ {print $3}')  
   metric "${METRIC\_NAME\_PREFIX}\_pf\_states" "" "${states:-0}"

4. **Register the Module in collect.sh:**  
   You must register the module in collect.sh by defining when it is sourced and when it is executed.  
   * **Source the library:** Append your script (e.g., pf.sh) to the LIB\_FILES variable. If you are adding it to the default fast scope, you must update LIB\_FILES in **two** places:  
     1. Inside the getopts arguments parser (case "$OPTARG" in fast)).  
     2. Inside the default fallback block (if \[ \-z "$SCOPE" \]; then).  
   * **Execute the collector:** Append the execution call if \[ "$ENABLE\_PF" \= "1" \]; then run\_collector "pf" collect\_pf; fi inside the corresponding collection function (e.g., collect\_all\_fast()).  
5. **Update Configuration:**  
   Add the default toggle ENABLE\_PF=1 to fbsd\_exporter.conf.

## **FILES**

* /usr/local/libexec/fbsd\_exporter/collect.sh  
  The primary metric collection executable.  
* /usr/local/libexec/fbsd\_exporter/fbsd\_exporter\_server.sh  
  The HTTP exposition server (for use with inetd).  
* /usr/local/libexec/fbsd\_exporter/lib/\*  
  Modular metric collection libraries sourced by collect.sh.  
* /usr/local/etc/fbsd\_exporter.conf  
  The master configuration file.  
* /var/spool/fbsd\_exporter/\*  
  The default spool directory containing the materialized Prometheus metrics (\*.prom files).  
* /var/log/fbsd\_exporter-debug.log  
  The default output file for crash dumps and debug traces when \-d is utilized.

## **EXAMPLES**

To execute a manual collection of the lightweight metrics with debugging enabled:  
/usr/local/libexec/fbsd\_exporter/collect.sh \-s fast \-d

To configure cron(8) to collect metrics at recommended intervals, add the following to /etc/crontab:  
\# Run fast metrics every minute  
\* \* \* \* \* root  /usr/local/libexec/fbsd\_exporter/collect.sh \-s fast

\# Run slow metrics every 5 minutes  
\*/5 \* \* \* \* root  /usr/local/libexec/fbsd\_exporter/collect.sh \-s slow

\# Run userspace metrics every 15 minutes  
\*/15 \* \* \* \* root  /usr/local/libexec/fbsd\_exporter/collect.sh \-s userspace

To configure inetd(8) to serve the metrics on port 9100, add the following to /etc/inetd.conf:  
9100 stream tcp nowait nobody /usr/local/libexec/fbsd\_exporter/fbsd\_exporter\_server.sh fbsd\_exporter\_server.sh

## **SEE ALSO**

awk(1), cron(8), inetd(8), lockf(1), sysctl(8), zfs(8), zpool(8)

## **HISTORY**

The **fbsd\_exporter** was developed to provide a robust, low-overhead alternative to compiled metric exporters on FreeBSD systems, relying entirely on the native base system utilities.