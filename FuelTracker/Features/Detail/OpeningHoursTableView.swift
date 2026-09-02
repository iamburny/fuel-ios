import SwiftUI

/// Direct port of `DetailScreen.kt`'s `OpeningHoursTable`. Today's row is computed fresh from the
/// device-local weekday each render (matches `LocalDate.now().dayOfWeek` — not cached from
/// screen-load time).
struct OpeningHoursTableView: View {
    let days: UsualDaysDTO

    private static let weekdaySymbolIndex: [String: Int] = [
        "Sunday": 1, "Monday": 2, "Tuesday": 3, "Wednesday": 4, "Thursday": 5, "Friday": 6, "Saturday": 7,
    ]

    var body: some View {
        let today = Calendar.current.component(.weekday, from: Date())
        VStack(spacing: 0) {
            ForEach(days.asList, id: \.day) { entry in
                let isToday = Self.weekdaySymbolIndex[entry.day] == today
                HStack {
                    Text(entry.day)
                        .fontWeight(isToday ? .bold : .regular)
                    Spacer()
                    Text(hoursText(entry.hours))
                        .fontWeight(isToday ? .bold : .regular)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(isToday ? Color.accentColor.opacity(0.15) : .clear)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func hoursText(_ hours: DayHoursDTO?) -> String {
        guard let hours else { return "—" }
        if hours.is24Hours == true { return "24 hours" }
        if let open = hours.open, let close = hours.close {
            return "\(OpeningHoursFormatter.format(open)) – \(OpeningHoursFormatter.format(close))"
        }
        return "—"
    }
}
