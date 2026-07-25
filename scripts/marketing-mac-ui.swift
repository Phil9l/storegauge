#!/usr/bin/env swift

import ApplicationServices
import CoreGraphics
import Foundation

private func attribute(_ name: String, from element: AXUIElement) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
    }
    return value
}

private func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
    attribute(name, from: element) as? String
}

private func children(of element: AXUIElement) -> [AXUIElement] {
    attribute(kAXChildrenAttribute, from: element) as? [AXUIElement] ?? []
}

private func walk(_ element: AXUIElement, depth: Int = 0, visit: (AXUIElement, Int) -> Bool) -> Bool {
    if visit(element, depth) {
        return true
    }
    for child in children(of: element) where walk(child, depth: depth + 1, visit: visit) {
        return true
    }
    return false
}

guard CommandLine.arguments.count >= 3,
      let pid = pid_t(CommandLine.arguments[1]) else {
    fputs("usage: marketing-mac-ui.swift <pid> list|press [label]\n", stderr)
    exit(2)
}

let command = CommandLine.arguments[2]
let app = AXUIElementCreateApplication(pid)

switch command {
case "window-id":
    let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly],
        kCGNullWindowID
    ) as? [[String: Any]] ?? []
    let candidates = windows.compactMap { window -> (id: Int, area: Double)? in
        guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
              window[kCGWindowLayer as String] as? Int == 0,
              let id = window[kCGWindowNumber as String] as? Int,
              let bounds = window[kCGWindowBounds as String] as? [String: Double],
              let width = bounds["Width"],
              let height = bounds["Height"] else {
            return nil
        }
        return (id, width * height)
    }
    guard let largest = candidates.max(by: { $0.area < $1.area }) else {
        exit(1)
    }
    print(largest.id)

case "list":
    _ = walk(app) { element, depth in
        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        let title = stringAttribute(kAXTitleAttribute, from: element) ?? ""
        let description = stringAttribute(kAXDescriptionAttribute, from: element) ?? ""
        if !title.isEmpty || !description.isEmpty {
            print("\(String(repeating: "  ", count: depth))\(role) | \(title) | \(description)")
        }
        return false
    }

case "press":
    guard CommandLine.arguments.count >= 4 else {
        fputs("press requires an accessibility label\n", stderr)
        exit(2)
    }
    let target = CommandLine.arguments[3]
    var matched = false
    _ = walk(app) { element, _ in
        let title = stringAttribute(kAXTitleAttribute, from: element)
        let description = stringAttribute(kAXDescriptionAttribute, from: element)
        let help = stringAttribute(kAXHelpAttribute, from: element)
        guard title == target || description == target || help == target else {
            return false
        }
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            matched = true
            return true
        }
        return false
    }
    guard matched else {
        fputs("no pressable accessibility element matched: \(target)\n", stderr)
        exit(1)
    }

default:
    fputs("unknown command: \(command)\n", stderr)
    exit(2)
}
