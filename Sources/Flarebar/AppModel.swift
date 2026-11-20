import Foundation
import Observation
import ServiceManagement
import SwiftUI
import FlarebarCore

/// The app's state: config, tokens, the latest snapshot per account, and refresh scheduling.
@MainActor
@Observable
final class AppModel {
    static let refreshInterval: TimeInterval = 600
    static let minimumInterval: TimeInterval = 60
    static let namesLifetime: TimeInterval = 3600

    /// A saved token and the accounts it can see. `accounts` is nil until Cloudflare has answered.
    struct SavedToken: Identifiable {
        let id = UUID()
        var value: String
        var accounts: [VisibleAccount]?
        var error: String?
    }

    var config: Config
    /// Keyed by account ID.
    var snapshots: [String: AccountSnapshot] = [:]
    var errors: [String: String] = [:]
    var lastRefresh: Date?
    var isRefreshing = false
    var tokens: [SavedToken] = []
    var settingsMessage: String?
    var expanded: Set<String> {
        didSet {
            if !DemoData.isOn { UserDefaults.standard.set(Array(expanded), forKey: "expanded") }
        }
    }
    /// A figure turns amber above this percentage of its allowance.
    var warningPercent: Int {
        didSet { UserDefaults.standard.set(warningPercent, forKey: "warningPercent") }
    }
    /// A figure turns red above this percentage of its allowance.
    var criticalPercent: Int {
        didSet { UserDefaults.standard.set(criticalPercent, forKey: "criticalPercent") }
    }
    /// The row the keyboard is on; nil until an arrow key is pressed.
    var selectedRow: String?
    /// Expanded project rows that show Deployments rather than Usage.
    var deploymentRows: Set<String> = []
    /// The system-wide shortcut that opens the menu.
    var hotKey: KeyCombo? {
        didSet {
            let data = hotKey.flatMap { try? JSONEncoder().encode($0) }
            UserDefaults.standard.set(data, forKey: "cloudflareHotKey")
        }
    }
    /// True when the system refused the shortcut, usually because another app holds it.
    var hotKeyRefused = false
    /// The settings page to show; set before opening the window to land on a page.
    var settingsPane: SettingsPane = .general
    /// Show a green dot in the menu bar when nothing is amber or red.
    var showDotWhenFine: Bool {
        didSet { UserDefaults.standard.set(showDotWhenFine, forKey: "showDotWhenFine") }
    }

    @ObservationIgnored private let configStore = ConfigStore(directory: ConfigStore.defaultDirectory)
    @ObservationIgnored private let cache = SnapshotCache(directory: ConfigStore.defaultDirectory)
    @ObservationIgnored private let tokenStore = TokenStore()
    @ObservationIgnored private var names: [String: (at: Date, names: ResourceNames)] = [:]
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// Set by the app delegate, which owns the settings window.
    @ObservationIgnored var openSettings: (SettingsPane) -> Void = { _ in }
    /// Set by the app delegate: asks for confirmation, then quits.
    @ObservationIgnored var requestQuit: () -> Void = {}

