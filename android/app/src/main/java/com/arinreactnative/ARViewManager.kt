package com.arinreactnative

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext

/**
 * View manager for ARView component
 * Manages the lifecycle and props of the AR view in React Native
 */
class ARViewManager(
    private val reactContext: ReactApplicationContext
) : SimpleViewManager<ARView>() {

    override fun getName(): String {
        return "ARViewNative"
    }

    override fun createViewInstance(reactContext: ThemedReactContext): ARView {
        val arView = ARView(reactContext)
        
        // Auto-start the AR session when view is created
        arView.post {
            arView.startSession()
        }
        
        return arView
    }

    override fun onDropViewInstance(view: ARView) {
        super.onDropViewInstance(view)
        view.stopSession()
    }
}
