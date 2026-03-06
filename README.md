# Mac Fan Control

A native macOS application built with SwiftUI to monitor system temperatures (CPU/GPU) and control fan speeds.

## Features

- **Real-time Monitoring**: View current CPU core temperatures, GPU cluster temperatures, and airflow sensor data.
- **Fan Speed Control**: Switch between Auto and Custom fan modes to manually adjust the target fan speeds and optimize cooling.
- **SMC Integration**: Communicates directly with the Apple System Management Controller (SMC) to read hardware sensor values and write fan control configurations.

## System Requirements

- **OS**: macOS
- **Hardware**: Compatible with modern Apple Silicon (e.g., M1, M2 series) and Intel Macs with SMC.

## Important Note

**Root Privileges Required for Fan Control**: Reading sensor data is allowed for standard users, but changing fan speeds requires modifying SMC values. Modifying SMC values requires root privileges (`kIOReturnNotPrivileged` error otherwise). To test manual fan control, you must run the application with `sudo` from the terminal.

```bash
sudo ./Build/Products/Debug/Fan\ noise\ control.app/Contents/MacOS/Fan\ noise\ control
```

## Disclaimer

Modifying fan speeds and system thermal management can affect your machine's hardware lifespan. Use this tool at your own risk.
