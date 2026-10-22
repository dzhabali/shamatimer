import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query(filter: #Predicate<Session> { $0.pendingDelete == false })
    private var sessions: [Session]

    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = Calendar.current.component(.month, from: Date())

    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Строка календаря: 7 равных колонок Пн…Вс + узкая колонка недели (28 pt).
    private func row<Days: View, Trailing: View>(@ViewBuilder _ days: () -> Days,
                                                 @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 4) {
            days()
            trailing().frame(width: 28)
        }
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

                row {
                    ForEach(weekdays, id: \.self) { CapsLabel($0, size: 9, tracking: 0.12).frame(maxWidth: .infinity) }
                } trailing: {
                    CapsLabel("wk", size: 9, tracking: 0.12)
                }
                .padding(.bottom, 6)

                // Обычные строки, не LazyVGrid: там id ячеек 0…6 повторялись в каждой неделе,
                // и сетка рисовала только первую неделю.
                VStack(spacing: 4) {
                    ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                        row {
                            ForEach(0..<7, id: \.self) { i in
                                DayCell(cell: week.cells[i]).frame(maxWidth: .infinity)
                            }
                        } trailing: {
                            Text(week.average > 0 ? "\(week.average)" : "—")
                                .font(Theme.serif(13))
                                .foregroundStyle(Theme.weekAvg)
                        }
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(Theme.border).frame(width: 1).offset(x: -28)
                        }
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
