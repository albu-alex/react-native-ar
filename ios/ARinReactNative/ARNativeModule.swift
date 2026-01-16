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
  
  // MARK: - Module Setup
  
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
  
  // MARK: - Cleanup
  
  deinit {
    arSession?.pause()
    arSession = nil
  }
}
