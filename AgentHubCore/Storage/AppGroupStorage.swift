import Foundation

/// App Group Container 기반 공유 스토리지 (앱과 위젯 간)
public class AppGroupStorage {
    public static let shared = AppGroupStorage()

    // App Group ID (엔타이틀먼트의 $(TeamIdentifierPrefix)group.com.agenthub 에 대응)
    private let appGroupId = "8LHHKYA787.group.com.agenthub"

    private var containerURL: URL {
        if let groupContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            return groupContainer
        }
        // Fallback
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("AgentHub")
    }

    private init() {
        ensureContainerExists()
    }

    private func ensureContainerExists() {
        let fm = FileManager.default
        let dir = containerURL
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - UserDefaults (호환성 유지)

    private var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? UserDefaults.standard
    }

    public func set(_ value: Any?, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    public func value(forKey key: String) -> Any? {
        userDefaults.value(forKey: key)
    }

    public func bool(forKey key: String) -> Bool {
        userDefaults.bool(forKey: key)
    }

    public func string(forKey key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    public func data(forKey key: String) -> Data? {
        userDefaults.data(forKey: key)
    }

    public func remove(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }

    // MARK: - File Storage

    public func fileURL(for filename: String) -> URL {
        ensureContainerExists()
        return containerURL.appendingPathComponent(filename)
    }

    public func write(_ data: Data, to filename: String) throws {
        let url = fileURL(for: filename)
        try data.write(to: url, options: .atomic)
    }

    public func read(from filename: String) throws -> Data {
        let url = fileURL(for: filename)
        return try Data(contentsOf: url)
    }

    public func delete(filename: String) throws {
        let url = fileURL(for: filename)
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Codable Helpers

    public func save<T: Encodable>(_ object: T, forKey key: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(object)
        let url = fileURL(for: "\(key).json")
        try data.write(to: url, options: .atomic)
    }

    public func load<T: Decodable>(forKey key: String) throws -> T? {
        let url = fileURL(for: "\(key).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Errors

public enum StorageError: Error, LocalizedError {
    case containerNotAvailable
    case encodingFailed
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .containerNotAvailable:
            return "공유 컨테이너를 사용할 수 없습니다."
        case .encodingFailed:
            return "데이터 인코딩에 실패했습니다."
        case .decodingFailed:
            return "데이터 디코딩에 실패했습니다."
        }
    }
}
