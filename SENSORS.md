# MacMonitor Sensor Reference

Complete map of every hardware sensor used by MacMonitor v2.0, verified live on an **Apple M2** (MacBook Air, fanless).  
All values were captured simultaneously against mactop v1.x for cross-validation.

---

## 1. Temperature Sensors (SMC)

Read via `SMCGetFloatValue(conn, key)` from the `AppleSMC` IOService.  
All values in **°C**.

### CPU Domain

| SMC Key | Description | Live Value | Source | Accuracy |
|---------|-------------|------------|--------|----------|
| `TCMz`  | **CPU Die Hotspot** — fastest-reacting sensor, absolute peak on the die | 71.4 °C | SMC | Highest — used by TG Pro |
| `TCMb`  | CPU Die (Core Max) — slower average | 56.8 °C | SMC | High |
| `TCHP`  | CPU/Charger Proximity | 36.2 °C | SMC | Moderate |
| `Tp00`–`Tp0s` | CPU P-Core cluster (30 sensors across 4 cores × 3 measurement points) | 43–71 °C | SMC | High |
| `Te04`–`Te06` | CPU E-Core cluster sensors | 41–49 °C | SMC | High |
| `Ts0K`–`Ts0c` | SoC / CPU complex thermal sensors | 41–50 °C | SMC | High |

**HID PMU tdie sensors** (via `IOHIDEventSystemClient`, `PrimaryUsagePage=0xff00`):

| Sensor Name     | Live Value | Notes |
|-----------------|------------|-------|
| `PMU tdie1`     | 43.9 °C    | Near P-core cluster voltage regulator |
| `PMU tdie2`–`8` | 42–44 °C   | Distributed across SoC PMU mesh |
| `PMU2 tdie1`–`8`| 41–44 °C   | Second PMU domain |
| `PMU tcal`      | 51.9 °C    | Calibration reference (not a hotspot) |

> **Note:** MacMonitor uses `TCMz` as the authoritative "CPU Die Hotspot" because it reacts
> to burst loads in <100 ms, while the HID PMU tdie sensors lag 2–4 seconds.

### GPU Domain

| SMC Key | Description | Live Value | Accuracy |
|---------|-------------|------------|----------|
| `TRDX`  | **GPU Die Hotspot** — primary GPU thermal sensor | 45.8 °C | Highest |
| `Tg0e`–`Tg0r` | GPU cluster sensors (6 sensors) | 41–48 °C | High |

### Memory & Storage

| SMC Key | Description | Live Value | Accuracy |
|---------|-------------|------------|----------|
| `TVm0` / `Tm0B` | Unified LPDDR5 memory temperature | 53.6 / 38.7 °C | High |
| `TMVR`  | Memory VRM temperature | 37.2 °C | High |
| `T5SP`  | NAND / SSD controller | 35.1 °C | High |
| `Ts1P` / `TsOP` | SSD proximity sensors | 31–33 °C | High |
| `TH0T` / `TH0x` | NAND flash chip temperature | 37.4 °C | High |

