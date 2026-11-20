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
        number(value) + " rpm"
    }

    /// e.g. "1,840–5,300 rpm".
    static func rpmRange(_ lower: Double, _ upper: Double) -> String {
        number(lower) + "–" + number(upper) + " rpm"
    }

    /// Rounds to tens: the last digit of a fan speed jitters constantly and isn't meaningful.
    private static func number(_ rpm: Double) -> String {
        ((rpm / 10).rounded() * 10).formatted(.number.precision(.fractionLength(0)))
    }
}
