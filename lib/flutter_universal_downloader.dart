import 'dart:async'; // Needed for Stream and StreamSubscription types.
import 'package:flutter/services.dart'; // Provides MethodChannel and EventChannel for platform communication.

/// Defines the possible states of a download operation managed by the plugin.
/// Each status provides crucial feedback on the download's lifecycle,
/// from initiation to completion, cancellation, or failure.
enum DownloadStatus {
  progress, // Indicates the download is actively ongoing, with progress updates available.
  completed, // The file has been successfully downloaded and saved to its destination.
  failed, // The download terminated prematurely due to an error, often with an associated message.
  cancelled, // The download was explicitly stopped by a user action or internal cancellation logic.
  invalidParams, // Indicates that the provided download parameters (e.g., URL, file name) were invalid.
  networkError, // A network-related issue occurred during the download (e.g., disconnection, timeout, unreachable server).
  ioError, // An input/output error occurred, typically related to file system operations (e.g., disk full, permission denied to write).
  generalError, // A broad category for other unclassified errors that prevent download completion.
  unknown, // The download status could not be determined or matched any known states.
}

/// An extension on [String] to facilitate parsing native string representations
/// of download statuses into the Dart [DownloadStatus] enum.
/// This ensures consistent type safety and readability when handling status updates
/// received from the platform-specific code.
extension _DownloadStatusParsing on String {
  /// Converts a string received from the native platform into a [DownloadStatus] enum.
  /// This mapping is crucial for bridging the native status codes (which are strings)
  /// to the strongly-typed Dart enum.
  DownloadStatus toDownloadStatus() {
    switch (this) {
      case 'progress':
        return DownloadStatus.progress;
      case 'completed':
        return DownloadStatus.completed;
      case 'failed':
        return DownloadStatus.failed;
      case 'canceled': // Explicitly matches the string 'canceled' often used by native download managers.
        return DownloadStatus.cancelled;
      case 'invalid_params':
        return DownloadStatus.invalidParams;
      case 'network_timeout': // Maps specific native network error strings to a generic networkError.
        return DownloadStatus.networkError;
      case 'io_error': // Maps native I/O error strings to the Dart enum.
        return DownloadStatus.ioError;
      case 'general_error': // Catches general error strings from native.
        return DownloadStatus.generalError;
      default:
        // Fallback for any unhandled or unexpected status strings from the native side.
        return DownloadStatus.unknown;
    }
  }
}

/// A data model class that encapsulates all relevant information about a download's
/// current state, progress, and any associated messages.
/// This object is emitted via the [FlutterUniversalDownloader.progressStream].
class DownloadProgress {
  final DownloadStatus
  status; // The current status of the download (e.g., progress, completed, failed).
  final int
  progress; // The download progress as a percentage (0-100). -1 if indeterminate (e.g., during initiation).
  final int
  downloadedBytes; // The number of bytes transferred so far. -1 if unknown.
  final int
  totalBytes; // The total size of the file in bytes. -1 if unknown (e.g., server doesn't provide Content-Length).
  final String?
  fileName; // The name of the file being downloaded, useful for identifying concurrent downloads.
  final String?
  message; // An optional message, typically used for error descriptions or additional context.

  /// Constructs a [DownloadProgress] instance.
  /// Default values are provided for numerical fields to indicate unknown or not applicable states.
  DownloadProgress({
    required this.status,
    this.progress = -1,
    this.downloadedBytes = -1,
    this.totalBytes = -1,
    this.fileName,
    this.message,
  });

  /// Factory constructor to create a [DownloadProgress] object from a `Map`
  /// received directly from the native platform via a `MethodChannel` or `EventChannel`.
  /// It safely casts map values and uses default values for missing or invalid data.
  factory DownloadProgress.fromMap(Map<dynamic, dynamic> map) {
    final String statusString =
        map['status'] as String? ?? 'unknown'; // Safely extract status string.
    return DownloadProgress(
      status: statusString.toDownloadStatus(), // Convert string status to enum.
      progress:
          (map['progress'] as int?) ??
          -1, // Safely extract and default progress.
      downloadedBytes:
          (map['downloaded'] as int?) ??
          -1, // Safely extract and default downloaded bytes.
      totalBytes:
          (map['total'] as int?) ??
          -1, // Safely extract and default total bytes.
      fileName: map['fileName'] as String?, // Safely extract file name.
      message: map['message'] as String?, // Safely extract message.
    );
  }

  /// Provides a string representation of the [DownloadProgress] for debugging and logging.
  @override
  String toString() {
    return 'DownloadProgress(status: $status, progress: $progress%, '
        'downloaded: $downloadedBytes bytes, total: $totalBytes bytes, '
        'fileName: $fileName, message: $message)';
  }
}

