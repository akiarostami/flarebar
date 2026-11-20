import AppKit
import FlarebarCore
import SwiftUI

/// The content of the menu that drops from the menu bar item.
struct PopoverView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(width: 372)
        .fontDesign(.rounded)
        // A wash of Cloudflare orange at the top, over the panel's blurred background.
        .background(alignment: .top) {
            LinearGradient(colors: [BrandIcon.orange.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
        }
        .overlay {
            RoundedRectangle(cornerRadius: MenuPanelController.cornerRadius)
                .strokeBorder(Color.primary.opacity(0.1))
        }
        // No focus ring on the first row when the menu opens.
        .focusEffectDisabled()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: BrandIcon.image(pointSize: 18, colour: .white))
                .frame(width: 28, height: 28)
                .background(BrandIcon.gradient, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 0) {
                Text("Flarebar").font(.title3.weight(.semibold))
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(updatedText(now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HeaderButton(symbol: "arrow.clockwise", help: "Refresh now", isBusy: model.isRefreshing) {
                Task { await model.refresh(force: true) }
            }
            .disabled(model.isRefreshing)
            HeaderButton(symbol: "gearshape.fill", help: "Settings (⌘,)") {
                model.openSettings(model.settingsPane)
            }
            HeaderButton(symbol: "power", help: "Quit Flarebar (⌘Q)") {
                model.requestQuit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder private var content: some View {
        if !model.hasToken || model.config.accounts.isEmpty {
            prompt(model.hasToken ? "Add an account to the menu." : "Connect a Cloudflare account to get started.",
                   symbol: "key", pane: .accounts)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.config.accounts, id: \.id) { account in
                            AccountSection(account: account)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 540)
                .fixedSize(horizontal: false, vertical: true)
                // Keep the row the keyboard is on in view.
                .onChange(of: model.selectedRow) { _, row in
                    if let row {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(row) }
                    }
                }
            }
        }
    }

    private func updatedText(now: Date) -> String {
        guard let last = model.snapshots.values.map(\.fetchedAt).max() else { return "No data yet" }
        let minutes = Int(now.timeIntervalSince(last) / 60)
        return minutes < 1 ? "Updated just now" : "Updated \(Format.ago(from: last, to: now)) ago"
    }

    private func prompt(_ text: String, symbol: String, pane: SettingsPane) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
            Button("Open Settings") { model.openSettings(pane) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// A round icon button for the top of the menu. Its name is shown as a tooltip.
private struct HeaderButton: View {
    let symbol: String
    let help: String
    var isBusy = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                }
            }
            .frame(width: 26, height: 26)
            .background(Color.primary.opacity(isHovered ? 0.14 : 0.07), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// One account as a card: its header (which opens the bill), its projects, and Other.
struct AccountSection: View {
    @Environment(AppModel.self) private var model
    let account: Account
    @State private var isHeaderHovered = false

    var body: some View {
        let snapshot = model.snapshots[account.id]
        let billID = "\(account.id)/#bill"
        let showsBill = model.expanded.contains(billID)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if showsBill {
                        model.expanded.remove(billID)
                    } else {
                        model.expanded.insert(billID)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(account.name).font(.headline)
                    if let plan = snapshot?.plan {
                        Text(plan == .paid ? "Paid" : "Free")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    Spacer()
                    Text(snapshot?.bill.totalUSD.map(Format.money) ?? "—")
                        .font(.headline.monospacedDigit())
                    Chevron(isOpen: showsBill)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .background(RowHighlight(isSelected: model.selectedRow == billID, isHovered: isHeaderHovered))
                .id(billID)
            }
            .buttonStyle(.plain)
            .onHover { isHeaderHovered = $0 }
            .help("Show what the bill is made of")

            if showsBill, let bill = snapshot?.bill {
                BillDetail(bill: bill)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            if let error = model.errors[account.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
            if let snapshot {
                ForEach(snapshot.projects, id: \.name) { project in
                    ProjectRow(id: "\(account.id)/\(project.name)", accountID: account.id,
                               title: project.name, project: project, monthStart: snapshot.monthStart)
                }
                if let other = snapshot.other {
                    ProjectRow(id: "\(account.id)/#other", accountID: account.id, title: other.name,
                               project: other, monthStart: snapshot.monthStart)
                }
                if snapshot.projects.isEmpty && snapshot.other == nil {
                    Text("No projects or Workers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }
            } else if model.errors[account.id] == nil {
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06))
        }
    }
}

/// What an account's bill is made of: paid plans, then metered usage per billed line.
struct BillDetail: View {
    let bill: Bill

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if bill.usageUSD == nil && bill.subscriptions.isEmpty {
                Text("This token cannot read billing.")
                    .foregroundStyle(.secondary)
            } else {
                if let start = bill.periodStart {
                    Text("Billing period since \(start)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                group("Plans", bill.subscriptions, subtotal: bill.subsUSD, empty: "No paid plans")
                group("Usage", bill.lineItems, subtotal: bill.usageUSD, empty: "No metered usage so far")
                Divider().padding(.vertical, 2)
                row("Total", bill.totalUSD, weight: .semibold)
                if let credit = bill.creditUSD {
                    row("Credit remaining", credit, weight: .regular)
                }
            }
        }
        .font(.callout)
        .padding(10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [MoneyItem], subtotal: Double?, empty: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer()
            if items.count > 1, let subtotal {
                Text(Format.money(subtotal)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
        if items.isEmpty {
            Text(subtotal == nil ? "Not available" : empty).foregroundStyle(.tertiary)
        }
        ForEach(items, id: \.name) { item in
            row(item.name, item.usd, weight: .regular)
        }
    }

    private func row(_ name: String, _ usd: Double?, weight: Font.Weight) -> some View {
        HStack {
            Text(name).fontWeight(weight).lineLimit(1)
            Spacer()
            Text(usd.map(Format.money) ?? "—").fontWeight(weight).monospacedDigit()
        }
    }
}
