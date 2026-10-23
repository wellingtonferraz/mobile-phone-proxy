import Foundation
import Network

/// Admission policy for the local installation: USB loopback or current Wi-Fi LAN.
enum LocalProxyAccess {
    struct IPv4Subnet {
        let address: UInt32
        let netmask: UInt32

        func contains(_ candidate: UInt32) -> Bool {
            // Invalid or missing masks must not widen access to every address.
            let inverse = ~netmask
            guard netmask != 0, inverse & (inverse &+ 1) == 0 else { return false }
            return candidate & netmask == address & netmask
        }
    }

    static func allows(_ endpoint: NWEndpoint, wifiSubnets: [IPv4Subnet]) -> Bool {
        guard case .hostPort(let host, _) = endpoint,
              case .ipv4(let ip) = host else { return false }
        let value = ip.rawValue.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        if value >> 24 == 127 { return true }

        let isPrivate = value & 0xff000000 == 0x0a000000
            || value & 0xfff00000 == 0xac100000
            || value & 0xffff0000 == 0xc0a80000
        return isPrivate && wifiSubnets.contains { $0.contains(value) }
    }
}
