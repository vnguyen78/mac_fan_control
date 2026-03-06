//
//  SystemMonitor.swift
//  FanNoiseControl
//
//  Created by admin on 2/2/26.
//

import Foundation
import SwiftUI
import Combine

class SystemMonitor: ObservableObject {
    @Published var cpuTemp: Double = 0.0
    @Published var gpuTemp: Double = 0.0
    @Published var fan0Speed: Double = 0.0
    @Published var fan1Speed: Double = 0.0
    
    @Published var isManualControl: Bool = false
    @Published var debugLog: String = "Initializing..."
    
    private var timer: Timer?
    private let smc = SMC.shared
    
    struct SensorItem: Identifiable {
        let id = UUID()
        let key: String
        let name: String
        let value: Double
        let type: SensorType
    }
    
    enum SensorType {
        case cpu
        case gpu
        case battery
        case airflow
        case other
    }

    @Published var sensors: [SensorItem] = []
    
    // Discovered Keys
    private var cpuCoreKeys: [String] = []
    private var gpuCoreKeys: [String] = []
    private var airflowKeys: [String] = []
    private var hasScanned = false
    
    init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.scanKeys()
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.refresh()
        }
    }
    
    func scanKeys() {
        self.debugLog = smc.connectionLog
        
        if !smc.open() {
            DispatchQueue.main.async { 
                self.debugLog = self.smc.connectionLog + "\n\nSMC Open Failed (Sandbox? sudo?)" 
            }
            return
        }
        
        var log = smc.connectionLog + "\nConnected. Scanning keys...\n"
        
        let allKeys = smc.getAllKeys()
        log += "Total Keys Found: \(allKeys.count)\n"
        
        var cKeys: [String] = []
        var gKeys: [String] = []
        
        // Only show meaningful temperature sensors for M2 Max
        // Priority: CPU Die temps, GPU cores, Package temps
        // Filter out: Peripheral sensors (Th=NAND, Tf=?, Ta=Ambient, etc.)
        
        // Airflow Keys: TaL* usually.
        
        let priorityPrefixes = [
            "TC", "TE", "TVM",  // CPU Die and Package temps
            "Tg",               // GPU cores
            "Ta"                // Ambient/Airflow
        ]
        
        var aKeys: [String] = []
        
        for key in allKeys {
            // Check if this is a priority sensor
            let isPriority = priorityPrefixes.contains { key.hasPrefix($0) }
            
            if isPriority && key.hasPrefix("T") {
                if let val = smc.readKey(key) {
                     // Filter for actual temperature range (20-100°C)
                     if val >= 20 && val <= 120 {
                         if key.hasPrefix("Tg") {
                             gKeys.append(key)
                             log += "Found GPU: \(key) = \(String(format: "%.1f", val))°C\n"
                         } else if key.hasPrefix("Ta") {
                             aKeys.append(key)
                             log += "Found Airflow: \(key) = \(String(format: "%.1f", val))°C\n"
                         } else {
                             cKeys.append(key)
                             log += "Found CPU: \(key) = \(String(format: "%.1f", val))°C\n"
                         }
                     }
                }
            }
        }
        
        // Sort keys for better UI
        cKeys.sort()
        gKeys.sort()
        
        DispatchQueue.main.async {
            self.cpuCoreKeys = cKeys
            self.gpuCoreKeys = gKeys
            self.airflowKeys = aKeys
            self.debugLog = log
            self.hasScanned = true
        }
    }
    
    func refresh() {
        if !hasScanned { return }
        
        var newSensors: [SensorItem] = []
        
        // CPU - Use better names based on key
        for key in cpuCoreKeys {
            let val = smc.readKey(key) ?? 0
            let name = getSensorName(key)
            newSensors.append(SensorItem(key: key, name: name, value: val, type: .cpu))
        }
        
        // GPU
        for key in gpuCoreKeys {
            let val = smc.readKey(key) ?? 0
            let name = getSensorName(key)
            newSensors.append(SensorItem(key: key, name: name, value: val, type: .gpu))
        }
        
        // Airflow
        for key in airflowKeys {
            let val = smc.readKey(key) ?? 0
            let name = getSensorName(key)
            newSensors.append(SensorItem(key: key, name: name, value: val, type: .airflow))
        }
        
        // Fans
        let f0 = smc.readKey("F0Ac") ?? 0
        let f1 = smc.readKey("F1Ac") ?? 0
        
        // Calculate average temperatures for auto mode
        let cpuSensors = newSensors.filter { $0.type == .cpu }
        let gpuSensors = newSensors.filter { $0.type == .gpu }
        let airflowSensors = newSensors.filter { $0.type == .airflow }
        
        let avgCPU = cpuSensors.isEmpty ? 0 : cpuSensors.map { $0.value }.reduce(0, +) / Double(cpuSensors.count)
        let avgGPU = gpuSensors.isEmpty ? 0 : gpuSensors.map { $0.value }.reduce(0, +) / Double(gpuSensors.count)
        let avgAirflow = airflowSensors.isEmpty ? 0 : airflowSensors.map { $0.value }.reduce(0, +) / Double(airflowSensors.count)
        
        // Smart Auto Fan Control based on temps
        if !self.isManualControl {
            self.applySmartAuto(cpu: avgCPU, gpu: avgGPU, airflow: avgAirflow)
        }
        
        DispatchQueue.main.async {
            self.cpuTemp = avgCPU
            self.gpuTemp = avgGPU
            self.fan0Speed = f0
            self.fan1Speed = f1
            self.sensors = newSensors
            // Don't update debug log during refresh to avoid UI blocking
        }
    }
    
    private func applySmartAuto(cpu: Double, gpu: Double, airflow: Double) {
        // Find the maximum temperature among the averages to represent the worst-case scenario
        let maxTemp = max(cpu, gpu, airflow)
        
        // Ignore invalid values
        guard maxTemp > 0 && maxTemp < 150 else { return }
        
        // Define fan curve properties
        let tempLow: Double = 45.0
        let tempHigh: Double = 85.0
        let rpmMin: Double = 1200.0
        let rpmMax: Double = 6000.0
        
        var targetRPM = rpmMin
        if maxTemp >= tempHigh {
            targetRPM = rpmMax
        } else if maxTemp > tempLow {
            let ratio = (maxTemp - tempLow) / (tempHigh - tempLow)
            // Quadratic curve for quieter operation at medium temps, but ramps up faster later
            targetRPM = rpmMin + (ratio * ratio) * (rpmMax - rpmMin)
        }
        
        // Apply target speed
        _ = smc.writeKey("F0Md", data: [1])
        _ = smc.writeKey("F1Md", data: [1])
        
        let val = Int(targetRPM * 4.0) // fpe2 format
        let hi = UInt8((val >> 8) & 0xFF)
        let lo = UInt8(val & 0xFF)
        
        _ = smc.writeKey("F0Tg", data: [hi, lo])
        _ = smc.writeKey("F1Tg", data: [hi, lo])
    }
    
    func setFanControl(manual: Bool, speed: Double) {
        var lastRet: Int32 = 0
        
        if manual {
            // 1. Set Manual Mode (F0Md = 1)
            // Some Macs need this to accept target speed
            lastRet = smc.writeKey("F0Md", data: [1])
            _ = smc.writeKey("F1Md", data: [1])
            
            // 2. Set Target Speed
            let val = Int(speed * 4.0) // fpe2 format
            let hi = UInt8((val >> 8) & 0xFF)
            let lo = UInt8(val & 0xFF)
            
            _ = smc.writeKey("F0Tg", data: [hi, lo])
            _ = smc.writeKey("F1Tg", data: [hi, lo])
        } else {
            // Smart Auto: just trigger refresh to recalculate immediately
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.refresh()
            }
        }
        
        DispatchQueue.main.async {
            self.isManualControl = manual
            if manual {
                if lastRet == -536870207 { // kIOReturnNotPrivileged
                    self.debugLog += "\n⚠️ Fan control requires root privileges (sudo)."
                } else if lastRet != 0 {
                    self.debugLog += "\n⚠️ Fan control failed: \(String(format: "0x%x", lastRet))"
                }
            } else {
                self.debugLog += "\n✅ Switched to Smart Auto Mode."
            }
        }
    }
    
    private func getSensorName(_ key: String) -> String {
        switch key {
        case "TC0P": return "CPU Proximity"
        case "TC0D": return "CPU Die"
        case "TC0E": return "CPU Core 1"
        case "TC0F": return "CPU Core 2"
        case "TC1C": return "CPU Core 3"
        case "TC2C": return "CPU Core 4"
        case "TC3C": return "CPU Core 5"
        case "TC4C": return "CPU Core 6"
        case "Tp01": return "CPU Package"
        case "Tp05": return "CPU Thermal"
        case "Tp09": return "CPU Sensor 3"
        case "Tp0D": return "CPU Sensor 4"
        case "Tp0P": return "CPU Sensor 5"
        case "Tg0D": return "GPU Die"
        case "Tg0P": return "GPU Proximity"
        case "Tg05": return "GPU Sensor 1"
        case "Tg0T": return "GPU Sensor 2"
        case "TaLP": return "Airflow Left"
        case "TaRT": return "Airflow Right"
        case "TaLW": return "Airflow Left Vent"
        case "TaRW": return "Airflow Right Vent"
        default: return key
        }
    }
}
