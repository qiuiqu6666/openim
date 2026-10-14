import Foundation

@main
struct NetworkPathTests {
    static func main() {
        var policy = IMNetworkPathPolicy()
        precondition(!policy.observe(path: "WiFi", online: true, foreground: true))
        for _ in 0..<20 {
            precondition(!policy.observe(path: "WiFi", online: true, foreground: true))
        }
        precondition(!policy.observe(path: "None", online: false, foreground: true))
        precondition(policy.observe(path: "WiFi", online: true, foreground: true))
        precondition(!policy.observe(path: "WiFi", online: true, foreground: true))
        precondition(!policy.observe(path: "Cellular", online: true, foreground: false))
        precondition(policy.observe(path: "Cellular", online: true, foreground: true))
        precondition(!policy.observe(path: "Cellular", online: true, foreground: true))
        policy.reset(path: "WiFi") // route reinitialization starts a new baseline
        precondition(!policy.observe(path: "WiFi", online: true, foreground: true))
        precondition(policy.observe(path: "Cellular", online: true, foreground: true))
        policy.reset()
        precondition(!policy.observe(path: "Cellular", online: true, foreground: true))
        precondition(policy.allowWake(path: "WiFi", now: 10))
        precondition(!policy.allowWake(path: "WiFi", now: 10.35))
        precondition(policy.allowWake(path: "Cellular", now: 10.5))
        precondition(!policy.allowWake(path: "Cellular", now: 10.8))
        precondition(policy.allowWake(path: "Cellular", now: 11.5))
        policy.reset(path: "Cellular")
        precondition(policy.allowWake(path: "Cellular", now: 11.6))
        print("Network path policy tests passed")
    }
}
