import SwiftUI
import AppKit

private enum ShowcaseStyle {
    static let background = Color(red: 0.95, green: 0.95, blue: 0.95)
    static let ink = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let secondary = Color(red: 0.43, green: 0.43, blue: 0.45)
}

/// The reference is rebuilt as native views. Only the laptop photography is
/// sampled from the supplied image; text, cards, sheets and controls are native.
struct ShowcaseView: View {
    @ObservedObject var alignment: AlignmentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detail: ShowcaseDetail?
    @State private var hoveringHandle = false
    @FocusState private var handleFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                ShowcaseStyle.background
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header(compact: geometry.size.width < 1000)
                        productCards(height: min(410, max(320, geometry.size.width * 0.325)))
                        footer
                    }
                    .frame(maxWidth: 1030)
                    .padding(.horizontal, geometry.size.width < 1000 ? 44 : 70)
                    .padding(.top, geometry.size.height < 720 ? 48 : 72)
                    .padding(.bottom, 76)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .disabled(alignment.isExpanded)
                .accessibilityHidden(alignment.isExpanded)

                if alignment.isExpanded {
                    Color.black.opacity(0.035)
                        .contentShape(Rectangle())
                        .onTapGesture { alignment.hide() }
                        .accessibilityHidden(true)
                    AlignmentTray(alignment: alignment)
                        .frame(width: min(600, geometry.size.width - 48))
                        .padding(.bottom, 18)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                } else {
                    Button { alignment.show() } label: {
                        Capsule()
                            .fill(ShowcaseStyle.ink.opacity(hoveringHandle ? 0.44 : 0.22))
                            .frame(width: hoveringHandle ? 68 : 48, height: 4)
                            .frame(width: 112, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focused($handleFocused)
                    .onHover { hoveringHandle = $0 }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hoveringHandle)
                    .accessibilityLabel("Show alignment controls")
                    .accessibilityIdentifier("alignment-reveal")
                    .help("Show alignment controls · ⌃⌥⇧L")
                    .opacity(alignment.isPeeking ? 1 : 0)
                    .disabled(!alignment.isPeeking)
                    .accessibilityHidden(!alignment.isPeeking)
                    .padding(.bottom, 6)
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.86), value: alignment.isExpanded)
            .clipped()
        }
        .foregroundStyle(ShowcaseStyle.ink)
        .background(ShowcaseWindowSetup())
        .sheet(item: $detail) { selected in
            ShowcaseDetailSheet(detail: selected)
        }
        .onDisappear { alignment.dismiss() }
        .onChange(of: detail) { _, selected in
            if selected != nil { alignment.dismiss() }
        }
        .onChange(of: alignment.isExpanded) { _, expanded in
            handleFocused = !expanded
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 5) {
                AlignmentTitleView(alignment: alignment, compact: compact)
                Text("M5 chip")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ShowcaseStyle.secondary)
                HStack(spacing: 6) {
                    ForEach(Array([Color(red: 0.72, green: 0.80, blue: 0.83), Color(red: 0.87, green: 0.87, blue: 0.87), Color(red: 0.89, green: 0.85, blue: 0.76), Color(red: 0.18, green: 0.20, blue: 0.24)].enumerated()), id: \.offset) { _, color in
                        Circle().fill(color)
                            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.75))
                            .frame(width: 11, height: 11)
                    }
                }
                .padding(.top, 9)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Finishes: sky blue, silver, starlight, midnight")
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text("From $1,499 or $124.91/mo. for 12 mo.ᴬ")
                Text("Lease from $28.99/mo.\nfor 36 mo. with Apple Upgrade^")
            }
            .font(.system(size: compact ? 16 : 19, weight: .semibold))
            .foregroundStyle(Color(white: 0.28))
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: compact ? 302 : 350, alignment: .leading)
            .padding(.top, 6)
        }
    }

    private func productCards(height: CGFloat) -> some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 850
            HStack(spacing: 22) {
                Button { detail = .pricing } label: {
                    VStack(spacing: 0) {
                        Spacer(minLength: 10)
                        ReferenceLaptopView()
                            .frame(maxWidth: 410)
                            .padding(.horizontal, compact ? 24 : 50)
                        Spacer(minLength: 10)
                        HStack {
                            Text("See pricing & offers")
                                .font(.system(size: compact ? 20 : 24, weight: .bold))
                                .tracking(-0.6)
                            Spacer()
                            CardArrow()
                        }
                    }
                    .padding(compact ? 18 : 26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .showcaseCard()
                }
                .buttonStyle(ShowcaseCardButtonStyle())
                .accessibilityIdentifier("pricing-card")
                .frame(width: (geometry.size.width - 22) * 0.67)

                VStack(spacing: 22) {
                    Button { detail = .compare } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Spacer(minLength: 0)
                            Image(systemName: "desktopcomputer.and.macbook")
                                .font(.system(size: compact ? 29 : 33, weight: .regular))
                                .accessibilityHidden(true)
                            HStack(alignment: .bottom) {
                                Text("Compare models")
                                    .font(.system(size: compact ? 17 : 20, weight: .bold))
                                    .tracking(-0.5)
                                Spacer(minLength: 2)
                                CardArrow()
                            }
                        }
                        .padding(compact ? 18 : 26)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .showcaseCard()
                    }
                    .buttonStyle(ShowcaseCardButtonStyle())
                    .accessibilityIdentifier("compare-card")

                    Button { detail = .upgrade } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Spacer(minLength: 0)
                            HStack(spacing: 1) {
                                Image(systemName: "apple.logo")
                                Text("Upgrade").tracking(-1.4)
                            }
                            .font(.system(size: compact ? 24 : 31, weight: .medium))
                            .foregroundStyle(LinearGradient(colors: [Color(red: 0.45, green: 0.13, blue: 0.73), .pink, Color(red: 0.79, green: 0.05, blue: 0.04)], startPoint: .leading, endPoint: .trailing))
                            HStack(alignment: .bottom) {
                                Text("Discover a new way to get your Mac")
                                    .font(.system(size: compact ? 16 : 19, weight: .bold))
                                    .tracking(-0.5)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 2)
                                CardArrow()
                            }
                        }
                        .padding(compact ? 18 : 26)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .showcaseCard()
                    }
                    .buttonStyle(ShowcaseCardButtonStyle())
                    .accessibilityIdentifier("upgrade-card")
                }
            }
        }
        .frame(height: height)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button { detail = .disclaimers } label: {
                Text("◊ See disclaimers")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.0, green: 0.37, blue: 0.73))
            }
            .buttonStyle(.plain)
            Divider().overlay(.black.opacity(0.02))
            Text("^ Apple Upgrade Lease: This offer is for a consumer lease, not a purchase or loan. Lease provided by Klarna. 12-, 24-, or 36-month terms. Your first monthly payment is due approximately 30 days after device is shipped or available for pickup. Lease approval is subject to eligibility and is based on creditworthiness. Monthly payments are based on the selected device and lease term.")
                .font(.system(size: 11))
                .foregroundStyle(ShowcaseStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
    }
}

