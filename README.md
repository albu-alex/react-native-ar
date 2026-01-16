# AR in React Native

A production-ready implementation demonstrating how to integrate native AR features into React Native apps using custom native modules with **ARKit** (iOS) and **ARCore** (Android).

## 🎯 Features

- ✅ **Native AR Integration**: ARKit (iOS) and ARCore (Android)
- ✅ **Type-Safe API**: Full TypeScript support
- ✅ **React Navigation**: Stack navigator with AR screen
- ✅ **Session Management**: Automatic AR session lifecycle handling
- ✅ **Graceful Fallback**: Detects and handles unsupported devices
- ✅ **Production Ready**: Proper error handling and cleanup

## 📋 Prerequisites

> **Note**: Make sure you have completed the [Set Up Your Environment](https://reactnative.dev/docs/set-up-your-environment) guide.

### Device Requirements
- **iOS**: Physical device with A9+ processor (iPhone 6s or later)
- **Android**: ARCore-compatible device ([see list](https://developers.google.com/ar/devices))

**Important**: AR features do NOT work in simulators/emulators.

## 🚀 Quick Start

### Step 1: Install Dependencies

```sh
npm install
```

### Step 2: Install iOS Pods

```sh
cd ios && pod install && cd ..
```

### Step 3: Start Metro

```sh
npm start
```

### Step 4: Build and Run

**Android:**
```sh
npm run android
```

**iOS:**
```sh
npm run ios
```

**Note**: Must use a physical device - AR does not work in simulators/emulators.

## 📱 Usage

1. Launch the app on your physical device
2. Tap **"Launch AR Experience"** on the home screen
3. Grant camera permissions when prompted
4. The app will check AR support and start an AR session
5. Use **"Start/Stop Session"** to control the AR session

## 🏗️ Architecture

See [AR_IMPLEMENTATION.md](./AR_IMPLEMENTATION.md) for detailed documentation including:
- Native module implementation details
- Platform-specific AR configuration
- TypeScript bridge API
- Lifecycle management
- Next steps for adding AR rendering

## 📂 Project Structure

```
src/
├── native/
│   └── ARNativeModule.ts       # TypeScript bridge to native modules
├── screens/
│   ├── HomeScreen.tsx          # Landing screen with navigation
│   └── ARScreen.tsx            # AR experience with session management
└── types/
    └── navigation.ts           # Navigation type definitions

ios/ARinReactNative/
├── ARNativeModule.swift        # ARKit implementation
├── ARNativeModule.m            # Objective-C bridge
└── Info.plist                  # Camera permissions

android/app/src/main/
├── java/com/arinreactnative/
│   ├── ARNativeModule.kt       # ARCore implementation
│   └── ARNativePackage.kt      # Module registration
└── AndroidManifest.xml         # Permissions and ARCore metadata
```

## 🔧 Native Module API

```typescript
interface ARNativeModuleType {
  // Check if AR is supported on this device
  isSupported(): Promise<boolean>;
  
  // Start an AR session with world tracking
  startSession(): Promise<void>;
  
  // Stop the current AR session
  stopSession(): Promise<void>;
}
```

## 🐛 Troubleshooting

### iOS
- **"AR Not Supported"**: Requires A9+ chip (iPhone 6s or later)
- **Camera permission denied**: Go to Settings → Privacy → Camera
- **Build errors**: Run `cd ios && pod install && cd ..`

### Android
- **"ARCore needs to be installed"**: Install ARCore from Google Play Store
- **"AR Not Supported"**: Check [device compatibility](https://developers.google.com/ar/devices)
- **Permission errors**: Grant camera permission in app settings

### General Issues
See the [React Native Troubleshooting](https://reactnative.dev/docs/troubleshooting) page.

## 🚀 Next Steps

To add actual AR rendering:
1. **iOS**: Integrate `ARSCNView` or `ARView` (RealityKit)
2. **Android**: Add `ArFragment` or custom rendering surface
3. **Both**: Implement hit testing, anchor placement, and 3D models

## 📚 Learn More

- [ARKit Documentation](https://developer.apple.com/documentation/arkit)
- [ARCore Documentation](https://developers.google.com/ar)
- [React Navigation](https://reactnavigation.org/)
- [React Native Documentation](https://reactnative.dev)

---

**Built with**: React Native 0.83, TypeScript, React Navigation, ARKit, ARCore
