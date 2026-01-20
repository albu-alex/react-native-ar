package com.arinreactnative

import com.facebook.react.bridge.*
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Session
import com.google.ar.core.exceptions.UnavailableException

class ARNativeModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    private var arSession: Session? = null

    override fun getName(): String {
        return "ARNativeModule"
    }

    /**
     * Check if ARCore is supported and installed on this device
     * @param promise - Resolves with boolean indicating AR support
     */
    @ReactMethod
    fun isSupported(promise: Promise) {
        try {
            val activity = reactApplicationContext.currentActivity
            if (activity == null) {
                promise.resolve(false)
                return
            }

            val availability = ArCoreApk.getInstance().checkAvailability(activity)
            
            // Check if ARCore is supported and installed
            val supported = when (availability) {
                ArCoreApk.Availability.SUPPORTED_INSTALLED -> true
                ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD,
                ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED -> {
                    // ARCore is supported but needs update/install
                    true
                }
                else -> false
            }
            
            promise.resolve(supported)
        } catch (e: Exception) {
            promise.resolve(false)
        }
    }

    /**
     * Start an ARCore session
     * @param promise - Resolves when session starts successfully, rejects on error
     */
    @ReactMethod
    fun startSession(promise: Promise) {
        try {
            val activity = reactApplicationContext.currentActivity
            if (activity == null) {
                promise.reject(
                    "NO_ACTIVITY",
                    "Activity is null, cannot start AR session"
                )
                return
            }

            // Check ARCore availability
            val availability = ArCoreApk.getInstance().checkAvailability(activity)
            if (!availability.isSupported) {
                promise.reject(
                    "AR_NOT_SUPPORTED",
                    "ARCore is not supported on this device"
                )
                return
            }

            // Request ARCore installation if needed
            if (availability == ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED ||
                availability == ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD) {
                // In production, you'd handle the installation flow
                // For now, we'll reject if not installed
                promise.reject(
                    "ARCORE_NOT_INSTALLED",
                    "ARCore needs to be installed or updated"
                )
                return
            }

            // Create session if it doesn't exist
            if (arSession == null) {
                arSession = Session(reactApplicationContext)
            }

            // Configure the session
            val config = Config(arSession).apply {
                // Enable plane finding
                planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                
                // Enable light estimation
                lightEstimationMode = Config.LightEstimationMode.AMBIENT_INTENSITY
                
                // Update mode - let ARCore decide optimal frame rate
                updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            }

            arSession?.configure(config)
            arSession?.resume()

            promise.resolve(null)
        } catch (e: UnavailableException) {
            promise.reject(
                "AR_UNAVAILABLE",
                "ARCore is unavailable: ${e.message}",
                e
            )
        } catch (e: Exception) {
            promise.reject(
                "START_SESSION_FAILED",
                "Failed to start AR session: ${e.message}",
                e
            )
        }
    }

    /**
     * Stop the current ARCore session
     * @param promise - Resolves when session stops
     */
    @ReactMethod
    fun stopSession(promise: Promise) {
        try {
            arSession?.pause()
            promise.resolve(null)
        } catch (e: Exception) {
            promise.reject(
                "STOP_SESSION_FAILED",
                "Failed to stop AR session: ${e.message}",
                e
            )
        }
    }

    /**
     * Clean up resources when module is destroyed
     */
    override fun onCatalystInstanceDestroy() {
        super.onCatalystInstanceDestroy()
        try {
            arSession?.pause()
            arSession?.close()
            arSession = null
        } catch (e: Exception) {
            // Ignore cleanup errors
        }
    }

    // MARK: - Photogrammetry Methods

    /**
     * Check if photogrammetry is supported on this device
     * On Android, we support image capture but not built-in processing
     */
    @ReactMethod
    fun isPhotogrammetrySupported(promise: Promise) {
        // Android can capture images but doesn't have built-in photogrammetry
        // User would need external tools/services for 3D reconstruction
        promise.resolve(PhotogrammetryCapture.isPhotogrammetrySupported())
    }

    /**
     * Start object scanning (photogrammetry capture)
     */
    @ReactMethod
    fun startObjectScan(promise: Promise) {
        try {
            val arView = ARView.getSharedInstance()
            if (arView == null) {
                promise.reject(
                    "AR_VIEW_NOT_FOUND",
                    "AR View is not initialized"
                )
                return
            }

            val result = arView.startObjectScan()
            if (result["success"] == true) {
                promise.resolve(null)
            } else {
                promise.reject(
                    "START_SCAN_FAILED",
                    result["error"] as? String ?: "Failed to start scan"
                )
            }
        } catch (e: Exception) {
            promise.reject(
                "START_SCAN_ERROR",
                "Error starting scan: ${e.message}",
                e
            )
        }
    }

    /**
     * Stop object scanning and get scan data
     */
    @ReactMethod
    fun stopObjectScan(promise: Promise) {
        try {
            val arView = ARView.getSharedInstance()
            if (arView == null) {
                promise.reject(
                    "AR_VIEW_NOT_FOUND",
                    "AR View is not initialized"
                )
                return
            }

            val result = arView.stopObjectScan()
            val map = Arguments.createMap().apply {
                putInt("imageCount", result["imageCount"] as? Int ?: 0)
                putString("directory", result["directory"] as? String ?: "")
                putString("scanType", result["scanType"] as? String ?: "photogrammetry")
            }
            
            promise.resolve(map)
        } catch (e: Exception) {
            promise.reject(
                "STOP_SCAN_ERROR",
                "Error stopping scan: ${e.message}",
                e
            )
        }
    }

    /**
     * Clear current scan
     */
    @ReactMethod
    fun clearScan(promise: Promise) {
        try {
            val arView = ARView.getSharedInstance()
            if (arView == null) {
                promise.reject(
                    "AR_VIEW_NOT_FOUND",
                    "AR View is not initialized"
                )
                return
            }

            arView.clearScan()
            promise.resolve(null)
        } catch (e: Exception) {
            promise.reject(
                "CLEAR_SCAN_ERROR",
                "Error clearing scan: ${e.message}",
                e
            )
        }
    }

    /**
     * Get the directory where photogrammetry images are being captured
     */
    @ReactMethod
    fun getPhotogrammetryCaptureDirectory(promise: Promise) {
        try {
            val arView = ARView.getSharedInstance()
            if (arView == null) {
                promise.reject(
                    "AR_VIEW_NOT_FOUND",
                    "AR View is not initialized"
                )
                return
            }

            val directory = arView.getPhotogrammetryCaptureDirectory()
            promise.resolve(directory)
        } catch (e: Exception) {
            promise.reject(
                "GET_DIRECTORY_ERROR",
                "Error getting capture directory: ${e.message}",
                e
            )
        }
    }

    /**
     * Get the current count of captured images
     */
    @ReactMethod
    fun getPhotogrammetryImageCount(promise: Promise) {
        try {
            val arView = ARView.getSharedInstance()
            if (arView == null) {
                promise.reject(
                    "AR_VIEW_NOT_FOUND",
                    "AR View is not initialized"
                )
                return
            }

            val count = arView.getPhotogrammetryImageCount()
            promise.resolve(count)
        } catch (e: Exception) {
            promise.reject(
                "GET_COUNT_ERROR",
                "Error getting image count: ${e.message}",
                e
            )
        }
    }

    /**
     * Process photogrammetry images
     * Note: Android doesn't have built-in photogrammetry like iOS
     * This method returns the directory path for external processing
     */
    @ReactMethod
    fun processPhotogrammetry(
        inputDirectory: String,
        outputFilename: String,
        detail: String,
        progressCallback: Callback,
        promise: Promise
    ) {
        // Android doesn't have built-in photogrammetry processing
        // User needs to use external tools/services
        promise.reject(
            "NOT_IMPLEMENTED",
            "3D reconstruction is not available on Android. Please use the captured images with external photogrammetry software (e.g., Metashape, RealityCapture, or cloud services like Polycam API)."
        )
    }
}
