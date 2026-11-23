import SwiftUI

extension RobotNotice.Kind {
    var color: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .update: return .blue
        }
    }
}

struct NoticeBellButton: View {
    let notices: [RobotNotice]
    let newKind: RobotNotice.Kind?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: notices.isEmpty ? "bell" : "bell.fill")
                .overlay(alignment: .topTrailing) {
                    if let newKind {
                        Circle()
                            .fill(newKind.color)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                            .offset(x: 3, y: -2)
                    }
                }
        }
        .accessibilityLabel(String(localized: "notices.title"))
        .accessibilityValue(newKind == nil
            ? String(localized: "notices.accessibility.none_new")
            : String(localized: "notices.accessibility.new"))
    }
}

struct RobotNoticesView: View {
    let viewModel: RobotDetailViewModel
    let onInstallUpdate: () -> Void
    @Environment(\.dismiss) private var dismiss
    // Captured on opening, so the dots on new entries stay while the sheet is open.
    @State private var seenBeforeOpening: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                let notices = viewModel.notices
                if notices.isEmpty {
                    ContentUnavailableView(
                        String(localized: "notices.empty"),
                        systemImage: "checkmark.circle",
                        description: Text(String(localized: "notices.empty.detail"))
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(notices) { notice in
                        row(for: notice, isNew: !seenBeforeOpening.contains(notice.id))
                    }
                }
            }
            .navigationTitle(String(localized: "notices.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "button.done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            seenBeforeOpening = viewModel.seenNoticeIds
            viewModel.markNoticesSeen()
        }
        .onDisappear {
            viewModel.markNoticesSeen()
        }
    }

    @ViewBuilder
    private func row(for notice: RobotNotice, isNew: Bool) -> some View {
        switch notice.source {
        case .robotError(let error):
            RobotErrorCardView(error: error)
                .listRowSeparator(.hidden)
        case .update(let version):
            VStack(alignment: .leading, spacing: 8) {
                header(notice, isNew: isNew, detail: "\(viewModel.updateService?.currentVersion ?? "?") → \(version)")
                Button(action: onInstallUpdate) {
                    Label(String(localized: "update.install"), systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        case .event(let id, let canDismiss):
            HStack(alignment: .top) {
                header(notice, isNew: isNew, detail: notice.detail)
                Spacer(minLength: 0)
                if canDismiss, let event = viewModel.events.first(where: { $0.id == id }) {
                    Button {
                        Task { await viewModel.dismissEvent(event) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "notices.dismiss"))
                }
            }
        case .consumable, .dockComponent:
            header(notice, isNew: isNew, detail: notice.detail)
        }
    }

    private func header(_ notice: RobotNotice, isNew: Bool, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.icon)
                .foregroundStyle(notice.kind.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(notice.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if isNew {
                        Circle()
                            .fill(notice.kind.color)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel(String(localized: "notices.new"))
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let date = notice.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
