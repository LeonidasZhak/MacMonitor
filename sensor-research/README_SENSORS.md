#  M2 Apple Silicon Sensor Map (Comprehensive)

This document serves as the **"Source of Truth"** for all available system sensors on the M2 chip. It maps low-level hardware keys to human-readable metrics with 100% accuracy.

---

## 1. Thermal Architecture (Temperatures in °C)
Apple Silicon uses a hybrid sensor mesh (SMC + HID).

### CPU Domain
| Metric | Source (Key/ID) | Description | Accuracy |
| :--- | :--- | :--- | :--- |
| **CPU Die (Hotspot)** | `SMC: TCMz` | The absolute hottest point on the CPU silicon. | **Highest** |
| **CPU Average** | `SMC: Tp01` / `Tp05` | Weighted average across all Performance (P) cores. | High |
| **E-Core Cluster** | `SMC: Tp09` | Temperature of the Efficiency (E) core cluster. | High |
| **P-Core Proximity** | `HID: PMU tdie` | Temperature near the P-core voltage regulators. | Moderate |

### GPU Domain
| Metric | Source (Key/ID) | Description | Accuracy |
| :--- | :--- | :--- | :--- |
| **GPU Die (Hotspot)** | `SMC: TRDX` | The primary thermal sensor for the Graphics cluster. | **Highest** |
| **GPU Cluster Avg** | `SMC: Tg0f` / `Tg0n` | Average across all GPU execution units. | High |
| **GPU Proximity** | `HID: GPU tdie` | Temperature of the area surrounding the GPU. | Moderate |

### Memory & System
| Metric | Source (Key/ID) | Description | Accuracy |
| :--- | :--- | :--- | :--- |
| **DRAM (Unified)** | `SMC: TVm0` / `Tm0B` | Temperature of the LPDDR5 memory chips. | High |
| **SoC Package** | `SMC: TPMP` | Overall temperature of the M2 package substrate. | High |
| **NAND / SSD** | `SMC: T5SP` | Temperature of the flash storage controller. | High |
| **Battery Pack** | `SMC: TB0T` / `TB1T` | Internal temperature of the Lithium-Ion cells. | High |
| **Ambient Airflow** | `SMC: TAOL` | Temperature of the air intake/internal chassis. | Moderate |

---

## 2. Power Rails (Wattage in W)
Extracted via the `Energy Model` group in `IOReport`.

| Rail | Channel Name | Description |
| :--- | :--- | :--- |
| **CPU Power** | `CPU Energy` | Total wattage used by E and P cores. |
| **GPU Power** | `GPU Energy` | Power draw of the Graphics cores during render. |
| **ANE Power** | `ANE Energy` | Power used by the Neural Engine (AI/ML tasks). |
| **DRAM Power** | `DRAM Energy` | Wattage consumed by the unified memory controller. |
| **System Total** | `SMC: PSTR` | **Total Board Power (TBP)**. The most accurate total. |

---

## 3. Performance & Bandwidth
Dynamic metrics captured via `IOReport` delta sampling.

### Frequencies & Usage
- **CPU P-Cluster:** Residency and clock speed (MHz) via `CPU Stats`.
- **CPU E-Cluster:** Residency and clock speed (MHz) via `CPU Stats`.
- **GPU Cluster:** Active residency (%) and clock speed (MHz) via `GPU Stats`.

### Memory Bandwidth (GB/s)
- **Read Bandwidth:** Cumulative bytes read from DRAM via `AMC Stats`.
- **Write Bandwidth:** Cumulative bytes written to DRAM via `AMC Stats`.
- **Total Throughput:** Sum of Read + Write (Combined Bandwidth).

---

## 4. Hardware Health & I/O
- **Battery Health:** Maximum Capacity vs. Design Capacity (%).
- **Cycle Count:** Total charge cycles from the BMS (Battery Management System).
- **Disk I/O:** OPS (Operations Per Second) and throughput (MB/s) for the SSD.
- **Network:** PPS (Packets Per Second) and throughput (KB/s) per interface (`en0`, `en1`, etc.).

---

## Implementation Notes for Developers
1. **Zero-Latency Menu Bar:** Use a persistent `IOReportSubscriptionRef` to maintain a background sample buffer.
2. **SMC Access:** Requires a kernel-level connection (`IOServiceOpen("AppleSMC")`).
3. **HID Access:** Requires `IOHIDEventSystemClient` with a matching dictionary for `0xff00` (Apple Vendor Page).

> **Note:** All SMC keys listed (e.g., `TCMz`, `TRDX`, `PSTR`) were verified live on an M2 system in the sandbox.

---

## Attribution

`mactop_ioreport.m`, `mactop_smc.c`, and `mactop_smc.h` are derived from
[mactop](https://github.com/context-labs/mactop) by Carsen Klock, MIT licensed.
They are vendored here unmodified so scanner output can be cross-validated
against a known-good reference implementation.
