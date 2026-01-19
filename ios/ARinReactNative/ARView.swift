//
//  ARView.swift
//  ARinReactNative
//
//  AR View component for displaying camera feed
//

import UIKit
import ARKit

class ARView: UIView, ARSCNViewDelegate, ARSessionDelegate {
  
  private var sceneView: ARSCNView!
  private var featurePointNode: SCNNode?
  private var hasLiDAR: Bool = false
  private var accumulatedPoints: [SIMD3<Float>] = []
  private var shapeDetectionNode: SCNNode?
  private var frameCount: Int = 0
  
  // Object scanning properties
  private var isScanning: Bool = false
  private var scannedMeshNodes: [SCNNode] = []
  private var scanBoundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)?
  private var meshAnchors: [ARMeshAnchor] = []
  private var objectScanNode: SCNNode?
  
  // Performance optimization
  private var lastVisualizationUpdate: TimeInterval = 0
  private let visualizationUpdateInterval: TimeInterval = 0.1 // 10 times per second
  private var processingQueue = DispatchQueue(label: "com.arview.processing", qos: .userInitiated)
  
  // Callbacks for React Native
  var onScanComplete: (([String: Any]) -> Void)?
  var onScanProgress: (([String: Any]) -> Void)?
  
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
    
    // Enable LiDAR scene reconstruction if available
    if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
      configuration.sceneReconstruction = .mesh
      hasLiDAR = true
    } else {
      hasLiDAR = false
    }
    
    sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    
    // Initialize feature point visualization for non-LiDAR devices
    if !hasLiDAR {
      setupFeaturePointVisualization()
    }
  }
  
  func stopSession() {
    sceneView.session.pause()
  }
  
  // MARK: - Object Scanning
  
  func startObjectScan(at position: SCNVector3? = nil) {
    isScanning = true
    scannedMeshNodes.removeAll()
    meshAnchors.removeAll()
    accumulatedPoints.removeAll()
    scanBoundingBox = nil
    lastVisualizationUpdate = 0
    
    // Create scan visualization node
    objectScanNode = SCNNode()
    sceneView.scene.rootNode.addChildNode(objectScanNode!)
    
    onScanProgress?(["status": "started", "meshCount": 0])
  }
  
  func stopObjectScan() -> [String: Any] {
    isScanning = false
    
    let scanData: [String: Any]
    
    // Use LiDAR mesh data if available, otherwise use feature points
    if hasLiDAR && !meshAnchors.isEmpty {
      scanData = generateScanData()
    } else {
      scanData = generateFeaturePointScanData()
    }
    
    onScanComplete?(scanData)
    
    return scanData
  }
  
  func clearScan() {
    isScanning = false
    scannedMeshNodes.removeAll()
    meshAnchors.removeAll()
    scanBoundingBox = nil
    objectScanNode?.removeFromParentNode()
    objectScanNode = nil
  }
  
  private func generateFeaturePointScanData() -> [String: Any] {
    guard !accumulatedPoints.isEmpty else {
      print("[ARView] No feature points accumulated")
      return [
        "vertices": [],
        "faces": [],
        "vertexCount": 0,
        "faceCount": 0,
        "meshCount": 0,
        "boundingBox": [:],
        "scanType": "featurePoints"
      ]
    }
    
    print("[ARView] Generating feature point scan data with \(accumulatedPoints.count) points")
    
    var vertices: [[Float]] = []
    vertices.reserveCapacity(accumulatedPoints.count)
    
    var minPoint = accumulatedPoints[0]
    var maxPoint = accumulatedPoints[0]
    
    // Convert feature points to vertices
    for point in accumulatedPoints {
      vertices.append([point.x, point.y, point.z])
      
      // Update bounding box
      minPoint = SIMD3<Float>(
        min(minPoint.x, point.x),
        min(minPoint.y, point.y),
        min(minPoint.z, point.z)
      )
      maxPoint = SIMD3<Float>(
        max(maxPoint.x, point.x),
        max(maxPoint.y, point.y),
        max(maxPoint.z, point.z)
      )
    }
    
    // Generate faces using simple triangulation
    // For a basic point cloud, we'll create a simple mesh
    var faces: [[Int]] = []
    
    // Simple triangulation: connect nearby points
    let stride = max(1, accumulatedPoints.count / 1000) // Limit complexity
    for i in stride..<min(accumulatedPoints.count - 2 * stride, 1000) where i % stride == 0 {
      faces.append([i, i + stride, i + 2 * stride])
    }
    
    return [
      "vertices": vertices,
      "faces": faces,
      "vertexCount": vertices.count,
      "faceCount": faces.count,
      "meshCount": 1,
      "boundingBox": [
        "min": [minPoint.x, minPoint.y, minPoint.z],
        "max": [maxPoint.x, maxPoint.y, maxPoint.z]
      ],
      "scanType": "featurePoints"
    ]
  }
  
  private func generateScanData() -> [String: Any] {
    var vertices: [[Float]] = []
    var faces: [[Int]] = []
    var totalVertexCount = 0
    
    // Combine all mesh anchors
    for meshAnchor in meshAnchors {
      let geometry = meshAnchor.geometry
      let transform = meshAnchor.transform
      
      // Extract vertices and transform them to world space
      let vertexBuffer = geometry.vertices.buffer.contents()
      let vertexStride = geometry.vertices.stride
      let vertexCount = geometry.vertices.count
      
      for i in 0..<vertexCount {
        let vertexPointer = vertexBuffer.advanced(by: i * vertexStride)
        let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        
        // Transform vertex to world space
        let worldVertex = simd_mul(transform, SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1.0))
        vertices.append([worldVertex.x, worldVertex.y, worldVertex.z])
      }
      
      // Extract faces (triangles)
      let faceBuffer = geometry.faces.buffer.contents()
      let faceCount = geometry.faces.count
      let bytesPerIndex = geometry.faces.bytesPerIndex
      
      for i in 0..<faceCount {
        let facePointer = faceBuffer.advanced(by: i * bytesPerIndex * 3)
        
        if bytesPerIndex == 2 {
          let indices = facePointer.assumingMemoryBound(to: UInt16.self)
          faces.append([
            Int(indices[0]) + totalVertexCount,
            Int(indices[1]) + totalVertexCount,
            Int(indices[2]) + totalVertexCount
          ])
        } else if bytesPerIndex == 4 {
          let indices = facePointer.assumingMemoryBound(to: UInt32.self)
          faces.append([
            Int(indices[0]) + totalVertexCount,
            Int(indices[1]) + totalVertexCount,
            Int(indices[2]) + totalVertexCount
          ])
        }
      }
      
      totalVertexCount += vertexCount
    }
    
    return [
      "vertices": vertices,
      "faces": faces,
      "vertexCount": totalVertexCount,
      "faceCount": faces.count,
      "meshCount": meshAnchors.count,
      "boundingBox": scanBoundingBox != nil ? [
        "min": [scanBoundingBox!.min.x, scanBoundingBox!.min.y, scanBoundingBox!.min.z],
        "max": [scanBoundingBox!.max.x, scanBoundingBox!.max.y, scanBoundingBox!.max.z]
      ] : [:],
      "scanType": "lidar"
    ]
  }
  
  func exportScanAsOBJ() -> String? {
    // Export LiDAR mesh if available
    if hasLiDAR && !meshAnchors.isEmpty {
      return exportMeshAsOBJ()
    }
    
    // Export feature points for non-LiDAR devices
    if !accumulatedPoints.isEmpty {
      return exportFeaturePointsAsOBJ()
    }
    
    return nil
  }
  
  private func exportFeaturePointsAsOBJ() -> String? {
    guard !accumulatedPoints.isEmpty else { return nil }
    
    var objString = "# Object scan exported from ARView (Feature Points)\n"
    objString += "# Vertices: \n"
    
    // Export vertices
    for point in accumulatedPoints {
      objString += "v \(point.x) \(point.y) \(point.z)\n"
    }
    
    objString += "# Point cloud - no faces generated\n"
    
    return objString
  }
  
  private func exportMeshAsOBJ() -> String? {
    guard !meshAnchors.isEmpty else { return nil }
    
    var objString = "# Object scan exported from ARView (LiDAR)\n"
    objString += "# Vertices: \n"
    
    var totalVertexCount = 0
    
    // Export vertices
    for meshAnchor in meshAnchors {
      let geometry = meshAnchor.geometry
      let transform = meshAnchor.transform
      
      let vertexBuffer = geometry.vertices.buffer.contents()
      let vertexStride = geometry.vertices.stride
      let vertexCount = geometry.vertices.count
      
      for i in 0..<vertexCount {
        let vertexPointer = vertexBuffer.advanced(by: i * vertexStride)
        let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        
        // Transform to world space
        let worldVertex = simd_mul(transform, SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1.0))
        objString += "v \(worldVertex.x) \(worldVertex.y) \(worldVertex.z)\n"
      }
      
      totalVertexCount += vertexCount
    }
    
    objString += "# Faces: \n"
    var faceOffset = 1
    
    // Export faces
    for meshAnchor in meshAnchors {
      let geometry = meshAnchor.geometry
      let faceBuffer = geometry.faces.buffer.contents()
      let faceCount = geometry.faces.count
      let bytesPerIndex = geometry.faces.bytesPerIndex
      
      for i in 0..<faceCount {
        let facePointer = faceBuffer.advanced(by: i * bytesPerIndex * 3)
        
        if bytesPerIndex == 2 {
          let indices = facePointer.assumingMemoryBound(to: UInt16.self)
          objString += "f \(Int(indices[0]) + faceOffset) \(Int(indices[1]) + faceOffset) \(Int(indices[2]) + faceOffset)\n"
        } else if bytesPerIndex == 4 {
          let indices = facePointer.assumingMemoryBound(to: UInt32.self)
          objString += "f \(Int(indices[0]) + faceOffset) \(Int(indices[1]) + faceOffset) \(Int(indices[2]) + faceOffset)\n"
        }
      }
      
      faceOffset += geometry.vertices.count
    }
    
    return objString
  }
  
  func saveOBJToFile(filename: String = "scan") -> URL? {
    guard let objContent = exportScanAsOBJ() else { return nil }
    
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let fileURL = documentsPath.appendingPathComponent("\(filename).obj")
    
    do {
      try objContent.write(to: fileURL, atomically: true, encoding: .utf8)
      return fileURL
    } catch {
      return nil
    }
  }
  
  // MARK: - ARSCNViewDelegate
  
  func renderer(_ renderer: any SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    // Handle mesh anchors from LiDAR scanning
    if let meshAnchor = anchor as? ARMeshAnchor {
      let meshNode = createMeshNode(from: meshAnchor)
      node.addChildNode(meshNode)
      
      // If scanning, store mesh data
      if isScanning {
        meshAnchors.append(meshAnchor)
        scannedMeshNodes.append(meshNode)
        updateScanBoundingBox(with: meshAnchor)
        
        onScanProgress?([
          "status": "scanning",
          "meshCount": meshAnchors.count,
          "vertexCount": meshAnchor.geometry.vertices.count
        ])
      }
      
      return
    }
    
    // Handle plane anchors
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
    // Update mesh anchors from LiDAR
    if let meshAnchor = anchor as? ARMeshAnchor {
      guard let meshNode = node.childNodes.first else { return }
      updateMeshNode(meshNode, from: meshAnchor)
      
      // If scanning, update stored mesh data
      if isScanning {
        if let index = meshAnchors.firstIndex(where: { $0.identifier == meshAnchor.identifier }) {
          meshAnchors[index] = meshAnchor
          updateScanBoundingBox(with: meshAnchor)
        }
      }
      
      return
    }
    
    // Update plane anchors
    guard let planeAnchor = anchor as? ARPlaneAnchor,
          let planeNode = node.childNodes.first,
          let plane = planeNode.geometry as? SCNPlane else { return }
    
    // Update plane dimensions
    plane.width = CGFloat(planeAnchor.planeExtent.width)
    plane.height = CGFloat(planeAnchor.planeExtent.height)
    
    planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
  }
  
  // MARK: - LiDAR Mesh Handling
  
  private func updateScanBoundingBox(with meshAnchor: ARMeshAnchor) {
    let vertices = meshAnchor.geometry.vertices
    let buffer = vertices.buffer.contents()
    let stride = vertices.stride
    let transform = meshAnchor.transform
    
    for i in 0..<vertices.count {
      let vertexPointer = buffer.advanced(by: i * stride)
      let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
      let worldVertex = simd_mul(transform, SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1.0))
      let point = SIMD3<Float>(worldVertex.x, worldVertex.y, worldVertex.z)
      
      if scanBoundingBox == nil {
        scanBoundingBox = (point, point)
      } else {
        scanBoundingBox = (
          min: SIMD3<Float>(
            min(scanBoundingBox!.min.x, point.x),
            min(scanBoundingBox!.min.y, point.y),
            min(scanBoundingBox!.min.z, point.z)
          ),
          max: SIMD3<Float>(
            max(scanBoundingBox!.max.x, point.x),
            max(scanBoundingBox!.max.y, point.y),
            max(scanBoundingBox!.max.z, point.z)
          )
        )
      }
    }
  }
  
  private func createMeshNode(from meshAnchor: ARMeshAnchor) -> SCNNode {
    let meshGeometry = createGeometry(from: meshAnchor.geometry)
    let meshNode = SCNNode(geometry: meshGeometry)
    
    // Create material based on scanning state
    let material = SCNMaterial()
    
    if isScanning {
      // Solid material with semi-transparency for scanning
      material.fillMode = .fill
      material.diffuse.contents = UIColor.cyan.withAlphaComponent(0.5)
      material.transparency = 0.5
    } else {
      // Wireframe for normal viewing
      material.fillMode = .lines
      material.diffuse.contents = UIColor.green.withAlphaComponent(0.6)
    }
    
    material.lightingModel = .constant
    meshGeometry.materials = [material]
    
    return meshNode
  }
  
  private func updateMeshNode(_ node: SCNNode, from meshAnchor: ARMeshAnchor) {
    let meshGeometry = createGeometry(from: meshAnchor.geometry)
    node.geometry = meshGeometry
    
    // Update material
    let material = SCNMaterial()
    material.fillMode = .lines
    material.diffuse.contents = UIColor.green.withAlphaComponent(0.6)
    material.lightingModel = .constant
    meshGeometry.materials = [material]
  }
  
  private func createGeometry(from meshGeometry: ARMeshGeometry) -> SCNGeometry {
    // Extract vertices
    let vertices = meshGeometry.vertices
    let vertexSource = SCNGeometrySource(buffer: vertices.buffer,
                                         vertexFormat: vertices.format,
                                         semantic: .vertex,
                                         vertexCount: vertices.count,
                                         dataOffset: vertices.offset,
                                         dataStride: vertices.stride)
    
    // Extract faces
    let faces = meshGeometry.faces
    let faceData = Data(bytesNoCopy: faces.buffer.contents(),
                       count: faces.buffer.length,
                       deallocator: .none)
    let geometryElement = SCNGeometryElement(data: faceData,
                                            primitiveType: .triangles,
                                            primitiveCount: faces.count,
                                            bytesPerIndex: faces.bytesPerIndex)
    
    return SCNGeometry(sources: [vertexSource], elements: [geometryElement])
  }
  
  // MARK: - Feature Point Visualization (Non-LiDAR devices)
  
  private func setupFeaturePointVisualization() {
    // Create a parent node for feature points
    featurePointNode = SCNNode()
    sceneView.scene.rootNode.addChildNode(featurePointNode!)
    
    // Create a node for shape detection visualization
    shapeDetectionNode = SCNNode()
    sceneView.scene.rootNode.addChildNode(shapeDetectionNode!)
  }
  
  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    // Only process feature points for non-LiDAR devices
    guard !hasLiDAR else { return }
    
    // CRITICAL: Extract data from frame immediately to avoid retaining ARFrame
    guard let rawPoints = frame.rawFeaturePoints?.points else { return }
    let currentTime = frame.timestamp
    
    // Copy points array immediately to avoid retaining frame
    let points = Array(rawPoints)
    
    frameCount += 1
    
    // Accumulate points for scanning - but only sample to avoid memory pressure
    if isScanning {
      // Sample points to reduce memory usage - take every 3rd point
      let sampledPoints = stride(from: 0, to: points.count, by: 3).map { points[$0] }
      
      // Use autoreleasepool to ensure immediate cleanup
      autoreleasepool {
        accumulatedPoints.append(contentsOf: sampledPoints)
        
        // Strict limit on accumulated points
        if accumulatedPoints.count > 8000 {
          accumulatedPoints.removeFirst(accumulatedPoints.count - 8000)
        }
      }
      
      // Report progress every 60 frames (~2 seconds) instead of 30
      if frameCount % 60 == 0 {
        let progressData: [String: Any] = [
          "status": "scanning",
          "meshCount": 0,
          "vertexCount": accumulatedPoints.count
        ]
        DispatchQueue.main.async { [weak self] in
          self?.onScanProgress?(progressData)
        }
      }
      
      // Update visualization at controlled rate
      if currentTime - lastVisualizationUpdate > visualizationUpdateInterval {
        lastVisualizationUpdate = currentTime
        updateScanVisualization()
      }
    } else {
      // When not scanning, only accumulate occasionally for shape detection
      if frameCount % 20 == 0 {
        // Sample even more aggressively when not scanning
        let sampledPoints = stride(from: 0, to: points.count, by: 5).map { points[$0] }
        
        autoreleasepool {
          accumulatedPoints.append(contentsOf: sampledPoints)
          
          if accumulatedPoints.count > 5000 {
            accumulatedPoints.removeFirst(accumulatedPoints.count - 5000)
          }
        }
        
        // Shape detection every 60 frames
        if frameCount % 60 == 0 {
          detectShapes()
        }
      }
      
      // Update visualization less frequently when not scanning
      if currentTime - lastVisualizationUpdate > 0.2 {
        lastVisualizationUpdate = currentTime
        updateIdleVisualization(points: points)
      }
    }
  }
  
  private func updateScanVisualization() {
    // Update on main thread but don't block
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      
      // Remove old visualizations
      self.featurePointNode?.childNodes.forEach { $0.removeFromParentNode() }
      
      // Show sampled accumulated points during scanning
      let stride = max(1, self.accumulatedPoints.count / 1500) // Limit to 1500 points max
      
      for (index, point) in self.accumulatedPoints.enumerated() where index % stride == 0 {
        let sphere = SCNSphere(radius: 0.004)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.cyan
        material.lightingModel = .constant
        sphere.materials = [material]
        
        let pointNode = SCNNode(geometry: sphere)
        pointNode.position = SCNVector3(point.x, point.y, point.z)
        
        self.featurePointNode?.addChildNode(pointNode)
      }
    }
  }
  
  private func updateIdleVisualization(points: [SIMD3<Float>]) {
    // Update on main thread but don't block
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      
      // Remove old visualizations
      self.featurePointNode?.childNodes.forEach { $0.removeFromParentNode() }
      
      // Show current frame points
      let stride = max(1, points.count / 1000) // Limit to 1000 points
      
      for (index, point) in points.enumerated() where index % stride == 0 {
        let sphere = SCNSphere(radius: 0.003)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.yellow
        material.lightingModel = .constant
        sphere.materials = [material]
        
        let pointNode = SCNNode(geometry: sphere)
        pointNode.position = SCNVector3(point.x, point.y, point.z)
        
        self.featurePointNode?.addChildNode(pointNode)
      }
    }
  }
  
  // MARK: - Shape Detection
  
  private func detectShapes() {
    guard !accumulatedPoints.isEmpty else {
      return
    }
    
    // Run shape detection on background queue to avoid blocking main thread
    let pointsCopy = accumulatedPoints
    processingQueue.async { [weak self] in
      guard let self = self else { return }
      
      // Group points into clusters
      let clusters = self.clusterPoints(pointsCopy, maxDistance: 0.3)
      
      guard !clusters.isEmpty else { return }
      
      // Analyze each cluster for circles or rectangles
      DispatchQueue.main.async {
        // Clear previous shape detections
        self.shapeDetectionNode?.childNodes.forEach { $0.removeFromParentNode() }
        
        for cluster in clusters {
          let result = self.analyzeClusterForShape(cluster)
          if let (shape, boundingBox) = result {
            self.visualizeShapeDetection(shape: shape, boundingBox: boundingBox)
          }
        }
      }
    }
  }
  
  private func clusterPoints(_ points: [SIMD3<Float>], maxDistance: Float) -> [[SIMD3<Float>]] {
    var clusters: [[SIMD3<Float>]] = []
    var unprocessed = points
    
    while !unprocessed.isEmpty {
      var cluster: [SIMD3<Float>] = []
      var toProcess = [unprocessed.removeFirst()]
      
      while !toProcess.isEmpty {
        let point = toProcess.removeFirst()
        cluster.append(point)
        
        // Find nearby points
        var i = 0
        while i < unprocessed.count {
          if distance(point, unprocessed[i]) < maxDistance {
            toProcess.append(unprocessed.remove(at: i))
          } else {
            i += 1
          }
        }
        
        // Limit cluster size for performance
        if cluster.count > 500 {
          break
        }
      }
      
      if cluster.count > 50 { // Minimum points for a shape
        clusters.append(cluster)
      }
      
      // Limit number of clusters
      if clusters.count >= 5 {
        break
      }
    }
    
    return clusters
  }
  
  private func analyzeClusterForShape(_ cluster: [SIMD3<Float>]) -> (shape: String, boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>))? {
    guard cluster.count >= 30 else {
      return nil
    }
    
    // Calculate bounding box in 2D (X-Z plane)
    var minPoint = cluster[0]
    var maxPoint = cluster[0]
    
    for point in cluster {
      minPoint = SIMD3<Float>(
        min(minPoint.x, point.x),
        min(minPoint.y, point.y),
        min(minPoint.z, point.z)
      )
      maxPoint = SIMD3<Float>(
        max(maxPoint.x, point.x),
        max(maxPoint.y, point.y),
        max(maxPoint.z, point.z)
      )
    }
    
    let size = maxPoint - minPoint
    let width = size.x
    let depth = size.z
    let height = size.y
    
    // Filter out too small or too large shapes (0.2m to 3m)
    guard width > 0.2 && width < 3.0 && depth > 0.2 && depth < 3.0 else {
      return nil
    }
    
    // Calculate center for circularity test
    let center = (minPoint + maxPoint) / 2
    
    // Check if points are roughly circular (similar distances from center)
    var distances: [Float] = []
    for point in cluster {
      let dx = point.x - center.x
      let dz = point.z - center.z
      let distance = sqrt(dx * dx + dz * dz)
      distances.append(distance)
    }
    
    let avgDistance = distances.reduce(0, +) / Float(distances.count)
    let variance = distances.map { pow($0 - avgDistance, 2) }.reduce(0, +) / Float(distances.count)
    let standardDeviation = sqrt(variance)
    
    // If standard deviation is small relative to average, it's likely a circle
    let circularity = standardDeviation / avgDistance
    
    // Determine shape based on aspect ratio and circularity
    let aspectRatio = max(width, depth) / min(width, depth)
    
    if circularity < 0.25 && aspectRatio < 1.3 {
      // Low variation in distances from center and roughly square aspect ratio = circle
      return ("CIRCLE", (minPoint, maxPoint))
    } else if aspectRatio < 2.0 {
      // Roughly square aspect ratio = square/rectangle
      return ("RECTANGLE", (minPoint, maxPoint))
    } else if aspectRatio >= 2.0 {
      // Long aspect ratio = elongated rectangle
      return ("RECTANGLE", (minPoint, maxPoint))
    }
    
    return nil
  }
  
  private func visualizeShapeDetection(shape: String, boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)) {
    let size = boundingBox.max - boundingBox.min
    let center = (boundingBox.min + boundingBox.max) / 2
    
    // Choose color based on shape
    let shapeColor: UIColor = shape == "CIRCLE" ? .cyan : .magenta
    
    // Create a wireframe box to show detected area
    let box = SCNBox(width: CGFloat(size.x),
                     height: CGFloat(size.y),
                     length: CGFloat(size.z),
                     chamferRadius: 0)
    
    // Colored wireframe material
    let material = SCNMaterial()
    material.diffuse.contents = UIColor.clear
    material.emission.contents = shapeColor
    material.fillMode = .lines
    box.materials = [material]
    
    let boxNode = SCNNode(geometry: box)
    boxNode.position = SCNVector3(center.x, center.y, center.z)
    
    // Add label above the box
    let text = SCNText(string: shape, extrusionDepth: 0.01)
    text.font = UIFont.systemFont(ofSize: 0.08)
    text.firstMaterial?.diffuse.contents = shapeColor
    text.firstMaterial?.emission.contents = shapeColor
    
    let textNode = SCNNode(geometry: text)
    textNode.position = SCNVector3(0, size.y / 2 + 0.1, 0)
    textNode.scale = SCNVector3(0.01, 0.01, 0.01)
    
    // Make text face camera
    let billboardConstraint = SCNBillboardConstraint()
    billboardConstraint.freeAxes = .Y
    textNode.constraints = [billboardConstraint]
    
    boxNode.addChildNode(textNode)
    shapeDetectionNode?.addChildNode(boxNode)
  }
}
