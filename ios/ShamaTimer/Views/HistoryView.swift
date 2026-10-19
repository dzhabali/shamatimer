import SwiftUI
import SwiftData

struct HistoryView: View {
    @EnvironmentObject private var sync: SyncEngine
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var healthExport: HealthExporter
    @Query(filter: #Predicate<Session> { $0.pendingDelete == false },
           sort: \Session.date, order: .reverse)
    private var sessions: [Session]

    @State private var selected: Session?
    @State private var adding = false
    @State private var toDelete: Session?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.bottom, 20)
                if !sessions.isEmpty {
                    summary.padding(.bottom, 16)
                }
                Text(syncText)
                    .font(Theme.ui(10))
                    .tracking(0.6)
                    .foregroundStyle(Theme.text3)
                    .frame(minHeight: 14, alignment: .leading)
                    .padding(.bottom, healthText.isEmpty ? 16 : 4)
                if !healthText.isEmpty {
                    HStack(spacing: 10) {
                        Text(healthText)
                            .font(Theme.ui(10))
                            .tracking(0.6)
                            .foregroundStyle(Theme.text3)
                        if healthExport.status == .noAccess {
                            Button("Connect Health") { env.health.requestAuthorizationIfNeeded() }
                                .font(Theme.ui(10))
                                .tracking(0.6)
                                .foregroundStyle(Theme.accent)
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 16)
                }
                if sessions.isEmpty {
                    empty
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(sessions.filter { !$0.isDeleted }) { s in
                            SessionRow(session: s)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = s }
                                .contextMenu {
                                    Button(role: .destructive) { toDelete = s } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .refreshable { await sync.sync() }
        .onChange(of: sessions.count) { _, _ in
            // синк удалил выбранную запись — закрыть лист
            if let s = selected, s.isDeleted || s.modelContext == nil { selected = nil }
        }
        .sheet(item: $selected) { s in
            SessionDetailSheet(session: s)
        }
        .sheet(isPresented: $adding) {
            AddSessionSheet()
        }
        .confirmationDialog("Delete this session?", isPresented: Binding(
            get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let s = toDelete, !s.isDeleted, s.modelContext != nil { env.store.delete(s) }
                toDelete = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("History")
                .font(Theme.serifItalic(28))
                .foregroundStyle(Theme.text)
            Spacer()
            if !sessions.isEmpty {
                Text("\(sessions.count) sessions")
                    .font(Theme.ui(11))
                    .tracking(0.9)
                    .foregroundStyle(Theme.text3)
            }
            Button { adding = true } label: {
                Text("+")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)
            .accessibilityLabel("Add session")
        }
    }

    private var summary: some View {
        let total = ShamaStats.totalTime(seconds: sessions.reduce(0) { $0 + $1.durationSec })
        let streak = ShamaStats.streak(dates: sessions.map(\.date), today: Date(), calendar: .current)
        return HStack(spacing: 10) {
            summaryCard("Total time", total.value, total.unit)
            summaryCard("Day streak", "\(streak)", " days")
        }
    }

    private func summaryCard(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CapsLabel(label, tracking: 0.12)
            (Text(value).font(Theme.serif(26)).foregroundColor(Theme.text)
             + Text(unit).font(Theme.ui(14)).foregroundColor(Theme.text3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .card()
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Text("◯").font(.system(size: 32)).opacity(0.4)
            Text("No sessions yet").font(Theme.ui(13)).tracking(0.8)
        }
        .foregroundStyle(Theme.text3)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var healthText: String {
        switch healthExport.status {
        case .unknown, .unavailable: return ""
        case .noAccess: return "Health: no access"
        case .sent(let d): return "Health → Life: " + d.formatted(date: .abbreviated, time: .shortened)
        }
    }

    private var syncText: String {
        switch sync.status {
        case .idle: return ""
        case .syncing: return "Syncing…"
        case .synced: return "✓ Synced"
        case .offline: return "Offline — showing local data"
        }
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(Formatters.dayLine.string(from: session.date))
                    if session.hasNote { Text("✎").foregroundStyle(Theme.text2) }
                }
                .font(Theme.ui(12))
                .tracking(0.5)
                .foregroundStyle(Theme.text3)
                Text("\(Formatters.time.string(from: session.date)) — \(Formatters.time.string(from: session.endDate))")
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.text3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                (Text("\(ShamaStats.minutes(session.durationSec)) ").font(Theme.serif(22)).foregroundColor(Theme.text)
                 + Text("min").font(Theme.ui(13)).foregroundColor(Theme.text3))
                CapsLabel(session.complete ? "complete" : "partial",
                          color: session.complete ? Theme.accent : Theme.danger.opacity(0.7), tracking: 0.08)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .card(radius: 10, border: session.complete ? Theme.border : Theme.danger.opacity(0.12))
    }
}
