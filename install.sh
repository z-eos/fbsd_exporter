#!/bin/sh
#

set -e

# Directories
LIBEXEC_DIR="/usr/local/libexec/fbsd_exporter"
ETC_DIR="/usr/local/etc"
METRICS_DIR="/var/spool/fbsd_exporter"

echo "==> Installing FreeBSD Prometheus Metrics Collector"

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Create directories
echo "==> Creating directories"
for dir in "${LIBEXEC_DIR}/lib" "$METRICS_DIR"; do
    if [ ! -d "$dir" ]; then
	mkdir -p "$dir"
	echo "    Created $dir"
    fi
done

# Set ownership and permissions
chown "root:wheel" "$METRICS_DIR"
chmod 755 "$METRICS_DIR"

# Install library files
echo "==> Installing library files"
for file in `ls lib`; do
    install -m 755 -o root -g wheel "lib/${file}" "${LIBEXEC_DIR}/lib/${file}"
    echo "    Installed file: $file"
done

# Install collector scripts
echo "==> Installing collector scripts"
for script in collect collect-test; do
    if [ -f "${script}.sh" ]; then
	install -m 755 -o root -g wheel "${script}.sh" "${LIBEXEC_DIR}/"
	echo "    Installed ${script}.sh"
    fi
done

# Install inetd server script
echo "==> Installing inetd server script"
if [ -f "fbsd_exporter_server.sh" ]; then
    install -m 755 -o root -g wheel "fbsd_exporter_server.sh" "${LIBEXEC_DIR}/"
    echo "    Installed fbsd_exporter_server.sh"
fi

# Install configuration file
echo "==> Installing configuration file"
if [ -f "fbsd_exporter.conf" ]; then
    if [ -f "${ETC_DIR}/fbsd_exporter.conf" ]; then
	echo "    Configuration file already exists, creating .sample"
	install -m 644 -o root -g wheel "fbsd_exporter.conf.dist" "${ETC_DIR}/fbsd_exporter.conf.sample"
    else
	install -m 644 -o root -g wheel "fbsd_exporter.conf.dist" "${ETC_DIR}/fbsd_exporter.conf"
	echo "    Installed fbsd_exporter.conf"
    fi
fi

# Create empty metric files
echo "==> Creating initial metric files"
for file in fbsd_exporter_fast.prom fbsd_exporter_slow.prom fbsd_exporter_userspace.prom; do
    touch "${METRICS_DIR}/${file}"
    chown "root:wheel" "${METRICS_DIR}/${file}"
    chmod 644 "${METRICS_DIR}/${file}"
    echo "    ${METRICS_DIR}/${file}"
done

echo ""
echo "==> Installation complete!"
echo ""
echo "Next steps:"
echo ""
echo "1. Edit configuration: ${ETC_DIR}/fbsd_exporter.conf"
echo ""
echo "2. Add to crontab:"
echo "   * * * * * ${LIBEXEC_DIR}/collect.sh"
echo "   */5 * * * * ${LIBEXEC_DIR}/collect.sh -s slow"
echo "   */15 * * * * ${LIBEXEC_DIR}/collect.sh -s userspace"
echo ""
echo "3. Configure inetd:"
echo "   Add to /etc/inetd.conf:"
echo "   9101 stream tcp nowait nobody ${LIBEXEC_DIR}/fbsd_exporter_server.sh fbsd_exporter_server.sh"
echo ""
echo "   Enable inetd in /etc/rc.conf:"
echo "   inetd_enable=\"YES\""
echo "   inetd_flags=\"-wW -C 60\""
echo ""
echo "   Restart inetd:"
echo "   service inetd restart"
echo ""
echo "4. Test the setup:"
echo "   curl http://localhost:9101/metrics"
echo ""
echo "5. Configure Prometheus to scrape http://$(hostname):9101/metrics"
echo ""
