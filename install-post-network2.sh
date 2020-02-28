#!/usr/bin/env bash
################################################################################
# This is property of eXtremeSHOK.com
# You are free to use, modify and distribute, however you may not remove this notice.
# Copyright (c) Adrian Jon Kriel :: admin@extremeshok.com
################################################################################
#
# Script updates can be found at: https://github.com/extremeshok/xshok-proxmox
#
# post-installation script for Proxmox
#
# License: BSD (Berkeley Software Distribution)
#
################################################################################
#
# Assumptions: proxmox installed
#
# Notes:
# to disable the MOTD banner, set the env NO_MOTD_BANNER to true (export NO_MOTD_BANNER=true)
#
################################################################################
#
#    THERE ARE NO USER CONFIGURABLE OPTIONS IN THIS SCRIPT
#
################################################################################

## Protect the web interface with fail2ban
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install fail2ban
# shellcheck disable=1117
cat <<EOF > /etc/fail2ban/filter.d/proxmox.conf
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
EOF
cat <<EOF > /etc/fail2ban/jail.d/proxmox.conf
[proxmox]
enabled = true
port = https,http,8006
filter = proxmox
logpath = /var/log/daemon.log
maxretry = 3
# 1 hour
bantime = 3600
EOF
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
banaction = iptables-ipset-proto4
EOF
systemctl enable fail2ban
##testing
#fail2ban-regex /var/log/daemon.log /etc/fail2ban/filter.d/proxmox.conf

## Increase max user watches
# BUG FIX : No space left on device
echo 1048576 > /proc/sys/fs/inotify/max_user_watches
echo "fs.inotify.max_user_watches=1048576" >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

## Increase max FD limit / ulimit
cat <<EOF >> /etc/security/limits.conf
# eXtremeSHOK.com Increase max FD limit / ulimit
* soft     nproc          256000
* hard     nproc          256000
* soft     nofile         256000
* hard     nofile         256000
root soft     nproc          256000
root hard     nproc          256000
root soft     nofile         256000
root hard     nofile         256000
EOF

## Enable TCP BBR congestion control
cat <<EOF > /etc/sysctl.d/10-kernel-bbr.conf
# eXtremeSHOK.com
# TCP BBR congestion control
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

## Increase kernel max Key limit
cat <<EOF > /etc/sysctl.d/60-maxkeys.conf
# eXtremeSHOK.com
# Increase kernel max Key limit
kernel.keys.root_maxkeys=1000000
kernel.keys.maxkeys=1000000
EOF

## Set systemd ulimits
echo "DefaultLimitNOFILE=256000" >> /etc/systemd/system.conf
echo "DefaultLimitNOFILE=256000" >> /etc/systemd/user.conf
echo 'session required pam_limits.so' | tee -a /etc/pam.d/common-session-noninteractive
echo 'session required pam_limits.so' | tee -a /etc/pam.d/common-session
echo 'session required pam_limits.so' | tee -a /etc/pam.d/runuser-l

## Set ulimit for the shell user
cd ~ && echo "ulimit -n 256000" >> .bashrc ; echo "ulimit -n 256000" >> .profile

# propagate the setting into the kernel
update-initramfs -u -k all

## Script Finish
echo -e '\033[1;33m Finished....please restart the system \033[0m'