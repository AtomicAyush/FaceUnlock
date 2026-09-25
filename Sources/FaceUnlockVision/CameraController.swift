import AVFoundation
import CoreVideo

/// Owns an `AVCaptureSession` on the built-in camera and hands each frame to a
/// callback as a `CVPixelBuffer`. Frames are delivered on a private serial queue;
/// the callback must hop to the main actor itself before touching UI.
public final class CameraController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    public enum CameraError: Error, CustomStringConvertible {
        case noCameraFound
        case cannotAddInput
        case cannotAddOutput
        case notAuthorized

        public var description: String {
            switch self {
            case .noCameraFound: return "No built-in camera was found."
            case .cannotAddInput: return "The camera could not be added to the capture session."
            case .cannotAddOutput: return "The video output could not be added to the capture session."
            case .notAuthorized: return "Camera access has not been granted."
            }
        }
    }

    public let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let frameQueue = DispatchQueue(label: "com.ayush.FaceUnlock.frames")

    /// Called for every delivered frame, on `frameQueue`.
    public var onFrame: ((CVPixelBuffer) -> Void)?

    public private(set) var isConfigured = false

    /// Current camera authorization status.
    public static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Ask for camera access if it has not been decided yet.
    public static func requestAccess() async -> Bool {
        switch authorizationStatus {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Build the capture graph: built-in camera → BGRA video frames.
    public func configure() throws {
        guard Self.authorizationStatus == .authorized else { throw CameraError.notAuthorized }

        session.beginConfiguration()
        session.sessionPreset = .vga640x480 // plenty for a face; light on power

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        else {
            session.commitConfiguration()
            throw CameraError.noCameraFound
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.cannotAddInput
        }
        session.addInput(input)

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraError.cannotAddOutput
        }
        session.addOutput(output)

        session.commitConfiguration()
        isConfigured = true
    }

    public func start() {
        guard isConfigured, !session.isRunning else { return }
        frameQueue.async { [session] in session.startRunning() }
    }

    public func stop() {
        guard session.isRunning else { return }
        frameQueue.async { [session] in session.stopRunning() }
    }

    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
