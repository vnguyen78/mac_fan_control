
import Foundation
import IOKit

// Models matching exelban/Stats implementation
internal struct SMCKeyData_t {
    typealias SMCBytes_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8)

    struct vers_t {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    struct LimitData_t {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct keyInfo_t {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = vers_t()
    var pLimitData = LimitData_t()
    var keyInfo = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0)
}

internal enum SMCKeys: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case writeBytes = 6
    case readIndex = 8
    case readKeyInfo = 9
    case readPLimit = 11
    case readVers = 12
}

class SMC {
    static let shared = SMC()
    private var conn: io_connect_t = 0
    
    // Connection Log
    var connectionLog: String = ""
    
    init() { }
    
    func open() -> Bool {
        if conn != 0 { return true }
        connectionLog = "Starting SMC Connection (Stats-Protocol Copy)...\n"
        
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if service == 0 {
            connectionLog += "AppleSMC not found.\n"
            return false
        }
        
        // Try Connection Type 0 (as per Stats)
        let ret = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        
        if ret != kIOReturnSuccess {
            connectionLog += "IOServiceOpen Failed: \(String(format:"0x%x", ret))\n"
            return false
        }
        
        connectionLog += "Connected to AppleSMC (Type 0). Verifying...\n"
        
        // Quick verification: Read #KEY count
        let keys = readKeyCount()
        connectionLog += "Read #KEY Count: \(keys)\n"
        
        return keys > 0
    }
    
