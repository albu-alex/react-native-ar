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

  /**
   * Start object scanning
   * @returns Promise that resolves when scanning starts
   */
  startObjectScan(): Promise<void>;

  /**
   * Stop object scanning and get scan data
   * @returns Promise with scan data (vertices, faces, counts, etc.)
   */
  stopObjectScan(): Promise<{
    vertices: number[][];
    faces: number[][];
    vertexCount: number;
    faceCount: number;
    meshCount: number;
    boundingBox?: {
      min: number[];
      max: number[];
    };
  }>;

  /**
   * Clear current scan
   * @returns Promise that resolves when scan is cleared
   */
  clearScan(): Promise<void>;

  /**
   * Export scan as OBJ string
   * @returns Promise with OBJ file content
   */
  exportScanAsOBJ(): Promise<string>;

  /**
   * Save scan to file
   * @param filename Name of the file (without extension)
   * @returns Promise with file path
   */
  saveOBJToFile(filename: string): Promise<string>;
}

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
