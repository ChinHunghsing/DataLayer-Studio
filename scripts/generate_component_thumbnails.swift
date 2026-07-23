#!/usr/bin/env swift

import AppKit
import Foundation

let components: [(String, String, NSColor)] = [
    ("speed", "gauge.with.dots.needle.bottom.50percent", .systemOrange),
    ("pace", "timer", .systemBlue),
    ("heartRate", "heart.fill", .systemRed),
    ("cadence", "figure.run", .systemGreen),
    ("calories", "flame.fill", .systemOrange),
    ("ascent", "mountain.2.fill", .systemMint),
    ("strideLength", "arrow.left.and.right", .systemTeal),
    ("power", "bolt.fill", .systemYellow),
    ("verticalOscillation", "arrow.up.and.down", .systemCyan),
    ("groundContactTime", "timer", .systemPurple),
    ("groundContactTimePercent", "percent", .systemIndigo),
    ("groundContactTimeBalance", "scalemass", .systemPink),
    ("verticalRatio", "arrow.up.and.down", .systemBlue),
    ("respirationRate", "lungs.fill", .systemMint),
    ("stepSpeedLoss", "speedometer", .systemOrange),
    ("formPower", "bolt.badge.clock", .systemYellow),
    ("airPower", "wind", .systemTeal),
    ("legSpringStiffness", "arrow.up.and.down", .systemGreen),
    ("weather", "cloud.sun.fill", .systemBlue),
    ("distance", "ruler", .systemGreen),
    ("route", "point.topleft.down.curvedto.point.bottomright.up", .systemBlue),
    ("altitudeProfile", "mountain.2.fill", .systemBlue),
    ("topProgress", "chart.bar.xaxis", .systemGreen),
    ("timeDate", "clock", .white)
]

let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Resources/ComponentThumbnails", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for (name, symbolName, accent) in components {
    let size = NSSize(width: 320, height: 180)
    let image = NSImage(size: size)
    image.lockFocus()

    let background = NSGradient(colors: [
        NSColor(calibratedRed: 0.075, green: 0.085, blue: 0.095, alpha: 1),
        NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.14, alpha: 1)
    ])!
    background.draw(in: NSRect(origin: .zero, size: size), angle: -35)

    NSColor.white.withAlphaComponent(0.055).setStroke()
    let grid = NSBezierPath()
    for x in stride(from: 32.0, through: 288.0, by: 32.0) {
        grid.move(to: NSPoint(x: x, y: 0))
        grid.line(to: NSPoint(x: x, y: 180))
    }
    for y in stride(from: 30.0, through: 150.0, by: 30.0) {
        grid.move(to: NSPoint(x: 0, y: y))
        grid.line(to: NSPoint(x: 320, y: y))
    }
    grid.lineWidth = 1
    grid.stroke()

    let panelRect = NSRect(x: 54, y: 42, width: 212, height: 96)
    let panel = NSBezierPath(roundedRect: panelRect, xRadius: 18, yRadius: 18)
    NSColor.white.withAlphaComponent(0.08).setFill()
    panel.fill()
    accent.withAlphaComponent(0.42).setStroke()
    panel.lineWidth = 2
    panel.stroke()

    if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 42, weight: .medium)
            .applying(.init(paletteColors: [accent, .white.withAlphaComponent(0.88)]))
        let configured = symbol.withSymbolConfiguration(configuration) ?? symbol
        configured.draw(
            in: NSRect(x: 82, y: 65, width: 52, height: 52),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    accent.withAlphaComponent(0.86).setFill()
    NSBezierPath(roundedRect: NSRect(x: 152, y: 91, width: 78, height: 12), xRadius: 6, yRadius: 6).fill()
    NSColor.white.withAlphaComponent(0.34).setFill()
    NSBezierPath(roundedRect: NSRect(x: 152, y: 70, width: 52, height: 7), xRadius: 3.5, yRadius: 3.5).fill()

    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode \(name)")
    }
    try png.write(to: outputDirectory.appendingPathComponent("component-\(name).png"))
}
