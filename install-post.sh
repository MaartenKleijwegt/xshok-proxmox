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

# Set the local
export LANG="en_US.UTF-8"
export LC_ALL="C"

## Force APT to use IPv4
echo -e "Acquire::ForceIPv4 \"true\";\\n" > /etc/apt/apt.conf.d/99force-ipv4

## disable enterprise proxmox repo
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
  echo -e "#deb https://enterprise.proxmox.com/debian stretch pve-enterprise\\n" > /etc/apt/sources.list.d/pve-enterprise.list
fi
## enable public proxmox repo
if [ ! -f /etc/apt/sources.list.d/proxmox.list ] && [ ! -f /etc/apt/sources.list.d/pve-public-repo.list ] && [ ! -f /etc/apt/sources.list.d/pve-install-repo.list ] ; then
  echo -e "deb http://download.proxmox.com/debian stretch pve-no-subscription\\n" > /etc/apt/sources.list.d/pve-public-repo.list
fi

## Add non-free to sources
sed -i "s/main contrib/main non-free contrib/g" /etc/apt/sources.list

## Add the latest ceph provided by proxmox
echo "deb http://download.proxmox.com/debian/ceph-luminous stretch main" > /etc/apt/sources.list.d/ceph.list

## Refresh the package lists
apt-get update > /dev/null

## Remove conflicting utilities
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' purge ntp openntpd chrony ksm-control-daemon

## Fix no public key error for debian repo
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install debian-archive-keyring

## Update proxmox and install various system utils
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' dist-upgrade
pveam update

## Fix no public key error for debian repo
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install debian-archive-keyring

## Install zfs-auto-snapshot
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install zfs-auto-snapshot
# make 5min snapshots , keep 12 5min snapshots
if [ -f "/etc/cron.d/zfs-auto-snapshot" ] ; then
  sed -i 's|--keep=[0-9]*|--keep=12|g' /etc/cron.d/zfs-auto-snapshot
  sed -i 's|*/[0-9]*|*/5|g' /etc/cron.d/zfs-auto-snapshot
fi
# keep 24 hourly snapshots
if [ -f "/etc/cron.hourly/zfs-auto-snapshot" ] ; then
  sed -i 's|--keep=[0-9]*|--keep=24|g' /etc/cron.hourly/zfs-auto-snapshot
fi
# keep 7 daily snapshots
if [ -f "/etc/cron.daily/zfs-auto-snapshot" ] ; then
  sed -i 's|--keep=[0-9]*|--keep=7|g' /etc/cron.daily/zfs-auto-snapshot
fi
# keep 4 weekly snapshots
if [ -f "/etc/cron.weekly/zfs-auto-snapshot" ] ; then
  sed -i 's|--keep=[0-9]*|--keep=4|g' /etc/cron.weekly/zfs-auto-snapshot
fi
# keep 3 monthly snapshots
if [ -f "/etc/cron.monthly/zfs-auto-snapshot" ] ; then
  sed -i 's|--keep=[0-9]*|--keep=3|g' /etc/cron.monthly/zfs-auto-snapshot
fi

## Install missing ksmtuned
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install ksmtuned
systemctl enable ksmtuned
systemctl enable ksm

## Install ceph support
echo "Y" | pveceph install

## Install common system utilities
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install whois omping tmux sshpass wget axel nano pigz net-tools htop iptraf iotop iftop iperf vim vim-nox unzip zip software-properties-common aptitude curl dos2unix dialog mlocate build-essential git ipset
#snmpd snmp-mibs-downloader

## Install kexec, allows for quick reboots into the latest updated kernel set as primary in the boot-loader.
# use command 'reboot-quick'
echo "kexec-tools kexec-tools/load_kexec boolean false" | debconf-set-selections
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install kexec-tools

cat <<'EOF' > /etc/systemd/system/kexec-pve.service
[Unit]
Description=boot into into the latest pve kernel set as primary in the boot-loader
Documentation=man:kexec(8)
DefaultDependencies=no
Before=shutdown.target umount.target final.target

