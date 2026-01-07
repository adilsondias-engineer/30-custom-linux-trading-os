# Check current hugepages
grep Huge /proc/meminfo

# Allocate 4 x 1GB hugepages (persistent across reboots)
echo 'vm.nr_hugepages=4' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Or allocate temporarily (lost on reboot)
echo 4 | sudo tee /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages

# Mount hugepages if not already mounted
sudo mkdir -p /dev/hugepages
sudo mount -t hugetlbfs nodev /dev/hugepages

# Check if IOMMU is enabled
dmesg | grep -i iommu

# If not enabled, add to /etc/default/grub:
GRUB_CMDLINE_LINUX="intel_iommu=on iommu=pt"

# Then update and reboot
sudo update-grub
sudo reboot

# Check current interface status
sudo dpdk-devbind.py --status

# Find your interface PCI address (e.g., eno2 = 0000:07:00.0)
lspci | grep -i ethernet

# Load VFIO driver
sudo modprobe vfio-pci

# Unbind from kernel driver and bind to VFIO
sudo dpdk-devbind.py --bind=vfio-pci 0000:07:00.0

# Verify binding
sudo dpdk-devbind.py --status | grep vfio


# Option A: Set capabilities
sudo setcap cap_net_raw,cap_net_admin,cap_sys_nice,cap_ipc_lock=eip ./order_gateway

# Option B: Run as root
sudo ./order_gateway ../config.json

