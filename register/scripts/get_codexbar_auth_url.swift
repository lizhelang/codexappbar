import AppKit
import ApplicationServices
import Foundation

func attr<T>(_ element: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? T
}

let authPrefix = "https://auth.openai.com/oauth/authorize?"

func isCompleteAuthURL(_ value: String) -> Bool {
    guard value.hasPrefix(authPrefix) else { return false }
    let requiredFragments = [
        "response_type=code",
        "client_id=",
        "redirect_uri=http://localhost:1455/auth/callback",
        "code_challenge=",
        "state=",
        "originator="
    ]
    return requiredFragments.allSatisfy { value.contains($0) }
}

func firstAuthURL(in element: AXUIElement) -> String? {
    for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
        if let value: String = attr(element, key),
           isCompleteAuthURL(value) {
            return value
        }
    }

    if let children: [AXUIElement] = attr(element, kAXChildrenAttribute) {
        for child in children {
            if let found = firstAuthURL(in: child) {
                return found
            }
        }
    }

    return nil
}

let timeoutSeconds = 10.0
let deadline = Date().addingTimeInterval(timeoutSeconds)

while Date() < deadline {
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "lzhl.codexAppBar")
    if let app = apps.first {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        if let windows: [AXUIElement] = attr(appElement, kAXWindowsAttribute),
           let window = windows.first(where: { (attr($0, kAXTitleAttribute) as String?) == "OpenAI OAuth" }) {
            if let authURL = firstAuthURL(in: window) {
                print(authURL)
                exit(0)
            }
        }
    }

    Thread.sleep(forTimeInterval: 0.2)
}

fputs("Timed out waiting for the OpenAI OAuth window auth URL.\n", stderr)
exit(1)
