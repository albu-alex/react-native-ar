# Android ARCore Photogrammetry Implementation

## Overview
Android implementation of photogrammetry image capture using Google ARCore. Unlike iOS which has built-in RealityKit PhotogrammetrySession, Android captures high-quality images with camera metadata for external processing.

## Architecture

### Core Components

1. **PhotogrammetryCapture.kt**
   - Captures images from ARCore camera frames
   - Saves JPEG images with 95% quality
   - Stores camera metadata (pose, intrinsics, tracking state)
   - Manages capture state and timing

2. **ARView.kt**
   - GLSurfaceView-based AR camera display
   - Integrates with ARCore Session
   - Processes frames for image capture
   - Sends events to React Native

3. **ARViewManager.kt**
   - React Native ViewManager for ARView
   - Manages view lifecycle
   - Auto-starts AR session

4. **ARNativeModule.kt**
   - React Native bridge module
   - Exposes AR and photogrammetry methods
   - Handles session management

## Key Differences from iOS

### Image Capture ✅
- **iOS**: Uses ARKit frames → UIImage → JPEG
- **Android**: Uses ARCore frames → YUV → JPEG
- Both save camera metadata (pose, intrinsics, resolution, timestamp)

### 3D Reconstruction ❌
- **iOS**: Built-in PhotogrammetrySession → USDZ models
- **Android**: No built-in processing - images only

### External Processing Options for Android

Users can process captured images using:

1. **Desktop Software**
   - Agisoft Metashape (Professional)
   - RealityCapture (Professional)
   - Meshroom (Free, Open Source)
   - COLMAP (Free, Open Source)

2. **Cloud Services**
   - Polycam API
   - Sketchfab 3D Scanner
   - Capturing Reality API
   - Azure Object Anchors

3. **Cross-Platform**
   - Transfer images to Mac/iOS device
   - Process with this app's iOS version
   - Generate USDZ models

## API Methods

### Common (iOS & Android)
```kotlin
// Check if AR is supported
isSupported(): Promise<boolean>

// Session management
startSession(): Promise<void>
stopSession(): Promise<void>

// Capture control
startObjectScan(): Promise<void>
stopObjectScan(): Promise<ScanData>
clearScan(): Promise<void>

// State queries
getPhotogrammetryCaptureDirectory(): Promise<string?>
getPhotogrammetryImageCount(): Promise<number>
isPhotogrammetrySupported(): Promise<boolean>
```

### iOS Only
```typescript
// 3D reconstruction with RealityKit
processPhotogrammetry(
  inputDirectory: string,
  outputFilename: string,
  detail: 'reduced' | 'medium' | 'full' | 'raw',
  progressCallback: (progress) => void
): Promise<string> // Returns USDZ file path
```

### Android Behavior
```kotlin
// Returns error with instructions for external processing
processPhotogrammetry(...): Promise<never>
// Error: "3D reconstruction is not available on Android. 
//         Please use external photogrammetry software."
```

## Captured Data Format

### Image Files
- **Format**: JPEG
- **Quality**: 95%
- **Naming**: `image_0001.jpg`, `image_0002.jpg`, etc.
- **Location**: `{filesDir}/PhotoCapture_{timestamp}/`

### Metadata Files (JSON)
```json
{
  "transform": [
    [tx, ty, tz],           // Translation
    [qx, qy, qz, qw]        // Rotation quaternion
  ],
  "intrinsics": {
    "focalLength": [fx, fy],
    "principalPoint": [cx, cy],
    "imageSize": [width, height]
  },
  "imageResolution": {
    "width": 1920,
    "height": 1080
  },
  "timestamp": 1234567890,
  "trackingState": "TRACKING"
}
```

## Device Requirements

### Minimum
- Android 7.0 (API 24) or higher
- ARCore support (most devices from 2018+)
- Camera permission
- Storage permission (for saving images)

### Recommended
- Android 10+ for better ARCore features
- 4GB+ RAM
- Good camera (12MP+)
- Sufficient storage (50-100 images = ~50-200MB)

### Check ARCore Support
Visit: https://developers.google.com/ar/devices

## Implementation Details

### ARCore Session Configuration
```kotlin
val config = Config(session).apply {
    planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
    lightEstimationMode = Config.LightEstimationMode.AMBIENT_INTENSITY
    updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
}
```

### Image Capture Timing
- Interval: 500ms (0.5 seconds)
- Triggered during `onDrawFrame()`
- Only when `isScanning = true`
- Uses `lastCaptureTime` to throttle

### YUV to JPEG Conversion
```kotlin
fun imageToJpeg(image: Image): ByteArray {
    // Extract YUV planes
    val yBuffer = image.planes[0].buffer
    val uBuffer = image.planes[1].buffer
    val vBuffer = image.planes[2].buffer
    
    // Convert to NV21 format
    val nv21 = ByteArray(ySize + uSize + vSize)
    // ... combine planes ...
    
    // Compress to JPEG
    val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
    yuvImage.compressToJpeg(rect, 95, outputStream)
}
```

