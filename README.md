# Project 30: TradingOS - Custom Linux Distribution for FPGA Trading

A minimal Linux distribution built with Buildroot, optimized for low-latency FPGA trading systems with NVIDIA GPU acceleration and PCIe passthrough.

## Overview

TradingOS is a custom Linux distribution designed to run the FPGA trading pipeline (Projects 24-29) with minimal overhead. Built using Buildroot's external tree mechanism, it provides:

- Kernel optimized for real-time trading workloads
- Xilinx XDMA driver for FPGA PCIe communication
- NVIDIA proprietary driver and CUDA runtime
- XGBoost library with GPU acceleration
- CPU isolation and real-time scheduling

## Target Hardware

| Component | Specification |
|-----------|---------------|
| CPU | Intel i9-14900KF (24 cores) |
| GPU | NVIDIA RTX 5090 |
| FPGA | Xilinx Artix-7 XC7A200T (AX7203) |
| RAM | 128+ GB DDR5 |
| Storage | NVMe SSD |
| Network | Intel I226-V 2.5GbE |

## Key Features

- **Real-time Kernel:** Preemptible kernel with 1000 Hz tick rate
- **CPU Isolation:** Cores 14-23 isolated from scheduler for trading workloads
- **PCIe DMA:** XDMA driver for FPGA communication (Projects 23-24)
- **GPU Acceleration:** NVIDIA CUDA and XGBoost for ML inference (Project 25)
- **Minimal Overhead:** Disabled wireless, Bluetooth, sound, virtualization
- **Systemd Services:** Automated startup of trading system orchestrator (Project 28)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    TradingOS (Buildroot)                     │
├─────────────────────────────────────────────────────────────┤
│  Linux Kernel (6.x)                                          │
│  - CPU isolation (isolcpus=14-23)                           │
│  - Real-time scheduling (PREEMPT)                            │
│  - PCIe/DMA support                                          │
│  - Intel I226-V network driver                               │
└──────────────────┬──────────────────────────────────────────┘
                    │
┌───────────────────┴─────────────────────────────────────────┐
│  Userspace                                                     │
│  ├── XDMA Driver (/dev/xdma0_*)                              │
│  ├── NVIDIA Driver (nvidia.ko, libcuda.so)                    │
│  ├── CUDA Runtime (/opt/cuda/)                               │
│  ├── XGBoost GPU (/opt/xgboost/)                             │
│  └── Trading System (Projects 24-29)                         │
│      ├── Project 24: Order Gateway (PCIe → Disruptor)         │
│      ├── Project 25: Market Maker (XGBoost + Strategy)       │
│      ├── Project 26: Order Execution (Matching Engine)        │
│      ├── Project 28: System Orchestrator                     │
│      └── Project 29: Control Panel (SDL2 DRM/KMS)            │
└───────────────────────────────────────────────────────────────┘
```

## Boot Configuration

Kernel command line parameters:
```
isolcpus=14-23 nohz_full=14-23 rcu_nocbs=14-23
intel_pstate=performance
mitigations=off
transparent_hugepage=never
```

## Custom Packages

- **XDMA Driver:** Xilinx DMA driver for PCIe-based FPGA communication
- **NVIDIA Driver:** Proprietary driver with CUDA support
- **CUDA Toolkit:** CUDA runtime libraries for GPU computation
- **XGBoost:** XGBoost library with CUDA acceleration (RTX 5090 optimized)

## Building TradingOS

### Prerequisites

- Linux host with Buildroot 2024.02+
- 50+ GB disk space
- 8+ GB RAM

### Build Commands

```bash
# Clone Buildroot
git clone https://github.com/buildroot/buildroot.git /work/tos/buildroot
cd /work/tos/buildroot

# Configure with external tree
BR2_EXTERNAL=/work/tos/trading-linux/buildroot-external make menuconfig

# Build
make -j$(nproc)
```

### Output

Build produces:
- `output/images/bzImage` - Linux kernel
- `output/images/rootfs.ext4` - Root filesystem
- `output/images/grub-iso.img` - Bootable ISO

## Deployment

See [docs/TRADINGOS.md](TRADINGOS.md) for detailed deployment instructions, including:
- NVMe installation procedure
- GRUB EFI configuration
- Systemd service setup
- Performance tuning
- Troubleshooting guide

## Status

**Project Status:** Complete - Custom Linux distribution built and validated for FPGA trading system deployment.

**Integration:** TradingOS runs Projects 24-29 (Order Gateway, Market Maker, Order Execution, System Orchestrator, Control Panel) with optimized kernel and drivers for low-latency trading workloads.

---

**Detailed Documentation:** See [docs/TRADINGOS.md](TRADINGOS.md) for complete technical specifications, kernel configuration, package details, and deployment procedures.

