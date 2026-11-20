import FlarebarCore
import SwiftUI

/// A page of the settings window. Each account in the menu has a page of its own.
enum SettingsPane: Hashable {
    case general, accounts, about
    case account(String)  // the account's ID
}

/// The settings window: General, then Accounts and one page per account, then About.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // A plain row of sidebar and page, rather than a split view, so the sidebar's width is
        // exactly what is set here.
        HStack(spacing: 0) {
            List(selection: Binding<SettingsPane?>(
                get: { model.settingsPane },
                set: { model.settingsPane = $0 ?? .general }
            )) {
                Label("General", systemImage: "gearshape").tag(SettingsPane.general)

                Section("Cloudflare") {
                    Label("Accounts", systemImage: "key").tag(SettingsPane.accounts)
                    ForEach(model.config.accounts, id: \.id) { account in
                        HStack {
                            Label(account.name, systemImage: "building.2")
                            Spacer()
                            Text("\(account.projects.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .help("\(account.projects.count) project\(account.projects.count == 1 ? "" : "s")")
                        }
                        .tag(SettingsPane.account(account.id))
                    }
                }

                Section {
                    Label("About", systemImage: "info.circle").tag(SettingsPane.about)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 250)

            Divider().ignoresSafeArea()

            Group {
            switch model.settingsPane {
            case .general: GeneralPage()
            case .accounts: AccountsPage()
            case .about: AboutPage()
            case .account(let id):
                if let account = model.config.accounts.first(where: { $0.id == id }) {
                    AccountPage(account: account).id(id)
                } else {
                    AccountsPage()
                }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 880, height: 600)
        .onChange(of: model.settingsPane) { _, _ in model.settingsMessage = nil }
        .task { await model.resolveTokens() }
    }
}

/// A status line at the top of a page, shown when there is something to report.
private struct MessageSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message = model.settingsMessage {
            Section {
                Label(message, systemImage: "info.circle").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: General

private struct GeneralPage: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = false

    var body: some View {
        @Bindable var model = model
        Form {
            MessageSection()
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if enabled != model.launchAtLogin { model.setLaunchAtLogin(enabled) }
                    }
            }

            Section {
                LabeledContent("Open Flarebar") {
                    ShortcutRecorder(combo: $model.hotKey)
                }
                if model.hotKeyRefused {
                    Label("macOS refused this shortcut; another app may be using it. Try a different one.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Works from any app. Press it again to close the menu.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Picker("Show the dot", selection: $model.showDotWhenFine) {
                    Text("Always").tag(true)
                    Text("Only when yellow or red").tag(false)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Status dot")
            } footer: {
                Text("The dot on the menu bar icon takes the colour of the worst figure in any project: red, else yellow, else green.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Stepper(value: $model.warningPercent, in: 1...98, step: 5) {
                    LabeledContent {
                        Text("\(model.warningPercent)%").monospacedDigit()
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(Color.yellow).frame(width: 10, height: 10)
                            Text("Yellow above")
                        }
                    }
                }
                .onChange(of: model.warningPercent) { _, warning in
                    if model.criticalPercent <= warning { model.criticalPercent = min(warning + 1, 99) }
                }
                Stepper(value: $model.criticalPercent, in: 2...99, step: 5) {
                    LabeledContent {
                        Text("\(model.criticalPercent)%").monospacedDigit()
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(Color.red).frame(width: 10, height: 10)
                            Text("Red above")
                        }
                    }
                }
                .onChange(of: model.criticalPercent) { _, critical in
                    if model.warningPercent >= critical { model.warningPercent = max(critical - 1, 1) }
                }
                if model.warningPercent != 70 || model.criticalPercent != 90 {
                    Button("Reset to 70% and 90%") {
                        model.warningPercent = 70
                        model.criticalPercent = 90
                    }
                }
            } header: {
                Text("Colours")
            } footer: {
                Text("Percentages are of the account's allowance. A project is green until one of its figures passes the yellow level.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LabeledContent("Refreshes", value: "Every 10 minutes, and when the menu is opened")
                LabeledContent("Last refresh") {
                    Text(model.lastRefresh.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Not yet")
                }
                Button("Refresh Now") {
                    Task { await model.refresh(force: true) }
                }
                .disabled(model.isRefreshing)
            } header: {
                Text("Data")
            }

            Section {
                HStack {
                    Text("Flarebar has no Dock icon or menus of its own; quit it here or from its menu.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit Flarebar") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear { launchAtLogin = model.launchAtLogin }
    }
}

// MARK: Accounts

/// The Cloudflare tokens and the accounts each can see. Adding an account here gives it a
/// page of its own in the sidebar.
private struct AccountsPage: View {
    @Environment(AppModel.self) private var model
    @State private var showsAddSheet = false
    @State private var tokenToRemove: TokenGroup?

    /// A token with the accounts listed under it. An account several tokens can see is
    /// listed under the first, which is the one used to fetch it.
    private struct TokenGroup: Identifiable {
        var id: UUID
        var number: Int
        var token: AppModel.SavedToken
        var accounts: [VisibleAccount]
    }

    private var groups: [TokenGroup] {
        var seen = Set<String>()
        return model.tokens.enumerated().map { index, token in
            let accounts = (token.accounts ?? []).filter { seen.insert($0.id).inserted }
            return TokenGroup(id: token.id, number: index + 1, token: token, accounts: accounts)
        }
    }

    var body: some View {
        let groups = groups
        let visible = Set(groups.flatMap { $0.accounts.map(\.id) })
        let orphans = model.config.accounts.filter { !visible.contains($0.id) }

        Form {
            Section {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cloudflare accounts").font(.title3.weight(.semibold))
                        Text("An account is reached with a read-only API token. One token can cover several accounts.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        showsAddSheet = true
                    } label: {
                        Label("Add Account…", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrandIcon.orange)
                }
                .padding(.vertical, 4)
                // The confirmation for the trash buttons below hangs on this row.
                .confirmationDialog(
                    "Remove the token for \(tokenToRemove.map(title) ?? "this account")?",
                    isPresented: Binding(get: { tokenToRemove != nil }, set: { if !$0 { tokenToRemove = nil } }),
                    titleVisibility: .visible
                ) {
                    Button("Remove Token", role: .destructive) {
                        if let group = tokenToRemove { model.removeToken(group.id) }
                        tokenToRemove = nil
                    }
                    Button("Cancel", role: .cancel) { tokenToRemove = nil }
                } message: {
                    Text("Its accounts stay in the menu but stop updating until a token that includes them is added. Delete the token in Cloudflare too, under API Tokens.")
                }
            }
            MessageSection()
            ForEach(groups) { group in
                Section {
                    ForEach(group.accounts, id: \.id) { account in
                        accountRow(id: account.id, name: account.name)
                    }
                    if group.accounts.isEmpty {
                        Text(group.token.accounts == nil ? "Checking…" : "This token sees no accounts of its own.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(group))
                            Text(group.token.error ?? "API token saved in the Keychain")
                                .font(.caption)
                                .foregroundStyle(group.token.error == nil ? Color.secondary : Color.orange)
                        }
                        Spacer()
                        Button {
                            tokenToRemove = group
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this token")
                    }
                }
            }

            if !orphans.isEmpty {
                Section {
                    ForEach(orphans, id: \.id) { account in
                        accountRow(id: account.id, name: account.name)
                    }
                } header: {
                    Text("Accounts no saved token can see")
                } footer: {
                    Text("These cannot be fetched until a token that includes them is added.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Accounts")
        .sheet(isPresented: $showsAddSheet) {
            AddAccountSheet()
        }
    }

    /// An account in the menu links to its page; one that is not offers to add it.
    @ViewBuilder
    private func accountRow(id: String, name: String) -> some View {
        if let account = model.config.accounts.first(where: { $0.id == id }) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(account.name)
                Spacer()
                Text(account.projects.isEmpty ? "No projects"
                     : "\(account.projects.count) project\(account.projects.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Button("Settings…") { model.settingsPane = .account(id) }
            }
        } else {
            HStack {
                Image(systemName: "circle").foregroundStyle(.tertiary)
                Text(name).foregroundStyle(.secondary)
                Spacer()
                Button("Add to Menu") {
                    model.updateConfig { $0.accounts.append(Account(id: id, name: name)) }
                    model.settingsPane = .account(id)
                }
            }
        }
    }

    /// The names of the token's accounts that are in the menu, as you named them; failing
    /// that, Cloudflare's name when the token sees a single account; else a number.
    private func title(_ group: TokenGroup) -> String {
        let inMenu = group.accounts.compactMap { visible in
            model.config.accounts.first { $0.id == visible.id }?.name
        }
        if !inMenu.isEmpty { return inMenu.joined(separator: ", ") }
        if group.accounts.count == 1 { return group.accounts[0].name }
        return "Cloudflare Account \(group.number)"
    }
}

/// Adds an account in two steps: create a read-only token on Cloudflare, then paste it.
private struct AddAccountSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var tokenText = ""
    @State private var isSaving = false
    @State private var failure: String?

    /// Cloudflare's token form with the read-only permissions Flarebar needs already ticked.
    private static let createTokenURL: URL? = {
        let permissions = ["account_analytics", "d1", "workers_kv_storage", "workers_scripts", "billing"]
            .map { "{\"key\":\"\($0)\",\"type\":\"read\"}" }
            .joined(separator: ",")
        var components = URLComponents(string: "https://dash.cloudflare.com/profile/api-tokens")
        components?.queryItems = [
            URLQueryItem(name: "permissionGroupKeys", value: "[\(permissions)]"),
            URLQueryItem(name: "accountId", value: "*"),
            URLQueryItem(name: "zoneId", value: "all"),
            URLQueryItem(name: "name", value: "Flarebar"),
        ]
        return components?.url
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: BrandIcon.image(pointSize: 22, colour: .white))
                    .frame(width: 44, height: 44)
                    .background(BrandIcon.gradient, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a Cloudflare account").font(.title2.weight(.semibold))
                    Text("Flarebar only ever reads; the token needs no write access.")
                        .foregroundStyle(.secondary)
                }
            }

            step(1, "Create a read-only API token") {
                Text("Cloudflare's form opens with the right permissions ticked: Account Analytics, D1, Workers KV Storage, Workers Scripts and Billing, all Read. Under Account Resources, include the accounts you want, then create the token.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if let url = Self.createTokenURL { NSWorkspace.shared.open(url) }
                } label: {
                    Label("Create a Token on Cloudflare", systemImage: "arrow.up.right.square")
                }
            }

            step(2, "Paste the token") {
                Text("Cloudflare shows it once. It is saved to your Keychain, never to a file.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                SecureField("API token", text: $tokenText, prompt: Text("Paste the token here"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .onSubmit(save)
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Checking…" : "Add Account", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(BrandIcon.orange)
                    .disabled(tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.bold))
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content()
            }
        }
    }

    /// Verifies and saves the token. Accounts it newly reaches go into the menu; with exactly
    /// one, its page opens so projects can be set up straight away.
    private func save() {
        guard !isSaving else { return }
        isSaving = true
        failure = nil
        Task {
            let before = model.tokens.count
            let known = Set(model.config.accounts.map(\.id))
            await model.addToken(tokenText)
            isSaving = false
            guard model.tokens.count > before else {
                failure = model.settingsMessage ?? "That token could not be added."
                model.settingsMessage = nil
                return
            }
            let reached = (model.tokens.last?.accounts ?? []).filter { !known.contains($0.id) }
            if !reached.isEmpty {
                model.updateConfig { config in
                    config.accounts.append(contentsOf: reached.map { Account(id: $0.id, name: $0.name) })
                }
            }
            model.settingsMessage = reached.isEmpty
                ? "Token saved. Its accounts were already in the menu."
                : "Added \(reached.map(\.name).joined(separator: ", ")). Set up projects on each account's page."
            if reached.count == 1 {
                model.settingsPane = .account(reached[0].id)
            }
            dismiss()
        }
    }
}

// MARK: One account

/// An account's own page: its name, its projects, the Workers no project claims, and removal.
private struct AccountPage: View {
    @Environment(AppModel.self) private var model
    let account: Account
    @State private var name = ""
    @State private var confirmsRemoval = false
    @FocusState private var nameFocused: Bool

    private var snapshot: AccountSnapshot? { model.snapshots[account.id] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let error = model.errors[account.id] {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Projects").font(.title3.weight(.semibold))
                        Spacer()
                        Button {
                            change { $0.projects.append(Project(name: uniqueName("New project"), prefixes: [])) }
                        } label: {
                            Label("New Project", systemImage: "plus")
                        }
                    }
                    Text("A project collects the Workers, D1 databases, KV namespaces and R2 buckets whose names start with one of its prefixes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if account.projects.isEmpty {
                        Text("No projects yet. Everything in this account shows under Other.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                    ForEach(Array(account.projects.enumerated()), id: \.offset) { index, project in
                        ProjectCard(accountID: account.id, index: index, project: project,
                                    workers: snapshot?.projects.first { $0.name == project.name }?.workers ?? [])
                    }
                }

                if let others = snapshot?.otherWorkers, !others.isEmpty {
                    unassigned(others)
                }

                Divider()
                HStack {
                    Text("Removing the account takes it and its projects out of the menu. Its token stays under Accounts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Remove Account…", role: .destructive) { confirmsRemoval = true }
                }
            }
            .padding(24)
        }
        .navigationTitle(account.name)
        .onAppear { name = account.name }
        .onChange(of: account.name) { _, new in name = new }
        .confirmationDialog("Remove \(account.name) from the menu?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove Account", role: .destructive) {
                let id = account.id
                model.settingsPane = .accounts
                model.updateConfig { $0.accounts.removeAll { $0.id == id } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(account.projects.isEmpty ? "You can add it again from Accounts."
                 : "Its \(account.projects.count) project\(account.projects.count == 1 ? "" : "s") will be deleted. You can add the account again from Accounts, but the projects would need to be set up again.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: BrandIcon.image(pointSize: 26, colour: .white))
                .frame(width: 52, height: 52)
                .background(BrandIcon.gradient, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                TextField("Account name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .focused($nameFocused)
                    .onSubmit(rename)
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { rename() }
                    }
                    .help("The name shown in the menu. Click to rename.")
                HStack(spacing: 8) {
                    if let snapshot {
                        Badge(text: snapshot.plan == .paid ? "Workers Paid" : "Workers Free")
                        if let total = snapshot.bill.totalUSD {
                            Badge(text: "\(Format.money(total)) so far")
                        }
                    }
                    Text(account.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    /// Workers no project claims, each with a one-click way to start a project from it.
    private func unassigned(_ workers: [WorkerInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not in any project").font(.title3.weight(.semibold))
            Text("These Workers match no prefix and show under Other in the menu.")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(workers, id: \.name) { worker in
                    HStack {
                        Image(systemName: "shippingbox").foregroundStyle(.secondary)
                        Text(worker.name).font(.body.monospaced())
                        Spacer()
                        Button("Make a Project") {
                            let prefix = suggestedPrefix(worker.name)
                            change { $0.projects.append(Project(name: uniqueName(projectName(prefix)), prefixes: [prefix])) }
                        }
                        .controlSize(.small)
                        .help("New project with the prefix “\(suggestedPrefix(worker.name))”")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    if worker.name != workers.last?.name {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// "shop-api" -> "shop-"; a name without a dash is its own prefix.
    private func suggestedPrefix(_ worker: String) -> String {
        guard let dash = worker.firstIndex(of: "-") else { return worker }
        return String(worker[...dash])
    }

    private func projectName(_ prefix: String) -> String {
        let base = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        return base.isEmpty ? "New project" : base.prefix(1).uppercased() + base.dropFirst()
    }

    private func uniqueName(_ base: String) -> String {
        let taken = Set(account.projects.map(\.name))
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            name = account.name
            return
        }
        guard trimmed != account.name else { return }
        change { $0.name = trimmed }
    }

    private func change(_ edit: (inout Account) -> Void) {
        model.updateConfig { config in
            if let index = config.accounts.firstIndex(where: { $0.id == account.id }) {
                edit(&config.accounts[index])
            }
        }
    }
}

private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.08), in: Capsule())
    }
}

/// One project as a card: its name, its prefixes as removable chips, and what it matches.
private struct ProjectCard: View {
    @Environment(AppModel.self) private var model
    let accountID: String
    let index: Int
    let project: Project
    let workers: [WorkerInfo]
    @State private var name = ""
    @State private var newPrefix = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Project name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .focused($nameFocused)
                    .onSubmit(rename)
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { rename() }
                    }
                    .help("Click to rename")
                Spacer()
                Button {
                    edit { $0.projects.remove(at: index) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete this project")
            }

            ChipFlow(spacing: 6) {
                ForEach(project.prefixes, id: \.self) { prefix in
                    HStack(spacing: 4) {
                        Text(prefix + "*").font(.callout.monospaced())
                        Button {
                            edit { $0.projects[index].prefixes.removeAll { $0 == prefix } }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove this prefix")
                    }
                    .padding(.leading, 9)
                    .padding(.trailing, 7)
                    .padding(.vertical, 4)
                    .background(BrandIcon.orange.opacity(0.16), in: Capsule())
                }
                TextField("Add prefix", text: $newPrefix, prompt: Text("Add a prefix…"))
                    .textFieldStyle(.plain)
                    .font(.callout.monospaced())
                    .frame(width: 130)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .onSubmit(addPrefix)
            }

            Text(matchText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)) }
        .onAppear { name = project.name }
        .onChange(of: project.name) { _, new in name = new }
    }

    private var matchText: String {
        if project.prefixes.isEmpty { return "Add a prefix to start collecting resources." }
        if workers.isEmpty { return "No Workers match yet. Databases and buckets with these prefixes still count." }
        let names = workers.prefix(4).map(\.name).joined(separator: ", ")
        let more = workers.count > 4 ? " and \(workers.count - 4) more" : ""
        return "\(workers.count) Worker\(workers.count == 1 ? "" : "s"): \(names)\(more)"
    }

    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            name = project.name
            return
        }
        guard trimmed != project.name else { return }
        edit { $0.projects[index].name = trimmed }
    }

    private func addPrefix() {
        let prefix = newPrefix.trimmingCharacters(in: CharacterSet(charactersIn: " ,*"))
        newPrefix = ""
        guard !prefix.isEmpty, !project.prefixes.contains(prefix) else { return }
        edit { $0.projects[index].prefixes.append(prefix) }
    }

    private func edit(_ change: (inout Account) -> Void) {
        model.updateConfig { config in
            if let accountIndex = config.accounts.firstIndex(where: { $0.id == accountID }),
               config.accounts[accountIndex].projects.indices.contains(index) {
                change(&config.accounts[accountIndex])
            }
        }
    }
}

/// Lays chips out left to right, wrapping to new lines as needed.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, arrangement.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, widest, y + rowHeight)
    }
}

// MARK: About

private struct AboutPage: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development build"
    }

    private var folder: URL { ConfigStore.defaultDirectory }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: BrandIcon.image(pointSize: 30, colour: .white))
                        .frame(width: 60, height: 60)
                        .background(BrandIcon.gradient, in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Flarebar").font(.title2.weight(.semibold))
                        Text("Version \(version)").foregroundStyle(.secondary)
                        Text("Cloudflare in your menu bar: usage, bill and Worker deployments, grouped by project.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                Text("A personal tool. Not affiliated with or endorsed by Cloudflare.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LabeledContent("Settings and cached data") {
                    Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Tokens", value: "macOS Keychain, service “flarebar”")
                Button("Show in Finder") {
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(folder)
                }
            } header: {
                Text("Where things are kept")
            } footer: {
                Text("Flarebar talks only to Cloudflare's API, with the read-only tokens you give it. Nothing is sent anywhere else.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Keyboard, with the menu open") {
                LabeledContent("Move between rows", value: "↑ ↓")
                LabeledContent("Open a row", value: "→")
                LabeledContent("Close a row", value: "←")
                LabeledContent("Usage / Deployments", value: "⌘← ⌘→")
                LabeledContent("Open or close a row", value: "Return or Space")
                LabeledContent("Settings", value: "⌘,")
                LabeledContent("Close the menu", value: "Esc")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }
}
