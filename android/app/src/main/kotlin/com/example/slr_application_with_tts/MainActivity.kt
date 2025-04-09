package com.example.slr_application_with_tts

import com.google.mediapipe.tasks.vision.core.RunningMode
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class MainActivity : FlutterActivity(), GestureRecognizerHelper.GestureRecognizerListener {
    private val CHANNEL = "com.example.handlandmarker/detection"
    private lateinit var gestureRecognizerHelper: GestureRecognizerHelper
    private lateinit var methodChannel: MethodChannel
    private lateinit var actionRecognizer: ActionRecognizer

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize MethodChannel
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        // Initialize ActionRecognizer
        actionRecognizer = ActionRecognizer(this)

        // Initialize GestureRecognizerHelper with this as the listener
        gestureRecognizerHelper = GestureRecognizerHelper(
            context = this,
            runningMode = RunningMode.LIVE_STREAM,
            minHandDetectionConfidence = 0.5f,
            minHandTrackingConfidence = 0.5f,
            minHandPresenceConfidence = 0.5f,
            currentDelegate = GestureRecognizerHelper.DELEGATE_CPU,
            gestureRecognizerListener = this
        )

        // Register the PlatformView factory
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "hand_landmarker_view",
            HandLandmarkerViewFactory(this, gestureRecognizerHelper, methodChannel)
        )

        // Set up method channel handler
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "toggleCamera" -> {
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Implement GestureRecognizerListener methods
    override fun onResults(resultBundle: GestureRecognizerHelper.ResultBundle) {
        // Process and send results to Flutter
        val results = resultBundle.results.firstOrNull()
        results?.let { result ->
            val gestures = result.gestures()
            if (gestures.isNotEmpty() && gestures[0].isNotEmpty()) {
                val gesture = gestures[0][0]
                
                // Process action recognition if landmarks available
                val landmarks = resultBundle.landmarks
                Log.d("MainActivity", "Got ${landmarks.size} landmarks")
                
                val actionResult = if (landmarks.isNotEmpty()) {
                    Log.d("MainActivity", "Calling actionRecognizer with landmarks")
                    actionRecognizer.recognizeAction(landmarks)
                } else {
                    Log.d("MainActivity", "No landmarks available for action recognition")
                    Pair(null, 0.0f)
                }
                
                Log.d("MainActivity", "Action result: ${actionResult.first} with confidence ${actionResult.second}")
                
                runOnUiThread {
                    methodChannel.invokeMethod("onGestureRecognized", mapOf(
                        "gesture" to gesture.categoryName(),
                        "confidence" to gesture.score(),
                        "inferenceTime" to resultBundle.inferenceTime,
                        "landmarks" to landmarks,
                        "action" to actionResult.first,
                        "actionConfidence" to actionResult.second
                    ))
                }
            }
        }
    }

    override fun onError(error: String, errorCode: Int) {
        // Send error to Flutter
        runOnUiThread {
            methodChannel.invokeMethod("onError", mapOf(
                "error" to error,
                "errorCode" to errorCode
            ))
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        gestureRecognizerHelper.clearGestureRecognizer()
        actionRecognizer.close()
    }
}