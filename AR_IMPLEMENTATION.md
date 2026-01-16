# AR Integration Implementation Guide

## Overview

This React Native app integrates native AR capabilities using **ARKit** (iOS) and **ARCore** (Android) through custom native modules, exposed via a unified TypeScript interface.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│              React Native (TypeScript)              │
│  ┌─────────────┐  ┌───────────┐  ┌───────────────┐ │
│  │ HomeScreen  │──│ ARScreen  │──│ Navigation    │ │
│  └─────────────┘  └───────────┘  └───────────────┘ │
│                          │                          │
│                 ┌────────┴────────┐                 │
│                 │ ARNativeModule  │                 │
│                 │   (TypeScript)  │                 │
│                 └────────┬────────┘                 │
└──────────────────────────┼──────────────────────────┘
                           │
           ┌───────────────┴───────────────┐
           │                               │
┌──────────▼──────────┐        ┌──────────▼──────────┐
│   iOS (Swift)       │        │  Android (Kotlin)   │
│  ┌───────────────┐  │        │  ┌───────────────┐  │
│  │ ARNativeModule│  │        │  │ ARNativeModule│  │
│  │   (ARKit)     │  │        │  │   (ARCore)    │  │
│  └───────────────┘  │        │  └───────────────┘  │
│  ARSession          │        │  Session            │
│  ARWorldTracking    │        │  PlaneDetection     │
└─────────────────────┘        └─────────────────────┘
```

## File Structure

```
ARinReactNative/
├── src/
│   ├── native/
│   │   └── ARNativeModule.ts          # TypeScript bridge interface
│   ├── screens/
│   │   ├── HomeScreen.tsx             # Landing screen
│   │   └── ARScreen.tsx               # AR experience screen
│   └── types/
│       └── navigation.ts              # Navigation type definitions
├── ios/
│   └── ARinReactNative/
│       ├── ARNativeModule.swift       # ARKit implementation
│       ├── ARNativeModule.m           # Objective-C bridge
│       └── Info.plist                 # Camera permissions
└── android/
    └── app/src/main/
        ├── java/com/arinreactnative/
        │   ├── ARNativeModule.kt      # ARCore implementation
        │   └── ARNativePackage.kt     # Module registration
        ├── AndroidManifest.xml        # Permissions
        └── build.gradle               # Dependencies
```

## Native Module API

### TypeScript Interface

```typescript
interface ARNativeModuleType {
  isSupported(): Promise<boolean>;
  startSession(): Promise<void>;
  stopSession(): Promise<void>;
}
```

### Methods

#### `isSupported(): Promise<boolean>`
- **Purpose**: Check if AR is supported on the device
- **iOS**: Checks `ARWorldTrackingConfiguration.isSupported`
- **Android**: Checks ARCore availability via `ArCoreApk.checkAvailability()`
- **Returns**: `true` if AR is supported, `false` otherwise

#### `startSession(): Promise<void>`
- **Purpose**: Initialize and start an AR session
- **iOS**: 
  - Creates `ARSession` if needed
  - Configures with `ARWorldTrackingConfiguration`
  - Enables horizontal/vertical plane detection
  - Enables light estimation
- **Android**:
  - Creates `Session` with activity context
  - Configures plane finding for horizontal and vertical surfaces
  - Enables ambient intensity light estimation
- **Throws**: Error if AR not supported or session fails

#### `stopSession(): Promise<void>`
- **Purpose**: Pause/stop the current AR session
- **iOS**: Calls `session.pause()`
- **Android**: Calls `session.pause()`
- **Returns**: Resolves when session is stopped

## Implementation Details

### iOS (ARKit)

**File**: `ios/ARinReactNative/ARNativeModule.swift`

Key features:
- Uses `@objc` decorator for React Native exposure
- Manages `ARSession` lifecycle
- `ARWorldTrackingConfiguration` with:
  - Plane detection (horizontal & vertical)
  - Light estimation
  - Reset tracking on start
- Proper cleanup in `deinit`

**Bridging**: `ios/ARinReactNative/ARNativeModule.m`
- Exports Swift methods to React Native bridge
- Uses `RCT_EXTERN_MODULE` and `RCT_EXTERN_METHOD`
- Ensures main queue execution

**Permissions**: `ios/ARinReactNative/Info.plist`
```xml
<key>NSCameraUsageDescription</key>
<string>This app requires camera access to provide AR experiences</string>
```

### Android (ARCore)

**File**: `android/app/src/main/java/com/arinreactnative/ARNativeModule.kt`

Key features:
- Extends `ReactContextBaseJavaModule`
- Checks ARCore availability and installation status
- Manages `Session` lifecycle
- Configuration includes:
  - Horizontal and vertical plane detection
  - Ambient intensity light estimation
  - Latest camera image update mode
- Cleanup in `onCatalystInstanceDestroy()`

**Registration**: `android/app/src/main/java/com/arinreactnative/ARNativePackage.kt`
- Implements `ReactPackage`
- Registers module in `createNativeModules()`

**Manifest**: `android/app/src/main/AndroidManifest.xml`
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera.ar" android:required="false" />
<meta-data android:name="com.google.ar.core" android:value="optional" />
```