/// A view crop keeps the original attachment intact. Replace this view's asset
/// with dedicated product photography when it is available.
private struct ReferenceLaptopView: View {
    private let crop = CGRect(x: 270, y: 290, width: 400, height: 270)
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / crop.width
            Image("ShowcaseReference")
                .resizable()
                .interpolation(.high)
                .frame(width: 1280 * scale, height: 806 * scale)
                .offset(x: -crop.minX * scale, y: -crop.minY * scale)
        }
        .aspectRatio(crop.width / crop.height, contentMode: .fit)
        .clipped()
        .accessibilityLabel("MacBook Air with a gold abstract wallpaper")
    }
}

private struct CardArrow: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ShowcaseStyle.secondary)
            .frame(width: 30, height: 30)
            .background(Color(white: 0.96), in: Circle())
            .accessibilityHidden(true)
    }
}

private extension View {
    func showcaseCard() -> some View {
        self.background(.white, in: RoundedRectangle(cornerRadius: 29, style: .continuous))
            .compositingGroup()
            .shadow(color: .black.opacity(0.10), radius: 9, x: 0, y: 5)
            .shadow(color: .black.opacity(0.035), radius: 2, x: 0, y: 0)
            .contentShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
    }
}

private struct ShowcaseCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct AlignmentTray: View {
    @ObservedObject var alignment: AlignmentStore
    @FocusState private var closeFocused: Bool

