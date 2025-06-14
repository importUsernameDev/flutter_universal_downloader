package com.example.flutter_universal_downloader

import android.app.*
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import kotlinx.coroutines.*
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLConnection
import java.text.DecimalFormat // For formatting bytes

/**
 * A foreground service responsible for downloading files in the background.
 * It uses Kotlin Coroutines for asynchronous operations and MediaStore for
 * saving files on Android Q (API 29) and above. It provides a persistent
 * notification to inform the user about ongoing downloads, as required
 * for foreground services.
 */
class DownloadService : Service() {

    // --- Constants and Service State Variables ---
    private val channelId = "download_foreground_channel" // Unique ID for the notification channel
    private val NOTIFICATION_ID = 1 // Unique ID for the foreground service notification

    // Flag to signal if the current download operation has been cancelled
    private var isCancelled = false

    // Stores the MediaStore URI of the currently downloading file.
    // This is used to delete incomplete files on cancellation or error.
    private var downloadUri: Uri? = null

    // Coroutine scope for managing background tasks within the service's lifecycle.
    // It's initialized with Dispatchers.IO for network/disk operations.
    // We use a nullable Job to allow cancellation and re-creation for new downloads.
    private var currentDownloadJob: Job? = null
    private val serviceScope = CoroutineScope(Dispatchers.IO) // Scope tied to the service's lifetime

    private val TAG = "DownloadService" // Tag for Logcat messages

    // For formatting byte sizes into human-readable strings (e.g., 1.5 MB)
    private val decimalFormat = DecimalFormat("#.##")

    // --- Service Lifecycle Callbacks ---

