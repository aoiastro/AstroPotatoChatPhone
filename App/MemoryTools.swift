import Foundation
import LocalLLMClient

actor MemoryStore {
    private static let userDefaultsKey = "apcp.memory.v1"
    private var storage: [String: String]

    init() {
        if
            let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        {
            storage = decoded
        } else {
            storage = [:]
        }
    }

    func upsert(key: String, value: String) -> Int {
        storage[key] = value
        persist()
        return storage.count
    }

    func value(for key: String) -> String? {
        storage[key]
    }

    func search(query: String, limit: Int) -> [[String: String]] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cappedLimit = max(1, min(limit, 10))

        let items = storage
            .filter { key, value in
                if normalized.isEmpty { return true }
                return key.lowercased().contains(normalized) || value.lowercased().contains(normalized)
            }
            .sorted { $0.key < $1.key }
            .prefix(cappedLimit)
            .map { ["key": $0.key, "value": $0.value] }

        return Array(items)
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(storage) {
            UserDefaults.standard.set(encoded, forKey: Self.userDefaultsKey)
        }
    }
}

@Tool("remember_user_fact")
struct RememberUserFactTool: LLMTool {
    let description = "Save stable user facts like preferences, profile, habits, and constraints."
    let store: MemoryStore

    @ToolArguments
    struct Arguments: Sendable {
        @ToolArgument("Short key for the fact. Example: favorite_language")
        var key: String

        @ToolArgument("Value to remember for that key.")
        var value: String
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        let normalizedKey = arguments.key.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = arguments.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = await store.upsert(key: normalizedKey, value: normalizedValue)
        return ToolOutput(data: [
            "ok": true,
            "saved_key": normalizedKey,
            "saved_value": normalizedValue,
            "memory_count": count
        ])
    }
}

@Tool("recall_user_fact")
struct RecallUserFactTool: LLMTool {
    let description = "Load one user fact by key."
    let store: MemoryStore

    @ToolArguments
    struct Arguments: Sendable {
        @ToolArgument("Key to look up.")
        var key: String
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        let normalizedKey = arguments.key.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = await store.value(for: normalizedKey)
        return ToolOutput(data: [
            "key": normalizedKey,
            "value": value ?? "",
            "found": value != nil
        ])
    }
}

@Tool("search_user_memory")
struct SearchUserMemoryTool: LLMTool {
    let description = "Search saved user facts by text query."
    let store: MemoryStore

    @ToolArguments
    struct Arguments: Sendable {
        @ToolArgument("Query string to search in memory keys and values.")
        var query: String

        @ToolArgument("Max number of results to return (1-10).")
        var limit: Int?
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        let results = await store.search(query: arguments.query, limit: arguments.limit ?? 5)
        return ToolOutput(data: [
            "query": arguments.query,
            "count": results.count,
            "results": results
        ])
    }
}
