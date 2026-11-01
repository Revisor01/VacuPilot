import SwiftUI

struct DockComponentChipsView: View {
    let components: [DockComponent]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(components) { chip(for: $0) }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.first?.id) { row in
                    HStack(spacing: 4) {
                        ForEach(row) { chip(for: $0) }
                    }
                }
            }
        }
    }

    private var rows: [[DockComponent]] {
        stride(from: 0, to: components.count, by: 2).map {
            Array(components[$0..<min($0 + 2, components.count)])
        }
    }

    @ViewBuilder
    private func chip(for component: DockComponent) -> some View {
        let color: Color = component.needsAttention ? .orange : (component.value == "ok" ? .green : .gray)
        HStack(spacing: 3) {
            Image(systemName: component.icon)
                .font(.system(size: 9))
            Text(component.needsAttention ? "\(component.displayName): \(component.valueDisplay)" : component.displayName)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(component.displayName): \(component.valueDisplay)")
    }
}
