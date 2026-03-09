package com.cjw.nonsmoking

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.cjw.nonsmoking/widget")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateWidget" -> {
                        NonsmokingWidget.requestUpdate(applicationContext)
                        result.success(null)
                    }
                    "syncWidgetData" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<String, Any>
                        if (args != null) {
                            NonsmokingWidget.syncDataFromFlutter(applicationContext, args)
                            NonsmokingWidget.requestUpdate(applicationContext)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
