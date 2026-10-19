import SwiftUI

struct SessionDetailSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let session: Session
    @State private var note = ""
    @State private var confirmDelete = false

    var body: some View {
        if session.isDeleted || session.modelContext == nil {
            // запись удалил синк (удалена в вебе), пока лист был открыт — не трогаем её поля
            Color.clear.onAppear { dismiss() }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            sheetHeader(title: "Session", cancel: "Close", confirm: "Save") {
                if !session.isDeleted, session.modelContext != nil {
                    env.store.setNote(session, note: note)
                }
                dismiss()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(Formatters.dayLineYear.string(from: session.date))
                Text(meta)
            }
            .font(Theme.ui(13))
            .foregroundStyle(Theme.text2)

            CapsLabel("Note")
            TextEditor(text: $note)
                .font(Theme.ui(14))
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 140)
                .card(radius: 8)
                .overlay(alignment: .topLeading) {
                    if note.isEmpty {
                        Text("Add a note to this session…")
                            .font(Theme.ui(14))
                            .foregroundStyle(Theme.text3)
                            .padding(.horizontal, 15).padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            Button(role: .destructive) { confirmDelete = true } label: {
                CapsLabel("Delete session", size: 11, color: Theme.danger, tracking: 0.1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.danger.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(24)
        .background(Theme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear { note = session.note ?? "" }
        .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if !session.isDeleted, session.modelContext != nil { env.store.delete(session) }
                dismiss()
            }
        }
    }

    private var meta: String {
        var s = "\(Formatters.time.string(from: session.date)) — \(Formatters.time.string(from: session.endDate))"
            + " · \(ShamaStats.minutes(session.durationSec)) min"
        if let a = session.activity, !a.isEmpty, a.lowercased() != "meditation" { s += " · \(a)" }
        return s
    }
}

struct AddSessionSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()
    @State private var minutes = ""
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sheetHeader(title: "Add session", cancel: "Cancel", confirm: "Save", action: save)
            CapsLabel("Date")
            DatePicker("Date", selection: $day, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.graphical)
                .tint(Theme.accent)
            CapsLabel("Minutes")
            TextField("", text: $minutes, prompt: Text("e.g. 45").foregroundColor(Theme.text3))
                .font(Theme.ui(14))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .card(radius: 8)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Text(error).font(Theme.ui(12)).foregroundStyle(Theme.danger)
            Spacer()
        }
        .padding(24)
        .background(Theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func save() {
        guard let m = Int(minutes.trimmingCharacters(in: .whitespaces)), m > 0, m <= 600 else {
            error = "Enter date and minutes"
            return
        }
        env.store.addManual(day: day, minutes: m)
        env.timer.toast = "Session added"
        dismiss()
    }
}

extension View {
    func sheetHeader(title: String, cancel: String, confirm: String, action: @escaping () -> Void) -> some View {
        SheetHeader(title: title, cancel: cancel, confirm: confirm, action: action)
    }
}

private struct SheetHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String, cancel: String, confirm: String
    let action: () -> Void

    var body: some View {
        HStack {
            Button { dismiss() } label: { CapsLabel(cancel, size: 11, color: Theme.text3, tracking: 0.1) }
                .buttonStyle(.plain)
            Spacer()
            Text(title).font(Theme.serifItalic(24)).foregroundStyle(Theme.text)
            Spacer()
            Button(action: action) { CapsLabel(confirm, size: 11, color: Theme.accent2, tracking: 0.1) }
                .buttonStyle(.plain)
        }
    }
}
