import CoreGraphics
import Foundation

public enum OverlayComponentID: String, CaseIterable, Codable, Identifiable {
    case speed
    case pace
    case heartRate
    case cadence
    case distance
    case route
    case topProgress
    case timeDate

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .speed:
            return "Speed"
        case .pace:
            return "Pace"
        case .heartRate:
            return "Heart rate"
        case .cadence:
            return "Cadence"
        case .distance:
            return "Distance value"
        case .route:
            return "GPS route"
        case .topProgress:
            return "Distance"
        case .timeDate:
            return "Time & Date"
        }
    }
}

public struct OverlayComponentStyle: Codable, Equatable {
    public var accentColor: OverlayAccentColor?
    public var panelOpacity: Double?
    public var textScale: Double

    public init(
        accentColor: OverlayAccentColor? = nil,
        panelOpacity: Double? = nil,
        textScale: Double = 1
    ) {
        self.accentColor = accentColor
        self.panelOpacity = panelOpacity
        self.textScale = textScale
    }
}

public struct OverlayColor: Codable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    public func withAlpha(_ alpha: Double) -> OverlayColor {
        OverlayColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    public static let white = OverlayColor(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.96)
    public static let muted = OverlayColor(red: 0.66, green: 0.72, blue: 0.78, alpha: 0.82)
    public static let label = OverlayColor(red: 0.74, green: 0.80, blue: 0.86, alpha: 0.92)
    public static let track = OverlayColor(red: 1, green: 1, blue: 1, alpha: 0.14)
}

public enum OverlayFontFamily: String, CaseIterable, Codable, Identifiable {
    case helveticaNeue
    case helveticaNeueBold
    case menloBold
    case avenirNextCondensedHeavy
    case futuraCondensedExtraBold

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .helveticaNeue:
            return "Helvetica Neue"
        case .helveticaNeueBold:
            return "Helvetica Neue Bold"
        case .menloBold:
            return "Menlo Bold"
        case .avenirNextCondensedHeavy:
            return "Avenir Next Condensed"
        case .futuraCondensedExtraBold:
            return "Futura Condensed"
        }
    }

    public var postScriptName: String {
        switch self {
        case .helveticaNeue:
            return "HelveticaNeue"
        case .helveticaNeueBold:
            return "HelveticaNeue-Bold"
        case .menloBold:
            return "Menlo-Bold"
        case .avenirNextCondensedHeavy:
            return "AvenirNextCondensed-Heavy"
        case .futuraCondensedExtraBold:
            return "Futura-CondensedExtraBold"
        }
    }
}

public struct OverlayElementCustomization: Codable, Equatable {
    public var labelOverride: String?
    public var unitOverride: String?
    public var iconOverride: String?
    public var showsLabel: Bool
    public var showsUnit: Bool
    public var showsIcon: Bool
    public var showsPanel: Bool
    public var showGaugeTicks: Bool?
    public var valuePrecision: Int?
    public var gaugeMinimum: Double?
    public var gaugeMaximum: Double?
    public var labelFont: OverlayFontFamily
    public var valueFont: OverlayFontFamily
    public var unitFont: OverlayFontFamily
    public var iconFont: OverlayFontFamily
    public var labelColor: OverlayColor?
    public var valueColor: OverlayColor?
    public var unitColor: OverlayColor?
    public var iconColor: OverlayColor?
    public var trackColor: OverlayColor?
    public var lineWidth: Double
    public var lengthScale: Double
    public var labelScale: Double
    public var valueScale: Double
    public var unitScale: Double
    public var iconScale: Double

