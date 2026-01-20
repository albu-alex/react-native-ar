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
  private var pointCameraTransforms: [simd_float4x4] = [] // Camera transform for each point
  private var pointNormals: [SIMD3<Float>] = [] // Surface normals for each point
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
    cleanup()
  }
  
  private func cleanup() {
    // Remove all delegates to prevent retain cycles
    sceneView?.session.delegate = nil
    sceneView?.delegate = nil
    
    // Clear all accumulated data
    accumulatedPoints.removeAll()
    meshAnchors.removeAll()
    scannedMeshNodes.removeAll()
    
    // Remove all nodes from scene
    featurePointNode?.removeFromParentNode()
    featurePointNode = nil
    
    shapeDetectionNode?.removeFromParentNode()
    shapeDetectionNode = nil
    
    objectScanNode?.removeFromParentNode()
    objectScanNode = nil
    
    // Clear callbacks to break retain cycles
    onScanComplete = nil
    onScanProgress = nil
    
    // Reset state
    isScanning = false
    scanBoundingBox = nil
    frameCount = 0
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
    accumulatedPoints.removeAll()
    pointCameraTransforms.removeAll()
    pointNormals.removeAll()
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
    
    // Create bounding box dictionary
    let boundingBox: [String: Any] = [
      "min": [minPoint.x, minPoint.y, minPoint.z],
      "max": [maxPoint.x, maxPoint.y, maxPoint.z]
    ]
    
    // Generate faces using simple triangulation
    // For a basic point cloud, we'll create a simple mesh
    var faces: [[Int]] = []
    
    // Guard against small point counts
    guard accumulatedPoints.count >= 3 else {
      print("[ARView] Not enough points for triangulation: \(accumulatedPoints.count)")
      return [
        "vertices": vertices,
        "faces": faces,
        "vertexCount": vertices.count,
        "faceCount": 0,
        "meshCount": 0,
        "boundingBox": boundingBox,
        "scanType": "featurePoints"
      ]
    }
    
    // Simple triangulation: connect nearby points
    let strideValue = max(1, accumulatedPoints.count / 1000) // Limit complexity
    let upperBound = accumulatedPoints.count - 2 * strideValue
    
    // Only triangulate if we have enough points
    if upperBound > strideValue {
      for i in stride(from: strideValue, to: min(upperBound, 1000), by: strideValue) {
        if i + 2 * strideValue < accumulatedPoints.count {
          faces.append([i, i + strideValue, i + 2 * strideValue])
        }
      }
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
    
    var objString = "# Wavefront OBJ file\n"
    objString += "# Generated by ARView Scanner (Feature Points with Mesh)\n"
    objString += "# Vertices: \(accumulatedPoints.count)\n"
    objString += "mtllib scan.mtl\n"
    objString += "o ScannedObject\n\n"
    
    // Calculate normals for each point
    let normals = calculateVertexNormals(for: accumulatedPoints)
    
    // Export vertices
    objString += "# Vertex coordinates\n"
    for point in accumulatedPoints {
      objString += "v \(point.x) \(point.y) \(point.z)\n"
    }
    objString += "\n"
    
    // Export vertex normals
    objString += "# Vertex normals\n"
    for normal in normals {
      objString += "vn \(normal.x) \(normal.y) \(normal.z)\n"
    }
    objString += "\n"
    
    // Generate mesh using triangulation
    let faces = generateMeshFromPoints(accumulatedPoints)
    
    objString += "# Faces (\(faces.count) triangles)\n"
    objString += "usemtl Material\n"
    objString += "s 1\n"
    
    for face in faces {
      // OBJ format: f v1//vn1 v2//vn2 v3//vn3 (vertex//normal)
      objString += "f \(face[0] + 1)//\(face[0] + 1) \(face[1] + 1)//\(face[1] + 1) \(face[2] + 1)//\(face[2] + 1)\n"
    }
    
    return objString
  }
  
  // Calculate vertex normals using neighboring points
  private func calculateVertexNormals(for points: [SIMD3<Float>]) -> [SIMD3<Float>] {
    // If we have stored normals from raycasting, use those
    if pointNormals.count == points.count {
      return pointNormals
    }
    
    // Fallback to calculated normals
    guard points.count >= 3 else {
      return points.map { _ in SIMD3<Float>(0, 1, 0) }
    }
    
    var normals = [SIMD3<Float>]()
    let searchRadius: Float = 0.05 // 5cm radius for neighbor search
    
    for (index, point) in points.enumerated() {
      // Find neighboring points
      var neighbors = [SIMD3<Float>]()
      
      for (i, otherPoint) in points.enumerated() {
        guard i != index else { continue }
        let distance = simd_distance(point, otherPoint)
        if distance < searchRadius && neighbors.count < 6 {
          neighbors.append(otherPoint)
        }
      }
      
      // Calculate normal from neighbors using PCA (simplified)
      if neighbors.count >= 2 {
        // Use cross product of vectors to neighbors
        let v1 = normalize(neighbors[0] - point)
        let v2 = normalize(neighbors[min(1, neighbors.count - 1)] - point)
        let normal = normalize(cross(v1, v2))
        
        // Ensure normal points outward (towards camera/up)
        let correctedNormal = normal.y < 0 ? -normal : normal
        normals.append(correctedNormal)
      } else {
        // Default normal pointing up
        normals.append(SIMD3<Float>(0, 1, 0))
      }
    }
    
    return normals
  }
  
  // Generate mesh using depth-aware 2.5D Delaunay-like triangulation
  // This projects points onto the average viewing plane and triangulates there
  private func generateMeshFromPoints(_ points: [SIMD3<Float>]) -> [[Int]] {
    guard points.count >= 3 else { return [] }
    guard pointCameraTransforms.count == points.count else {
      // Fallback to simple triangulation if no camera data
      return generateSimpleTriangulation(points)
    }
    
    var faces = [[Int]]()
    
    // Calculate average camera position and viewing direction
    var avgCameraPos = SIMD3<Float>(0, 0, 0)
    var avgViewDir = SIMD3<Float>(0, 0, 0)
    
    for transform in pointCameraTransforms {
      let camPos = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
      avgCameraPos += camPos
      
      // Camera looks down negative Z in its local space
      let viewDir = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
      avgViewDir += viewDir
    }
    
    avgCameraPos /= Float(pointCameraTransforms.count)
    avgViewDir = normalize(avgViewDir)
    
    // Project points onto a plane perpendicular to viewing direction
    // This creates a 2.5D representation from the camera's perspective
    let planeOrigin = avgCameraPos + avgViewDir * 0.5 // Plane in front of camera
    
    var projected2D: [(x: Float, y: Float, depth: Float, index: Int)] = []
    
    // Create coordinate system for the projection plane
    let up = SIMD3<Float>(0, 1, 0)
    let right = normalize(cross(avgViewDir, up))
    let adjustedUp = normalize(cross(right, avgViewDir))
    
    for (i, point) in points.enumerated() {
      let toPoint = point - planeOrigin
      let depth = dot(toPoint, avgViewDir) // Distance along viewing direction
      let x = dot(toPoint, right)
      let y = dot(toPoint, adjustedUp)
      
      projected2D.append((x: x, y: y, depth: depth, index: i))
    }
    
    // Build triangles using 2D proximity with depth constraints
    let maxEdgeLength2D: Float = 0.12 // 12cm in projected space
    let maxDepthDiff: Float = 0.15 // 15cm depth difference allowed
    
    for i in 0..<projected2D.count {
      let p1 = projected2D[i]
      let point1 = points[p1.index]
      
      // Find nearby points in 2D projection
      var neighbors: [(index: Int, dist2D: Float)] = []
      
      for j in 0..<projected2D.count {
        guard i != j else { continue }
        let p2 = projected2D[j]
        
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let dist2D = sqrt(dx*dx + dy*dy)
        
        // Check depth similarity (points should be on similar depth)
        let depthDiff = abs(p2.depth - p1.depth)
        
        if dist2D < maxEdgeLength2D && depthDiff < maxDepthDiff {
          neighbors.append((index: j, dist2D: dist2D))
        }
      }
      
      // Sort by 2D distance
      neighbors.sort { $0.dist2D < $1.dist2D }
      
      // Form triangles with nearest neighbors
      for j in 0..<min(neighbors.count, 6) {
        let idx2 = neighbors[j].index
        let p2 = projected2D[idx2]
        let point2 = points[p2.index]
        
        for k in (j+1)..<min(neighbors.count, 10) {
          let idx3 = neighbors[k].index
          let p3 = projected2D[idx3]
          let point3 = points[p3.index]
          
          // Check all edges in both 2D and 3D space
          let dist2D_23 = sqrt(pow(p3.x - p2.x, 2) + pow(p3.y - p2.y, 2))
          let dist3D_12 = simd_distance(point1, point2)
          let dist3D_23 = simd_distance(point2, point3)
          let dist3D_31 = simd_distance(point3, point1)
          
          guard dist2D_23 < maxEdgeLength2D,
                dist3D_12 < 0.15,
                dist3D_23 < 0.15,
                dist3D_31 < 0.15 else {
            continue
          }
          
          // Calculate triangle area in 3D
          let v1 = point2 - point1
          let v2 = point3 - point1
          let crossProd = cross(v1, v2)
          let area = length(crossProd) * 0.5
          
          // Avoid degenerate triangles
          guard area > 0.0002 else { continue }
          
          // Check if triangle faces towards camera
          let triangleCenter = (point1 + point2 + point3) / 3.0
          let toCamera = normalize(avgCameraPos - triangleCenter)
          let normal = normalize(crossProd)
          
          // Only add triangles facing the camera
          if dot(normal, toCamera) > 0 {
            faces.append([p1.index, p2.index, p3.index])
          } else {
            // Flip winding order
            faces.append([p1.index, p3.index, p2.index])
          }
          
          // Limit to prevent over-triangulation
          if faces.count >= points.count * 4 {
            return faces
          }
        }
      }
    }
    
    return faces
  }
  
  // Fallback simple triangulation for when camera data isn't available
  private func generateSimpleTriangulation(_ points: [SIMD3<Float>]) -> [[Int]] {
    var faces = [[Int]]()
    let maxDistance: Float = 0.1
    
    for i in 0..<min(points.count, 200) {
      let p1 = points[i]
      var nearby: [(Int, Float)] = []
      
      for j in (i+1)..<points.count {
        let dist = simd_distance(p1, points[j])
        if dist < maxDistance {
          nearby.append((j, dist))
        }
      }
      
      nearby.sort { $0.1 < $1.1 }
      
      for j in 0..<min(nearby.count, 4) {
        for k in (j+1)..<min(nearby.count, 6) {
          let idx2 = nearby[j].0
          let idx3 = nearby[k].0
          
          let d23 = simd_distance(points[idx2], points[idx3])
          guard d23 < maxDistance else { continue }
          
          let v1 = points[idx2] - p1
          let v2 = points[idx3] - p1
          let area = length(cross(v1, v2)) * 0.5
          
          if area > 0.0001 {
            faces.append([i, idx2, idx3])
          }
        }
      }
    }
    
    return faces
  }
  
  private func exportMeshAsOBJ() -> String? {
    guard !meshAnchors.isEmpty else { return nil }
    
    var objString = "# Wavefront OBJ file\n"
    objString += "# Generated by ARView Scanner (LiDAR)\n"
    objString += "# Meshes: \(meshAnchors.count)\n"
    objString += "mtllib scan.mtl\n"
    objString += "o ScannedObject\n\n"
    
    var totalVertexCount = 0
    var totalFaceCount = 0
    var allVertices = [SIMD3<Float>]()
    var allNormals = [SIMD3<Float>]()
    
    // First pass: collect all vertices and normals
    for meshAnchor in meshAnchors {
      let geometry = meshAnchor.geometry
      let transform = meshAnchor.transform
      
      let vertexBuffer = geometry.vertices.buffer.contents()
      let vertexStride = geometry.vertices.stride
      let vertexCount = geometry.vertices.count
      
      // Get normals if available
      let normalBuffer = geometry.normals.buffer.contents()
      let normalStride = geometry.normals.stride
      
      for i in 0..<vertexCount {
        let vertexPointer = vertexBuffer.advanced(by: i * vertexStride)
        let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        
        // Transform to world space
        let worldVertex = simd_mul(transform, SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1.0))
        allVertices.append(SIMD3<Float>(worldVertex.x, worldVertex.y, worldVertex.z))
        
        // Transform normal
        let normalPointer = normalBuffer.advanced(by: i * normalStride)
        let normal = normalPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        let worldNormal = simd_mul(transform, SIMD4<Float>(normal.x, normal.y, normal.z, 0.0))
        allNormals.append(normalize(SIMD3<Float>(worldNormal.x, worldNormal.y, worldNormal.z)))
      }
    }
    
    // Export vertices
    objString += "# Vertex coordinates (\(allVertices.count) vertices)\n"
    for vertex in allVertices {
      objString += "v \(vertex.x) \(vertex.y) \(vertex.z)\n"
    }
    objString += "\n"
    
    // Export normals
    objString += "# Vertex normals\n"
    for normal in allNormals {
      objString += "vn \(normal.x) \(normal.y) \(normal.z)\n"
    }
    objString += "\n"
    
    // Export faces
    objString += "# Faces\n"
    objString += "usemtl Material\n"
    objString += "s 1\n"
    
    var vertexOffset = 1
    
    for meshAnchor in meshAnchors {
      let geometry = meshAnchor.geometry
      let faceBuffer = geometry.faces.buffer.contents()
      let faceCount = geometry.faces.count
      let bytesPerIndex = geometry.faces.bytesPerIndex
      
      for i in 0..<faceCount {
        let facePointer = faceBuffer.advanced(by: i * bytesPerIndex * 3)
        
        if bytesPerIndex == 2 {
          let indices = facePointer.assumingMemoryBound(to: UInt16.self)
          let v1 = Int(indices[0]) + vertexOffset
          let v2 = Int(indices[1]) + vertexOffset
          let v3 = Int(indices[2]) + vertexOffset
          objString += "f \(v1)//\(v1) \(v2)//\(v2) \(v3)//\(v3)\n"
        } else if bytesPerIndex == 4 {
          let indices = facePointer.assumingMemoryBound(to: UInt32.self)
          let v1 = Int(indices[0]) + vertexOffset
          let v2 = Int(indices[1]) + vertexOffset
          let v3 = Int(indices[2]) + vertexOffset
          objString += "f \(v1)//\(v1) \(v2)//\(v2) \(v3)//\(v3)\n"
        }
      }
      
      totalFaceCount += faceCount
      vertexOffset += geometry.vertices.count
    }
    
    objString += "\n# End of file\n"
    objString += "# Total: \(allVertices.count) vertices, \(totalFaceCount) faces\n"
    
    return objString
  }
  
  func saveOBJToFile(filename: String = "scan") -> URL? {
    guard let objContent = exportScanAsOBJ() else { return nil }
    
    // Ensure valid OBJ content
    guard !objContent.isEmpty else { return nil }
    
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let fileURL = documentsPath.appendingPathComponent("\(filename).obj")
    let mtlURL = documentsPath.appendingPathComponent("\(filename).mtl")
    
    do {
      // Remove existing files if they exist
      if FileManager.default.fileExists(atPath: fileURL.path) {
        try FileManager.default.removeItem(at: fileURL)
      }
      if FileManager.default.fileExists(atPath: mtlURL.path) {
        try FileManager.default.removeItem(at: mtlURL)
      }
      
      // Create MTL file content (material definition)
      let mtlContent = """
        # Material file for AR scan
        newmtl Material
        Ka 0.6 0.6 0.6
        Kd 0.8 0.8 0.8
        Ks 0.5 0.5 0.5
        Ns 32.0
        d 1.0
        illum 2
        """
      
      // Write MTL file
      try mtlContent.write(to: mtlURL, atomically: true, encoding: .utf8)
      
      // Update OBJ content to reference the correct MTL filename
      let updatedObjContent = objContent.replacingOccurrences(of: "mtllib scan.mtl", with: "mtllib \(filename).mtl")
      
      // Write OBJ file synchronously with atomically=true to ensure complete write
      try updatedObjContent.write(to: fileURL, atomically: true, encoding: .utf8)
      
      // Explicitly sync to disk
      if let fileHandle = FileHandle(forReadingAtPath: fileURL.path) {
        try fileHandle.synchronize()
        fileHandle.closeFile()
      }
      
      // Set file attributes to ensure both files are readable
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: fileURL.path
      )
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: mtlURL.path
      )
      
      // Wait briefly for file system to flush
      Thread.sleep(forTimeInterval: 0.1)
      
      // Verify OBJ file was created, is readable, and has content
      guard FileManager.default.fileExists(atPath: fileURL.path),
            FileManager.default.isReadableFile(atPath: fileURL.path) else {
        print("[ARView] File verification failed: OBJ file not accessible")
        return nil
      }
      
      // Verify file size matches content
      let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
      guard let fileSize = attributes[.size] as? UInt64, fileSize > 0 else {
        print("[ARView] File verification failed: empty OBJ file")
        return nil
      }
      
      // Try to read back the file to ensure it's actually accessible
      guard let readContent = try? String(contentsOf: fileURL, encoding: .utf8),
            !readContent.isEmpty else {
        print("[ARView] File verification failed: cannot read OBJ content")
        return nil
      }
      
      print("[ARView] OBJ and MTL files saved and verified: \(fileURL.path), size: \(fileSize) bytes")
      
      return fileURL
    } catch {
      print("[ARView] Error saving OBJ file: \(error)")
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
    
    frameCount += 1
    
    // For non-LiDAR devices, use raycast-based scanning instead of random feature points
    // This gives us actual surface points on continuous objects
    
    let processingInterval = isScanning ? 2 : 10
    guard frameCount % processingInterval == 0 else { return }
    
    let timestamp = frame.timestamp
    let cameraTransform = frame.camera.transform
    
    // Cast rays in a grid pattern to find object surfaces
    if isScanning {
      let raycastPoints = performRaycastScanning(frame: frame)
      
      if !raycastPoints.isEmpty {
        accumulatedPoints.append(contentsOf: raycastPoints.map { $0.position })
        pointCameraTransforms.append(contentsOf: Array(repeating: cameraTransform, count: raycastPoints.count))
        pointNormals.append(contentsOf: raycastPoints.map { $0.normal })
        
        // Hard limit
        if accumulatedPoints.count > 2000 {
          let removeCount = accumulatedPoints.count - 2000
          accumulatedPoints.removeFirst(removeCount)
          pointCameraTransforms.removeFirst(removeCount)
          pointNormals.removeFirst(removeCount)
        }
        
        // Report progress
        if frameCount % 180 == 0 {
          let count = accumulatedPoints.count
          DispatchQueue.main.async { [weak self] in
            self?.onScanProgress?(["status": "scanning", "meshCount": 0, "vertexCount": count])
          }
        }
        
        // Update visualization
        if timestamp - lastVisualizationUpdate > 0.2 {
          lastVisualizationUpdate = timestamp
          let copy = accumulatedPoints
          DispatchQueue.main.async { [weak self] in
            self?.updateScanVisualization(with: copy)
          }
        }
      }
    } else {
      // Idle mode - minimal raycasting
      if frameCount % 60 == 0 {
        let raycastPoints = performRaycastScanning(frame: frame, density: .low)
        
        if !raycastPoints.isEmpty {
          accumulatedPoints.append(contentsOf: raycastPoints.map { $0.position })
          pointNormals.append(contentsOf: raycastPoints.map { $0.normal })
          
          if accumulatedPoints.count > 2000 {
            let removeCount = accumulatedPoints.count - 2000
            accumulatedPoints.removeFirst(removeCount)
            pointNormals.removeFirst(removeCount)
          }
        }
      }
      
      // Visualize rarely
      if timestamp - lastVisualizationUpdate > 0.5 {
        lastVisualizationUpdate = timestamp
        let limited = Array(accumulatedPoints.prefix(300))
        DispatchQueue.main.async { [weak self] in
          self?.updateIdleVisualization(with: limited)
        }
      }
    }
  }
  
  // Perform raycast-based scanning to find actual object surfaces
  private func performRaycastScanning(frame: ARFrame, density: ScanDensity = .medium) -> [(position: SIMD3<Float>, normal: SIMD3<Float>)] {
    var surfacePoints: [(position: SIMD3<Float>, normal: SIMD3<Float>)] = []
    
    let imageResolution = frame.camera.imageResolution
    let width = imageResolution.width
    let height = imageResolution.height
    
    // Grid size based on density
    let gridSize: Int
    switch density {
    case .low:
      gridSize = 6  // 6x6 = 36 rays
    case .medium:
      gridSize = 10 // 10x10 = 100 rays
    case .high:
      gridSize = 14 // 14x14 = 196 rays
    }
    
    let stepX = width / CGFloat(gridSize)
    let stepY = height / CGFloat(gridSize)
    
    // Cast rays in a grid pattern from screen coordinates
    for row in 0..<gridSize {
      for col in 0..<gridSize {
        let x = stepX * CGFloat(col) + stepX * 0.5
        let y = stepY * CGFloat(row) + stepY * 0.5
        
        let screenPoint = CGPoint(x: x, y: y)
        
        // Perform raycast from screen point
        let results = sceneView.hitTest(screenPoint, types: [.existingPlaneUsingExtent, .existingPlane, .featurePoint])
        
        if let result = results.first {
          let transform = result.worldTransform
          let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
          
          // Extract normal from the transform (Y axis points up from the surface)
          let normal = SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
          
          // Filter out points too far from camera
          let cameraPos = SIMD3<Float>(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)
          let distance = simd_distance(position, cameraPos)
          
          if distance < 3.0 && distance > 0.05 {
            surfacePoints.append((position: position, normal: normalize(normal)))
          }
        }
      }
    }
    
    // If no surface points found, try using feature points as fallback
    if surfacePoints.isEmpty, let featurePoints = frame.rawFeaturePoints?.points {
      let pointsArray = Array(featurePoints)
      let samplingRate = max(1, pointsArray.count / 50) // Get at most 50 points
      
      for i in stride(from: 0, to: pointsArray.count, by: samplingRate) {
        let point = pointsArray[i]
        let cameraPos = SIMD3<Float>(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)
        let distance = simd_distance(point, cameraPos)
        
        if distance < 3.0 && distance > 0.05 {
          // Estimate normal pointing toward camera
          let toCamera = normalize(cameraPos - point)
          surfacePoints.append((position: point, normal: toCamera))
        }
      }
    }
    
    // Filter outliers if we have enough points
    return surfacePoints.count > 10 ? filterOutliers(surfacePoints) : surfacePoints
  }
  
  enum ScanDensity {
    case low, medium, high
  }
  
  // Filter outlier points that don't belong to main object cluster
  private func filterOutliers(_ points: [(position: SIMD3<Float>, normal: SIMD3<Float>)]) -> [(position: SIMD3<Float>, normal: SIMD3<Float>)] {
    guard points.count > 3 else { return points }
    
    // Simple spatial clustering - keep points close to the densest region
    var densityScores: [Int] = Array(repeating: 0, count: points.count)
    let neighborRadius: Float = 0.15 // 15cm radius
    
    for i in 0..<points.count {
      for j in 0..<points.count {
        if i != j {
          let distance = simd_distance(points[i].position, points[j].position)
          if distance < neighborRadius {
            densityScores[i] += 1
          }
        }
      }
    }
    
    // Find the median density
    let sortedScores = densityScores.sorted()
    let medianScore = sortedScores[sortedScores.count / 2]
    
    // Keep points with reasonable density (at least 30% of median)
    let threshold = max(2, Int(Float(medianScore) * 0.3))
    
    var filtered: [(position: SIMD3<Float>, normal: SIMD3<Float>)] = []
    for i in 0..<points.count {
      if densityScores[i] >= threshold {
        filtered.append(points[i])
      }
    }
    
    return filtered.isEmpty ? points : filtered
  }
  
  private func updateScanVisualization(with points: [SIMD3<Float>]) {
    guard let featurePointNode = self.featurePointNode else { return }
    
    // Remove old visualizations
    featurePointNode.childNodes.forEach { $0.removeFromParentNode() }
    
    // Limit visualization to 400 nodes max for performance
    let stride = max(1, points.count / 400)
    
    for (index, point) in points.enumerated() where index % stride == 0 {
      let sphere = SCNSphere(radius: 0.004)
      let material = SCNMaterial()
      material.diffuse.contents = UIColor.cyan
      material.lightingModel = .constant
      sphere.materials = [material]
      
      let pointNode = SCNNode(geometry: sphere)
      pointNode.position = SCNVector3(point.x, point.y, point.z)
      
      featurePointNode.addChildNode(pointNode)
    }
  }
  
  private func updateIdleVisualization(with points: [SIMD3<Float>]) {
    guard let featurePointNode = self.featurePointNode else { return }
    
    // Remove old visualizations
    featurePointNode.childNodes.forEach { $0.removeFromParentNode() }
    
    // Show limited points - max 300 nodes
    let stride = max(1, points.count / 300)
    
    for (index, point) in points.enumerated() where index % stride == 0 {
      let sphere = SCNSphere(radius: 0.003)
      let material = SCNMaterial()
      material.diffuse.contents = UIColor.yellow
      material.lightingModel = .constant
      sphere.materials = [material]
      
      let pointNode = SCNNode(geometry: sphere)
      pointNode.position = SCNVector3(point.x, point.y, point.z)
      
      featurePointNode.addChildNode(pointNode)
    }
  }
  
  // MARK: - Shape Detection
  
  private func detectShapes(with points: [SIMD3<Float>]) {
    guard !points.isEmpty else {
      return
    }
    
    // Group points into clusters
    let clusters = self.clusterPoints(points, maxDistance: 0.3)
    
    guard !clusters.isEmpty else { return }
    
    // Analyze each cluster for circles or rectangles
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      
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