    /**
     * Called when the service is first created.
     * Initializes the notification channel.
     */
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created.")
        createNotificationChannel()
    }

    /**
     * Called when the service is started via startService().
     * This is the entry point for handling download requests.
     */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Service onStartCommand called.")

        // --- Handle Cancel Action ---
        // Check if the intent is for cancelling the current download.
        if (intent?.action == "CANCEL_DOWNLOAD") {
            Log.d(TAG, "Download cancellation requested.")
            isCancelled = true // Set cancellation flag

            // Attempt to cancel the ongoing download coroutine
            currentDownloadJob?.cancel()

            // Delete incomplete file if its URI was stored
            downloadUri?.let { uri ->
                try {
                    contentResolver.delete(uri, null, null)
                    Log.d(TAG, "Incomplete download deleted: $uri")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to delete incomplete file: ${e.message}")
                }
            }
            sendDownloadResultToFlutter(false, "Download cancelled", "canceled")
            // Update notification to reflect cancellation (e.g., "Download Cancelled")
            // Pass -1L for byte counts as they are not relevant for cancelled state contentText logic
            updateNotification("Download Cancelled", 0, 0, -1L, -1L, false, NotificationCompat.CATEGORY_STATUS)
            stopForeground(true) // Remove notification and stop foreground state immediately
            stopSelf() // Stop the service itself
            return START_NOT_STICKY // Don't restart the service if it's killed
        }

        // --- Extract Download Parameters ---
        val url = intent?.getStringExtra("url")
        val fileName = intent?.getStringExtra("fileName")

        if (url == null || fileName == null) {
            Log.e(TAG, "URL or fileName is null, stopping service.")
            sendDownloadResultToFlutter(false, "Invalid download parameters", "invalid_params")
            stopSelf() // Stop service if parameters are invalid
            return START_NOT_STICKY
        }

        // --- Prepare for a New Download ---
        // Cancel any previously running download job to ensure only one is active at a time.
        // If you want to support concurrent downloads, you'd manage a list of jobs.
        currentDownloadJob?.cancel()

        isCancelled = false // Reset cancellation flag for the new download
        downloadUri = null // Reset download URI for the new download

        // Start the foreground notification immediately with a "Preparing..." message.
        // This is critical for Android to understand that your service is performing
        // a user-visible task and prevent it from being killed.
        // Initially, pass -1L for byte counts as they are unknown.
        startForegroundNotification(fileName)

        // --- Launch Download Coroutine ---
        // Launch a new coroutine for the download operation within the service's scope.
        // This allows the download to run asynchronously without blocking the main thread.
        currentDownloadJob = serviceScope.launch {
            try {
                // Perform the actual file download
                downloadFile(url, fileName)

                // Only send success if the download wasn't explicitly cancelled by the user
                if (!isCancelled) {
                    Log.d(TAG, "Download successful for $fileName")
                    // Final update for successful download: 100% and complete message
                    updateNotification("Download Complete!", 100, 100, -1L, -1L, false, NotificationCompat.CATEGORY_SERVICE)
                    sendDownloadResultToFlutter(true, "Download successful", "completed")
                }
            } catch (e: CancellationException) {
                // This block catches cancellations, including those from currentDownloadJob?.cancel()
                Log.d(TAG, "Download job cancelled for $fileName (via CancellationException).")
                // No need to send Flutter event here, as it's handled by the "CANCEL_DOWNLOAD" action
                // or the loop's `isCancelled` check.
            } catch (e: Exception) {
                 Log.e(TAG, "Download failed for $fileName: ${e.message}", e)
    val errorMessage = e.localizedMessage ?: "Unknown download error"
    val errorStatus = when (e) {
        is CancellationException -> "canceled" // Though handled earlier, good to be explicit
        is java.net.SocketTimeoutException -> "network_timeout"
        is java.io.IOException -> "io_error" // General I/O issues (disk space, stream problems)
        is Exception -> "general_error" // Catch-all for other exceptions
        else -> "unknown_error"
    }
    updateNotification("Download Failed!", 0, 0, -1L, -1L, false, NotificationCompat.CATEGORY_ERROR)
    sendDownloadResultToFlutter(false, errorMessage, errorStatus)

                // Clean up the incomplete file if it wasn't a user-initiated cancellation
                if (!isCancelled) {
                    downloadUri?.let { uri ->
                        try {
                            contentResolver.delete(uri, null, null)
                            Log.d(TAG, "Incomplete file deleted due to error: $uri")
                        } catch (deleteEx: Exception) {
                            Log.e(TAG, "Failed to delete error file: ${deleteEx.message}")
                        }
                    }
                }
            } finally {
                // This 'finally' block ensures cleanup happens regardless of success, failure, or cancellation.
                Log.d(TAG, "Download coroutine for $fileName finished. Stopping service components.")

                // Keep the final notification visible for a few seconds so the user can see the result.
                delay(3000)

                // Stop the foreground state and remove the notification.
                // Using `true` here removes the notification as well.
                stopForeground(true) // THIS IS CRUCIAL: Removes the notification and foreground status

                // Stop the service itself. This ensures the service's resources are released.
                stopSelf()
                Log.d(TAG, "Service stopped for $fileName.")
            }
        }

        // START_NOT_STICKY: The system will not try to recreate the service if it's killed.
        // This is suitable for services that perform a one-time operation.
        return START_NOT_STICKY
    }

    /**
     * Called when the service is no longer used and is being destroyed.
     * Cancels all coroutines launched within the service's scope.
     */
    override fun onDestroy() {
        super.onDestroy()
        currentDownloadJob?.cancel() // Ensure the current download job is cancelled
        serviceScope.cancel() // Cancel the entire scope and its children
        Log.d(TAG, "Service destroyed.")
    }

    /**
     * Return null for onBind() because this service is not designed to be bound by clients.
     */
    override fun onBind(intent: Intent?): IBinder? = null

    // --- Notification Management ---

    /**
     * Creates a notification channel for Android 8.0 (Oreo) and above.
     * This is required for displaying notifications on newer Android versions.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Background Downloads"
            val descriptionText = "Notifications for ongoing file downloads."
            // IMPORTANCE_LOW is generally sufficient for ongoing background tasks.
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(channelId, name, importance).apply {
                description = descriptionText
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    /**
     * Helper to format bytes into human-readable string (e.g., 1.5 MB).
     * Used for displaying downloaded/total bytes in the notification.
     */
    private fun formatBytes(bytes: Long): String {
        if (bytes <= 0) return "0 B"
        val units = arrayOf("B", "KB", "MB", "GB", "TB")
        val digitGroups = (Math.log10(bytes.toDouble()) / Math.log10(1024.0)).toInt()
        return "${decimalFormat.format(bytes / Math.pow(1024.0, digitGroups.toDouble()))} ${units[digitGroups]}"
    }

    /**
     * Creates and returns a NotificationCompat.Builder instance.
     * This builder is used to create both the initial and updated notifications.
     *
     * @param title The main title of the notification (e.g., "Downloading: MyVideo.mp4").
     * @param contentText The detailed text below the title (e.g., "50% - 10MB / 20MB").
     * @param progress The current progress (0-100).
     * @param maxProgress The maximum progress value (usually 100).
     * @param indeterminate True if progress is indeterminate (e.g., waiting for total size).
     * @param category Optional: e.g., NotificationCompat.CATEGORY_PROGRESS, CATEGORY_SERVICE, CATEGORY_ERROR.
     */
    private fun createNotificationBuilder(
        title: String,
        contentText: String,
        progress: Int,
        maxProgress: Int,
        indeterminate: Boolean,
        category: String? = null
    ): NotificationCompat.Builder {
        // Intent to launch the app when the notification is tapped.
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent: PendingIntent? = launchIntent?.let {
            // FLAG_IMMUTABLE is required for PendingIntents on API 23+
            // FLAG_UPDATE_CURRENT ensures that if the intent is recreated, it updates the existing one.
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }

        // Intent for the "Cancel" action button in the notification.
        val cancelIntent = Intent(this, DownloadService::class.java).apply {
            action = "CANCEL_DOWNLOAD" // Custom action to identify cancellation requests
        }
        val pendingCancelIntent = PendingIntent.getService(
            this, NOTIFICATION_ID, cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle(title)
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.stat_sys_download) // Standard system download icon
            .setProgress(maxProgress, progress, indeterminate) // Set progress bar
            .setOngoing(true) // Makes the notification non-dismissible by user swipe (for ongoing tasks)
            .setOnlyAlertOnce(true) // Only alert for the first notification, then update silently
            .setContentIntent(pendingIntent) // Tapping the notification opens the app
            .addAction(android.R.drawable.ic_delete, "Cancel", pendingCancelIntent) // Add a Cancel button
            .apply {
                if (category != null) setCategory(category) // Set notification category if provided
            }
    }

    /**
     * Starts the foreground service by displaying an initial indeterminate progress notification.
     * This uses a specific "Preparing..." message.
     *
     * @param fileName The name of the file being prepared for download.
     */
    private fun startForegroundNotification(fileName: String) {
        val notification = createNotificationBuilder(
            "Downloading...",
            "Preparing: $fileName", // Initial message, more descriptive than just "Downloading..."
            0, 100, true // Indeterminate progress initially
        ).build()
        startForeground(NOTIFICATION_ID, notification) // Elevates the service to foreground status
    }

    /**
     * Updates the existing foreground notification with new progress or status.
     * Now includes downloadedBytes and totalBytes to craft a more informative contentText.
     *
     * @param title The main title of the notification.
     * @param progress The current percentage progress (0-100).
     * @param maxProgress The maximum progress value (usually 100).
     * @param downloadedBytes The number of bytes downloaded so far. Use -1L if not applicable (e.g., final states).
     * @param totalBytes The total size of the file in bytes. Use -1L if unknown or not applicable.
     * @param indeterminate True if progress is indeterminate.
     * @param category Optional category for the notification.
     * @param customContentText Optional: If provided, this text will override the default contentText logic.
     */
    private fun updateNotification(
        title: String,
        progress: Int,
        maxProgress: Int,
        downloadedBytes: Long,
        totalBytes: Long,
        indeterminate: Boolean,
        category: String? = null,
        customContentText: String? = null // New parameter for custom text
    ) {
        val contentText: String = customContentText ?: if (indeterminate) {
            "Downloading..." // Still indeterminate (e.g., initial state, or server didn't provide contentLength)
        } else if (progress >= 0 && progress < 100 && totalBytes > 0) {
            // Actively downloading with known total size: "X% - YMB / ZMB"
            "${progress}% - ${formatBytes(downloadedBytes)} / ${formatBytes(totalBytes)}"
        } else if (progress == 100) {
            "Download complete!" // When 100%
        } else {
            // For failed/cancelled or other final states where progress isn't relevant
            title // Fallback to the main title if no specific progress context
        }

        val notification = createNotificationBuilder(
            title,
            contentText,
            progress,
            maxProgress,
            indeterminate,
            category
        ).apply {
            // For final states (complete/failed/cancelled), make the notification dismissible.
            // This allows the user to swipe it away once the task is finished.
            if (!indeterminate && (progress == maxProgress || progress == 0 || isCancelled)) {
                setOngoing(false) // No longer an ongoing task
                setAutoCancel(true) // Can be dismissed on tap
            }
        }.build()

        NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, notification) // Update the notification
    }

    // --- Download Logic ---

    /**
     * Performs the actual file download operation.
     * This function runs within a CoroutineScope (Dispatchers.IO).
     * Includes more granular notification updates for the "preparing" phase.
     *
     * @param urlStr The URL of the file to download.
     * @param fileName The desired base name for the downloaded file (without extension).
     */
    private suspend fun downloadFile(urlStr: String, fileName: String) = withContext(Dispatchers.IO) {
        var connection: HttpURLConnection? = null
        var outputStream: OutputStream? = null
        var inputStream: InputStream? = null

        try {
            // Step 1: Notify that we are connecting to the server
            updateNotification("Connecting...", 0, 100, -1L, -1L, true, customContentText = "Establishing connection...")
            delay(500) // Small delay for UX, so user can see the message change

            val url = URL(urlStr)
            connection = url.openConnection() as HttpURLConnection
            connection.connect()

            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                throw Exception("Server returned HTTP ${connection.responseCode} ${connection.responseMessage}")
            }

            val contentLength = connection.contentLengthLong // Total size of the file
            val mimeType = getMimeType(fileName, connection.contentType) // Determine MIME type

            // Step 2: Notify that we are preparing storage
            updateNotification("Preparing Storage...", 0, 100, -1L, -1L, true, customContentText = "Allocating space for $fileName...")
            delay(500) // Small delay for UX

            // --- MediaStore Insertion for Android Q (API 29) and above ---
            // Create ContentValues to describe the file for MediaStore
            val contentValues = ContentValues().apply {
                put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mimeType)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    // Save to the "FlutterDownloads" subdirectory within the standard Downloads folder.
                    put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + File.separator + "FlutterDownloads")
                    put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1) // Mark as pending while downloading
                } else {
                    // For older Android versions, we are still using MediaStore.Downloads.EXTERNAL_CONTENT_URI.
                    // If WRITE_EXTERNAL_STORAGE is granted and you need to specify a more traditional path,
                    // you would create a File object and use a FileOutputStream here, not MediaStore.
                    // This example continues using MediaStore for pre-Q as it's generally cleaner if possible.
                }
            }

            val resolver = applicationContext.contentResolver
            // Insert a new record into MediaStore and get its URI.
            downloadUri = resolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)

            if (downloadUri == null) {
                throw Exception("Failed to create MediaStore record for $fileName.")
            }

            // Open an output stream to write data to the MediaStore URI.
            outputStream = resolver.openOutputStream(downloadUri!!)
            if (outputStream == null) {
                throw Exception("Failed to open output stream for URI: $downloadUri")
            }

            inputStream = connection.inputStream // Get the input stream from the HTTP connection

            val buffer = ByteArray(4 * 1024) // 4KB buffer for reading data
            var downloadedBytes = 0L
            var bytesRead: Int

            // Calculate update interval to avoid too frequent notification updates.
            // Update roughly every 1% or at least every 1 byte if the file is tiny.
            val updateIntervalBytes = (contentLength / 100).coerceAtLeast(1L)
            var lastNotifiedProgress = -1 // Track last notified percentage to avoid redundant updates

            // --- Download Loop ---
            // Read data from the input stream and write it to the output stream.
            // Loop continues as long as data is being read and download is not cancelled.
            while (inputStream.read(buffer).also { bytesRead = it } != -1 && !isCancelled) {
                outputStream.write(buffer, 0, bytesRead)
                downloadedBytes += bytesRead

                // Update notification and send progress to Flutter
                if (contentLength > 0) { // If total size is known, show percentage
                    val currentProgress = (downloadedBytes * 100 / contentLength).toInt().coerceIn(0, 100)
                    // Update only when progress percentage has changed or it's the very first byte read at 0%
                    if (currentProgress != lastNotifiedProgress || (currentProgress == 0 && downloadedBytes > 0)) {
                        updateNotification("Downloading: $fileName", currentProgress, 100, downloadedBytes, contentLength, false)
                        sendProgressToFlutter(currentProgress, downloadedBytes, contentLength, fileName)
                        lastNotifiedProgress = currentProgress
                    }
                } else { // If total size is unknown (indeterminate progress)
                    // Show bytes downloaded if total is unknown
                    updateNotification("Downloading: $fileName", 0, 0, downloadedBytes, -1L, true, customContentText = "Downloaded: ${formatBytes(downloadedBytes)}")
                    sendProgressToFlutter(-1, downloadedBytes, -1, fileName) // -1 for unknown progress
                }

                // Check for cancellation within the loop
                if (isCancelled) {
                    throw CancellationException("Download cancelled by user.")
                }
            }

            // Ensure all buffered data is written to the file before marking as complete
            outputStream.flush()

            // If the loop finished and it wasn't cancelled, ensure final 100% update if total size was known
            if (!isCancelled && contentLength > 0) {
                 updateNotification("Downloading: $fileName", 100, 100, contentLength, contentLength, false)
            }


            // --- Finalize MediaStore Entry ---
            // If on Android Q+, mark the file as no longer pending and make it visible.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val fileFinalValues = ContentValues().apply {
                    put(android.provider.MediaStore.MediaColumns.IS_PENDING, 0) // File is complete
                }
                resolver.update(downloadUri!!, fileFinalValues, null, null)
            } else {
                // For older APIs, MediaScannerConnection might be needed if files
                // saved via MediaStore.Downloads are not immediately visible.
                // Generally, for files written to public directories, the system handles it.
                // If issues, uncomment:
                // MediaScannerConnection.scanFile(applicationContext, arrayOf(File(downloadUri!!.path!!).absolutePath), null, null)
            }

        } finally {
            // --- Cleanup Resources ---
            // Ensure all streams and connections are closed to prevent resource leaks.
            try {
                outputStream?.close()
                inputStream?.close()
                connection?.disconnect()
            } catch (e: Exception) {
                Log.e(TAG, "Error closing streams/connection: ${e.message}")
            }
        }
    }

    /**
     * Determines the MIME type of a file based on its extension or Content-Type header.
     *
     * @param fileName The name of the file.
     * @param contentTypeHeader The Content-Type header from the HTTP response.
     * @return The determined MIME type as a String.
     */
    private fun getMimeType(fileName: String, contentTypeHeader: String?): String {
        val extension = MimeTypeMap.getFileExtensionFromUrl(fileName)
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: contentTypeHeader?.split("; ")?.get(0) // Fallback to content type from header
            ?: "application/octet-stream" // Default if no specific type can be determined
    }

    // --- Communication with Flutter (via EventChannel) ---

    /**
     * Sends current download progress updates to the Flutter side via the EventChannel.
     * Ensures the operation is dispatched to the main thread where eventSink is accessible.
     */
    private fun sendProgressToFlutter(progress: Int, downloaded: Long, total: Long, fileName: String) {
        MainScope().launch { // Use MainScope to ensure UI-related operations are on the main thread
            FlutterUniversalDownloaderPlugin.eventSink?.success(mapOf(
                "progress" to progress,
                "downloaded" to downloaded,
                "total" to total,
                "fileName" to fileName,
                "status" to "progress" // Indicate this is a progress update
            ))
        }
    }

    /**
     * Sends the final download result (success, failure, cancellation) to the Flutter side.
     * Ensures the operation is dispatched to the main thread.
     */
    private fun sendDownloadResultToFlutter(isSuccess: Boolean, message: String, status: String) {
        MainScope().launch {
            FlutterUniversalDownloaderPlugin.eventSink?.success(mapOf(
                "status" to status, // "completed", "failed", "canceled", "invalid_params"
                "message" to message,
                "fileName" to "download_result" // A generic identifier for the result
            ))
        }
    }
}