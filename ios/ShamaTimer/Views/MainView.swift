import SwiftUI

enum AppTab: String, CaseIterable {
    case timer = "Timer", calendar = "Calendar", history = "History"
}

struct MainView: View {
    @EnvironmentObject private var timer: TimerController
    @EnvironmentObject private var auth: AuthManager
    @State private var tab: AppTab = .timer
    @State private var confirmSignOut = false

    private var dimmed: Bool { timer.isDimmed && tab == .timer }

    var body: some View {
        VStack(spacing: 0) {
            nav
                .opacity(dimmed ? 0 : 1)
                .allowsHitTesting(!dimmed)
            Group {
                switch tab {
                case .timer: TimerView()
                case .calendar: CalendarView()
                case .history: HistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .overlay {
            if dimmed {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { timer.undim() }
            }
        }
        .overlay(alignment: .bottom) {
            if let t = timer.toast {
                Text(t)
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.accent2)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .card(radius: 20)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: dimmed)
        .animation(.easeInOut(duration: 0.3), value: timer.toast)
        .confirmationDialog("Sign out of Life?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { auth.signOut() }
        }
    }

    private var nav: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { t in
                    Button { tab = t } label: {
                        VStack(spacing: 6) {
                            Text(t.rawValue.uppercased())
                                .font(.system(size: 11, weight: .regular))
                                .tracking(11 * 0.12)
                                .foregroundStyle(tab == t ? Theme.accent2 : Theme.text3)
                            Rectangle()
                                .fill(tab == t ? Theme.accent : .clear)
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Text(Self.versionString)
                    .font(Theme.ui(10))
                    .tracking(0.6)
                    .foregroundStyle(Theme.text3.opacity(0.6))
                Spacer()
                Button { confirmSignOut = true } label: {
                    Image(systemName: auth.offline ? "person.crop.circle.badge.exclamationmark" : "person.crop.circle")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(Theme.text3)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Account")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let v = info["CFBundleShortVersionString"] as? String ?? "?"
        let b = info["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }
}
