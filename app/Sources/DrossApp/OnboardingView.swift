import SwiftUI

/// Sequential onboarding — one step at a time, datasheet chrome.
/// 1 appears left → exits → 2 appears middle → exits → 3 appears right → finish.
struct OnboardingView: View {
    let name: String
    var onFinish: (OnboardingAnswers) -> Void

    @State private var step: Int = 1
    @State private var problems: Set<String> = []
    @State private var source: String?
    @State private var building: String?

    private let pageBackground = Theme.bone

    private let problemOptions: [(id: String, label: String)] = [
        ("drift", "App and API disagree"),
        ("dead", "Dead code still ships"),
        ("demo", "Demo data in production"),
        ("env", "Env keys missing at deploy"),
        ("main", "Ship to main with no review"),
    ]

    private let sourceOptions: [(id: String, label: String)] = [
        ("friend", "Friend / teammate"),
        ("x", "X / Twitter"),
        ("bip", "Build-in-public / blog"),
        ("cursor", "Cursor / AI tooling"),
        ("other", "Other"),
    ]

    private let buildingOptions: [(id: String, label: String)] = [
        ("solo", "Solo side project"),
        ("startup", "Startup MVP"),
        ("client", "Client work"),
        ("oss", "Open source"),
    ]

    private var canAdvance: Bool {
        switch step {
        case 1: return !problems.isEmpty
        case 2: return source != nil
        case 3: return building != nil
        default: return false
        }
    }

    var body: some View {
        GeometryReader { geo in
            let colW = min(420, geo.size.width * 0.42)

            VStack(spacing: 0) {
                CheckerStrip(cell: 7)
                metaBar
                Rectangle().fill(Theme.ink).frame(height: 1)

                HStack(alignment: .top, spacing: 0) {
                    SpineLabel(text: "Onboarding protocol")
                        .frame(width: 36)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .trailing) { Rectangle().fill(Theme.ink).frame(width: 1) }

                    ZStack {
                        if step == 1 {
                            stepPanel(
                                index: 1,
                                title: "Why Dross?",
                                subtitle: "COMMON PROBLEMS — PICK WHAT HITS YOU.",
                                hint: "SELECT ALL THAT APPLY",
                                width: colW
                            ) {
                                ForEach(problemOptions, id: \.id) { opt in
                                    choiceRow(
                                        label: opt.label,
                                        selected: problems.contains(opt.id)
                                    ) {
                                        toggleProblem(opt.id)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .padding(.leading, 28)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .leading)),
                                removal: .opacity.combined(with: .move(edge: .leading))
                            ))
                        }

                        if step == 2 {
                            stepPanel(
                                index: 2,
                                title: "How’d you find us?",
                                subtitle: "ONE SOURCE IS ENOUGH.",
                                hint: nil,
                                width: colW
                            ) {
                                ForEach(sourceOptions, id: \.id) { opt in
                                    choiceRow(
                                        label: opt.label,
                                        selected: source == opt.id
                                    ) {
                                        source = opt.id
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                removal: .opacity.combined(with: .move(edge: .bottom))
                            ))
                        }

                        if step == 3 {
                            stepPanel(
                                index: 3,
                                title: "What are you building?",
                                subtitle: "SO WE KNOW WHAT “SHIP” MEANS FOR YOU.",
                                hint: nil,
                                width: colW
                            ) {
                                ForEach(buildingOptions, id: \.id) { opt in
                                    choiceRow(
                                        label: opt.label,
                                        selected: building == opt.id
                                    ) {
                                        building = opt.id
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .padding(.trailing, 28)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity
                            ))
                        }
                    }
                    .animation(.spring(response: 0.45, dampingFraction: 0.88), value: step)

                    SpineLabel(text: "Limitations: none registered")
                        .frame(width: 28)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.ink).frame(width: 1) }
                }
                .frame(maxHeight: .infinity)

                Rectangle().fill(Theme.ink).frame(height: 1)
                footer
            }
            .background(PageGrain())
        }
        .frame(minWidth: 880, minHeight: 560)
    }

    private var metaBar: some View {
        HStack(spacing: 16) {
            Text("TYPE: SETUP / ONBOARDING")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.ink)
            Text("·")
                .foregroundStyle(Theme.inkAlpha(0.35))
            Text(name.uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            Text("STEP \(step) / 3")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.ink)
            InkBadge(text: step == 3 ? "Final" : "In motion")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 16) {
            HatchBar(filled: step, total: 3, color: Theme.ink, height: 8)
                .frame(width: 120)
            if step > 1 {
                Button(action: goBack) {
                    Text("← BACK")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button(action: advance) {
                Text(step == 3 ? "CONTINUE" : "NEXT")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(canAdvance ? pageBackground : Theme.inkAlpha(0.35))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(canAdvance ? Theme.ink : Theme.inkAlpha(0.08))
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func stepPanel<Content: View>(
        index: Int,
        title: String,
        subtitle: String,
        hint: String?,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hi \(name).")
                .font(.system(size: 32, weight: .bold, design: .default))
                .tracking(-0.8)
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 10)
            Text("SCAN / FIX / VERIFY / COMMIT")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(Theme.inkAlpha(0.55))
            Text(">>>>>>>>>>>>>>>>")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 18)

            specHeader("STEP \(index)", extra: title.uppercased())
            Text(subtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.inkAlpha(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))

            if let hint {
                Text(hint)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkAlpha(0.4))
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 24)
        .frame(width: width, alignment: .leading)
    }

    private func specHeader(_ left: String, extra: String) -> some View {
        HStack {
            Text(left)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Theme.bone)
            Spacer()
            Text(extra)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.bone.opacity(0.75))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.ink)
    }

    private func choiceRow(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(selected ? "[●]" : "[  ]")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkAlpha(0.4))
                Text(label.uppercased())
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(selected ? Theme.ink : Theme.inkAlpha(0.55))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if selected {
                    Text("ON")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Theme.ink)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(selected ? Theme.ink.opacity(0.06) : Color.clear)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleProblem(_ id: String) {
        if problems.contains(id) { problems.remove(id) }
        else { problems.insert(id) }
    }

    private func advance() {
        guard canAdvance else { return }
        if step < 3 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                step += 1
            }
        } else if let source, let building {
            onFinish(OnboardingAnswers(
                problems: Array(problems).sorted(),
                source: source,
                building: building
            ))
        }
    }

    private func goBack() {
        guard step > 1 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            step -= 1
        }
    }
}

struct OnboardingAnswers: Equatable {
    var problems: [String]
    var source: String
    var building: String
}

#Preview {
    OnboardingView(name: "Arnau", onFinish: { _ in })
        .frame(width: 1100, height: 700)
}