    public init(
        labelOverride: String? = nil,
        unitOverride: String? = nil,
        iconOverride: String? = nil,
        showsLabel: Bool = true,
        showsUnit: Bool = true,
        showsIcon: Bool = false,
        showsPanel: Bool = true,
        showGaugeTicks: Bool? = nil,
        valuePrecision: Int? = nil,
        gaugeMinimum: Double? = nil,
        gaugeMaximum: Double? = nil,
        labelFont: OverlayFontFamily = .helveticaNeueBold,
        valueFont: OverlayFontFamily = .menloBold,
        unitFont: OverlayFontFamily = .helveticaNeueBold,
        iconFont: OverlayFontFamily = .helveticaNeueBold,
        labelColor: OverlayColor? = nil,
        valueColor: OverlayColor? = nil,
        unitColor: OverlayColor? = nil,
        iconColor: OverlayColor? = nil,
        trackColor: OverlayColor? = nil,
        lineWidth: Double = 1,
        lengthScale: Double = 1,
        labelScale: Double = 1,
        valueScale: Double = 1,
        unitScale: Double = 1,
        iconScale: Double = 1
    ) {
        self.labelOverride = labelOverride
        self.unitOverride = unitOverride
        self.iconOverride = iconOverride
        self.showsLabel = showsLabel
        self.showsUnit = showsUnit
        self.showsIcon = showsIcon
        self.showsPanel = showsPanel
        self.showGaugeTicks = showGaugeTicks
        self.valuePrecision = valuePrecision
        self.gaugeMinimum = gaugeMinimum
        self.gaugeMaximum = gaugeMaximum
        self.labelFont = labelFont
        self.valueFont = valueFont
        self.unitFont = unitFont
        self.iconFont = iconFont
        self.labelColor = labelColor
        self.valueColor = valueColor
        self.unitColor = unitColor
        self.iconColor = iconColor
        self.trackColor = trackColor
        self.lineWidth = lineWidth
        self.lengthScale = lengthScale
        self.labelScale = labelScale
        self.valueScale = valueScale
        self.unitScale = unitScale
        self.iconScale = iconScale
    }

    public func label(default defaultLabel: String) -> String {
        guard let labelOverride, !labelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultLabel
        }
        return labelOverride
    }

    public func unit(default defaultUnit: String) -> String {
        guard let unitOverride, !unitOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultUnit
        }
        return unitOverride
    }

    public func icon(default defaultIcon: String) -> String {
        guard let iconOverride, !iconOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultIcon
        }
        return iconOverride
    }
}

public struct OverlayElement: Codable, Identifiable, Equatable {
    public var id: String
    public var kind: OverlayComponentID
    public var frame: OverlayComponentFrame
    public var customization: OverlayElementCustomization

    public init(
        id: String,
        kind: OverlayComponentID,
        frame: OverlayComponentFrame,
        customization: OverlayElementCustomization = OverlayElementCustomization()
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.customization = customization
    }
}

public struct OverlayComponentFrame: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var scale: Double
    public var isVisible: Bool
    public var style: OverlayComponentStyle

    public init(
        x: Double,
        y: Double,
        scale: Double = 1,
        isVisible: Bool = true,
        style: OverlayComponentStyle = OverlayComponentStyle()
    ) {
        self.x = x
        self.y = y
        self.scale = scale
        self.isVisible = isVisible
        self.style = style
    }
}

public enum OverlayAccentColor: String, CaseIterable, Codable, Identifiable {
    case telemetryGreen
    case electricBlue
    case amber
    case hotRed
    case cleanWhite

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .telemetryGreen:
            return "Telemetry green"
        case .electricBlue:
            return "Electric blue"
        case .amber:
            return "Amber"
        case .hotRed:
            return "Hot red"
        case .cleanWhite:
            return "Clean white"
        }
    }

    public var cgColor: CGColor {
        switch self {
        case .telemetryGreen:
            return CGColor(red: 0.46, green: 0.97, blue: 0.58, alpha: 0.98)
        case .electricBlue:
            return CGColor(red: 0.45, green: 0.82, blue: 1.00, alpha: 0.98)
        case .amber:
            return CGColor(red: 1.00, green: 0.76, blue: 0.35, alpha: 0.98)
        case .hotRed:
            return CGColor(red: 1.00, green: 0.38, blue: 0.42, alpha: 0.98)
        case .cleanWhite:
            return CGColor(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.98)
        }
    }
}

