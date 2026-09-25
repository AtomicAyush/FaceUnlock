import SwiftUI

/// The enrollment window: live preview, a capture button, progress dots, and a
/// save/finish control. Kept deliberately plain — it is the only real UI in v1.
struct EnrollmentView: View {
    @ObservedObject var model: EnrollmentModel

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.9))
                CameraPreview(session: model.previewSession)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if model.faceInFrame {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green, lineWidth: 3)
                        .padding(2)
                }
            }
            .frame(height: 300)

            HStack(spacing: 8) {
                ForEach(0..<model.targetSamples, id: \.self) { i in
                    Circle()
                        .fill(i < model.sampleCount ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 12, height: 12)
                }
            }

            Text(model.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
                .padding(.horizontal)

            HStack {
                Button("Reset", action: model.reset)
                    .disabled(model.sampleCount == 0)

                Spacer()

                if model.isComplete {
                    Button(model.isSaved ? "Saved ✓" : "Save", action: model.save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.isSaved)
                } else {
                    Button("Capture", action: model.captureSample)
                        .keyboardShortcut(.space, modifiers: [])
                        .disabled(!model.canCapture)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 420)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}
