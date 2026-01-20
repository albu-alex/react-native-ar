package com.arinreactnative

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.util.AttributeSet
import android.util.Log
import android.view.MotionEvent
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.events.RCTEventEmitter
import com.google.ar.core.*
import com.google.ar.core.exceptions.CameraNotAvailableException
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * ARCore view component for React Native
 * Handles AR camera display and frame capture for photogrammetry
 */
class ARView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : GLSurfaceView(context, attrs), GLSurfaceView.Renderer {

    private var session: Session? = null
    private val photogrammetryCapture = PhotogrammetryCapture()
    private var isScanning = false
    
    companion object {
        private const val TAG = "ARView"
        
        // Store reference for native module access
        private var sharedInstance: ARView? = null
        
        fun getSharedInstance(): ARView? = sharedInstance
    }

    init {
        sharedInstance = this
        
        // Configure GLSurfaceView
        preserveEGLContextOnPause = true
        setEGLContextClientVersion(2)
        setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        setRenderer(this)
        renderMode = RENDERMODE_CONTINUOUSLY
    }

    /**
     * Start AR session
     */
    fun startSession() {
        try {
            if (session == null) {
                session = Session(context)
                
                // Configure session
                val config = Config(session).apply {
                    planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                    lightEstimationMode = Config.LightEstimationMode.AMBIENT_INTENSITY
                    updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                }
                
                session?.configure(config)
            }
            
            session?.resume()
            Log.d(TAG, "AR session started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start session: ${e.message}", e)
        }
    }

    /**
     * Stop AR session
     */
    fun stopSession() {
        try {
            session?.pause()
            Log.d(TAG, "AR session paused")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop session: ${e.message}", e)
        }
    }

    /**
     * Start photogrammetry scanning
     */
    fun startObjectScan(): Map<String, Any> {
        return try {
            val documentsDir = context.filesDir
            val captureDir = photogrammetryCapture.startCapture(documentsDir)
            isScanning = true
            
            sendEvent("onScanProgress", mapOf(
                "status" to "started",
                "imageCount" to 0
            ))
            
            mapOf(
                "success" to true,
                "directory" to captureDir.absolutePath
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start scan: ${e.message}", e)
            mapOf(
                "success" to false,
                "error" to (e.message ?: "Unknown error")
            )
        }
    }

    /**
     * Stop photogrammetry scanning
     */
    fun stopObjectScan(): Map<String, Any> {
        isScanning = false
        val (directory, imageCount) = photogrammetryCapture.stopCapture()
        
        val result = mapOf(
            "imageCount" to imageCount,
            "directory" to (directory?.absolutePath ?: ""),
            "scanType" to "photogrammetry"
        )
        
        sendEvent("onScanComplete", result)
        Log.d(TAG, "Stopped scan. Images: $imageCount")
        
        return result
    }

    /**
     * Clear current scan
     */
    fun clearScan() {
        isScanning = false
        // PhotogrammetryCapture will be reset on next startCapture
    }

    /**
     * Get current capture directory
     */
    fun getPhotogrammetryCaptureDirectory(): String? {
        return photogrammetryCapture.getCurrentCaptureDirectory()?.absolutePath
    }

    /**
     * Get current image count
     */
    fun getPhotogrammetryImageCount(): Int {
        return photogrammetryCapture.getCurrentImageCount()
    }

    /**
     * Send event to React Native
     */
    private fun sendEvent(eventName: String, params: Map<String, Any>) {
        val reactContext = context as? ReactContext ?: return
        val event = Arguments.createMap()
        
        params.forEach { (key, value) ->
            when (value) {
                is String -> event.putString(key, value)
                is Int -> event.putInt(key, value)
                is Double -> event.putDouble(key, value)
                is Boolean -> event.putBoolean(key, value)
                else -> event.putString(key, value.toString())
            }
        }
        
        reactContext
            .getJSModule(RCTEventEmitter::class.java)
            .receiveEvent(id, eventName, event)
    }

    // GLSurfaceView.Renderer implementation
    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.1f, 0.1f, 0.1f, 1.0f)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        session?.setDisplayGeometry(0, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        // Clear screen
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)

        val session = this.session ?: return

        try {
            // Update session to get latest frame
            session.setCameraTextureName(0)
            val frame = session.update()

            // Process frame for photogrammetry capture
            if (isScanning) {
                photogrammetryCapture.processFrame(frame)
            }

            // Draw camera image (simplified - in production you'd use proper rendering)
            // For now we just update the frame, rendering is handled by ARCore
            
        } catch (e: CameraNotAvailableException) {
            Log.e(TAG, "Camera not available: ${e.message}", e)
        } catch (e: Exception) {
            Log.e(TAG, "Error in onDrawFrame: ${e.message}", e)
        }
    }

    override fun onPause() {
        super.onPause()
        session?.pause()
    }

    override fun onResume() {
        super.onResume()
        try {
            session?.resume()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to resume session: ${e.message}", e)
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        session?.close()
        session = null
        sharedInstance = null
    }
}
