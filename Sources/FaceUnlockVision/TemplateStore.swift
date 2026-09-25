import Foundation
import FaceUnlockCore

/// Persists the owner's enrolled `FaceTemplate` to Application Support.
///
/// v1 stores it as JSON with owner-only file permissions (0600). The stored data
/// is the owner's own face embeddings — not a credential, and never the login
/// password (this app has none). Encrypting the template at rest behind Touch ID
/// is a planned follow-up, tracked in docs/SECURITY.md.
public final class TemplateStore {

    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let base = try fileManager.url(for: .applicationSupportDirectory,
                                       in: .userDomainMask,
                                       appropriateFor: nil,
                                       create: true)
        let dir = base.appendingPathComponent("FaceUnlock", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        self.fileURL = dir.appendingPathComponent("enrollment.json")
    }

    public var hasEnrollment: Bool {
        fileManager.fileExists(atPath: fileURL.path)
    }

    public func load() -> FaceTemplate? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(FaceTemplate.self, from: data)
    }

    public func save(_ template: FaceTemplate) throws {
        let data = try JSONEncoder().encode(template)
        try data.write(to: fileURL, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func delete() throws {
        guard hasEnrollment else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
