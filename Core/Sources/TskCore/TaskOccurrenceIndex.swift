extension TaskRecord {
    var occurrenceIndex: Int? {
        guard let raw = attributes["imask"] else { return nil }
        let parts = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let whole = parts.first, !whole.isEmpty,
              whole.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        if parts.count == 2 {
            guard !parts[1].isEmpty, parts[1].utf8.allSatisfy({ $0 == 48 }) else { return nil }
        }
        return Int(whole)
    }
}
