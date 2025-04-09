package com.example.slr_application_with_tts

import android.app.Activity
import android.content.Context
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizerResult
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

class HandLandmarkerView(
    private val context: Context,
    private val gestureRecognizerHelper: GestureRecognizerHelper,
    private val methodChannel: MethodChannel
) : PlatformView, GestureRecognizerHelper.GestureRecognizerListener {
    private val previewView: PreviewView = PreviewView(context).apply {
        layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
    }
    
    private val container: FrameLayout = FrameLayout(context)
    private var camera: Camera? = null
    private var preview: Preview? = null
    private var imageAnalyzer: ImageAnalysis? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private val overlayView: OverlayView = OverlayView(context, null).apply {
        layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
    }

    companion object {
        private const val TAG = "HandLandmarkerView"
    }

    init {
        container.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        container.addView(previewView)
        container.addView(overlayView)
        
        // Set up method channel handler
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "toggleCamera" -> {
                    if (camera == null) {
                        startCamera()
                        result.success(true)
                    } else {
                        stopCamera()
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                
                // Preview use case
                preview = Preview.Builder()
                    .setTargetRotation(previewView.display.rotation)
                    .build()
                    .also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }

                // Image analysis use case
                imageAnalyzer = ImageAnalysis.Builder()
                    .setTargetRotation(previewView.display.rotation)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .build()
                    .also {
                        it.setAnalyzer(
                            ContextCompat.getMainExecutor(context)
                        ) { image ->
                            gestureRecognizerHelper.recognizeLiveStream(image)
                        }
                    }

                // Front camera
                val cameraSelector = CameraSelector.Builder()
                    .requireLensFacing(CameraSelector.LENS_FACING_FRONT)
                    .build()

                try {
                    cameraProvider?.unbindAll()
                    camera = cameraProvider?.bindToLifecycle(
                        context as LifecycleOwner,
                        cameraSelector,
                        preview,
                        imageAnalyzer
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "Use case binding failed", e)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Camera initialization failed", e)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun stopCamera() {
        cameraProvider?.unbindAll()
        camera = null
        overlayView.clear()
    }

    private fun recognizeHand(imageProxy: ImageProxy) {
        gestureRecognizerHelper.recognizeLiveStream(
            imageProxy = imageProxy
        )
    }

    override fun onResults(resultBundle: GestureRecognizerHelper.ResultBundle) {
        val activity = context as Activity
        activity.runOnUiThread {
            // Update overlay with landmarks
            overlayView.setResults(
                resultBundle.results.first(),
                resultBundle.inputImageHeight,
                resultBundle.inputImageWidth,
                RunningMode.LIVE_STREAM
            )

            // Send results to Flutter
            val gestureCategories = resultBundle.results.first().gestures()
            if (gestureCategories.isNotEmpty()) {
                val firstGesture = gestureCategories.first()
                if (firstGesture.isNotEmpty()) {
                    val gestureName = firstGesture.first().categoryName()
                    val confidence = firstGesture.first().score()
                    
                    // Extract landmarks for action recognition
                    val landmarks = resultBundle.landmarks
                    
                    methodChannel.invokeMethod("onGestureRecognized", mapOf(
                        "gesture" to gestureName,
                        "confidence" to confidence,
                        "inferenceTime" to resultBundle.inferenceTime,
                        "landmarks" to landmarks
                    ))
                }
            }
        }
    }

    override fun onError(error: String, errorCode: Int) {
        // Send error to Flutter through MethodChannel
        methodChannel.invokeMethod("onError", mapOf(
            "error" to error,
            "errorCode" to errorCode
        ))
    }

    override fun getView(): View = container

    override fun dispose() {
        cameraProvider?.unbindAll()
        camera = null
    }
}