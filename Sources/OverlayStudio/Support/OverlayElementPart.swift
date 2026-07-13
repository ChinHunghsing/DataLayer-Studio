import OverlayCore

/// A selectable part inside a canvas element. Selecting a part on the canvas (second click)
/// focuses the inspector's style controls on that part's font and color.
enum OverlayElementPart: String, CaseIterable, Identifiable {
    case label
    case value
    case unit
    case icon

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .label:
            return "inspector.label"
        case .value:
            return "inspector.value"
        case .unit:
            return "inspector.unit"
        case .icon:
            return "inspector.icon"
        }
    }

    /// Part titles differ for the progress bar, whose label/value/unit map to
    /// start/current/end distance labels.
    func localizationKey(for kind: OverlayComponentID) -> String {
        guard kind == .topProgress else {
            if kind == .timeDate, self == .unit {
                return "inspector.clockAndDate"
            }
            return localizationKey
        }
        switch self {
        case .label:
            return "inspector.startDistance"
        case .value:
            return "inspector.currentDistance"
        case .unit:
            return "inspector.endDistance"
        case .icon:
            return "inspector.icon"
        }
    }

    /// Parts that can currently be styled on the element, mirroring the visibility
    /// toggles that gate each text row.
    static func availableParts(for element: OverlayElement) -> [OverlayElementPart] {
        guard element.kind != .route else { return [] }
        var parts: [OverlayElementPart] = []
        if element.customization.showsLabel {
            parts.append(.label)
        }
        if element.kind == .topProgress {
            // The current-distance readout only draws while the start label is shown.
            if element.customization.showsLabel {
                parts.append(.value)
            }
        } else {
            parts.append(.value)
        }
        if element.customization.showsUnit {
            parts.append(.unit)
        }
        if element.customization.showsIcon {
            parts.append(.icon)
        }
        return parts
    }
}
