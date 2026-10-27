import CoreGraphics
import Foundation
import IOKit

/// Brightness control for the built-in panel and Apple displays via the private DisplayServices framework.
enum DisplayServices {
    private typealias CanChangeFn = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let canChangeFn: CanChangeFn? = symbol("DisplayServicesCanChangeBrightness")
    private static let getFn: GetFn? = symbol("DisplayServicesGetBrightness")
    private static let setFn: SetFn? = symbol("DisplayServicesSetBrightness")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    static func canChangeBrightness(_ display: CGDirectDisplayID) -> Bool {
        canChangeFn?(display) ?? false
    }

    static func brightness(_ display: CGDirectDisplayID) -> Float? {
        var value: Float = 0
        guard let getFn, getFn(display, &value) == 0 else { return nil }
        return value
    }

    static func setBrightness(_ display: CGDirectDisplayID, _ value: Float) {
        _ = setFn?(display, value)
    }
}

/// DDC/CI brightness control for external monitors on Apple Silicon, via the private IOAVService I2C API.
/// Calls block for tens of milliseconds, so run them off the main thread.
enum DDC {
    struct Monitor {
        /// IORegistry entry ID of the DCPAVServiceProxy; stable for the lifetime of the connection.
        let id: UInt64
        fileprivate let service: CFTypeRef
    }

    static let brightnessVCP: UInt8 = 0x10

    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias I2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    private static let createFn: CreateFn? = symbol("IOAVServiceCreateWithService")
    private static let readFn: I2CFn? = symbol("IOAVServiceReadI2C")
    private static let writeFn: I2CFn? = symbol("IOAVServiceWriteI2C")

    private static let chipAddress: UInt32 = 0x37
    private static let hostAddress: UInt32 = 0x51
    private static let displayAddress: UInt8 = 0x6E

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    static func externalMonitors() -> [Monitor] {
        guard let createFn else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var monitors: [Monitor] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard location == "External", let service = createFn(kCFAllocatorDefault, entry)?.takeRetainedValue() else {
                continue
            }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(entry, &id)
            monitors.append(Monitor(id: id, service: service))
        }
        return monitors
    }

    static func read(_ monitor: Monitor, vcp: UInt8) -> (current: Int, max: Int)? {
        guard let readFn, let writeFn else { return nil }
        for _ in 0..<4 {
            var request: [UInt8] = [0x82, 0x01, vcp, 0]
            request[3] = checksum(request[0..<3])
            // Some monitors (e.g. LG) answer a single request with a DDC null message; sending it twice is reliable.
            var wrote = kIOReturnSuccess
            for _ in 0..<2 {
                wrote = request.withUnsafeMutableBytes {
                    writeFn(monitor.service, chipAddress, hostAddress, $0.baseAddress!, UInt32($0.count))
                }
                usleep(10_000)
            }
            guard wrote == kIOReturnSuccess else {
                usleep(20_000)
                continue
            }
            usleep(50_000)

            var reply = [UInt8](repeating: 0, count: 12)
            let read = reply.withUnsafeMutableBytes {
                readFn(monitor.service, chipAddress, hostAddress, $0.baseAddress!, UInt32($0.count))
            }
            guard read == kIOReturnSuccess else { continue }

            // VCP feature reply: 02 <result=00> <vcp> <type> <maxHi> <maxLo> <curHi> <curLo>
            if let i = (0...(reply.count - 8)).first(where: { reply[$0] == 0x02 && reply[$0 + 1] == 0x00 && reply[$0 + 2] == vcp }) {
                let max = Int(reply[i + 4]) << 8 | Int(reply[i + 5])
                let current = Int(reply[i + 6]) << 8 | Int(reply[i + 7])
                return (current, max)
            }
        }
        return nil
    }

    @discardableResult
    static func write(_ monitor: Monitor, vcp: UInt8, value: Int) -> Bool {
        guard let writeFn else { return false }
        var packet: [UInt8] = [0x84, 0x03, vcp, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF), 0]
        packet[5] = checksum(packet[0..<5])
        var succeeded = false
        // Monitors occasionally drop a write; sending it twice is the usual remedy.
        for _ in 0..<2 {
            let result = packet.withUnsafeMutableBytes {
                writeFn(monitor.service, chipAddress, hostAddress, $0.baseAddress!, UInt32($0.count))
            }
            succeeded = succeeded || result == kIOReturnSuccess
            usleep(30_000)
        }
        return succeeded
    }

    private static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        bytes.reduce(displayAddress ^ UInt8(hostAddress), ^)
    }
}
