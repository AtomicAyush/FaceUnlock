import Foundation
import CoreML
import CoreVideo

/// Turns an aligned 112×112 face crop into an embedding vector using a compiled
/// Core ML model (`FaceEmbedding.mlmodelc`) bundled in the app's Resources.
///
/// The model is the only third-party artifact in this project and is downloaded
/// and converted separately (see docs/MODEL.md), then dropped into the bundle by
/// the build script. Until it is present, `load()` returns an embedder with
/// `isAvailable == false`: the app still runs, detects faces, and — per the v1
/// design — does nothing. `embed` then throws rather than inventing a vector.
public final class FaceEmbedder {

    public enum EmbedderError: Error, CustomStringConvertible {
        case modelUnavailable
        case badInput
        case noOutput

        public var description: String {
            switch self {
            case .modelUnavailable: return "The face-embedding model is not installed."
            case .badInput: return "The model rejected the aligned face image."
            case .noOutput: return "The model produced no embedding."
            }
        }
    }

    public let isAvailable: Bool
    public let modelIdentifier: String
    public let dimension: Int

    private let model: MLModel?
    private let inputName: String?
    private let outputName: String?

    private init(model: MLModel?, identifier: String, dimension: Int,
                 inputName: String?, outputName: String?) {
        self.model = model
        self.modelIdentifier = identifier
        self.dimension = dimension
        self.inputName = inputName
        self.outputName = outputName
        self.isAvailable = model != nil
    }

    /// Load `FaceEmbedding.mlmodelc` from the app bundle, or return an unavailable
    /// embedder if it is not there or cannot be read.
    public static func load(bundle: Bundle = .main) -> FaceEmbedder {
        guard let url = bundle.url(forResource: "FaceEmbedding", withExtension: "mlmodelc") else {
            return FaceEmbedder(model: nil, identifier: "none", dimension: 0,
                                inputName: nil, outputName: nil)
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        guard let model = try? MLModel(contentsOf: url, configuration: config) else {
            return FaceEmbedder(model: nil, identifier: "none", dimension: 0,
                                inputName: nil, outputName: nil)
        }

        let desc = model.modelDescription
        // First image input; first multiarray output.
        let input = desc.inputDescriptionsByName.first(where: { $0.value.type == .image })?.key
            ?? desc.inputDescriptionsByName.keys.first
        let outputEntry = desc.outputDescriptionsByName.first(where: { $0.value.type == .multiArray })
            ?? desc.outputDescriptionsByName.first
        let dim = outputEntry?.value.multiArrayConstraint?.shape.last?.intValue ?? 0
        let identifier = (desc.metadata[.description] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent

        return FaceEmbedder(model: model, identifier: identifier, dimension: dim,
                            inputName: input, outputName: outputEntry?.key)
    }

    /// Embed an aligned face crop. The returned vector is L2-normalised so callers
    /// can compare with plain cosine similarity.
    public func embed(_ aligned: CVPixelBuffer) throws -> [Float] {
        guard let model, let inputName, let outputName else { throw EmbedderError.modelUnavailable }

        let value = MLFeatureValue(pixelBuffer: aligned)
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: value]) else {
            throw EmbedderError.badInput
        }
        let result = try model.prediction(from: provider)
        guard let multi = result.featureValue(for: outputName)?.multiArrayValue else {
            throw EmbedderError.noOutput
        }

        var vector = [Float](repeating: 0, count: multi.count)
        for i in 0..<multi.count { vector[i] = multi[i].floatValue }
        return l2Normalized(vector)
    }

    private func l2Normalized(_ v: [Float]) -> [Float] {
        var sum: Double = 0
        for x in v { sum += Double(x) * Double(x) }
        let norm = sum.squareRoot()
        guard norm > 1e-12 else { return v }
        return v.map { Float(Double($0) / norm) }
    }
}
