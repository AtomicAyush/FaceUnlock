import Foundation

/// The owner's enrolled face: a small gallery of embeddings plus the identity of
/// the model that produced them. Embeddings from one model are meaningless to
/// another, so `modelIdentifier` and `dimension` guard against a mismatched
/// template after the model is swapped or upgraded.
public struct FaceTemplate: Codable, Sendable, Equatable {
    public var embeddings: [[Float]]
    public var modelIdentifier: String
    public var dimension: Int
    public var createdAt: Date

    public init(embeddings: [[Float]], modelIdentifier: String, dimension: Int, createdAt: Date) {
        self.embeddings = embeddings
        self.modelIdentifier = modelIdentifier
        self.dimension = dimension
        self.createdAt = createdAt
    }

    public var isEmpty: Bool { embeddings.isEmpty }

    /// True if this template was made by the given model and its vectors are the
    /// right width to compare against that model's output.
    public func isCompatible(withModel id: String, dimension dim: Int) -> Bool {
        modelIdentifier == id && dimension == dim && embeddings.allSatisfy { $0.count == dim }
    }
}
