import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var password = ""
    @State private var error = ""
    @State private var busy = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Shama")
                .font(Theme.serifItalic(40))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 6)
            CapsLabel("meditation timer", tracking: 0.16)
                .padding(.bottom, 40)

            VStack(spacing: 10) {
                SecureField("", text: $password, prompt: Text("Life password").foregroundColor(Theme.text3))
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.text)
                    .textContentType(.password)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .card(radius: 8, border: focused ? Theme.accent.opacity(0.4) : Theme.border)

                Button(action: submit) {
                    Group {
                        if busy { ProgressView().tint(Theme.accent2) } else { CapsLabel("Sign in", size: 12, color: Theme.accent2, tracking: 0.1) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(busy || password.isEmpty)
                .padding(.top, 4)

                Text(error)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.danger)
                    .frame(minHeight: 18)
            }
            .frame(maxWidth: 300)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { focused = true }
    }

    private func submit() {
        guard !busy, !password.isEmpty else { return }
        busy = true
        error = ""
        let pw = password
        Task {
            let err = await auth.signIn(password: pw)
            busy = false
            if let err { error = err } else { password = "" }
        }
    }
}
