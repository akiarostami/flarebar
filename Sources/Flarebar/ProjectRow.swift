import AppKit
import FlarebarCore
import SwiftUI

/// A project: one summary line that expands to usage bars and deployments.
/// "Other" is shown the same way.
struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    let id: String
    let accountID: String
    let title: String
    let project: ProjectSnapshot
    let monthStart: String
    @State private var isHovered = false

    private enum Tab: String, CaseIterable {
        case usage = "Usage"
        case deployments = "Deployments"
    }

    private var tab: Tab { model.deploymentRows.contains(id) ? .deployments : .usage }

    private func select(_ new: Tab) {
        if new == .deployments {
            model.deploymentRows.insert(id)
        } else {
            model.deploymentRows.remove(id)
        }
    }

    private var isExpanded: Bool { model.expanded.contains(id) }

    /// The project's colour: that of its figure closest to its allowance.
    private var severity: Severity { project.worstBar?.severity(model.thresholds) ?? .normal }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isExpanded {
                        model.expanded.remove(id)
                    } else {
                        model.expanded.insert(id)
                    }
                }
            } label: {
                summary
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if !project.bars.isEmpty {
                        tabs
                    }
                    if tab == .usage && !project.bars.isEmpty {
                        ForEach(project.bars, id: \.key) { bar in
                            BarView(bar: bar, monthStart: monthStart)
                        }
                    } else {
                        DeploymentsList(accountID: accountID, workers: project.workers)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 10)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(project.bars.isEmpty ? Color.secondary.opacity(0.5) : severity.colour)
                .frame(width: 8, height: 8)
                .shadow(color: project.bars.isEmpty ? .clear : severity.colour.opacity(0.6), radius: 3)
            Text(title).font(.body.weight(.medium))
            Spacer()
            if let worst = project.worstBar {
                HStack(spacing: 4) {
                    Text(worst.shortLabel).foregroundStyle(.secondary)
                    Text(Format.percent(worst.ratio))
                        .fontWeight(.semibold)
                        .foregroundStyle(severity == .normal ? Color.primary : severity.colour)
                }
                .font(.callout.monospacedDigit())
            } else {
                Text("\(project.workers.count) Worker\(project.workers.count == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Chevron(isOpen: isExpanded)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(RowHighlight(isSelected: model.selectedRow == id, isHovered: isHovered))
        .id(id)
    }

    /// Usage and Deployments as two pills.
    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    select(item)
                } label: {
                    Text(item.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(tab == item ? Color.primary.opacity(0.12) : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

/// The background of a row: tinted when the keyboard is on it, faint under the pointer.
struct RowHighlight: View {
    let isSelected: Bool
    var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(isHovered ? 0.06 : 0))
    }
}

/// The disclosure arrow at the end of a row; it turns when the row opens.
struct Chevron: View {
    let isOpen: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(isOpen ? 90 : 0))
            .frame(width: 12)
    }
}

/// One figure against its allowance.
struct BarView: View {
    @Environment(AppModel.self) private var model
    let bar: Bar
    let monthStart: String

    private var severity: Severity { bar.severity(model.thresholds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(bar.label).font(.callout)
                Spacer()
                Text(Format.value(bar)).font(.callout.weight(.medium).monospacedDigit())
                Text("/ \(bar.limitText)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [severity.barColour.opacity(0.75), severity.barColour],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(bar.value > 0 ? 6 : 0, geometry.size.width * bar.fraction))
                }
            }
            .frame(height: 6)
            HStack {
                Text(windowText)
                Spacer()
                Text(Format.percent(bar.ratio))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(severity == .normal ? Color.secondary : severity.colour)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private var windowText: String {
        switch bar.window {
        case .day: return "Today (UTC)"
        case .period: return "Since \(monthStart)"
        case .now: return "Current"
        }
    }
}

/// The Workers of a project, newest first. A click opens the Worker in the Cloudflare dashboard.
struct DeploymentsList: View {
    let accountID: String
    let workers: [WorkerInfo]

    var body: some View {
        if workers.isEmpty {
            Text("No Workers match this project.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 2) {
                ForEach(workers, id: \.name) { worker in
                    DeploymentRow(worker: worker) { open(worker) }
                }
            }
        }
    }

    private func open(_ worker: WorkerInfo) {
        let name = worker.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? worker.name
        if let url = URL(string: "https://dash.cloudflare.com/\(accountID)/workers/services/view/\(name)/production") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct DeploymentRow: View {
    let worker: WorkerInfo
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(worker.name).font(.callout.weight(.medium))
                    Text(deployedText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let modified = worker.modifiedOn {
                    Text(Format.ago(from: modified, to: Date()))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isHovered ? Color.secondary : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(RowHighlight(isSelected: false, isHovered: isHovered))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open in the Cloudflare dashboard")
    }

    /// "wrangler" -> "Deployed via Wrangler", "quick_editor" -> "Deployed via Quick Editor".
    private var deployedText: String {
        guard let client = worker.deployedFrom, !client.isEmpty else { return "Worker" }
        return "Deployed via " + client.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
