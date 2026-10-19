import SwiftUI

struct TimerView: View {
    @EnvironmentObject private var timer: TimerController

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            OrbView()
                .padding(.bottom, timer.isDimmed ? 0 : 32)
            if timer.active == nil {
                durationSection
                    .padding(.bottom, 28)
            }
            controls
            Spacer(minLength: 0)
        }
        .padding(24)
        .animation(.easeInOut(duration: 0.4), value: timer.active == nil)
    }

    private var durationSection: some View {
        VStack(spacing: 0) {
            CapsLabel("duration")
                .padding(.bottom, 14)
            HStack(spacing: 6) {
                ForEach(TimerController.presets, id: \.self) { m in
                    let on = timer.totalMinutes == m
                    Button { timer.setPreset(m) } label: {
                        Text("\(m)")
                            .font(Theme.ui(12))
                            .foregroundStyle(on ? Theme.accent2 : Theme.text2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(on ? Theme.accent.opacity(0.12) : Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(on ? Theme.accent.opacity(0.35) : Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 16)
            HStack(spacing: 12) {
                adjustButton("−", -5)
                Text("\(timer.totalMinutes)")
                    .font(Theme.serif(28))
                    .foregroundStyle(Theme.text)
                    .frame(minWidth: 80)
                    .monospacedDigit()
                adjustButton("+", 5)
            }
        }
        .frame(maxWidth: 340)
        .opacity(timer.isDimmed ? 0 : 1)
    }

    private func adjustButton(_ label: String, _ delta: Int) -> some View {
        Button { timer.adjust(delta) } label: {
            Text(label)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.text2)
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button { timer.playTapped() } label: {
                Image(systemName: timer.playIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent2)
                    .frame(width: 64, height: 64)
                    .background(Theme.accent.opacity(0.1), in: Circle())
                    .overlay(Circle().stroke(Theme.accent.opacity(0.25), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScale())
            .opacity(timer.mode == .stopwatch ? 0.35 : 1)

            if timer.active != nil {
                Button { timer.finishTapped() } label: {
                    Text("finish")
                        .font(Theme.ui(13))
                        .tracking(0.8)
                        .foregroundStyle(Theme.text3)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .opacity(timer.isDimmed ? 0 : 1)
                .allowsHitTesting(!timer.isDimmed)
            }
        }
        .padding(.bottom, 24)
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

struct OrbView: View {
    @EnvironmentObject private var timer: TimerController
    @State private var breathe = false

    private let size: CGFloat = 220

    var body: some View {
        let running = timer.isRunning
        ZStack {
            Circle()
                .stroke(Theme.accent.opacity(0.08), lineWidth: 2)
                .frame(width: size + 20, height: size + 20)
            Circle()
                .trim(from: 0, to: timer.ringFraction)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .opacity(0.7)
                .rotationEffect(.degrees(-90))
                .frame(width: size + 20, height: size + 20)
                .animation(.linear(duration: 0.25), value: timer.ringFraction)

            Circle()
                .fill(RadialGradient(stops: [
                    .init(color: Color(hex: 0x2a3d2a), location: 0),
                    .init(color: Color(hex: 0x141a14), location: 0.6),
                    .init(color: Color(hex: 0x0d110d), location: 1),
                ], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.62))
                .overlay(Circle().stroke(Theme.accent.opacity(0.1), lineWidth: 1))
                .shadow(color: Theme.accent.opacity(running ? (breathe ? 0.22 : 0.15) : 0.08),
                        radius: running ? (breathe ? 50 : 40) : 30)
                .shadow(color: Theme.accent.opacity(running ? (breathe ? 0.10 : 0.07) : 0.04),
                        radius: running ? (breathe ? 100 : 80) : 60)
                .frame(width: size, height: size)

            VStack(spacing: 6) {
                Text(timer.displayText)
                    .font(Theme.serif(52))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !timer.orbLabel.isEmpty {
                    CapsLabel(timer.orbLabel, tracking: 0.16)
                }
            }
        }
        .frame(width: size + 20, height: size + 20)
        .contentShape(Circle())
        .onTapGesture { timer.orbTapped() }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Stopwatch")
    }
}
