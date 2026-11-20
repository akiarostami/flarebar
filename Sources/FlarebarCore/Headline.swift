import Foundation

/// The one-line summary: the worst bar across all projects (Other included) and the total bill across accounts,
/// for example "Storefront R2 74% · $10.05".
public enum Headline {
    public static func make(_ snapshots: [AccountSnapshot], thresholds: Thresholds = .standard) -> (text: String, severity: Severity)? {
        var worst: (project: String, bar: Bar)?
        for snapshot in snapshots {
            for project in snapshot.projectsAndOther {
                guard let bar = project.worstBar else { continue }
                if worst == nil || bar.ratio > worst!.bar.ratio {
                    worst = (project.name, bar)
                }
            }
        }
        guard let worst else { return nil }
        var text = "\(worst.project) \(worst.bar.shortLabel) \(Format.percent(worst.bar.ratio))"
        let totals = snapshots.compactMap { $0.bill.totalUSD }
        if !totals.isEmpty {
            text += " · " + Format.money(totals.reduce(0, +))
        }
        return (text, worst.bar.severity(thresholds))
    }
}
