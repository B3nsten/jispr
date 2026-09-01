import SwiftUI

@MainActor
@Observable
final class IndicatorModel {
    enum Phase: Equatable {
        case preparing(progress: Double?)
        case listening
        case finishing
        case error(String)
    }

    var phase: Phase = .listening
    var level: Float = 0
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
            case .finishing:
                ProgressView().controlSize(.small).tint(.white)
                Text("Finishing…")
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