public struct OverlayStyle: Codable, Equatable {
    public var accentColor: OverlayAccentColor
    public var panelOpacity: Double
    public var metricScale: Double
    public var showGaugeTicks: Bool

    public init(
        accentColor: OverlayAccentColor = .telemetryGreen,
        panelOpacity: Double = 0.64,
        metricScale: Double = 1,
        showGaugeTicks: Bool = true
    ) {
        self.accentColor = accentColor
        self.panelOpacity = panelOpacity
        self.metricScale = metricScale
        self.showGaugeTicks = showGaugeTicks
    }
}

public struct OverlayLayout: Codable, Equatable {
    public var elements: [OverlayElement]
    public var style: OverlayStyle

    public init(
        speed: OverlayComponentFrame = OverlayComponentFrame(x: 0.025, y: 0.682),
        pace: OverlayComponentFrame = OverlayComponentFrame(
            x: 0.255,
            y: 0.814,
            style: OverlayComponentStyle(accentColor: .electricBlue)
        ),
        distance: OverlayComponentFrame = OverlayComponentFrame(
            x: 0.349,
            y: 0.814,
            style: OverlayComponentStyle(accentColor: .amber)
        ),
        heartRate: OverlayComponentFrame = OverlayComponentFrame(
            x: 0.443,
            y: 0.814,
            style: OverlayComponentStyle(accentColor: .hotRed)
        ),
        cadence: OverlayComponentFrame = OverlayComponentFrame(
            x: 0.537,
            y: 0.814,
            style: OverlayComponentStyle(accentColor: .telemetryGreen)
        ),
        route: OverlayComponentFrame = OverlayComponentFrame(x: 0.776, y: 0.682),
        topProgress: OverlayComponentFrame = OverlayComponentFrame(
            x: 0.070,
            y: 0.035,
            style: OverlayComponentStyle(accentColor: .cleanWhite, panelOpacity: 0.42)
        ),
        timeDate: OverlayComponentFrame = OverlayComponentFrame(
            x: 0.792,
            y: 0.720,
            style: OverlayComponentStyle(accentColor: .cleanWhite)
        ),
        style: OverlayStyle = OverlayStyle()
    ) {
        self.elements = [
            OverlayElement.defaultElement(kind: .topProgress, frame: topProgress),
            OverlayElement.defaultElement(kind: .speed, frame: speed),
            OverlayElement.defaultElement(kind: .pace, frame: pace),
            OverlayElement.defaultElement(kind: .distance, frame: distance),
            OverlayElement.defaultElement(kind: .heartRate, frame: heartRate),
            OverlayElement.defaultElement(kind: .cadence, frame: cadence),
            OverlayElement.defaultElement(kind: .route, frame: route),
            OverlayElement.defaultElement(kind: .timeDate, frame: timeDate)
        ]
        self.style = style
    }

    public init(elements: [OverlayElement], style: OverlayStyle = OverlayStyle()) {
        self.elements = elements
        self.style = style
    }

    public static let `default` = OverlayLayout()

    public func component(_ id: OverlayComponentID) -> OverlayComponentFrame {
        if let element = elements.first(where: { $0.kind == id }) {
            return element.frame
        }
        return OverlayElement.defaultElement(kind: id).frame
    }

    public var visibleElements: [OverlayElement] {
        elements.filter { $0.frame.isVisible }
    }

