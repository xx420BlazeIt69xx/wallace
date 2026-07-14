#!/bin/sh
# Report the J614s GL9755 endpoint without binding its driver or touching media.
set -eu

dev=/sys/bus/pci/devices/0000:02:00.0

if [ ! -d "$dev" ]; then
	echo "FAIL: GL9755 PCI function 0000:02:00.0 is absent"
	exit 1
fi

vendor=$(cat "$dev/vendor")
device=$(cat "$dev/device")
class=$(cat "$dev/class")

if [ "$vendor" != "0x17a0" ] || [ "$device" != "0x9755" ]; then
	echo "FAIL: expected 17a0:9755, found ${vendor#0x}:${device#0x}"
	exit 1
fi

case "$class" in
	0x0805*) ;;
	*)
		echo "FAIL: expected SD-host class 0x0805xx, found $class"
		exit 1
		;;
esac

if [ -L "$dev/driver" ]; then
	echo "FAIL: endpoint driver is already bound; this is not the unbound test"
	ls -l "$dev/driver"
	exit 1
fi

if [ ! -L "$dev/iommu_group" ]; then
	echo "FAIL: endpoint has no IOMMU group; check port-1 DART mapping"
	exit 1
fi

echo "PASS: GL9755 present and unbound: ${vendor#0x}:${device#0x} class $class"
ls -l "$dev/iommu_group"

if [ -r "$dev/current_link_speed" ]; then
	echo "current link speed: $(cat "$dev/current_link_speed")"
fi
if [ -r "$dev/current_link_width" ]; then
	echo "current link width: $(cat "$dev/current_link_width")"
fi
