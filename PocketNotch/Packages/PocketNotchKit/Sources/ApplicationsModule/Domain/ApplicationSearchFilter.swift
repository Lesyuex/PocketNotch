import Foundation

/// 应用搜索过滤规则。
enum ApplicationSearchFilter {
    static func filter(_ applications: [ApplicationItem], query: String) -> [ApplicationItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return applications }
        return applications.filter { $0.name.localizedStandardContains(trimmed) }
    }
}