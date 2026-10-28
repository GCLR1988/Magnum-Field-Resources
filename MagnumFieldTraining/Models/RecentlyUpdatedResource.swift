import Foundation

/// A dated resource from the current catalog. Missing legacy dates are omitted until sync.
struct RecentlyUpdatedResource: Identifiable {
    let program: Program
    let resource: WalkthroughResource
    let modifiedAt: Date

    var id: String { resource.persistenceKey }

    static func select(
        from documents: [(program: Program, resource: WalkthroughResource)],
        limit: Int = 5
    ) -> [RecentlyUpdatedResource] {
        var seen = Set<String>()
        let dated = documents.compactMap { item -> RecentlyUpdatedResource? in
            guard case .dropbox(let file) = item.resource.location,
                  let date = file.modifiedDate else { return nil }
            return RecentlyUpdatedResource(program: item.program, resource: item.resource, modifiedAt: date)
        }.sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.id < $1.id
        }
        return Array(dated.filter { seen.insert($0.id).inserted }.prefix(max(0, limit)))
    }
}
