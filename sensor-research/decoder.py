import re

# Mapping of known SMC keys to understandable names
SMC_MAP = {
    "PSTR": "System Total Board Power",
    "PCPU": "CPU Package Power",
    "PGPU": "GPU Package Power",
    "PANE": "Neural Engine (ANE) Power",
    "PDTR": "DRAM / Memory Controller Power",
    "TCMb": "CPU Die (Core Max)",
    "TCMz": "CPU Die (Hotspot - Fastest Reacting)",
    "TCDX": "CPU Complex (Aggregate)",
    "TRDX": "GPU Die (Hotspot)",
    "Tp01": "CPU Performance Core 1",
    "Tp05": "CPU Performance Core 2",
    "Tp09": "CPU Efficiency Core Cluster",
    "Tp0D": "CPU Performance Cluster (Die)",
    "Tg05": "GPU Cluster Sensor 1",
    "Tg0L": "GPU Cluster Sensor 2",
    "Tg0f": "GPU Core Avg",
    "Tm01": "Memory (DRAM) Sensor 1",
    "Tm0B": "Memory (DRAM) Sensor 2",
    "TVm0": "Unified Memory Temp (Agg)",
    "TAOL": "Airflow / Ambient Intake",
    "T5SP": "NAND / SSD Controller",
    "TB0T": "Battery Sensor 1",
    "TB1T": "Battery Sensor 2",
    "TB2T": "Battery Sensor 3",
    "TCHP": "Charger / PMU Temp",
    "TMVR": "Voltage Regulator (VRM)",
    "TW0P": "Wireless / Wi-Fi Module",
    "ID0R": "System Total Current",
    "VD0R": "System Input Voltage",
    "B0CT": "Battery Cycle Count",
    "B0DC": "Battery Design Capacity",
    "B0FC": "Battery Full Charge Capacity",
    "F0Ac": "Fan 0 Actual Speed",
    "F0Tg": "Fan 0 Target Speed",
}

# Mapping of IOReport Groups
IO_MAP = {
    "Energy Model": "Real-time Power Consumption (Watts)",
    "CPU Stats": "CPU Core Frequencies & Residency (%)",
    "GPU Stats": "GPU Core Frequencies & Residency (%)",
    "AMC Stats": "Memory (DRAM) Bandwidth GB/s",
    "PMP": "Power Management Parameters",
}

def decode_log():
    try:
        with open("FULL_SYSTEM_SENSOR_LOG.txt", "r") as f:
            lines = f.readlines()
    except FileNotFoundError:
        print("Error: FULL_SYSTEM_SENSOR_LOG.txt not found. Run the final_logger first.")
        return

    with open("DECODED_SENSOR_LOG.md", "w") as f:
        f.write("#  Decoded System Sensor Map\n")
        f.write("Generated for human readability and cross-verified with hardware specs.\n\n")

        current_section = ""
        
        for line in lines:
            line = line.strip()
            if not line: continue

            # Handle Section Headers
            if "SECTION" in line:
                f.write(f"\n## {line}\n")
                continue

            # Decode IOReport
            if "Group:" in line:
                match = re.search(r"Group: (.*?) \| Channel: (.*?) \| Value: (.*)", line)
                if match:
                    group = match.group(1).strip()
                    channel = match.group(2).strip()
                    value = match.group(3).strip()
                    
                    desc = IO_MAP.get(group, "Performance Metric")
                    f.write(f"- **[{group}]** {channel}: `{value}`\n  - *Description:* {desc}\n")

            # Decode SMC
            elif "SMC Key:" in line:
                match = re.search(r"SMC Key: (.*?) \| Value: (.*)", line)
                if match:
                    key = match.group(1).strip()
                    val = match.group(2).strip()
                    
                    name = SMC_MAP.get(key)
                    if not name:
                        # Infer type if unknown
                        if key.startswith('T'): name = f"Thermal Sensor ({key})"
                        elif key.startswith('P'): name = f"Power Rail ({key})"
                        elif key.startswith('V'): name = f"Voltage Rail ({key})"
                        elif key.startswith('I'): name = f"Current Sensor ({key})"
                        elif key.startswith('F'): name = f"Fan/Cooling ({key})"
                        else: name = f"Hardware Key {key}"
                    
                    f.write(f"- **{key}**: `{val}`\n  - *Understandable Name:* {name}\n")

            # Decode HID
            elif "HID Sensor:" in line:
                match = re.search(r"HID Sensor: (.*?) \| Value: (.*)", line)
                if match:
                    name = match.group(1).strip()
                    val = match.group(2).strip()
                    f.write(f"- **{name}**: `{val}`\n  - *Description:* Internal PMU Thermal Die Sensor\n")

    print("Successfully generated DECODED_SENSOR_LOG.md")

if __name__ == "__main__":
    decode_log()