**Dependencies**: `android/app/build.gradle`
```gradle
implementation 'com.google.ar:core:1.41.0'
```

## Navigation Setup

Uses React Navigation v6 with Native Stack Navigator:

```typescript
<Stack.Navigator>
  <Stack.Screen name="Home" component={HomeScreen} />
  <Stack.Screen name="AR" component={ARScreen} />
</Stack.Navigator>
```

## ARScreen Component Lifecycle

1. **Mount**: 
   - Check AR support via `isSupported()`
   - Show alert if not supported

2. **Focus** (via `useFocusEffect`):
   - Start AR session automatically
   - Manages session state

3. **Blur/Unmount**:
   - Stop AR session
   - Clean up resources

4. **User Controls**:
   - Toggle session manually
   - Navigate back to home

## Why This Architecture?

### Native Modules (Not Expo Modules)
- **Direct integration**: Access platform-specific AR APIs without abstraction layers
- **Performance**: No JavaScript bridge overhead for critical AR operations
- **Full control**: Complete access to ARKit and ARCore features

### Separate Platform Implementations
- **ARKit vs ARCore differences**: Different APIs, capabilities, and behaviors
- **Platform-specific configuration**: Unique setup for each platform
- **Independent updates**: Can optimize each platform separately

### Session Management in Native
- **Resource efficiency**: Native code manages AR resources directly
- **Lifecycle handling**: Proper cleanup when app backgrounds/closes
- **State consistency**: Single source of truth in native layer

### TypeScript Bridge
- **Type safety**: Full IntelliSense and compile-time checks
- **Error handling**: Promise-based API with proper error propagation
- **Platform abstraction**: JS code doesn't need to know about platform differences

## Running the App

### iOS
```bash
cd ios && pod install && cd ..
npm run ios
```

### Android
```bash
npm run android
```

## Next Steps

To add actual AR rendering:

1. **iOS**: 
   - Add `ARSCNView` or `ARView` (RealityKit)
   - Create UIViewRepresentable bridge
   - Implement delegate methods for tracking

2. **Android**:
   - Add `ArFragment` or custom `SurfaceView`
   - Implement rendering pipeline
   - Handle frame updates

3. **Cross-platform**:
   - Add native UI component modules
   - Bridge AR anchor/hit-test results to JS
   - Implement 3D object placement

## Common Issues

### iOS
- **Simulator**: ARKit not supported - use physical device
- **Permissions**: Denied camera access - check Settings
- **Device compatibility**: Requires A9+ processor (iPhone 6s+)

### Android
- **ARCore not installed**: User must install from Play Store
- **Device compatibility**: Check [supported devices](https://developers.google.com/ar/devices)
- **Permissions**: Runtime camera permission required

## Testing

- **iOS**: Requires physical device with A9+ chip
- **Android**: Requires ARCore-supported device
- **Fallback**: App gracefully handles unsupported devices

---

**Key Benefits**:
✅ Production-ready native integration  
✅ Type-safe TypeScript API  
✅ Proper lifecycle management  
✅ Platform-specific optimization  
✅ Graceful degradation  
✅ Clean separation of concerns