    init() {
        config = (try? configStore.load()) ?? Config()
        expanded = Set(UserDefaults.standard.stringArray(forKey: "expanded") ?? [])
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["warningPercent": 70, "criticalPercent": 90, "showDotWhenFine": true])
        hotKey = defaults.data(forKey: "cloudflareHotKey").flatMap {
            try? JSONDecoder().decode(KeyCombo.self, from: $0)
        }
        warningPercent = defaults.integer(forKey: "warningPercent")
        criticalPercent = defaults.integer(forKey: "criticalPercent")
        showDotWhenFine = defaults.bool(forKey: "showDotWhenFine")
        if DemoData.isOn {
            // Invented data only: no Keychain, no saved settings, no network.
            config = DemoData.config
            expanded = []
            tokens = DemoData.tokenAccounts.enumerated().map { SavedToken(value: "demo-\($0.offset)", accounts: $0.element) }
            for snapshot in DemoData.snapshots() {
                snapshots[snapshot.accountID] = snapshot
            }
            lastRefresh = Date()
            return
        }
        // Once: re-create the Keychain item from this app, so macOS stops asking for the
        // login password on every launch. Earlier builds had the build script create it.
        if !defaults.bool(forKey: "keychainItemOwned"), tokenStore.takeOwnership() {
            defaults.set(true, forKey: "keychainItemOwned")
        }
        tokens = tokenStore.readAll().map { SavedToken(value: $0) }
        for snapshot in cache.load() {
            snapshots[snapshot.accountID] = snapshot
        }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
            }
        }
    }

    var hasToken: Bool { !tokens.isEmpty }

    /// Every account any saved token can see, without duplicates.
    var visibleAccounts: [VisibleAccount] {
        var seen = Set<String>()
        return tokens.flatMap { $0.accounts ?? [] }.filter { seen.insert($0.id).inserted }
    }

    var thresholds: Thresholds {
        Thresholds(warning: Double(warningPercent) / 100, critical: Double(criticalPercent) / 100)
    }

    // MARK: Keyboard navigation

    enum NavigationKey {
        case up, down, left, right, toggle, usageTab, deploymentsTab
    }

    /// The rows the arrow keys move through, top to bottom: each account's header (which
    /// opens its bill), then its projects, then Other.
    var navigableRows: [String] {
        guard hasToken else { return [] }
        var rows: [String] = []
        for account in config.accounts {
            rows.append("\(account.id)/#bill")
            guard let snapshot = snapshots[account.id] else { continue }
            rows.append(contentsOf: snapshot.projects.map { "\(account.id)/\($0.name)" })
            if snapshot.other != nil {
                rows.append("\(account.id)/#other")
            }
        }
        return rows
    }

    /// Up and Down move the selection. Right opens the selected row and Left closes it;
    /// Return or Space toggles it. In an open project, Command-Left and Command-Right switch
    /// between Usage and Deployments.
    func navigate(_ key: NavigationKey) {
        let rows = navigableRows
        guard !rows.isEmpty else { return }
        let index = selectedRow.flatMap { rows.firstIndex(of: $0) }
        switch key {
        case .down:
            selectedRow = rows[index.map { min($0 + 1, rows.count - 1) } ?? 0]
        case .up:
            selectedRow = rows[index.map { max($0 - 1, 0) } ?? rows.count - 1]
        case .right:
            guard let row = selectedRow, index != nil else { return }
            expanded.insert(row)
        case .left:
            guard let row = selectedRow, index != nil else { return }
            expanded.remove(row)
        case .usageTab, .deploymentsTab:
            // Only an open project has tabs; an account's bill does not.
            guard let row = selectedRow, index != nil, expanded.contains(row), !row.hasSuffix("/#bill") else { return }
            if key == .deploymentsTab {
                deploymentRows.insert(row)
            } else {
                deploymentRows.remove(row)
            }
        case .toggle:
            guard let row = selectedRow, index != nil else { return }
            if expanded.contains(row) {
                expanded.remove(row)
            } else {
                expanded.insert(row)
            }
        }
    }

    // MARK: Summary

    /// The worst figure across all projects, which sets the status dot's colour.
    var headline: (text: String, severity: Severity)? {
        Headline.make(config.accounts.compactMap { snapshots[$0.id] }, thresholds: thresholds)
    }

    /// The colour for the menu bar dot: the worst figure in any project, or nil when no dot should show.
    var menuBarStatus: Severity? {
        guard let severity = headline?.severity else { return nil }
        return severity == .normal && !showDotWhenFine ? nil : severity
    }

    // MARK: Tokens

    /// Asks Cloudflare which accounts each token can see, for tokens not asked yet.
    func resolveTokens() async {
        for index in tokens.indices where tokens[index].accounts == nil {
            let value = tokens[index].value
            do {
                let accounts = try await CloudflareClient(token: value).accounts()
                if let current = tokens.firstIndex(where: { $0.value == value }) {
                    tokens[current].accounts = accounts
                    tokens[current].error = nil
                }
            } catch {
                if let current = tokens.firstIndex(where: { $0.value == value }) {
                    tokens[current].error = error.localizedDescription
                }
            }
        }
    }

    private func token(for accountID: String) -> String? {
        tokens.first { ($0.accounts ?? []).contains { $0.id == accountID } }?.value
    }

    /// Verifies the token with Cloudflare, saves it to the Keychain and lists the accounts it can see.
    func addToken(_ text: String) async {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("bearer ") {
            value = String(value.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        guard !value.isEmpty, !value.contains(",") else {
            settingsMessage = "Paste one token."
            return
        }
        guard !tokens.contains(where: { $0.value == value }) else {
            settingsMessage = "That token is already saved."
            return
        }
        do {
            let client = CloudflareClient(token: value)
            try await client.verifyToken()
            let accounts = try await client.accounts()
            try tokenStore.saveAll(tokens.map(\.value) + [value])
            tokens.append(SavedToken(value: value, accounts: accounts))
            settingsMessage = "Token saved. It can see \(accounts.count) account(s)."
            await refresh(force: true)
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    func removeToken(_ id: UUID) {
        let remaining = tokens.filter { $0.id != id }
        do {
            try tokenStore.saveAll(remaining.map(\.value))
            tokens = remaining
            settingsMessage = "Token removed from the Keychain. Delete it in Cloudflare too, under API Tokens."
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    // MARK: Refresh

    /// Fetches every account. Skipped when the last refresh was under a minute ago, unless forced.
    func refresh(force: Bool = false) async {
        guard !DemoData.isOn, !isRefreshing, hasToken, !config.accounts.isEmpty else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < Self.minimumInterval { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await resolveTokens()

        struct Outcome: Sendable {
            var accountID: String
            var snapshot: AccountSnapshot?
            var names: ResourceNames?
            var error: String?
        }
        let now = Date()
        let outcomes = await withTaskGroup(of: Outcome.self) { group in
            for account in config.accounts {
                guard let token = token(for: account.id) else {
                    let reason = tokens.compactMap(\.error).first ?? "No saved token can see this account."
                    group.addTask { Outcome(accountID: account.id, error: reason) }
                    continue
                }
                let cached = names[account.id].flatMap {
                    now.timeIntervalSince($0.at) < Self.namesLifetime ? $0.names : nil
                }
                let lastPlan = snapshots[account.id]?.plan
                group.addTask {
                    do {
                        let raw = try await CloudflareClient(token: token)
                            .fetch(account: account, cachedNames: cached, now: now)
                        let snapshot = UsageBuilder.build(account: account, raw: raw, lastKnownPlan: lastPlan, now: now)
                        return Outcome(accountID: account.id, snapshot: snapshot, names: cached == nil ? raw.names : nil)
                    } catch {
                        return Outcome(accountID: account.id, error: error.localizedDescription)
                    }
                }
            }
            var all: [Outcome] = []
            for await outcome in group { all.append(outcome) }
            return all
        }
        for outcome in outcomes {
            if let snapshot = outcome.snapshot {
                snapshots[outcome.accountID] = snapshot
                errors[outcome.accountID] = nil
            } else {
                errors[outcome.accountID] = outcome.error
            }
            if let fresh = outcome.names {
                names[outcome.accountID] = (now, fresh)
            }
        }
        lastRefresh = now
        try? cache.save(config.accounts.compactMap { snapshots[$0.id] })
    }

    // MARK: Config

    /// Applies a change, saves the config, drops data for removed accounts and refreshes.
    func updateConfig(_ change: (inout Config) -> Void) {
        change(&config)
        if DemoData.isOn { return }  // demo changes are never saved
        do {
            try configStore.save(config)
        } catch {
            settingsMessage = "Could not save settings: \(error.localizedDescription)"
        }
        let ids = Set(config.accounts.map(\.id))
        snapshots = snapshots.filter { ids.contains($0.key) }
        errors = errors.filter { ids.contains($0.key) }
        names = [:]  // prefixes or accounts changed; cheap to look up again
        Task { await refresh(force: true) }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            settingsMessage = "Launch at login: \(error.localizedDescription)"
        }
    }
}
