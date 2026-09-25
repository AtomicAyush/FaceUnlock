import SwiftUI

/// The watching window: a live mirror of the camera with a tracking box over the
/// detected face and a similarity meter, so you can see yourself and watch the
/// model score you in real time. It shows recognition; it takes no action.
struct WatchingView: View {
    @ObservedObject var model: WatchingModel

    private var ringColor: Color {
        if model.isRecognized { return .green }
        if model.facePresent { return .yellow }
        return .gray.opacity(0.5)
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.black)
                CameraPreview(session: model.session, mirrored: true)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                // Tracking box over the detected face.
                GeometryReader { geo in
                    if let box = model.faceBox,
                       let rect = displayedRect(for: box, in: geo.size, aspect: model.imageAspect) {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ringColor, lineWidth: 3)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .animation(.easeOut(duration: 0.12), value: rect)
                    }
                }

                RoundedRectangle(cornerRadius: 14)
                    .stroke(ringColor, lineWidth: model.isRecognized ? 4 : 2)
                    .padding(1)
            }
            .frame(height: 285)

            VStack(spacing: 4) {
                Text(model.headline)
                    .font(.headline)
                    .foregroundStyle(model.isRecognized ? .green : .primary)
                Text(model.awaitingBlink ? "Blink once to confirm you're live" : " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SimilarityMeter(score: model.score, threshold: model.threshold)
                .frame(height: 34)
                .padding(.horizontal, 4)

            Text("Recognition only — nothing happens when you're recognized.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 380)
    }

    /// Map a normalised (0…1, top-left) image-space box to the aspect-fill,
    /// horizontally-mirrored preview's own coordinates.
    private func displayedRect(for box: CGRect, in view: CGSize, aspect: CGFloat) -> CGRect? {
        guard view.width > 0, view.height > 0, aspect > 0 else { return nil }
        let viewAspect = view.width / view.height
        var dispW = view.width, dispH = view.height, offX: CGFloat = 0, offY: CGFloat = 0
        if aspect > viewAspect {           // image wider than view → height fills
            dispH = view.height
            dispW = dispH * aspect
            offX = (view.width - dispW) / 2
        } else {                           // width fills
            dispW = view.width
            dispH = dispW / aspect
            offY = (view.height - dispH) / 2
        }
        let x = offX + box.minX * dispW
        let y = offY + box.minY * dispH
        let w = box.width * dispW
        let h = box.height * dispH
        let mirroredX = view.width - (x + w)   // preview is mirrored
        return CGRect(x: mirroredX, y: y, width: w, height: h)
    }
}

/// A horizontal similarity bar with the match threshold marked.
private struct SimilarityMeter: View {
    let score: Double?
    let threshold: Double

    private var fraction: CGFloat {
        guard let score else { return 0 }
        return CGFloat(min(max(score, 0), 1))
    }
    private var meets: Bool { (score ?? -1) >= threshold }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(meets ? Color.green : Color.orange)
                        .frame(width: geo.size.width * fraction)
                    // Threshold marker.
                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 2)
                        .position(x: geo.size.width * CGFloat(min(max(threshold, 0), 1)),
                                  y: geo.size.height / 2)
                }
            }
            .frame(height: 12)

            HStack {
                Text(score.map { String(format: "similarity %.2f", $0) } ?? "no face")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "match ≥ %.2f", threshold))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
