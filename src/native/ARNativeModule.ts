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
   * Check if photogrammetry is supported on this device
   * Requires Mac with 4GB+ GPU and ray tracing, or iOS device with LiDAR
   * @returns Promise resolving to true if photogrammetry is supported
   */
  isPhotogrammetrySupported(): Promise<boolean>;

  /**
   * Process captured images using RealityKit's PhotogrammetrySession
   * @param inputDirectory Path to directory containing captured images
   * @param outputFilename Name for output USDZ file (without extension)
   * @param detail Quality level - "reduced", "medium", "full", or "raw"
   * @param progressCallback Callback for progress updates
   * @returns Promise with path to generated USDZ file
   */
  processPhotogrammetry(
    inputDirectory: string,
    outputFilename: string,
    detail: string,
    progressCallback: (progress: { status: string; progress: number }[]) => void
  ): Promise<string>;

  /**
   * Get the directory where photogrammetry images are being captured
   * @returns Promise with directory path or null
   */
  getPhotogrammetryCaptureDirectory(): Promise<string | null>;

  /**
   * Get the current count of captured images
   * @returns Promise with image count
   */
  getPhotogrammetryImageCount(): Promise<number>;
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
