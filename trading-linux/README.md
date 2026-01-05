# Trading Linux Buildroot External Tree

This is the Buildroot external tree for the FPGA Trading System, as specified in the `MINIMAL_LINUX_BUILD_PLAN.md`.

## Structure

```
buildroot-external/
├── Config.in                 # Main external tree config
├── external.mk              # External tree makefile
├── external.desc           # External tree description
├── busybox.config          # Custom busybox configuration
├── configs/
│   └── trading_defconfig   # Buildroot defconfig (optional)
├── kernel-fragments/
│   └── trading.config       # Linux kernel config fragment
├── package/
│   ├── Config.in           # Package menu
│   ├── xgboost/            # XGBoost package (CUDA-enabled)
│   └── xdma/               # Xilinx XDMA driver package
└── board/
    └── trading/            # Board-specific files
        ├── post-build.sh   # Post-build script
        ├── overlay/       # Root filesystem overlay
        └── grub.cfg       # GRUB configuration
```

## Usage

Build with the external tree:

```bash
cd /work/tos/buildroot
BR2_EXTERNAL=/work/tos/trading-linux/buildroot-external make
```

Or use the provided `run.sh` script:

```bash
cd /work/tos/buildroot
./run.sh
```

## Configuration

- **Busybox**: Custom config at `busybox.config`
- **Kernel**: Config fragment at `kernel-fragments/trading.config`
- **Packages**: XGBoost (CUDA) and XDMA driver

## Next Steps

1. Customize `busybox.config` as needed
2. Adjust `kernel-fragments/trading.config` for your hardware
3. Complete XGBoost and XDMA package implementations
4. Add board-specific overlay files
5. Create `trading_defconfig` if needed

