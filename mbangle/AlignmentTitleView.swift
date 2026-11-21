import SwiftUI

/// Quiet, momentary feedback, confined to the glyphs of the existing heading.
struct AlignmentTitleView: View {
    @ObservedObject var alignment: AlignmentStore
    var compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: some View {
        Text("MacBook Air 15″")
            .font(.system(size: compact ? 35 : 42, weight: .bold))
            .tracking(-1.4)
    }

    private var tint: Color {
        // Blending over the dark title keeps both states restrained and legible.
        alignment.isOnTarget
            ? Color(red: 0.20, green: 0.56, blue: 0.35)
            : Color(red: 0.70, green: 0.25, blue: 0.25)
    }

    var body: some View {
        title
            .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.12))
            .overlay {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(tint.opacity(0.62))
                        .frame(width: geometry.size.width * alignment.titleFillFraction)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .mask(title)
                // Fade out on release instead of sweeping backward across text.
                .opacity(alignment.isPeeking && alignment.hasReading ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: alignment.titleFillFraction)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: alignment.isOnTarget)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: alignment.isPeeking)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("MacBook Air 15-inch")
            .accessibilityValue(alignment.isPeeking ? alignment.correction : "")
            .accessibilityIdentifier("alignment-title")
    }
}