[Service]
Type=oneshot
ExecStart=/sbin/kexec -l /boot/pve/vmlinuz --initrd=/boot/pve/initrd.img --reuse-cmdline

[Install]
WantedBy=kexec.target
EOF
systemctl enable kexec-pve.service
echo "alias reboot-quick='systemctl kexec'" >> /root/.bash_profile

## Remove no longer required packages and purge old cached updates
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' autoremove
/usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' autoclean

## Set Timezone to UTC and enable NTP
timedatectl set-timezone UTC
cat <<EOF > /etc/systemd/timesyncd.conf
[Time]
NTP=0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org
FallbackNTP=0.debian.pool.ntp.org 1.debian.pool.ntp.org 2.debian.pool.ntp.org 3.debian.pool.ntp.org
RootDistanceMaxSec=5
PollIntervalMinSec=32
PollIntervalMaxSec=2048
EOF
service systemd-timesyncd start
timedatectl set-ntp true

## Set pigz to replace gzip, 2x faster gzip compression
cat  <<EOF > /bin/pigzwrapper
#!/bin/sh
PATH=/bin:\$PATH
GZIP="-1"
exec /usr/bin/pigz "\$@"
EOF
mv -f /bin/gzip /bin/gzip.original
cp -f /bin/pigzwrapper /bin/gzip
chmod +x /bin/pigzwrapper
chmod +x /bin/gzip

## Increase vzdump backup speed, enable pigz and fix ionice
sed -i "s/#bwlimit:.*/bwlimit: 0/" /etc/vzdump.conf
sed -i "s/#pigz:.*/pigz: 1/" /etc/vzdump.conf
sed -i "s/#ionice:.*/ionice: 5/" /etc/vzdump.conf

## Remove subscription banner
if [ -f "/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js" ] ; then
  sed -i "s/data.status !== 'Active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
  # create a daily cron to make sure the banner does not re-appear
  cat <<'EOF' > /etc/cron.daily/proxmox-nosub
#!/bin/sh
# eXtremeSHOK.com Remove subscription banner
sed -i "s/data.status !== 'Active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
EOF
  chmod 755 /etc/cron.daily/proxmox-nosub
fi

## Optimise ZFS arc size
if [ "$(command -v zfs)" != "" ] ; then
  RAM_SIZE_GB=$(( $(vmstat -s | grep -i "total memory" | xargs | cut -d" " -f 1) / 1024 / 1000))
  if [[ RAM_SIZE_GB -lt 16 ]] ; then
    # 1GB/1GB
    MY_ZFS_ARC_MIN=1073741824
    MY_ZFS_ARC_MAX=1073741824
  else
    MY_ZFS_ARC_MIN=$((RAM_SIZE_GB * 1073741824 / 16))
    MY_ZFS_ARC_MAX=$((RAM_SIZE_GB * 1073741824 / 8))
  fi
  # Enforce the minimum, incase of a faulty vmstat
  if [[ MY_ZFS_ARC_MIN -lt 1073741824 ]] ; then
    MY_ZFS_ARC_MIN=1073741824
  fi
  if [[ MY_ZFS_ARC_MAX -lt 1073741824 ]] ; then
    MY_ZFS_ARC_MAX=1073741824
  fi
  cat <<EOF > /etc/modprobe.d/zfs.conf
# eXtremeSHOK.com ZFS tuning

# Use 1/16 RAM for MAX cache, 1/8 RAM for MIN cache, or 1GB
options zfs zfs_arc_min=$MY_ZFS_ARC_MIN
options zfs zfs_arc_max=$MY_ZFS_ARC_MAX

# use the prefetch method
options zfs l2arc_noprefetch=0

# max write speed to l2arc
# tradeoff between write/read and durability of ssd (?)
# default : 8 * 1024 * 1024
# setting here : 500 * 1024 * 1024
options zfs l2arc_write_max=524288000
EOF
fi

# propagate the setting into the kernel
update-initramfs -u -k all

## Script Finish
echo -e '\033[1;33m Finished....please restart the system \033[0m'
