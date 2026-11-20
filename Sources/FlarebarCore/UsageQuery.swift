import Foundation

/// The GraphQL usage query: today's and the period's counters per resource, R2 operations
/// for the period, and recent R2 storage samples.
public enum UsageQuery {
    public static let text = """
    query Usage(
      $accountTag: string!
      $dayStart: Time!
      $monthStart: Time!
      $storageStart: Time!
      $now: Time!
      $today: Date!
      $periodDate: Date!
    ) {
      viewer {
        accounts(filter: { accountTag: $accountTag }) {
          workers: workersInvocationsAdaptive(limit: 10000, filter: { datetime_geq: $dayStart, datetime_leq: $now }) {
            sum { requests }
            dimensions { scriptName }
          }
          d1: d1AnalyticsAdaptiveGroups(limit: 10000, filter: { date_geq: $today }) {
            sum { rowsRead rowsWritten }
            dimensions { databaseId }
          }
          kv: kvOperationsAdaptiveGroups(limit: 10000, filter: { date_geq: $today, actionType: "read" }) {
            sum { requests }
            dimensions { namespaceId }
          }
          durableObjects: durableObjectsInvocationsAdaptiveGroups(limit: 10000, filter: { datetime_geq: $dayStart, datetime_leq: $now }) {
            sum { requests }
            dimensions { namespaceId }
          }
          workersMonth: workersInvocationsAdaptive(limit: 10000, filter: { datetime_geq: $monthStart, datetime_leq: $now }) {
            sum { requests }
            dimensions { scriptName }
          }
          d1Month: d1AnalyticsAdaptiveGroups(limit: 10000, filter: { date_geq: $periodDate }) {
            sum { rowsRead rowsWritten }
            dimensions { databaseId }
          }
          kvMonth: kvOperationsAdaptiveGroups(limit: 10000, filter: { date_geq: $periodDate, actionType: "read" }) {
            sum { requests }
            dimensions { namespaceId }
          }
          durableObjectsMonth: durableObjectsInvocationsAdaptiveGroups(limit: 10000, filter: { datetime_geq: $monthStart, datetime_leq: $now }) {
            sum { requests }
            dimensions { namespaceId }
          }
          r2Ops: r2OperationsAdaptiveGroups(limit: 10000, filter: { datetime_geq: $monthStart, datetime_leq: $now }) {
            sum { requests }
            dimensions { actionType bucketName }
          }
          r2Storage: r2StorageAdaptiveGroups(limit: 10000, filter: { datetime_geq: $storageStart, datetime_leq: $now }, orderBy: [datetime_DESC]) {
            max { payloadSize }
            dimensions { bucketName datetime }
          }
        }
      }
    }
    """

    public static func variables(accountID: String, now: Date, monthStart: Date) -> [String: String] {
        let calendar = UsageBuilder.utc
        let dayStart = calendar.startOfDay(for: now)
        let time = DateFormatter()
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        let day = UsageBuilder.dayFormatter()
        return [
            "accountTag": accountID,
            "dayStart": time.string(from: dayStart),
            "monthStart": time.string(from: monthStart),
            "periodDate": day.string(from: monthStart),
            // Storage is sampled periodically; look back far enough to find the latest sample.
            "storageStart": time.string(from: now.addingTimeInterval(-3 * 86400)),
            "now": time.string(from: now),
            "today": day.string(from: dayStart),
        ]
    }
}
