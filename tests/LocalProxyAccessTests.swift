import Foundation
import Network

@main
struct LocalProxyAccessTests {
    static func value(_ ip: String) -> UInt32 {
        IPv4Address(ip)!.rawValue.reduce(0) { ($0 << 8) | UInt32($1) }
    }
    static func subnet(_ ip: String, _ mask: String) -> LocalProxyAccess.IPv4Subnet {
        .init(address: value(ip), netmask: value(mask))
    }
    static func endpoint(_ ip: String) -> NWEndpoint {
        .hostPort(host: .ipv4(IPv4Address(ip)!), port: 12345)
    }
    static func main() {
        let lan = [subnet("192.168.1.10", "255.255.255.0")]
        var count = 0
        func check(_ label: String, _ remote: NWEndpoint, _ networks: [LocalProxyAccess.IPv4Subnet], _ expected: Bool) {
            guard LocalProxyAccess.allows(remote, wifiSubnets: networks) == expected else {
                fatalError("Failed: \(label)")
            }
            count += 1
        }
        check("USB with Wi-Fi off", endpoint("127.0.0.1"), [], true)
        check("USB with Wi-Fi on", endpoint("127.0.0.1"), lan, true)
        check("current LAN", endpoint("192.168.1.50"), lan, true)
        check("other private LAN", endpoint("192.168.2.50"), lan, false)
        check("private without Wi-Fi", endpoint("192.168.1.50"), [], false)
        check("previous LAN after change", endpoint("192.168.1.50"), [subnet("192.168.2.10", "255.255.255.0")], false)
        check("unrelated private network", endpoint("10.0.0.2"), lan, false)
        check("public source", endpoint("8.8.8.8"), lan, false)
        check("carrier NAT source", endpoint("100.64.0.2"), lan, false)
        check("IPv4 link-local", endpoint("169.254.1.2"), lan, false)
        check("unspecified source", endpoint("0.0.0.0"), lan, false)
        check("multicast source", endpoint("224.0.0.1"), lan, false)
        check("actual wider mask", endpoint("10.9.250.2"), [subnet("10.9.1.2", "255.255.0.0")], true)
        check("outside wider mask", endpoint("10.10.0.2"), [subnet("10.9.1.2", "255.255.0.0")], false)
        check("172 private range", endpoint("172.31.20.2"), [subnet("172.31.16.5", "255.255.240.0")], true)
        check("172 public range", endpoint("172.32.20.2"), [subnet("172.32.16.5", "255.255.240.0")], false)
        check("zero mask", endpoint("10.1.2.3"), [subnet("192.168.1.10", "0.0.0.0")], false)
        check("noncontiguous mask", endpoint("192.168.1.50"), [subnet("192.168.1.10", "255.0.255.0")], false)
        check("hostname must not bypass policy", .hostPort(host: .name("127.0.0.1", nil), port: 12345), lan, false)
        check("IPv6 public", .hostPort(host: .ipv6(IPv6Address("2001:db8::1")!), port: 12345), lan, false)
        check("IPv6 mapped IPv4", .hostPort(host: .ipv6(IPv6Address("::ffff:192.168.1.50")!), port: 12345), lan, false)
        check("unknown endpoint", .service(name: "local", type: "_http._tcp", domain: "local", interface: nil), lan, false)
        if let ip = NetworkInterface.address(for: .wifi) {
            let networks = NetworkInterface.wifiIPv4Subnets()
            if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") {
                check("real interface address and netmask byte order", endpoint(ip), networks, true)
            }
        }
        print("PASS: \(count) admission checks")
    }
}
