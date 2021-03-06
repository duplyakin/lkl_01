#!/bin/bash

set -e

script_dir=$(cd $(dirname ${BASH_SOURCE:-$0}); pwd)
hijack_script=${script_dir}/../bin/lkl-hijack.sh

if [[ ! -e ${script_dir}/../liblkl-hijack.so ]]; then
    echo "WARNING: tests can't be run. Quitting early."
    exit 0;
fi

# Make a temporary directory to run tests in, since we'll be copying
# things there.
work_dir=$(mktemp -d)

# And make sure we clean up when we're done
function clear_work_dir {
    test -f ${VDESWITCH}.pid && kill $(cat ${VDESWITCH}.pid)
    rm -rf ${work_dir}
    sudo ip link set dev lkl_ptt0 down &> /dev/null || true
    sudo ip tuntap del dev lkl_ptt0 mode tap &> /dev/null || true
}

trap clear_work_dir EXIT

echo "Running tests in ${work_dir}"

echo "== ip addr test=="
${hijack_script} ip addr

echo "== ip route test=="
${hijack_script} ip route

echo "== ping test=="
cp `which ping` .
${hijack_script} ./ping 127.0.0.1 -c 1
rm ./ping

echo "== ping6 test=="
cp `which ping6` .
${hijack_script} ./ping6 ::1 -c 1
rm ./ping6

echo "== Mount/dump tests =="
# Need to say || true because ip -h returns < 0
ans=$(LKL_HIJACK_MOUNT=proc,sysfs\
  LKL_HIJACK_DUMP=/sysfs/class/net/lo/mtu,/sysfs/class/net/lo/dev_id\
  LKL_HIJACK_DEBUG=1\
  ${hijack_script} ip -h) || true
# Need to grab the end because something earlier on prints out this
# number
echo "$ans" | tail -n 15 | grep "65536" # lo's MTU
# lo's dev id
echo "$ans" | grep "0x0"        # lo's dev_id
# Doesn't really belong in this section, but might as well check for
# it here.
! echo "$ans" | grep "WARN: failed to free"

echo "== TAP tests =="
if [ ! -c /dev/net/tun ]; then
    echo "WARNING: missing /dev/net/tun, skipping TAP and VDE tests."
    exit 0
fi

export LKL_HIJACK_NET_IFTYPE=tap
export LKL_HIJACK_NET_IFPARAMS=lkl_ptt0
export LKL_HIJACK_NET_IP=192.168.13.2
export LKL_HIJACK_NET_NETMASK_LEN=24

# Set up the TAP device we'd like to use
sudo ip tuntap del dev lkl_ptt0 mode tap || true
sudo ip tuntap add dev lkl_ptt0 mode tap user $USER
sudo ip link set dev lkl_ptt0 up
sudo ip addr add dev lkl_ptt0 192.168.13.1/24

# Make sure our device has the addresses we expect
addr=$(LKL_HIJACK_DEBUG=1\
  LKL_HIJACK_NET_MAC="aa:bb:cc:dd:ee:ff" ${hijack_script} ip addr) 
echo "$addr" | grep eth0
echo "$addr" | grep 192.168.13.2
echo "$addr" | grep "aa:bb:cc:dd:ee:ff"
! echo "$addr" | grep "WARN: failed to free"

# Copy ping so we're allowed to run it under LKL
cp `which ping` .

# Make sure we can ping the host from inside LKL
${hijack_script} ./ping 192.168.13.1 -c 1
rm ./ping

# Now let's check that the host can see LKL.
sudo arp -d 192.168.13.2
sudo ping -i 0.01 -c 65 192.168.13.2 &
${hijack_script} sleep 3

sh ${script_dir}/run_netperf.sh 192.168.13.1 1 0 TCP_STREAM
sh ${script_dir}/run_netperf.sh 192.168.13.1 1 0 TCP_RR

echo "== VDE tests =="
if [ ! -x "$(which vde_switch)" ]; then
    echo "WARNING: Cannot find a vde_switch executable, skipping VDE tests."
    exit 0
fi
VDESWITCH=${work_dir}/vde_switch

export LKL_HIJACK_NET_IFTYPE=vde
export LKL_HIJACK_NET_IFPARAMS=${VDESWITCH}
export LKL_HIJACK_NET_IP=192.168.13.2
export LKL_HIJACK_NET_NETMASK_LEN=24

sudo ip link set dev lkl_ptt0 down &> /dev/null || true
sudo ip link del dev lkl_ptt0 &> /dev/null || true
sudo ip tuntap add dev lkl_ptt0 mode tap user $USER
sudo ip link set dev lkl_ptt0 up
sudo ip addr add dev lkl_ptt0 192.168.13.1/24

sleep 2
vde_switch -d -t lkl_ptt0 -s ${VDESWITCH} -p ${VDESWITCH}.pid

# Make sure our device has the addresses we expect
addr=$(LKL_HIJACK_NET_MAC="aa:bb:cc:dd:ee:ff" ${hijack_script} ip addr) 
echo "$addr" | grep eth0
echo "$addr" | grep 192.168.13.2
echo "$addr" | grep "aa:bb:cc:dd:ee:ff"

# Copy ping so we're allowed to run it under LKL
cp $(which ping) .

# Make sure we can ping the host from inside LKL
${hijack_script} ./ping 192.168.13.1 -c 1
rm ./ping

# Now let's check that the host can see LKL.
sudo arp -d 192.168.13.2
sudo ping -i 0.01 -c 65 192.168.13.2 &
${hijack_script} sleep 3
