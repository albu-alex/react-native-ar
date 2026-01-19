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
  
  @objc
  func exportScanAsOBJ(
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
      if let objContent = arView.exportScanAsOBJ() {
        resolve(objContent)
      } else {
        reject(
          "NO_SCAN_DATA",
          "No scan data available to export",
          NSError(domain: "ARNativeModule", code: 3, userInfo: nil)
        )
      }
    }
  }
  
  @objc
  func saveOBJToFile(
    _ filename: String,
    resolver resolve: @escaping RCTPromiseResolveBlock,
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
    
    // Perform save synchronously on main thread to ensure completion
    DispatchQueue.main.async {
      guard let fileURL = arView.saveOBJToFile(filename: filename) else {
        reject(
          "SAVE_FAILED",
          "Failed to save OBJ file - no data available or write failed",
          NSError(domain: "ARNativeModule", code: 4, userInfo: nil)
        )
        return
      }
      
      // File has been saved and verified by saveOBJToFile
      // Double-check accessibility before returning
      let fileManager = FileManager.default
      guard fileManager.fileExists(atPath: fileURL.path),
            fileManager.isReadableFile(atPath: fileURL.path) else {
        reject(
          "FILE_NOT_ACCESSIBLE",
          "File was created but is not accessible after verification",
          NSError(domain: "ARNativeModule", code: 5, userInfo: nil)
        )
        return
      }
      
      // Try to get file size as final verification
      do {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        if let fileSize = attributes[.size] as? UInt64, fileSize > 0 {
          print("[ARNativeModule] File ready for sharing: \(fileURL.path), size: \(fileSize) bytes")
          // Return the absolute file path
          resolve(fileURL.path)
        } else {
          reject(
            "FILE_EMPTY",
            "File was created but has no content",
            NSError(domain: "ARNativeModule", code: 6, userInfo: nil)
          )
        }
      } catch {
        reject(
          "FILE_VERIFICATION_FAILED",
          "Failed to verify file: \(error.localizedDescription)",
          error as NSError
        )
      }
    }
  }
  
  // MARK: - Cleanup
  
  deinit {
    arSession?.pause()
    arSession = nil
  }
}
