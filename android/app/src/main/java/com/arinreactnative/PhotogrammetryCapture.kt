package com.arinreactnative

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.Image
import android.util.Log
import com.google.ar.core.Frame
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*

/**
 * Handles photogrammetry image capture from ARCore frames
 * Similar to iOS implementation but without actual 3D reconstruction
 * (Android doesn't have built-in photogrammetry like iOS RealityKit)
 */
class PhotogrammetryCapture {
    private var captureDirectory: File? = null
    private var imageCount: Int = 0
    private var isCapturing: Boolean = false
    private var lastCaptureTime: Long = 0
    private val captureIntervalMs: Long = 500 // Capture every 0.5 seconds

    companion object {
        private const val TAG = "PhotogrammetryCapture"
        
        /**
         * Check if photogrammetry is supported
         * On Android, we can capture images but don't have built-in 3D reconstruction
         * User would need to use external tools/services for processing
         */
        fun isPhotogrammetrySupported(): Boolean {
            // On Android, we support image capture but not processing
            // This returns true to indicate capture is supported
            // Actual 3D reconstruction would require external library/service
            return true
        }
    }

    /**
     * Start capturing images
     * @param documentsDir The app's documents directory
     * @return The directory where images will be saved
     */
    fun startCapture(documentsDir: File): File {
        if (isCapturing) {
            throw IllegalStateException("Already capturing")
        }

        // Create timestamped directory
        val timestamp = System.currentTimeMillis()
        val captureDir = File(documentsDir, "PhotoCapture_$timestamp")
        captureDir.mkdirs()

        this.captureDirectory = captureDir
        this.imageCount = 0
        this.isCapturing = true
        this.lastCaptureTime = 0

        Log.d(TAG, "Started capture in: ${captureDir.absolutePath}")
        return captureDir
    }

    /**
     * Stop capturing and return results
     * @return Pair of directory and image count
     */
    fun stopCapture(): Pair<File?, Int> {
        isCapturing = false
        val results = Pair(captureDirectory, imageCount)
        Log.d(TAG, "Stopped capture. Total images: $imageCount")
        return results
    }

    /**
     * Get current image count without stopping capture
     */
    fun getCurrentImageCount(): Int {
        return imageCount
    }

    /**
     * Get current capture directory without stopping capture
     */
    fun getCurrentCaptureDirectory(): File? {
        return captureDirectory
    }

    /**
     * Check if currently capturing
     */
    fun isCurrentlyCapturing(): Boolean {
        return isCapturing
    }

    /**
     * Process an ARCore frame and capture if needed
     * @param frame The ARCore frame to process
     */
    fun processFrame(frame: Frame) {
        if (!isCapturing) return
        val captureDir = captureDirectory ?: return

        val currentTime = System.currentTimeMillis()
        
        // Check if enough time has passed since last capture
        if (currentTime - lastCaptureTime < captureIntervalMs) return

        try {
            captureImage(frame, captureDir)
            lastCaptureTime = currentTime
            imageCount++
            Log.d(TAG, "Captured image $imageCount")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to capture image: ${e.message}", e)
        }
    }

    /**
     * Capture a single image with metadata from ARCore frame
     */
    private fun captureImage(frame: Frame, directory: File) {
        // Get camera image
        val cameraImage = frame.acquireCameraImage()
        
        try {
            // Convert to JPEG
            val jpegData = imageToJpeg(cameraImage)
            
            // Save image
            val imageFilename = String.format("image_%04d.jpg", imageCount)
            val imageFile = File(directory, imageFilename)
            FileOutputStream(imageFile).use { it.write(jpegData) }

            // Save metadata
            val metadata = JSONObject().apply {
                // Camera pose (transform)
                val pose = frame.camera.pose
                put("transform", JSONArray().apply {
                    // Convert pose to 4x4 matrix
                    val translation = pose.translation
                    val rotation = pose.rotationQuaternion
                    
                    // Store translation and rotation quaternion
                    put(JSONArray().apply {
                        put(translation[0])
                        put(translation[1])
                        put(translation[2])
                    })
                    put(JSONArray().apply {
                        put(rotation[0])
                        put(rotation[1])
                        put(rotation[2])
                        put(rotation[3])
                    })
                })

                // Camera intrinsics
                val intrinsics = frame.camera.imageIntrinsics
                val focalLength = intrinsics.focalLength
                val principalPoint = intrinsics.principalPoint
                val imageSize = intrinsics.imageDimensions
                
                put("intrinsics", JSONObject().apply {
                    put("focalLength", JSONArray().apply {
                        put(focalLength[0])
                        put(focalLength[1])
                    })
                    put("principalPoint", JSONArray().apply {
                        put(principalPoint[0])
                        put(principalPoint[1])
                    })
                    put("imageSize", JSONArray().apply {
                        put(imageSize[0])
                        put(imageSize[1])
                    })
                })

                // Image resolution
                put("imageResolution", JSONObject().apply {
                    put("width", cameraImage.width)
                    put("height", cameraImage.height)
                })

                // Timestamp
                put("timestamp", frame.timestamp)
                
                // Tracking state
                put("trackingState", frame.camera.trackingState.name)
            }

            val metadataFilename = String.format("image_%04d.json", imageCount)
            val metadataFile = File(directory, metadataFilename)
            FileOutputStream(metadataFile).use {
                it.write(metadata.toString(2).toByteArray())
            }
        } finally {
            cameraImage.close()
        }
    }

    /**
     * Convert ARCore Image to JPEG bytes
     */
    private fun imageToJpeg(image: Image): ByteArray {
        // ARCore camera images are in YUV format
        val yBuffer = image.planes[0].buffer
        val uBuffer = image.planes[1].buffer
        val vBuffer = image.planes[2].buffer

        val ySize = yBuffer.remaining()
        val uSize = uBuffer.remaining()
        val vSize = vBuffer.remaining()

        val nv21 = ByteArray(ySize + uSize + vSize)

        yBuffer.get(nv21, 0, ySize)
        vBuffer.get(nv21, ySize, vSize)
        uBuffer.get(nv21, ySize + vSize, uSize)

        val yuvImage = YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
        val out = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, image.width, image.height), 95, out)
        
        return out.toByteArray()
    }
}
