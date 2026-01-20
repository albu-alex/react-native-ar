//
//  ARNativeModule.swift
//  ARinReactNative
//
//  Created by React Native on 2026-01-16.
//

import Foundation
import ARKit

@objc(ARNativeModule)
class ARNativeModule: NSObject {
  private var arSession: ARSession?
  private static var sharedARView: ARView?
  
  @objc
  static func setSharedARView(_ view: ARView) {
    sharedARView = view
  }
  
  @objc
  static func requiresMainQueueSetup() -> Bool {
    return true
  }
  
  // MARK: - Public API
  
  /// Check if AR is supported on this device
  /// Returns: Promise<boolean> - true if ARWorldTrackingConfiguration is supported
  @objc
  func isSupported(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    let supported = ARWorldTrackingConfiguration.isSupported
    resolve(supported)
  }
  
  /// Start an AR session with world tracking configuration
  /// Returns: Promise<void> - resolves when session starts, rejects on error
  @objc
  func startSession(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    // Check if AR is supported first
    guard ARWorldTrackingConfiguration.isSupported else {
      reject(
        "AR_NOT_SUPPORTED",
        "ARKit is not supported on this device",
        NSError(domain: "ARNativeModule", code: 1, userInfo: nil)
      )
      return
    }
    
    // Initialize session if needed
    if arSession == nil {
      arSession = ARSession()
    }
    
    // Configure the session
    let configuration = ARWorldTrackingConfiguration()
    
    // Enable plane detection (optional, can be customized later)
    configuration.planeDetection = [.horizontal, .vertical]
    
    // Enable light estimation
    configuration.isLightEstimationEnabled = true
    
    // Run the session
    arSession?.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    
    resolve(nil)
  }
  
  /// Stop the current AR session
  /// Returns: Promise<void> - resolves when session stops
  @objc
  func stopSession(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    guard let session = arSession else {
      // Session already stopped or never started
      resolve(nil)
      return
    }
    
    session.pause()
    resolve(nil)
  }
  
  // MARK: - Object Scanning Methods
  
  @objc
  func startObjectScan(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    guard let arView = ARNativeModule.sharedARView else {
      reject(
        "AR_VIEW_NOT_FOUND",
        "AR View is not initialized",
        NSError(domain: "ARNativeModule", code: 2, userInfo: nil)
      )
      return
    }
    
    DispatchQueue.main.async {
      arView.startObjectScan()
      resolve(nil)
    }
  }
  
  @objc
  func stopObjectScan(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    guard let arView = ARNativeModule.sharedARView else {
      reject(
        "AR_VIEW_NOT_FOUND",
        "AR View is not initialized",
        NSError(domain: "ARNativeModule", code: 2, userInfo: nil)
      )
      return
    }
    
    DispatchQueue.main.async {
      let scanData = arView.stopObjectScan()
      resolve(scanData)
    }
  }
  
  @objc
  func clearScan(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    guard let arView = ARNativeModule.sharedARView else {
      reject(
        "AR_VIEW_NOT_FOUND",
        "AR View is not initialized",
        NSError(domain: "ARNativeModule", code: 2, userInfo: nil)
      )
      return
    }
    
    DispatchQueue.main.async {
      arView.clearScan()
      resolve(nil)
    }
  }
  
  // MARK: - Photogrammetry Methods
  
  /// Check if photogrammetry is supported on this device
  /// Requires Mac with 4GB+ GPU and ray tracing, or iOS device with LiDAR
  @objc
  func isPhotogrammetrySupported(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    let supported = PhotogrammetryCapture.isPhotogrammetrySupported()
    resolve(supported)
  }
  
  /// Process captured images with PhotogrammetrySession
  /// @param inputDirectory: Path to directory containing captured images
  /// @param outputFilename: Name for output USDZ file (without extension)
  /// @param detail: Quality level - "reduced", "medium", "full", or "raw"
  /// @param progressCallback: RCTResponseSenderBlock for progress updates
  @objc
  func processPhotogrammetry(
    _ inputDirectory: String,
    outputFilename: String,
    detail: String,
    progressCallback: @escaping RCTResponseSenderBlock,
    resolver resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    // Check if photogrammetry is supported
    guard PhotogrammetryCapture.isPhotogrammetrySupported() else {
      reject(
        "PHOTOGRAMMETRY_NOT_SUPPORTED",
        "Photogrammetry is not supported on this device. Requires Mac with 4GB+ GPU and ray tracing, or iOS device with LiDAR.",
        NSError(domain: "ARNativeModule", code: 7, userInfo: nil)
      )
      return
    }
    
    // Stop AR session before processing
    guard let arView = ARNativeModule.sharedARView else {
      reject(
        "AR_VIEW_NOT_FOUND",
        "AR View is not initialized",
        NSError(domain: "ARNativeModule", code: 2, userInfo: nil)
      )
      return
    }
    
    DispatchQueue.main.async {
      arView.stopSession()
      
      Task { @MainActor in
        do {
          let photogrammetry = PhotogrammetryCapture()
          let inputURL = URL(fileURLWithPath: inputDirectory)
          
          let outputURL = try await photogrammetry.processWithPhotogrammetrySession(
            inputDirectory: inputURL,
            outputFilename: outputFilename,
            detail: detail
          ) { status, progress in
            // Send progress updates
            progressCallback([[
              "status": status,
              "progress": progress
            ]])
          }
          
          // Restart AR session after processing
          arView.startSession()
          
          resolve(outputURL.path)
        } catch {
          // Restart AR session even on error
          arView.startSession()
          
          reject(
            "PHOTOGRAMMETRY_FAILED",
            "Failed to process photogrammetry: \(error.localizedDescription)",
            error as NSError
          )
        }
      }
    }
  }
  
  /// Get the directory where photogrammetry images are being captured
  @objc
  func getPhotogrammetryCaptureDirectory(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    guard let arView = ARNativeModule.sharedARView else {
      reject(
        "AR_VIEW_NOT_FOUND",
        "AR View is not initialized",
        NSError(domain: "ARNativeModule", code: 2, userInfo: nil)
      )
      return
    }
    
    DispatchQueue.main.async {
      if let directory = arView.getPhotogrammetryCaptureDirectory() {
        resolve(directory)
      } else {
        resolve(NSNull())
      }
    }
  }
  
  /// Get the current count of captured images
  @objc
  func getPhotogrammetryImageCount(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    guard let arView = ARNativeModule.sharedARView else {
      reject(
        "AR_VIEW_NOT_FOUND",
        "AR View is not initialized",
        NSError(domain: "ARNativeModule", code: 2, userInfo: nil)
      )
      return
    }
    
    DispatchQueue.main.async {
      let count = arView.getPhotogrammetryImageCount()
      resolve(count)
    }
  }
  
  // MARK: - Cleanup
  
  deinit {
    arSession?.pause()
    arSession = nil
  }
}
