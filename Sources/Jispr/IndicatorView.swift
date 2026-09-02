import SwiftUI

@MainActor
@Observable
final class IndicatorModel {
    enum Phase: Equatable {
        case preparing(progress: Double?)
        case listening
        case recording
        case finishing
        case transcribing(String)
        case saved(String)
        case error(String)
    }

    var phase: Phase = .listening
    var level: Float = 0
    /// Seconds since the recording started. Shown while `.recording`.
    var elapsed: TimeInterval = 0
}

struct IndicatorView: View {
    var model: IndicatorModel

    var body: some View {
        HStack(spacing: 10) {
            switch model.phase {
            case .preparing(let progress):
                ProgressView().controlSize(.small).tint(.white)
                if let progress {
                    Text("Downloading model \(Int(progress * 100))%")
                } else {
                    Text("Preparing…")
                }
            case .listening:
                LevelBars(level: model.level)
                Text("Listening")
            case .recording:
                LevelBars(level: model.level)
                Text("Recording \(Self.clock(model.elapsed))").monospacedDigit()
            case .finishing:
                ProgressView().controlSize(.small).tint(.white)
                Text("Finishing…")
            case .transcribing(let name):
                ProgressView().controlSize(.small).tint(.white)
                Text("Transcribing \(name)…")
            case .saved(let name):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Saved \(name)")
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(message)
            }
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.86)))
        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.15), value: model.phase)
    }

    /// `m:ss`, or `h:mm:ss` from one hour on.
    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

struct LevelBars: View {
    var level: Float
    private let shape: [CGFloat] = [0.45, 0.8, 1.0, 0.7, 0.5]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(shape.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.red)
                    .frame(width: 3, height: 4 + 14 * CGFloat(level) * shape[i])
            }
        }
        .frame(width: 27, height: 18)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
