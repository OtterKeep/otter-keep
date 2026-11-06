import Foundation

/// Locale-aware labels for the hour/minute pickers used by backup schedules.
///
/// Hard-coding `"%02d:00"` produced 24-hour labels even for users on a 12-hour clock, so the
/// picker disagreed with every other time shown in the app. Building the label from a real `Date`
/// lets the system apply the user's 12/24-hour preference and localized digits.
enum ScheduleTimeFormatting {
    /// All 24 hours of the day, labelled for the current locale (e.g. `14:00` or `2 PM`).
    static var hourLabels: [(hour: Int, label: String)] {
        (0..<24).map { hour in (hour, hourLabel(hour)) }
    }

    /// The quarter-hour marks offered by the minute picker.
    static let minuteOptions = [0, 15, 30, 45]

    static func hourLabel(_ hour: Int) -> String {
        guard let date = date(hour: hour, minute: 0) else { return String(format: "%02d:00", hour) }
        return timeFormatter.string(from: date)
    }

    static func minuteLabel(_ minute: Int) -> String {
        ":" + (minuteFormatter.string(from: NSNumber(value: minute)) ?? String(format: "%02d", minute))
    }

    private static let minuteFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumIntegerDigits = 2
        return formatter
    }()

    private static func date(hour: Int, minute: Int) -> Date? {
        // Anchored to today: `DateComponents` without a date yields year 1, which formats as empty.
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
    }

    /// `Date.formatted` resolves to an empty string in some headless environments, so the labels are
    /// produced by an explicit formatter that honours the user's 12/24-hour preference.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
