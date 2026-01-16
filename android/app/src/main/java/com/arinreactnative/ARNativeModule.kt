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
            val activity = currentActivity
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
            val activity = currentActivity
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
                arSession = Session(activity)
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
}
