package com.zennora.zed_display

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.zennora.zed_display/intent"
    private var sharedFileContent: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_VIEW -> {
                intent.data?.let { uri ->
                    try {
                        // Read file content from content:// URI
                        contentResolver.openInputStream(uri)?.use { inputStream ->
                            BufferedReader(InputStreamReader(inputStream)).use { reader ->
                                sharedFileContent = reader.readText()
                            }
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedFileContent" -> {
                    result.success(sharedFileContent)
                    sharedFileContent = null // Clear after reading
                }
                else -> result.notImplemented()
            }
        }
    }
}
