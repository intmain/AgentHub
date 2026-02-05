import Foundation

/// App Group 기반 공유 스토리지
public class AppGroupStorage {
    public static let shared = AppGroupStorage()

    private let appGroupId = "group.com.agenthub"

    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    private init() {}

    // MARK: - UserDefaults

    public func set(_ value: Any?, forKey key: String) {
        userDefaults?.set(value, forKey: key)
    }

    public func value(forKey key: String) -> Any? {
        userDefaults?.value(forKey: key)
    }

    public func bool(forKey key: String) -> Bool {
        userDefaults?.bool(forKey: key) ?? false
    }

    public func string(forKey key: String) -> String? {
        userDefaults?.string(forKey: key)
    }

    public func data(forKey key: String) -> Data? {
        userDefaults?.data(forKey: key)
    }

    public func remove(forKey key: String) {
        userDefaults?.removeObject(forKey: key)
    }

    // MARK: - File Storage

    public func fileURL(for filename: String) -> URL? {
        containerURL?.appendingPathComponent(filename)
    }

    public func write(_ data: Data, to filename: String) throws {
        guard let url = fileURL(for: filename) else {
            throw StorageError.containerNotAvailable
        }
        try data.write(to: url)
    }

    public func read(from filename: String) throws -> Data {
        guard let url = fileURL(for: filename) else {
            throw StorageError.containerNotAvailable
        }
        return try Data(contentsOf: url)
    }

    public func delete(filename: String) throws {
        guard let url = fileURL(for: filename) else {
            throw StorageError.containerNotAvailable
        }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Codable Helpers

    public func save<T: Encodable>(_ object: T, forKey key: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(object)
        userDefaults?.set(data, forKey: key)
    }

    public func load<T: Decodable>(forKey key: String) throws -> T? {
        guard let data = userDefaults?.data(forKey: key) else {
            return nil
        }
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
            return "App Group 컨테이너를 사용할 수 없습니다."
        case .encodingFailed:
            return "데이터 인코딩에 실패했습니다."
        case .decodingFailed:
            return "데이터 디코딩에 실패했습니다."
        }
    }
}
