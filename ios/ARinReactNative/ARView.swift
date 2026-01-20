//
//  ARView.swift
//  ARinReactNative
//
//  AR View component for photogrammetry capture
//

import UIKit
import ARKit
import RealityKit

class ARView: UIView, ARSCNViewDelegate, ARSessionDelegate {
  
  private var sceneView: ARSCNView!
  private var photogrammetryCapture: PhotogrammetryCapture?
  
  // Callbacks for React Native
  var onScanComplete: (([String: Any]) -> Void)?
  var onScanProgress: (([String: Any]) -> Void)?
  
  deinit {
    cleanup()
  }
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
    ARNativeModule.setSharedARView(self)
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
    ARNativeModule.setSharedARView(self)
  }
  
  private func setupView() {
    // Create and configure ARSCNView
    sceneView = ARSCNView(frame: bounds)
    sceneView.delegate = self
    sceneView.session.delegate = self
    sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    
    // Show statistics (FPS, timing)
    sceneView.showsStatistics = true
    
    // Enable default lighting
    sceneView.autoenablesDefaultLighting = true
    
    addSubview(sceneView)
    
    // Initialize photogrammetry capture
    photogrammetryCapture = PhotogrammetryCapture()
    
    // Auto-start the AR session
    startSession()
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    sceneView.frame = bounds
  }
  
  func startSession() {
    guard ARWorldTrackingConfiguration.isSupported else {
      return
    }
    
    let configuration = ARWorldTrackingConfiguration()
    configuration.planeDetection = [.horizontal, .vertical]
    configuration.isLightEstimationEnabled = true
    
    sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
  }
  
  func stopSession() {
    sceneView.session.pause()
    cleanup()
  }
  
  private func cleanup() {
    // Remove all delegates to prevent retain cycles
    sceneView?.session.delegate = nil
    sceneView?.delegate = nil
    
    // Clear callbacks to break retain cycles
    onScanComplete = nil
    onScanProgress = nil
  }
  
  // MARK: - Photogrammetry Scanning
  
  func startObjectScan() {
    do {
      let captureDir = try photogrammetryCapture?.startCapture()
      onScanProgress?(["status": "started", "imageCount": 0])
      print("[ARView] Started photogrammetry capture at: \(captureDir?.path ?? "unknown")")
    } catch {
      print("[ARView] Failed to start capture: \(error)")
      onScanProgress?(["status": "error", "message": error.localizedDescription])
    }
  }
  
  func stopObjectScan() -> [String: Any] {
    guard let capture = photogrammetryCapture else {
      return ["imageCount": 0, "directory": ""]
    }
    
    let result = capture.stopCapture()
    
    let scanData: [String: Any] = [
      "imageCount": result.imageCount,
      "directory": result.directory?.path ?? "",
      "scanType": "photogrammetry"
    ]
    
    onScanComplete?(scanData)
    print("[ARView] Stopped capture. Images: \(result.imageCount)")
    
    return scanData
  }
  
  func clearScan() {
    // Reset photogrammetry capture
    photogrammetryCapture = PhotogrammetryCapture()
  }
  
  func getPhotogrammetryCaptureDirectory() -> String? {
    return photogrammetryCapture?.getCurrentCaptureDirectory()?.path
  }
  
  func getPhotogrammetryImageCount() -> Int {
    return photogrammetryCapture?.getCurrentImageCount() ?? 0
  }
  
  // MARK: - ARSessionDelegate
  
  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    // Process frame for photogrammetry capture
    photogrammetryCapture?.processFrame(frame, currentTime: frame.timestamp)
  }
  
  func session(_ session: ARSession, didFailWithError error: Error) {
    print("[ARView] AR Session failed: \(error.localizedDescription)")
  }
  
  func sessionWasInterrupted(_ session: ARSession) {
    print("[ARView] AR Session was interrupted")
  }
  
  func sessionInterruptionEnded(_ session: ARSession) {
    print("[ARView] AR Session interruption ended")
    // Restart session
    startSession()
  }
}
