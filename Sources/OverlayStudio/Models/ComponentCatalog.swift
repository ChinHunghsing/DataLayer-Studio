import AppKit
import Foundation
import OverlayCore

enum ComponentCatalogGroup: String, CaseIterable, Identifiable {
    case basics
    case runningDynamics
    case routeAndProgress
    case information

    var id: String { rawValue }
    var localizationKey: String { "library.components.group.\(rawValue)" }
}

struct ComponentCatalogItem: Identifiable {
    var component: OverlayComponentID
    var group: ComponentCatalogGroup

    var id: OverlayComponentID { component }
    var thumbnailResourceName: String { "component-\(component.rawValue)" }

    static let all: [ComponentCatalogItem] = OverlayComponentID.allCases.map { component in
        ComponentCatalogItem(component: component, group: group(for: component))
    }

    private static func group(for component: OverlayComponentID) -> ComponentCatalogGroup {
        switch component {
        case .speed, .pace, .heartRate, .cadence, .calories, .ascent, .distance:
            return .basics
        case .strideLength, .power, .verticalOscillation, .groundContactTime,
             .groundContactTimePercent, .groundContactTimeBalance, .verticalRatio,
             .respirationRate, .stepSpeedLoss, .formPower, .airPower, .legSpringStiffness:
            return .runningDynamics
        case .route, .topProgress:
            return .routeAndProgress
        case .weather, .timeDate:
            return .information
        }
    }
}

enum ComponentDragPayload {
    private static let prefix = "datalayer-component:"

    static func value(for component: OverlayComponentID) -> String {
        prefix + component.rawValue
    }

    static func component(from value: String) -> OverlayComponentID? {
        guard value.hasPrefix(prefix) else { return nil }
        return OverlayComponentID(rawValue: String(value.dropFirst(prefix.count)))
    }
}

@MainActor
enum ComponentThumbnailLoader {
    private static var cache: [String: NSImage] = [:]

    static func image(named name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }

        let image: NSImage?
        if let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "ComponentThumbnails"
        ) {
            image = NSImage(contentsOf: url)
        } else {
            let localURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/ComponentThumbnails/\(name).png")
            image = NSImage(contentsOf: localURL)
        }

        if let image {
            cache[name] = image
        }
        return image
    }
}
