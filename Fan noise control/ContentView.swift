
import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var monitor = SystemMonitor()
    @State private var fan0Manual: Bool = false
    @State private var fan0Target: Double = 3000
    @State private var fan1Manual: Bool = false
    @State private var fan1Target: Double = 3000
    
    var body: some View {
        HSplitView {
            // LEFT PANE: FANS
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text("Fan")
                        .font(.caption.bold())
                        .frame(width: 80, alignment: .leading)
                    Divider()
                    Text("Min / Current / Max RPM")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 8)
                    Divider()
                    Text("Control")
                        .font(.caption.bold())
                        .frame(width: 200, alignment: .leading)
                        .padding(.leading, 8)
                }
                .frame(height: 24)
                .background(Color(nsColor: .controlBackgroundColor))
                .border(Color.gray.opacity(0.3), width: 0.5)
                
                List {
                    FanRowView(
                        name: "Left side",
                        speed: monitor.fan0Speed,
                        min: 1200,
                        max: 6000,
                        isManual: $fan0Manual,
                        targetSpeed: $fan0Target
                    )
                    .environmentObject(monitor)
                    
                    // Always show 2nd fan as requested
                    FanRowView(
                        name: "Right side",
                        speed: monitor.fan1Speed,
                        min: 1200,
                        max: 6000,
                        isManual: $fan1Manual,
                        targetSpeed: $fan1Target
                    )
                    .environmentObject(monitor)
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 450, maxWidth: .infinity)
            
            // RIGHT PANE: SENSORS
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text("Sensor")
                         .font(.caption.bold())
                         .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    Text("Value")
                         .font(.caption.bold())
                         .frame(width: 80, alignment: .trailing)
                         .padding(.trailing, 4)
                }
                .frame(height: 24)
                .background(Color(nsColor: .controlBackgroundColor))
                .border(Color.gray.opacity(0.3), width: 0.5)
                
                List {
                    SensorSection(title: "CPU Core Average", sensors: monitor.sensors.filter { $0.type == .cpu })
                    SensorSection(title: "GPU Clusters", sensors: monitor.sensors.filter { $0.type == .gpu })
                    SensorSection(title: "Airflow", sensors: monitor.sensors.filter { $0.type == .airflow })
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 250, maxWidth: 350)
        }
        .frame(minWidth: 800, minHeight: 500)
        
        // Debug Log
        ScrollViewReader { proxy in
            ScrollView {
                Text(monitor.debugLog)
                    .id("logBottom")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled) // Allow copying
            }
            .frame(height: 120) // Increased height for better readability
            .background(Color.black)
            .foregroundColor(.green)
            .onChange(of: monitor.debugLog) { _ in
                withAnimation {
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }
        }
    }
}

struct FanRowView: View {
    let name: String
    let speed: Double
    let min: Int
    let max: Int
    @Binding var isManual: Bool
    @Binding var targetSpeed: Double
    @EnvironmentObject var monitor: SystemMonitor
    
    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "fanblades.fill")
                .font(.title2)
                .frame(width: 40)
            
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 80, alignment: .leading)
            
            // Speed Range
            HStack(spacing: 4) {
                Text("\(min)")
                    .foregroundColor(.secondary)
                Text("—")
                    .foregroundColor(.secondary)
                Text("\(speed.isFinite && speed < Double(Int.max) && speed > Double(Int.min) ? Int(speed) : 0)")
                    .font(.system(size: 13, weight: .bold))
                Text("—")
                    .foregroundColor(.secondary)
                Text("\(max)")
                    .foregroundColor(.secondary)
            }
            .font(.system(size: 12, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
            
            // Control
            HStack(spacing: 8) {
                Picker("", selection: $isManual) {
                    Text("Smart Auto").tag(false)
                    Text("Custom").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .onChange(of: isManual) { _, newValue in
                    if !newValue {
                        // Switched to Smart Auto - start applying
                        monitor.setFanControl(manual: false, speed: 0)
                    }
                }
                
                if isManual {
                    Slider(value: $targetSpeed, in: Double(min)...Double(max), step: 100)
                        .frame(width: 120)
                    
                    Text("\(Int(targetSpeed))")
                        .font(.caption.monospacedDigit())
                        .frame(width: 50)
                    
                    Button("Apply") {
                        monitor.setFanControl(manual: true, speed: targetSpeed)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .frame(minWidth: 200, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

struct SensorSection: View {
    let title: String
    let sensors: [SystemMonitor.SensorItem]
    
    var body: some View {
        if !sensors.isEmpty {
            Section(header: Text(title).font(.subheadline.bold())) {
                ForEach(sensors) { sensor in
                    HStack {
                        Image(systemName: "cpu") // Dynamic icon would be better
                            .foregroundColor(.green)
                            .font(.caption)
                        Text(sensor.name)
                            .font(.system(size: 12))
                        Spacer()
                        Text(String(format: "%.0f", sensor.value))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                }
            }
        }
    }
}
