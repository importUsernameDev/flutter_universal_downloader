package com.example.flutter_universal_downloader

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import android.webkit.MimeTypeMap
import android.widget.Toast
import androidx.annotation.NonNull
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLConnection

class FlutterUniversalDownloaderPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    companion object {
        var eventSink: EventChannel.EventSink? = null
    }
    private lateinit var context: Context

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "flutter_universal_downloader")
        channel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "flutter_universal_downloader/progress")
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
        when (call.method) {
            "foregroundDownload" -> {
                val url = call.argument<String>("url")
                val fileName = call.argument<String>("fileName") ?: "file_${System.currentTimeMillis()}"
                if (url == null) {
                    result.error("INVALID_URL", "URL is null", null)
                    return
                }
                val intent = Intent(context, DownloadService::class.java).apply {
                    putExtra("url", url)
                    putExtra("fileName", fileName)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                result.success(true)
            }
            "cancelDownload" -> {
                val intent = Intent(context, DownloadService::class.java).apply {
                    action = "CANCEL_DOWNLOAD" // Reuse the existing cancel action
                }
                context.startService(intent) // Send intent to service to trigger cancellation
                result.success(true)
            }
            else -> result.notImplemented()
        }
    } // This is the correct closing brace for onMethodCall

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}