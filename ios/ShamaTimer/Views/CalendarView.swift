import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query(filter: #Predicate<Session> { $0.pendingDelete == false })
    private var sessions: [Session]

    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = Calendar.current.component(.month, from: Date())

    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7) + [GridItem(.fixed(28), spacing: 4)]
    }

    var body: some View {
        let cal = Calendar.current
        let byDay = ShamaStats.secondsByDay(sessions.map { ($0.date, $0.durationSec) }, calendar: cal)
        let grid = ShamaStats.monthGrid(year: year, month: month, byDay: byDay, today: Date(), calendar: cal)

        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    arrow("‹") { shift(-1) }
                    Spacer()
                    Text(monthTitle).font(Theme.serifItalic(22)).foregroundStyle(Theme.text)
                    Spacer()
                    arrow("›") { shift(1) }
                }
                .padding(.bottom, 16)

                HStack(alignment: .firstTextBaseline) {
                    CapsLabel("avg per active day", tracking: 0.12)
                    Spacer()
                    (Text(grid.average > 0 ? "\(grid.average) " : "— ").font(Theme.serif(26)).foregroundColor(Theme.text)
                     + Text("min").font(Theme.ui(13)).foregroundColor(Theme.text3))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .card()
                .padding(.bottom, 18)

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(weekdays, id: \.self) { CapsLabel($0, size: 9, tracking: 0.12) }
                    CapsLabel("wk", size: 9, tracking: 0.12)
                }
                .padding(.bottom, 6)

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                        ForEach(0..<7, id: \.self) { i in
                            DayCell(cell: week.cells[i])
                        }
                        Text(week.average > 0 ? "\(week.average)" : "—")
                            .font(Theme.serif(13))
                            .foregroundStyle(Theme.weekAvg)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private var monthTitle: String {
        var c = DateComponents(); c.year = year; c.month = month; c.day = 1
        return Calendar.current.date(from: c).map { Formatters.month.string(from: $0) } ?? ""
    }

    private func shift(_ delta: Int) {
        month += delta
        if month < 1 { month = 12; year -= 1 }
        if month > 12 { month = 1; year += 1 }
    }

    private func arrow(_ s: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(s)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.text2)
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct DayCell: View {
    let cell: ShamaStats.Cell?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        ZStack {
            if let c = cell {
                shape.fill(Theme.accent.opacity(ShamaStats.levelAlpha[c.level]))
                shape.stroke(c.isToday ? Theme.accent.opacity(0.55) : Theme.border, lineWidth: 1)
                VStack(spacing: 2) {
                    Text("\(c.day)")
                        .font(Theme.ui(10))
                        .foregroundStyle(c.level == 5 ? Theme.text2 : Theme.text3)
                    if c.level > 0 {
                        Text("\(c.minutes)")
                            .font(Theme.serif(14))
                            .foregroundStyle(c.level >= 4 ? Theme.text : Theme.text2)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