/// A Flutter plugin that provides cross-platform (currently Android focused)
/// functionality for downloading files. It supports foreground downloads with
/// progress updates and cancellation capabilities.
class FlutterUniversalDownloader {
  // MethodChannel is used for invoking methods from Dart to the native platform
  // (e.g., starting or canceling a download).
  static const MethodChannel _methodChannel = MethodChannel(
    'flutter_universal_downloader',
  );
  // EventChannel is used for receiving a stream of events from the native platform
  // to Dart (e.g., continuous download progress updates).
  static const EventChannel _eventChannel = EventChannel(
    'flutter_universal_downloader/progress',
  );

  /// A lazily initialized broadcast stream of [DownloadProgress] updates.
  /// This stream is the primary way to receive real-time download status
  /// and progress information from the native download manager.
  /// Using `receiveBroadcastStream()` allows multiple listeners to subscribe
  /// without issues.
  static Stream<DownloadProgress>? _progressStream;

  /// Provides access to the broadcast stream of download progress updates.
  /// The stream is created only once upon its first access (`_progressStream ??= ...`).
  static Stream<DownloadProgress> get progressStream {
    _progressStream ??= _eventChannel.receiveBroadcastStream().map(
      // Map each raw event (a Map from native) into a strongly-typed DownloadProgress object.
      (event) => DownloadProgress.fromMap(event as Map<dynamic, dynamic>),
    );
    return _progressStream!; // Return the initialized stream.
  }

  /// Initiates a **foreground download** on the native platform.
  ///
  /// On Android, this typically means the download runs as a foreground service,
  /// with a persistent notification indicating its progress. This service
  /// ensures the download continues even if the user navigates away from the app.
  ///
  /// @param url The direct URL of the file to be downloaded.
  /// @param fileName The desired local file name (e.g., "my_document.pdf").
  ///                 If not provided, the native platform might infer a name
  ///                 from the URL or use a generic one.
  ///
  /// @returns A `Future<bool>` which resolves to `true` if the download request
  ///          was successfully handed over to the native platform, indicating
  ///          that the native download process has started. It returns `false`
  ///          if the initiation failed (e.g., due to invalid parameters before
  ///          reaching native code, or immediate native rejection).
  ///          **Crucially, `true` does NOT mean the download has completed
  ///          successfully; for actual download status, listen to [progressStream].**
  ///
  /// @throws [PlatformException] If there's an underlying error during the
  ///         communication with the native platform (e.g., native method not found,
  ///         missing manifest permissions on Android *before* request, etc.).
  ///         This exception should be caught and handled by the calling Dart code.
  static Future<bool> downloadFile(String url, {String? fileName}) async {
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>(
        'foregroundDownload',
        <String, dynamic>{'url': url, 'fileName': fileName},
      );
      return result ??
          false; // Safely return false if the native result is null.
    } on PlatformException catch (e) {
      // It's good practice to log platform exceptions for debugging purposes.
      // TODO: Replace 'print' with a proper logging framework (e.g., `logger` package) for production builds.
      print(
        "FlutterUniversalDownloader: Failed to start foreground download: '${e.code}' - ${e.message}.",
      );
      // Re-throwing the exception allows the calling Dart code to handle specific platform errors.
      rethrow;
    } catch (e) {
      // Catch any unexpected Dart-level errors that might occur before or during the platform call.
      // TODO: Replace 'print' with a proper logging framework.
      print(
        "FlutterUniversalDownloader: An unexpected error occurred while calling foregroundDownload: $e",
      );
      rethrow;
    }
  }

  /// Attempts to cancel the currently active foreground download.
  ///
  /// This method sends a cancellation signal to the native download manager.
  ///
  /// @returns A `Future<bool>` resolving to `true` if the cancellation request
  ///          was successfully sent to the native side. This means the native
  ///          service acknowledged the request; it does not guarantee immediate
  ///          cancellation or that a download was actually active.
  ///          The [progressStream] will eventually emit a [DownloadProgress] event
  ///          with [DownloadStatus.cancelled] if the cancellation is processed
  ///          and acknowledged by the native system.
  ///
  /// @throws [PlatformException] If there's an error during communication with the
  ///         native platform when attempting to send the cancel command.
  static Future<bool> cancelDownload() async {
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>(
        'cancelDownload',
      );
      return result ??
          false; // Safely return false if the native result is null.
    } on PlatformException catch (e) {
      // Log platform exceptions related to cancellation.
      print(
        "FlutterUniversalDownloader: Failed to send cancel request: '${e.code}' - ${e.message}.",
      );
      rethrow;
    } catch (e) {
      // Catch any unexpected Dart-level errors during the cancellation attempt.
      print(
        "FlutterUniversalDownloader: An unexpected error occurred while calling cancelDownload: $e",
      );
      rethrow;
    }
  }
}
