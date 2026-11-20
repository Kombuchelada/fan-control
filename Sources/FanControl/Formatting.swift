import Foundation

enum Format {
    static func temperature(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0))) + " °C"
    }

    /// Compact form for the menu bar, e.g. "62°".
    static func shortTemperature(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0))) + "°"
    }

    static func rpm(_ value: Double) -> String {
        // Round to tens: the last digit jitters constantly and isn't meaningful.
        ((value / 10).rounded() * 10).formatted(.number.precision(.fractionLength(0))) + " rpm"
    }
}
