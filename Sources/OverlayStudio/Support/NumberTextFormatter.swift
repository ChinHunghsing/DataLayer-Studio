import Foundation

enum NumberTextFormatter {
    static func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }

        let decimalSeparator = formatter.decimalSeparator ?? "."
        let normalized = trimmed.replacingOccurrences(of: decimalSeparator, with: ".")
        return Double(normalized)
    }

    static func formatDouble(_ value: Double, maximumFractionDigits: Int = 3) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maximumFractionDigits)f", value)
    }

    static func parseInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = false
        if let number = formatter.number(from: trimmed) {
            let value = number.doubleValue
            guard value.isFinite,
                  value.rounded() == value,
                  value >= Double(Int.min),
                  value <= Double(Int.max) else {
                return nil
            }
            return Int(value)
        }

        return Int(trimmed)
    }

    static func formatInt(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
