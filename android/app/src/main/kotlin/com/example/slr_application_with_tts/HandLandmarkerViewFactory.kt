package com.example.slr_application_with_tts

import android.content.Context
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class HandLandmarkerViewFactory(
    private val activity: FlutterActivity,
    private val gestureRecognizerHelper: GestureRecognizerHelper,
    private val methodChannel: MethodChannel
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
        return HandLandmarkerView(activity, gestureRecognizerHelper, methodChannel)
    }
}