    public mutating func updateElement(id: String, _ update: (inout OverlayElement) -> Void) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        update(&elements[index])
    }

    public mutating func removeElement(id: String) {
        elements.removeAll { $0.id == id }
    }

    public mutating func updateFirstElement(kind: OverlayComponentID, _ update: (inout OverlayElement) -> Void) {
        if let index = elements.firstIndex(where: { $0.kind == kind }) {
            update(&elements[index])
        } else {
            var element = OverlayElement.defaultElement(kind: kind)
            update(&element)
            elements.append(element)
        }
    }

    public var speed: OverlayComponentFrame {
        get { component(.speed) }
        set { updateFirstElement(kind: .speed) { $0.frame = newValue } }
    }

    public var pace: OverlayComponentFrame {
        get { component(.pace) }
        set { updateFirstElement(kind: .pace) { $0.frame = newValue } }
    }

    public var heartRate: OverlayComponentFrame {
        get { component(.heartRate) }
        set { updateFirstElement(kind: .heartRate) { $0.frame = newValue } }
    }

    public var cadence: OverlayComponentFrame {
        get { component(.cadence) }
        set { updateFirstElement(kind: .cadence) { $0.frame = newValue } }
    }

    public var distance: OverlayComponentFrame {
        get { component(.distance) }
        set { updateFirstElement(kind: .distance) { $0.frame = newValue } }
    }

    public var route: OverlayComponentFrame {
        get { component(.route) }
        set { updateFirstElement(kind: .route) { $0.frame = newValue } }
    }

    public var topProgress: OverlayComponentFrame {
        get { component(.topProgress) }
        set { updateFirstElement(kind: .topProgress) { $0.frame = newValue } }
    }

    public var timeDate: OverlayComponentFrame {
        get { component(.timeDate) }
        set { updateFirstElement(kind: .timeDate) { $0.frame = newValue } }
    }
}

public extension OverlayElement {
    static func defaultElement(
        kind: OverlayComponentID,
        id: String? = nil,
        frame: OverlayComponentFrame? = nil
    ) -> OverlayElement {
        OverlayElement(
            id: id ?? kind.rawValue,
            kind: kind,
            frame: frame ?? defaultFrame(for: kind),
            customization: defaultCustomization(for: kind)
        )
    }

    static func defaultFrame(for kind: OverlayComponentID) -> OverlayComponentFrame {
        switch kind {
        case .speed:
            return OverlayComponentFrame(x: 0.025, y: 0.682)
        case .pace:
            return OverlayComponentFrame(
                x: 0.255,
                y: 0.814,
                style: OverlayComponentStyle(accentColor: .electricBlue)
            )
        case .distance:
            return OverlayComponentFrame(
                x: 0.349,
                y: 0.814,
                style: OverlayComponentStyle(accentColor: .amber)
            )
        case .heartRate:
            return OverlayComponentFrame(
                x: 0.443,
                y: 0.814,
                style: OverlayComponentStyle(accentColor: .hotRed)
            )
        case .cadence:
            return OverlayComponentFrame(
                x: 0.537,
                y: 0.814,
                style: OverlayComponentStyle(accentColor: .telemetryGreen)
            )
        case .route:
            return OverlayComponentFrame(x: 0.776, y: 0.682)
        case .topProgress:
            return OverlayComponentFrame(
                x: 0.070,
                y: 0.035,
                style: OverlayComponentStyle(accentColor: .cleanWhite, panelOpacity: 0.42)
            )
        case .timeDate:
            return OverlayComponentFrame(
                x: 0.792,
                y: 0.720,
                style: OverlayComponentStyle(accentColor: .cleanWhite)
            )
        }
    }

    static func defaultCustomization(for kind: OverlayComponentID) -> OverlayElementCustomization {
        switch kind {
        case .speed:
            return OverlayElementCustomization(valuePrecision: 1, gaugeMinimum: 0, gaugeMaximum: 24, lineWidth: 12)
        case .distance:
            return OverlayElementCustomization(valuePrecision: nil)
        case .topProgress:
            return OverlayElementCustomization(showsPanel: true, showGaugeTicks: false, valuePrecision: 1, lineWidth: 8)
        case .timeDate:
            return OverlayElementCustomization(showsLabel: false, showsPanel: false, showGaugeTicks: false, valueScale: 1.08, unitScale: 1.04)
        case .route:
            return OverlayElementCustomization(lineWidth: 5.5)
        case .pace, .heartRate, .cadence:
            return OverlayElementCustomization()
        }
    }
}