    func close() {
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
        }
    }
    
    private func call(index: Int, input: inout SMCKeyData_t, output: inout SMCKeyData_t) -> kern_return_t {
         let inputSize = MemoryLayout<SMCKeyData_t>.stride
         var outputSize = MemoryLayout<SMCKeyData_t>.stride

         return IOConnectCallStructMethod(conn, UInt32(index), &input, inputSize, &output, &outputSize)
    }
    
    private func fourChar(_ s: String) -> UInt32 {
        let d = s.data(using: .ascii) ?? Data()
        if d.count < 4 { return 0 }
        return (UInt32(d[0]) << 24) | (UInt32(d[1]) << 16) | (UInt32(d[2]) << 8) | UInt32(d[3])
    }
    
    func readKeyCount() -> Int {
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        
        input.key = fourChar("#KEY")
        input.data8 = SMCKeys.readKeyInfo.rawValue
        
        if call(index: Int(SMCKeys.kernelIndex.rawValue), input: &input, output: &output) != kIOReturnSuccess {
            return 0
        }
        
        // Now read data
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = SMCKeys.readBytes.rawValue
        
        if call(index: Int(SMCKeys.kernelIndex.rawValue), input: &input, output: &output) != kIOReturnSuccess {
            return 0
        }
        
        // #KEY is UI32
        let val = UInt32(output.bytes.0) << 24 | UInt32(output.bytes.1) << 16 | UInt32(output.bytes.2) << 8 | UInt32(output.bytes.3)
        return Int(val)
    }
    
    func getAllKeys() -> [String] {
        let count = readKeyCount()
        if count == 0 { return [] }
        
        var list: [String] = []
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        
        for i in 0..<count {
            input.data8 = SMCKeys.readIndex.rawValue
            input.data32 = UInt32(i)
            
            if call(index: Int(SMCKeys.kernelIndex.rawValue), input: &input, output: &output) == kIOReturnSuccess {
                let keyVal = output.key
                // Convert 4-char code to string
                let s = String(bytes: [
                    UInt8((keyVal >> 24) & 0xFF),
                    UInt8((keyVal >> 16) & 0xFF),
                    UInt8((keyVal >> 8) & 0xFF),
                    UInt8(keyVal & 0xFF)
                ], encoding: .ascii) ?? ""
                
                // Filter out non-ascii garbage
                if s.count == 4 {
                    list.append(s)
                }
            }
        }
        return list
    }
    
    func readKey(_ key: String) -> Double? {
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        
        input.key = fourChar(key)
        input.data8 = SMCKeys.readKeyInfo.rawValue
        
        if call(index: Int(SMCKeys.kernelIndex.rawValue), input: &input, output: &output) != kIOReturnSuccess {
            // connectionLog += "Failed to get info for \(key)\n"
            return nil
        }
        
        // Parse type
        let typeVal = output.keyInfo.dataType
        let typeStr = String(bytes: [
            UInt8((typeVal >> 24) & 0xFF),
            UInt8((typeVal >> 16) & 0xFF),
            UInt8((typeVal >> 8) & 0xFF),
            UInt8(typeVal & 0xFF)
        ], encoding: .ascii) ?? "????"
        
        let size = Int(output.keyInfo.dataSize)

        // Read Data
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = SMCKeys.readBytes.rawValue
        
        if call(index: Int(SMCKeys.kernelIndex.rawValue), input: &input, output: &output) != kIOReturnSuccess {
            // connectionLog += "Failed to read data for \(key)\n"
            return nil
        }
        
        let bytes: [UInt8] = [
            output.bytes.0, output.bytes.1, output.bytes.2, output.bytes.3,
            output.bytes.4, output.bytes.5, output.bytes.6, output.bytes.7,
            output.bytes.8, output.bytes.9, output.bytes.10, output.bytes.11,
            output.bytes.12, output.bytes.13, output.bytes.14, output.bytes.15,
            output.bytes.16, output.bytes.17, output.bytes.18, output.bytes.19,
            output.bytes.20, output.bytes.21, output.bytes.22, output.bytes.23,
            output.bytes.24, output.bytes.25, output.bytes.26, output.bytes.27,
            output.bytes.28, output.bytes.29, output.bytes.30, output.bytes.31
        ]
        
        let val = parseBytes(bytes, type: typeStr)
        
        // Verbose logging disabled to prevent UI blocking during refresh
        // if key.hasPrefix("Tp") || key.hasPrefix("F0") {
        //      connectionLog += "\(key) [\(typeStr), Sz:\(size)]: \(bytes.prefix(4)) -> \(val ?? -1)\n"
        // }
        
        return val
    }
    
    private func parseBytes(_ bytes: [UInt8], type: String) -> Double? {
         if type == "ui8 " { return Double(bytes[0]) }
         if type == "ui16" { return Double((Int(bytes[0]) << 8) + Int(bytes[1])) }
         if type == "ui32" { return Double((Int(bytes[0]) << 24) + (Int(bytes[1]) << 16) + (Int(bytes[2]) << 8) + Int(bytes[3])) }
         if type == "sp78" { return Double((Int(bytes[0]) << 8) + Int(bytes[1])) / 256.0 }
         if type == "fpe2" { return Double((Int(bytes[0]) << 8) + Int(bytes[1])) / 4.0 }
         if type == "flt " {
             // M1/ARM SMC returns floats in Little Endian (Host Order)
             let bits = (UInt32(bytes[3]) << 24) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[1]) << 8) | UInt32(bytes[0])
             return Double(Float32(bitPattern: bits))
         }
         return nil
    }
    
    // Write not strictly needed for reading fans, but useful
    func writeKey(_ key: String, data: [UInt8]) -> Int32 {
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        
        input.key = fourChar(key)
        input.data8 = SMCKeys.readKeyInfo.rawValue
        
        let infoRet = call(index: Int(SMCKeys.kernelIndex.rawValue), input: &input, output: &output)
        if infoRet != kIOReturnSuccess {
            return infoRet
        }
        
        // Prepare write
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.keyInfo.dataType = output.keyInfo.dataType
        input.data8 = SMCKeys.writeBytes.rawValue
        
        // Fill bytes tuple (clumsy but necessary)
        // Simplest: just map the first few.
        if data.count > 0 { input.bytes.0 = data[0] }
        if data.count > 1 { input.bytes.1 = data[1] }
        if data.count > 2 { input.bytes.2 = data[2] }
        if data.count > 3 { input.bytes.3 = data[3] }
        
        return call(index: Int(SMCKeys.kernelIndex.rawValue), input: &input, output: &output)
    }
    
    // Probe diagnostics (Reduced)
    func probeSMC() -> String {
        return connectionLog
    }
}
