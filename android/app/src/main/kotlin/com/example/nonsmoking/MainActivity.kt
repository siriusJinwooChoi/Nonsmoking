package com.cjw.nonsmoking

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // FlutterActivity는 ComponentActivity가 아니라 enableEdgeToEdge() 확장을 쓸 수 없음.
        // WindowCompat으로 콘텐츠를 시스템 바 뒤까지 그리도록 맞춤 (Android 15 edge-to-edge 권장과 유사).
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

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