### Memory Management
- Images captured in `onDrawFrame()` loop
- Camera image acquired and closed per frame
- ByteArrayOutputStream used for conversion
- Files written directly to disk (not kept in memory)

## Permissions

### AndroidManifest.xml
```xml
<!-- Required -->
<uses-permission android:name="android.permission.CAMERA" />

<!-- For saving images (Android 12 and below) -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />

<!-- AR features -->
<uses-feature android:name="android.hardware.camera.ar" android:required="false" />
<uses-feature android:glEsVersion="0x00020000" android:required="true" />

<!-- ARCore metadata -->
<meta-data android:name="com.google.ar.core" android:value="optional" />
```

### Runtime Permissions
Camera permission is requested by React Native automatically. For Android 13+, no storage permission needed when using app-specific directory (`filesDir`).

## UI Workflow

### Capture Phase
1. User taps "Start Photogrammetry"
2. ARView starts capturing images every 0.5s
3. Counter updates in real-time (polls every 500ms)
4. User moves around object (50-100 images recommended)
5. User taps "Stop Capture"

### Post-Capture (Android)
1. Shows alert: "Captured X images"
2. Options:
   - **OK**: Dismiss
   - **Process Now**: Shows Android limitation message
   - **Share Images**: Shares directory path

### Post-Capture (iOS)
1. Shows alert: "Captured X images"
2. Options:
   - **OK**: Dismiss
   - **Process Now**: Quality selection → Processing
   - **Share Images**: Shares directory

## Building and Testing

### Build
```bash
cd android
./gradlew clean
./gradlew assembleDebug
cd ..

# Or via React Native CLI
npx react-native run-android
```

### Test on Device
1. Enable USB debugging
2. Connect Android device
3. Install ARCore (Google Play Store)
4. Run `npx react-native run-android`
5. Grant camera permission
6. Start capture, move around object
7. Stop and check image count
8. Images saved to: `/data/data/com.arinreactnative/files/PhotoCapture_{timestamp}/`

### Access Captured Images
```bash
# Via adb
adb shell run-as com.arinreactnative ls files/
adb shell run-as com.arinreactnative cp -r files/PhotoCapture_* /sdcard/
adb pull /sdcard/PhotoCapture_* ./captured_images/
```

## External Processing Workflow

### Option 1: Desktop Software (Recommended)
1. Transfer images to computer:
   ```bash
   adb pull /data/data/com.arinreactnative/files/PhotoCapture_* ./
   ```

2. Process with Metashape:
   - Import images
   - Align photos (uses EXIF/metadata)
   - Build dense cloud
   - Build mesh
   - Export (OBJ, FBX, USDZ, etc.)

### Option 2: Cloud Service
1. Share images from app
2. Upload to service (Polycam, Sketchfab)
3. Wait for processing
4. Download 3D model

### Option 3: Cross-Platform
1. Transfer images to Mac/iPhone
2. Open this app on iOS
3. Import images
4. Process with RealityKit
5. Get USDZ model

## Troubleshooting

### "ARCore not supported"
- Check device compatibility: https://developers.google.com/ar/devices
- Update Google Play Services
- Install ARCore from Play Store

### "Images not capturing"
- Check camera permission granted
- Verify ARSession is running
- Check logs: `adb logcat | grep PhotogrammetryCapture`

### "Counter not updating"
- Ensure `getPhotogrammetryImageCount()` is being called
- Check polling interval is running
- Verify ARView instance is available

### "Out of storage"
- Each image ~1-2MB
- 100 images ~100-200MB
- Clear old captures from `filesDir`

### Performance Issues
- Reduce capture interval (currently 500ms)
- Close other apps
- Ensure good lighting
- Move slowly for better tracking

## Comparison Matrix

| Feature | iOS | Android |
|---------|-----|---------|
| Image Capture | ✅ ARKit | ✅ ARCore |
| Metadata Saved | ✅ | ✅ |
| 3D Reconstruction | ✅ RealityKit | ❌ External only |
| Output Format | USDZ | Images only |
| Device Requirements | LiDAR or A12+ | ARCore compatible |
| Processing Time | 5-30 min | N/A |
| Quality Options | 4 levels | N/A |
| Export | USDZ | JPEG + JSON |

## Future Enhancements

### Potential Additions
1. **On-Device Processing**
   - Integrate open-source libraries (COLMAP, OpenMVG)
   - Would significantly increase app size
   - Processing time likely longer than iOS

2. **Cloud Processing Integration**
   - Direct upload to Polycam/Sketchfab API
   - Background upload while capturing
   - Push notification when complete

3. **Improved Capture Guidance**
   - Visual indicators for coverage
   - Automatic quality assessment
   - Recommended capture count

4. **Depth Data Integration**
   - Use ARCore depth API (supported devices)
   - Enhance reconstruction quality
   - Better scale estimation

## References

- [ARCore Documentation](https://developers.google.com/ar)
- [ARCore Devices](https://developers.google.com/ar/devices)
- [Camera Intrinsics](https://developers.google.com/ar/develop/java/camera-config)
- [Best Practices](https://developers.google.com/ar/develop/best-practices)