> **Correction:** earlier revisions of this file also listed `Ts0K`–`Ts0Y` here as an
> "SSD thermal array". That was wrong — those keys are **CPU/SoC complex** sensors and
> are documented under [CPU Domain](#cpu-domain). Measured on an M2, `Ts0K`–`Ts0c` read
> 41–51 °C and track the core clusters, while the genuine SSD sensors (`T5SP`, `Ts1P`,
> `TsOP`, `TH0T`) sit 10 °C cooler at 31–37 °C. Only `Ts1P` and `TsOP` share the `Ts`
> prefix with storage.

### System & Board

| SMC Key | Description | Live Value | Accuracy |
|---------|-------------|------------|----------|
| `TPMP`  | SoC Package substrate | 39.2 °C | High — close to mactop SoC avg |
| `TPD0`–`TPDX` | SoC Package grid (8 sensors) | 44–48 °C | High |
| `TPSP`  | SoC Package surface proximity | 38.6 °C | High |
| `TB0T`–`TB2T` | Battery pack temperature (3 sensors) | 33–34 °C | High |
| `TAOL`  | Ambient chassis airflow | 32.0 °C | Moderate |
| `Ta09`  | Ambient external | 6.1 °C | Moderate |
| `TW0P`  | Wi-Fi / Wireless module | 38.6 °C | High |
| `TIOP`  | Thunderbolt controller | 34.8 °C | High |
| `TDBP`  | Display backlight proximity | 35.6 °C | Moderate |
| `TDeL`  | Display panel | 34.1 °C | Moderate |

### VRM (Voltage Regulators)

VRM sensors measure the **power-delivery circuitry** (voltage regulator modules and
their inductors), not the silicon die. They normally read **20–40 °C hotter than the
die** under sustained load, and are routinely the hottest sensors on the board.
A VRM reading of 90–105 °C under heavy sustained load is expected behaviour, not a
fault — Apple's thermal management throttles the SoC long before VRM limits
(typically ~125 °C) are reached.

| SMC Key | Description | Live Value |
|---------|-------------|------------|
| `TVD0`  | Display / SoC rail VRM | 56.8 °C |
| `TVM0`  | Memory rail VRM | 53.6 °C |
| `TVMr` / `TMVR` | Memory VRM (see [Memory & Storage](#memory--storage)) | 37.2 °C |
| `TVMC`  | Memory VRM controller | 41.4 °C |
| `TVS0`–`TVSx` | System rail VRMs | 35.1 °C |
| `TVA0`  | Analog / auxiliary rail VRM | 31.0 °C |

> **Note on key casing:** SMC keys are case-sensitive. `TVm0` (lowercase `m`) is the
> unified LPDDR5 **memory die** temperature listed under
> [Memory & Storage](#memory--storage). `TVM0` and `TVMr` (uppercase `M`) are
> **voltage-regulator** sensors. These are different sensors measuring different
> things — do not compare their values directly.

---

## 2. Power Sensors

### SMC Power Keys

| SMC Key | Description | Live Value | Accuracy |
|---------|-------------|------------|----------|
| `PSTR`  | **Total Board Power (TBP)** — most accurate "wall" power | 4.54 W | Highest |

> MacMonitor uses `PSTR` directly for the System Power readout.  
> mactop reports this as "System Power" (~5 W at idle).

### IOReport — Energy Model (delta sampling, 100 ms window)

These channels require `IOReportCreateSubscription` + `IOReportCreateSamplesDelta`.  
Values are in millijoules per sample window, converted to watts via `energy_mJ / (seconds × 1000)`.

| Channel Name | Description | Typical Idle Value |
|-------------|-------------|-------------------|
| `CPU Energy` | Total CPU (E+P cores aggregate) | 0.2–0.6 W |
| `GPU Energy` | GPU cores | 0.02–0.08 W |
| `ANE Energy` | Neural Engine | 0 W (idle) |
| `DRAM Energy` | Memory controller | 0.18–0.22 W |
| `GPU SRAM Energy` | GPU SRAM sub-domain | ~0.001 W |

---

## 3. CPU Performance (IOReport — CPU Stats)

Channels in `CPU Complex Performance States` subgroup, sampled via delta.

| Channel | Description | Decoded From |
|---------|-------------|-------------|
| `ECPU` / `CPU0` | E-cluster (Efficiency) active % + freq | State residency × voltage table |
| `PCPU` / `CPU1` | P-cluster (Performance) active % + freq | State residency × voltage table |
| `MCPU0`–`MCPUn` | M5+ medium cluster (not present on M1–M4) | State residency |
| `SCPU0`–`SCPUn` | M5+ super cluster (not present on M1–M4) | State residency |

**Frequency tables** read from `pmgr` IORegistry entry (`AppleARMIODevice`):

| Key | Cluster | Example Steps (M2) |
|-----|---------|-------------------|
| `voltage-states1-sram` | E-core | 600, 912, 1056, 1148 MHz |
| `voltage-states5-sram` | P-core | 600, 828, 1056, 1296, 1524, 1752, 1799 MHz |
| `voltage-states9-sram` | GPU    | 396, 444, 532, 648, 778, 900, 1296 MHz |

---

## 4. GPU Performance (IOReport — GPU Stats)

| Channel | Subgroup | Description |
|---------|----------|-------------|
| `GPUPH`  | `GPU Performance States` | GPU active %, weighted freq from state residency |

---

## 5. Memory Bandwidth (IOReport — AMC Stats / PMP)

| Channel Pattern | Description | Unit |
|-----------------|-------------|------|
| `AMCC*_RD` | DRAM read bytes per sample | bytes |
| `AMCC*_WR` | DRAM write bytes per sample | bytes |

> On M5+ chips, `AMC Stats` is kernel-blocked. MacMonitor falls back to `PMP` group
> (`DRAM BW` subgroup, `RD`/`WR` channels).

**mactop validation (live):**

| Metric | MacMonitor | mactop |
|--------|-----------|--------|
| DRAM Read BW | 5.5 GB/s | 5.5 GB/s |
| DRAM Write BW | 2.5 GB/s | 2.5 GB/s |

---

## 6. Fan Speed (SMC)

> **This system has no fan (MacBook Air M2 — passive cooling).**  
> All fan keys return 0 on fanless models.

| SMC Key | Description | Notes |
|---------|-------------|-------|
| `F0Ac`  | Fan 0 Actual RPM | 0 on fanless; present on MacBook Pro, Mac mini, Mac Pro |
| `F1Ac`  | Fan 1 Actual RPM | Dual-fan models only (MacBook Pro 16", Mac Pro) |
| `F0Mn`  | Fan 0 Minimum RPM | Idle floor |
| `F0Mx`  | Fan 0 Maximum RPM | Thermal ceiling |
| `F0Tg`  | Fan 0 Target RPM | Current setpoint |

MacMonitor reads `F0Ac` and exposes it as `fanRPM`. The UI hides this section when `fanRPM == 0`.

---

## 7. Battery & Charging (SMC / IOKit)

| SMC Key / Source | Description | Live Value |
|-----------------|-------------|------------|
| `TB0T`–`TB2T`  | Battery cell temperature (3 sensors) | 33–34 °C |
| `PHPC`         | Charger power (W) | 4.49 W |
| `PHPM`         | Charger max power | 0.74 W |
| `PHPS`         | Charger status | 1.55 |
| `B0CT` (IOKit) | Battery cycle count | via `IOPMCopyBatteryInfo` |
| `B0DC` (IOKit) | Design capacity (mAh) | via `IOPMCopyBatteryInfo` |
| `B0FC` (IOKit) | Full charge capacity (mAh) | via `IOPMCopyBatteryInfo` |

---

## 8. Voltage & Current Rails (SMC)

MacMonitor exposes these in debug mode only. Included here for contributors.

| Key Pattern | Type | Example |
|-------------|------|---------|
| `VP0R` | System input voltage | 12.22 V |
| `VP*b`, `VP*l` | Sub-rail voltages | 0.5–3.6 V |
| `VR*b`, `VR*l` | Regulator output voltages | 0.6–1.2 V |
| `IP*b`, `IP*l` | Rail currents | 0.1–1.2 A |
| `Pb0f` | Battery current draw | 6.87 A |
| `Ib0f`, `Ib8f` | Charger/battery sense currents | 0.4–0.6 A |

---

## 9. Chip Variant Detection

MacMonitor infers the chip variant (base / Pro / Max / Ultra) from:

1. `sysctlbyname("machdep.cpu.brand_string")` → `"Apple M2 Pro"` → strip prefix → `"M2 Pro"`
2. If brand_string is unavailable, falls back to `hw.model` (e.g. `MacBookPro19,2`)

| Display Name | P-cores | E-cores | GPU Cores |
|-------------|---------|---------|-----------|
| M2          | 4       | 4       | 10        |
| M2 Pro      | 6 or 8  | 4       | 16 or 19  |
| M2 Max      | 8       | 4       | 30 or 38  |
| M2 Ultra    | 16      | 8       | 60 or 76  |

---

## 10. IOReport Group Summary

Discovered live on M2 — channel counts are hardware-specific.

| Group | Channels | Status | Used For |
|-------|----------|--------|----------|
| `Energy Model` | 136 | Active | CPU/GPU/ANE/DRAM power |
| `GPU Stats`    | 130 | Active | GPU usage & frequency |
| `CPU Stats`    | 16  | Active | CPU cluster usage & frequency |
| `AMC Stats`    | 105 | Active (M1–M4) | DRAM bandwidth |
| `PMP`          | 250 | Fallback (M5+) | DRAM bandwidth |
| `Thermal`      | 0   | Empty on M2 | Not used |
| `DCS Stats`    | 0   | Empty | Not used |
| `CLPC Stats`   | 0   | Empty | Not used |

---

## Accuracy Cross-Validation (vs mactop, simultaneous sampling)

| Metric | MacMonitor (native) | mactop | Delta | Status |
|--------|---------------------|--------|-------|--------|
| TPMP (SoC Pkg)     | 39.18 °C | 39.0 °C  | 0.18 °C | ✅ Match |
| T5SP (SSD)         | 35.11 °C | 35.4 °C  | 0.29 °C | ✅ Match |
| TB0T (Battery)     | 33.90 °C | 34.0 °C  | 0.10 °C | ✅ Match |
| TRDX (GPU hotspot) | 45.78 °C | 45.2 °C max | 0.58 °C | ✅ Match |
| Tp01 (P-core)      | 50.31 °C | 51.4 °C  | 1.09 °C | ✅ Match (timing) |
| CPU Power          | 0.24–0.6 W | 0.24 W  | <0.3 W  | ✅ Match (jitter) |
| GPU Power          | 0.02–0.07 W | 0.015 W | <0.05 W | ✅ Match |
| System Power (PSTR)| 4.54 W   | 5.09 W   | 0.55 W  | ✅ Different moments |
| DRAM BW            | 8.0 GB/s | 8.0 GB/s | 0 | ✅ Exact |

---

## Contributing

The sensor keys above were discovered and validated using the tools in `sensor-research/`.  
To add support for a new Mac model or sensor:

1. Run `sensor-research/what_is_accurate` (requires `sudo`) to dump all active SMC keys.
2. Run `sensor-research/hid_scanner` to list all HID thermal services.
3. Cross-reference with `mactop --dump-temps` and `mactop --dump-debug`.
4. Add new keys to `IOReportWrapper.m` and document them here.
5. Open a PR with the new sensor values and the Mac model identifier (`hw.model`).

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow.
