//
//  PhotogrammetryCapture.swift
//  ARinReactNative
//
//  Handles photogrammetry capture using RealityKit's PhotogrammetrySession
//

import Foundation
import ARKit
import RealityKit
import UIKit

class PhotogrammetryCapture {
    private var captureDirectory: URL?
    private var imageCount: Int = 0
    private var isCapturing: Bool = false
    private var lastCaptureTime: TimeInterval = 0
    private let captureInterval: TimeInterval = 0.5 // Capture every 0.5 seconds
    
    // Callbacks for progress updates
    var onProgress: ((String, Float) -> Void)?
    
    // Check if photogrammetry is supported on this device
    static func isPhotogrammetrySupported() -> Bool {
        return PhotogrammetrySession.isSupported
    }
    
    // Start capturing images
    func startCapture() throws -> URL {
        guard !isCapturing else {
            throw NSError(domain: "PhotogrammetryCapture", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Already capturing"])
        }
        
        // Create a timestamped directory in Documents
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = Int(Date().timeIntervalSince1970)
        let captureDir = documentsPath.appendingPathComponent("PhotoCapture_\(timestamp)")
        
        try FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)
        
        self.captureDirectory = captureDir
        self.imageCount = 0
        self.isCapturing = true
        self.lastCaptureTime = 0
        
        print("[PhotogrammetryCapture] Started capture in: \(captureDir.path)")
        return captureDir
    }
    
    // Stop capturing and return results
    func stopCapture() -> (directory: URL?, imageCount: Int) {
        isCapturing = false
        let results = (directory: captureDirectory, imageCount: imageCount)
        print("[PhotogrammetryCapture] Stopped capture. Total images: \(imageCount)")
        return results
    }
    
    // Get current image count without stopping capture
    func getCurrentImageCount() -> Int {
        return imageCount
    }
    
    // Get current capture directory without stopping capture
    func getCurrentCaptureDirectory() -> URL? {
        return captureDirectory
    }
    
    // Check if currently capturing
    func isCurrentlyCapturing() -> Bool {
        return isCapturing
    }
    
    // Process an AR frame and capture if needed
    func processFrame(_ frame: ARFrame, currentTime: TimeInterval) {
        guard isCapturing else { return }
        guard let captureDir = captureDirectory else { return }
        
        // Check if enough time has passed since last capture
        guard currentTime - lastCaptureTime >= captureInterval else { return }
        
        // Use autoreleasepool to manage memory for image conversion
        autoreleasepool {
            do {
                try captureImage(frame: frame, to: captureDir)
                lastCaptureTime = currentTime
                imageCount += 1
                
                print("[PhotogrammetryCapture] Captured image \(imageCount)")
            } catch {
                print("[PhotogrammetryCapture] Failed to capture image: \(error)")
            }
        }
    }
    
    // Capture a single image with metadata
    private func captureImage(frame: ARFrame, to directory: URL) throws {
        // Convert ARFrame's CVPixelBuffer to UIImage
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw NSError(domain: "PhotogrammetryCapture", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        
        // Save image as JPEG
        guard let imageData = uiImage.jpegData(compressionQuality: 0.95) else {
            throw NSError(domain: "PhotogrammetryCapture", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to convert to JPEG"])
        }
        
        let imageFilename = String(format: "image_%04d.jpg", imageCount)
        let imageURL = directory.appendingPathComponent(imageFilename)
        try imageData.write(to: imageURL)
        
        // Save camera metadata
        let metadata: [String: Any] = [
            "transform": matrixToArray(frame.camera.transform),
            "intrinsics": matrixToArray3x3(frame.camera.intrinsics),
            "imageResolution": [
                "width": ciImage.extent.width,
                "height": ciImage.extent.height
            ],
            "exposureDuration": frame.camera.exposureDuration,
            "timestamp": frame.timestamp
        ]
        
        let metadataFilename = String(format: "image_%04d.json", imageCount)
        let metadataURL = directory.appendingPathComponent(metadataFilename)
        let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
        try jsonData.write(to: metadataURL)
    }
    
    // Process captured images with PhotogrammetrySession
    @MainActor
    func processWithPhotogrammetrySession(
        inputDirectory: URL,
        outputFilename: String,
        detail: String = "medium",
        progressCallback: @escaping (String, Float) -> Void
    ) async throws -> URL {
        // Check if photogrammetry is supported
        guard PhotogrammetrySession.isSupported else {
            throw NSError(domain: "PhotogrammetryCapture", code: 4,
                         userInfo: [NSLocalizedDescriptionKey: "Photogrammetry is not supported on this device. Requires Mac with 4GB+ GPU and ray tracing, or iOS device with LiDAR."])
        }
        
        // Map detail level
        let detailLevel: PhotogrammetrySession.Request.Detail = .reduced
        
        // Create output URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputURL = documentsPath.appendingPathComponent("\(outputFilename).usdz")
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        print("[PhotogrammetryCapture] Starting PhotogrammetrySession")
        print("[PhotogrammetryCapture] Input: \(inputDirectory.path)")
        print("[PhotogrammetryCapture] Output: \(outputURL.path)")
        print("[PhotogrammetryCapture] Detail level: \(detail)")
        
        // Create photogrammetry session
        let session = try PhotogrammetrySession(input: inputDirectory)
        
        // Create request
        let request = PhotogrammetrySession.Request.modelFile(
            url: outputURL,
            detail: detailLevel
        )
        
        // Start processing
        try session.process(requests: [request])
        
        // Monitor progress
        for try await output in session.outputs {
            switch output {
            case .processingComplete:
                await MainActor.run {
                    progressCallback("Complete", 1.0)
                }
                print("[PhotogrammetryCapture] Processing complete!")
                return outputURL
                
            case .requestError(let request, let error):
                await MainActor.run {
                    progressCallback("Error: \(error.localizedDescription)", 0.0)
                }
                throw error
                
            case .requestProgress(let request, let fractionComplete):
                await MainActor.run {
                    progressCallback("Processing", Float(fractionComplete))
                }
                print("[PhotogrammetryCapture] Progress: \(Int(fractionComplete * 100))%")
                
            case .inputComplete:
                await MainActor.run {
                    progressCallback("Input validated", 0.1)
                }
                print("[PhotogrammetryCapture] Input complete")
                
            case .requestComplete(let request, let result):
                await MainActor.run {
                    progressCallback("Request complete", 0.95)
                }
                print("[PhotogrammetryCapture] Request complete: \(result)")
                
            case .processingCancelled:
                await MainActor.run {
                    progressCallback("Cancelled", 0.0)
                }
                throw NSError(domain: "PhotogrammetryCapture", code: 5,
                             userInfo: [NSLocalizedDescriptionKey: "Processing was cancelled"])
                
            @unknown default:
                print("[PhotogrammetryCapture] Unknown output: \(output)")
            }
        }
        
        // If we reach here without returning, something went wrong
        throw NSError(domain: "PhotogrammetryCapture", code: 6,
                     userInfo: [NSLocalizedDescriptionKey: "Processing completed without generating output file"])
    }
    
    // Helper: Convert 4x4 matrix to array
    private func matrixToArray(_ matrix: simd_float4x4) -> [[Float]] {
        return [
            [matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w],
            [matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w],
            [matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w],
            [matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w]
        ]
    }
    
    // Helper: Convert 3x3 matrix to array
    private func matrixToArray3x3(_ matrix: simd_float3x3) -> [[Float]] {
        return [
            [matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z],
            [matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z],
            [matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z]
        ]
    }
}
