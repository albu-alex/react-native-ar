import { NativeModules, Platform } from 'react-native';

const LINKING_ERROR =
  `The package 'ARNativeModule' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go\n';

export interface ARNativeModuleType {
  /**
   * Check if AR is supported on this device
   * @returns Promise resolving to true if AR is supported, false otherwise
   */
  isSupported(): Promise<boolean>;

  /**
   * Start an AR session with world tracking
   * @returns Promise that resolves when session starts successfully
   * @throws Error if AR is not supported or session fails to start
   */
  startSession(): Promise<void>;

  /**
   * Stop the current AR session
   * @returns Promise that resolves when session stops
   */
  stopSession(): Promise<void>;
}

// Debug: Log all available native modules
console.log('Available NativeModules:', Object.keys(NativeModules));
console.log('ARNativeModule exists?', !!NativeModules.ARNativeModule);
console.log('ARNativeModule value:', NativeModules.ARNativeModule);

// Link to the native module
const ARNativeModuleRaw = NativeModules.ARNativeModule
  ? NativeModules.ARNativeModule
  : new Proxy(
      {},
      {
        get() {
          throw new Error(LINKING_ERROR);
        },
      }
    );

/**
 * Native AR Module
 * Provides unified interface for ARKit (iOS) and ARCore (Android)
 */
export const ARNativeModule: ARNativeModuleType = ARNativeModuleRaw;
