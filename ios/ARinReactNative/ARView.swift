//
//  ARView.swift
//  ARinReactNative
//
//  AR View component for displaying camera feed
//

import UIKit
import ARKit

class ARView: UIView, ARSCNViewDelegate {
  
  private var sceneView: ARSCNView!
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }
  
  private func setupView() {
    // Create and configure ARSCNView
    sceneView = ARSCNView(frame: bounds)
    sceneView.delegate = self
    sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    
    // Show statistics (FPS, timing)
    sceneView.showsStatistics = true
    
    // Enable default lighting
    sceneView.autoenablesDefaultLighting = true
    
    addSubview(sceneView)
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    sceneView.frame = bounds
  }
  
  func startSession() {
    guard ARWorldTrackingConfiguration.isSupported else {
      print("ARWorldTracking not supported")
      return
    }
    
    let configuration = ARWorldTrackingConfiguration()
    configuration.planeDetection = [.horizontal, .vertical]
    configuration.isLightEstimationEnabled = true
    
    sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
  }
  
  func stopSession() {
    sceneView.session.pause()
  }
  
  // MARK: - ARSCNViewDelegate
  
  func renderer(_ renderer: any SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
    
    // Create a plane geometry
    let plane = SCNPlane(width: CGFloat(planeAnchor.planeExtent.width),
                        height: CGFloat(planeAnchor.planeExtent.height))
    
    // Create semi-transparent material
    let material = SCNMaterial()
    material.diffuse.contents = UIColor.cyan.withAlphaComponent(0.3)
    plane.materials = [material]
    
    let planeNode = SCNNode(geometry: plane)
    planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
    planeNode.eulerAngles.x = -.pi / 2
    
    node.addChildNode(planeNode)
  }
  
  func renderer(_ renderer: any SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
    guard let planeAnchor = anchor as? ARPlaneAnchor,
          let planeNode = node.childNodes.first,
          let plane = planeNode.geometry as? SCNPlane else { return }
    
    // Update plane dimensions
    plane.width = CGFloat(planeAnchor.planeExtent.width)
    plane.height = CGFloat(planeAnchor.planeExtent.height)
    
    planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
  }
}
