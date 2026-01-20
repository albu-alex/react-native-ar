# Photogrammetry Implementation

## Overview
Pivoted from feature point-based scanning to Apple's RealityKit PhotogrammetrySession for professional 3D object reconstruction from photos.

## What Changed

### New Files Created
1. **PhotogrammetryCapture.swift** - Core photogrammetry implementation
   - Handles image capture from AR camera with metadata
   - Processes images using PhotogrammetrySession
   - Generates USDZ 3D models
   - Device capability checking

### Files Modified
1. **ARView.swift** - Simplified to photogrammetry-only (200 lines vs 1400+)
   - Removed all feature point detection code
   - Removed mesh/OBJ export functionality
   - Integrated PhotogrammetryCapture for image capture
   - Tracks AR session updates for image capture

2. **ARNativeModule.swift** - Updated bridge methods
   - Removed: `exportScanAsOBJ()`, `saveOBJToFile()`
   - Added: `isPhotogrammetrySupported()`, `processPhotogrammetry()`, `getPhotogrammetryCaptureDirectory()`, `getPhotogrammetryImageCount()`
   - Handles AR session lifecycle (stop during processing, restart after)

3. **ARNativeModule.m** - Updated method exports
   - Removed old OBJ export methods
   - Added photogrammetry method declarations

4. **ARNativeModule.ts** - Updated TypeScript interface
   - Removed old mesh/OBJ methods
   - Added photogrammetry methods with proper typing

5. **ARScreen.tsx** - Complete UI workflow update
   - Shows real-time image capture count
   - Post-capture options: OK / Process Now / Share Images
   - Device capability checking before processing
   - Quality selection dialog (Reduced/Medium/Full/Raw)
   - Progress tracking during processing
   - Shares generated USDZ models

## How It Works

### Capture Phase
1. User starts photogrammetry capture
2. App captures images every 0.5 seconds from AR camera
3. Each image saved as JPEG with JSON metadata:
   - Camera transform (position/orientation)
   - Camera intrinsics (focal length, principal point)
   - Image resolution
   - Exposure duration
   - Timestamp
4. User moves around object to capture from multiple angles (50-100 images recommended)
5. Stop capture when complete

### Processing Phase
1. Check device capability (PhotogrammetrySession.isSupported)
2. User selects quality level:
   - **Reduced**: Fast, lower quality
   - **Medium**: Balanced (recommended)
   - **Full**: High quality, slower
   - **Raw**: Maximum quality, very slow
3. AR session stops (PhotogrammetrySession needs exclusive access)
4. PhotogrammetrySession processes images:
   - Validates input images
   - Reconstructs 3D geometry
   - Generates textures
   - Outputs USDZ file
5. Progress updates shown to user (0-100%)
6. AR session restarts after completion
7. User can share generated USDZ model

## Device Requirements

### Supported Devices
- **Mac**: Requires 4GB+ GPU RAM and ray tracing support
- **iOS**: Requires LiDAR sensor (iPhone 12 Pro and later, iPad Pro 2020 and later)

### Why These Requirements?
PhotogrammetrySession uses advanced reconstruction algorithms that require:
- Significant GPU memory for processing large image sets
- Ray tracing for accurate geometry reconstruction
- (iOS) LiDAR for depth information and scale estimation

## Key Features

### Image Capture
- Automatic capture every 0.5 seconds
- Camera metadata preserved for accurate reconstruction
- JPEG compression at 95% quality
- Organized in timestamped directories

### Processing
- Quality level selection
- Real-time progress updates
- Background processing (async/await)
- Error handling with device capability checks

### Output
- USDZ format (Universal Scene Description)
- Industry-standard 3D format
- Viewable in AR Quick Look on iOS
- Compatible with major 3D software

## Next Steps

### Building
1. **Add PhotogrammetryCapture.swift to Xcode**:
   - Open `ios/ARinReactNative.xcworkspace` in Xcode
   - Right-click `ARinReactNative` folder
   - Select "Add Files to ARinReactNative"
   - Choose `ios/ARinReactNative/PhotogrammetryCapture.swift`
   - Ensure "ARinReactNative" target is checked
   - Click "Add"

2. **Clean and Build**:
   ```bash
   cd ios
   pod install
   cd ..
   npx react-native run-ios
   ```

### Testing
1. Run on LiDAR-capable device (iPhone 12 Pro+, iPad Pro 2020+)
2. Start photogrammetry capture
3. Move slowly around a small object
4. Capture 50-100 images from different angles
5. Stop capture
6. Select "Process Now" → "Medium" quality
7. Wait for processing to complete (may take several minutes)
8. Share or view generated USDZ model

### Optimization Tips
- **Image Count**: 50-100 images typically provides good quality
- **Coverage**: Capture from all angles, including top and bottom
- **Distance**: Maintain consistent distance from object
- **Lighting**: Use even, diffuse lighting (avoid harsh shadows)
- **Background**: Simple, contrasting background helps
- **Quality**: Start with "Reduced" for testing, use "Full" for final output

## Troubleshooting

### "Photogrammetry not supported"
- Verify device has LiDAR (Settings → General → About → Model)
- On Mac, check GPU has 4GB+ RAM and ray tracing

### Processing fails
- Ensure 50+ images captured
- Check images have sufficient overlap
- Try "Reduced" quality first to validate workflow

### Out of memory
- Reduce number of input images
- Use "Reduced" or "Medium" quality
- Close other apps during processing

## Technical Details

### Architecture
```
ARScreen.tsx (UI)
    ↓
ARNativeModule.ts (TypeScript Bridge)
    ↓
ARNativeModule.m (Objective-C Export)
    ↓
ARNativeModule.swift (Swift Bridge)
    ↓
ARView.swift (AR Camera + Capture)
    ↓
PhotogrammetryCapture.swift (RealityKit Processing)
    ↓
PhotogrammetrySession (Apple Framework)
```

### Data Flow
1. **Capture**: ARFrame → UIImage → JPEG + JSON metadata
2. **Processing**: Image directory → PhotogrammetrySession → USDZ file
3. **Sharing**: USDZ path → React Native Share API

### Thread Safety
- All PhotogrammetrySession operations run on main thread (@MainActor)
- AR session updates handled on session queue
- File I/O uses autoreleasepool for memory management
- Progress callbacks dispatched to main thread

## References
- [Apple RealityKit Documentation](https://developer.apple.com/documentation/realitykit)
- [PhotogrammetrySession API](https://developer.apple.com/documentation/realitykit/photogrammetrysession)
- [USDZ File Format](https://graphics.pixar.com/usd/docs/index.html)
