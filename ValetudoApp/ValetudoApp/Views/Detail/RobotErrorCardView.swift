import SwiftUI

struct RobotErrorCardView: View {
    let error: RobotErrorInfo

    static func color(for error: RobotErrorInfo) -> Color {
        switch error.severityLevel {
        case .warning: return .orange
        case .info: return .blue
        case .error, .catastrophic, .unknown, .none: return .red
        }
    }

    private var icon: String {
        switch error.severityLevel {
        case .info: return "info.circle.fill"
        case .catastrophic: return "xmark.octagon.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        let explanation = error.explanation
        let color = Self.color(for: error)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(explanation.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                Text(explanation.help)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = explanation.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