    private var statusColor: Color {
        alignment.angle == nil ? ShowcaseStyle.secondary : (alignment.isOnTarget ? Color(red: 0.12, green: 0.48, blue: 0.29) : ShowcaseStyle.ink)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button { alignment.hide() } label: {
                Capsule().fill(.black.opacity(0.18))
                    .frame(width: 36, height: 4)
                    .frame(width: 90, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($closeFocused)
            .accessibilityLabel("Hide alignment controls")
            .accessibilityIdentifier("alignment-hide")

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LID ANGLE")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(ShowcaseStyle.secondary)
                    Text(alignment.angle.map { String(format: "%.1f°", $0) } ?? "—")
                        .font(.system(size: 38, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(statusColor)
                        .accessibilityIdentifier("live-angle")
                }
                .frame(width: 140, alignment: .leading)

                VStack(alignment: .leading, spacing: 13) {
                    Label(alignment.correction, systemImage: alignment.angle == nil ? "waveform.slash" : alignment.isOnTarget ? "checkmark.circle.fill" : (alignment.angle ?? 0) > alignment.target ? "arrow.up" : "arrow.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("alignment-status")
                    AlignmentScale(angle: alignment.angle, target: alignment.target, tolerance: alignment.tolerance, onTarget: alignment.isOnTarget)
                        .frame(height: 12)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 8) {
                    Text("TARGET")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(ShowcaseStyle.secondary)
                    HStack(spacing: 8) {
                        adjustButton(symbol: "minus", label: "Decrease target angle", step: -0.1)
                        Text(String(format: "%.1f°", alignment.target))
                            .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                            .frame(minWidth: 66)
                            .accessibilityIdentifier("target-angle")
                        adjustButton(symbol: "plus", label: "Increase target angle", step: 0.1)
                    }
                    Button("Set current angle") { alignment.setCurrentAsTarget() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(alignment.hasReading ? Color.accentColor : ShowcaseStyle.secondary)
                        .disabled(!alignment.hasReading)
                        .accessibilityIdentifier("set-current-angle")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 2)
            .padding(.bottom, 20)

            Divider().opacity(0.55)
            HStack {
                Text("C set target   ·   ↑↓ adjust   ·   ⇧ for 1°")
                Spacer()
                Button("Done") { alignment.hide() }
                    .buttonStyle(.plain)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("alignment-done")
                Text("esc").foregroundStyle(ShowcaseStyle.secondary.opacity(0.7))
            }
            .font(.system(size: 11))
            .foregroundStyle(ShowcaseStyle.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 24, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lid alignment")
        .accessibilityIdentifier("alignment-tray")
        .onAppear { closeFocused = true }
    }

    private func adjustButton(symbol: String, label: String, step: Double) -> some View {
        Button { alignment.adjustTarget(by: step) } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 24, height: 24)
                .background(.black.opacity(0.045), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct AlignmentScale: View {
    var angle: Double?
    var target: Double
    var tolerance: Double
    var onTarget: Bool
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                Capsule().fill(.black.opacity(0.08)).frame(height: 3)
                Capsule().fill(Color.green.opacity(0.18))
                    .frame(width: min(width, max(8, width * tolerance / 5)), height: 7)
                Rectangle().fill(.black.opacity(0.25)).frame(width: 1, height: 12)
                if let angle {
                    Circle().fill(onTarget ? Color(red: 0.12, green: 0.48, blue: 0.29) : ShowcaseStyle.ink)
                        .frame(width: 7, height: 7)
                        .offset(x: CGFloat(min(5, max(-5, angle - target))) / 10 * (width - 8))
                }
            }
            .frame(width: width, height: geometry.size.height)
        }
    }
}

private enum ShowcaseDetail: String, Identifiable {
    case pricing, compare, upgrade, disclaimers
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pricing: "Pricing & offers"
        case .compare: "Compare models"
        case .upgrade: "Apple Upgrade"
        case .disclaimers: "Disclaimers"
        }
    }
}

private struct ShowcaseDetailSheet: View {
    let detail: ShowcaseDetail
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(detail.title).font(.system(size: 28, weight: .bold)).tracking(-0.8)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close details")
            }
            switch detail {
            case .pricing:
                Text("MacBook Air 15″ · M5 chip").font(.headline).foregroundStyle(.secondary)
                Text("From $1,499").font(.system(size: 38, weight: .semibold))
                Text("Or $124.91/mo. for 12 months.ᴬ")
                Divider()
                Text("Apple Upgrade").font(.headline)
                Text("Lease from $28.99/mo. for 36 months.^")
            case .compare:
                HStack(alignment: .top, spacing: 30) {
                    modelOption(size: "13″", caption: "A smaller footprint.")
                    modelOption(size: "15″", caption: "More room for what you love.")
                }
            case .upgrade:
                Text("Discover a new way to get your Mac.").font(.title2.weight(.semibold))
                Text("Lease from $28.99/mo. for 36 months.^").font(.title3)
                Text("12-, 24-, or 36-month lease terms. Lease provided by Klarna.")
                Text("This offer is for a consumer lease, not a purchase or loan.").foregroundStyle(.secondary)
            case .disclaimers:
                Text("Apple Upgrade Lease").font(.headline)
                Text("This offer is for a consumer lease, not a purchase or loan. Lease provided by Klarna. 12-, 24-, or 36-month terms. Your first monthly payment is due approximately 30 days after device is shipped or available for pickup. Lease approval is subject to eligibility and is based on creditworthiness. Monthly payments are based on the selected device and lease term.")
                    .foregroundStyle(.secondary)
                Text("Pricing and offers shown are from the supplied showcase reference.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(36)
        .frame(width: 560)
        .background(ShowcaseStyle.background)
    }

    private func modelOption(size: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "laptopcomputer").font(.system(size: size == "15″" ? 62 : 52, weight: .ultraLight))
                .frame(height: 75, alignment: .bottom)
            Text("MacBook Air \(size)").font(.headline)
            Text(caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShowcaseWindowSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.identifier = NSUserInterfaceItemIdentifier("mbangle-showcase")
            window?.title = "MacBook Air"
            window?.backgroundColor = NSColor(white: 0.95, alpha: 1)
            window?.titlebarAppearsTransparent = true
        }
    }
}
