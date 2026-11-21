import SwiftUI

/// Standard macOS settings keep optional cues out of the showcase interface.
struct FeedbackSettingsView: View {
    @ObservedObject var feedback: AlignmentFeedback

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $feedback.soundEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confirmation sound")
                        Text("A quiet tick when the lid reaches its target.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Confirmation sound")
                .accessibilityIdentifier("feedback-sound-toggle")

                Toggle(isOn: $feedback.hapticsEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trackpad tap")
                        Text("Rest a finger on a Force Touch trackpad to feel the tap.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityLabel("Trackpad tap")
                .accessibilityIdentifier("feedback-haptics-toggle")
            } header: {
                Text("Alignment feedback")
            } footer: {
                Text("Sound uses your current audio output and follows its volume and mute setting.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                HStack {
                    Text("Preview the enabled cues.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Try feedback") {
                        feedback.preview()
                    }
                    .disabled(!feedback.isAnyEnabled)
                    .accessibilityIdentifier("feedback-preview")
                }
            }
        }
        .toggleStyle(.switch)
        .formStyle(.grouped)
        .frame(width: 440, height: 300)
    }
}
