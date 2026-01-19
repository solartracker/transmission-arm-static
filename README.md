# transmission-arm-static

This repository contains build scripts for compiling **Transmission** as a **fully statically linked executable** for ARMv7 Linux devices.

Two build methods are provided. Both produce functionally identical Transmission binaries, but use different toolchains and build environments.

---

## What is Transmission?

**Transmission** is a lightweight, open-source BitTorrent client for Linux and other platforms. It supports:

- Fast, low-overhead downloads and uploads  
- Simple configuration and control via CLI, Web UI, or RPC  
- Minimal system requirements, ideal for ARM devices and embedded platforms  
- Fully static builds for deployment on systems without package managers or shared libraries  

Static builds simplify deployment on embedded ARM devices by bundling all runtime dependencies into a single binary.

---

## Build Methods

### 1. Tomatoware-Based Static Build

- Build script: `transmission-arm-tomatoware.sh`  
- Uses the Tomatoware cross-compilation environment  
- Produces a fully statically-linked Transmission binary  
- Intended for Tomato/Tomatoware-based systems or users already invested in that ecosystem  

The resulting binary runs on ARMv7 Linux devices without requiring any shared libraries.

---

### 2. arm-linux-musleabi (musl) Static Build

- Build script: `transmission-arm-musl.sh`  
- Uses a standalone `arm-linux-musleabi` cross-compiler based on musl libc  
- Produces a fully statically-linked Transmission binary  
- Suitable for generic ARM Linux systems and embedded devices  

In practice, binaries produced with the musl-based toolchain are typically **smaller and more efficient**, particularly on **older or resource-constrained ARM hardware**. This is primarily due to musl’s smaller runtime footprint and cleaner static linking behavior.

Both build methods produce equivalent Transmission functionality; the difference lies in toolchain dependency and output characteristics.

---

## What is Tomatoware?

Tomatoware is a modern, self-contained ARM cross-compilation toolchain. It allows you to compile up-to-date open-source software for older ARM systems that were previously limited to outdated toolchains.

Tomatoware provides compilers, libraries, and utilities in a single, isolated environment, ensuring reproducible builds without modifying or interfering with host system libraries.

---

## Setup Instructions

1. **Clone this repository**

   ```bash
   git clone https://github.com/solartracker/transmission-arm-static
   cd transmission-arm-static
   ```

2. **Run the build script of your choice**

   - **Tomatoware build**:

     ```bash
     ./transmission-arm-tomatoware.sh
     ```

   - **Musl build**:

     ```bash
     ./transmission-arm-musl.sh
     ```

Both scripts build **Transmission daemon (`transmission-daemon`)** and associated CLI tools as **statically linked binaries** under `/mmc/sbin`. You can copy the binaries directly to your ARM target device.

---

## Notes on Older ARM Hardware

Older ARM cores (ARM9, ARM11, early Cortex-A) are particularly sensitive to binary size, cache pressure, and memory overhead. For these systems, the **musl-based build** is generally the preferred option.

---

## Note on Building Transmission

Compiling Transmission and its dependencies (e.g., OpenSSL, libevent, c-ares) on ARM devices can generate significant heat, especially when using all CPU cores.

On Raspberry Pi systems, an aluminum case combined with **properly sized copper shims and thermal paste** provides effective passive cooling and prevents thermal throttling during long builds. Copper shims are particularly important because they create a low-resistance thermal path between the SoC and the case:

- Much higher thermal conductivity than thermal tape (~400 W/m·K vs. ~0.5–1 W/m·K)  
- Consistent physical contact that eliminates insulating air gaps  
- No long-term compression or degradation  

For slower, cooler builds, you can also limit parallelism by adjusting the `MAKE` line in the build script to use a single core.

---
