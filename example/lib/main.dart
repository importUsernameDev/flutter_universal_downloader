import 'dart:io';
import 'dart:async'; // Required for StreamSubscription
import 'dart:math'
    as math; // Aliased to avoid conflicts with custom 'num' extension methods

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_universal_downloader/flutter_universal_downloader.dart';
import 'package:permission_handler/permission_handler.dart';

/// The entry point of the Flutter application.
void main() {
  runApp(const MyApp());
}

/// The root widget of the application.
/// It sets up the MaterialApp, defining the app's title, theme, and initial screen.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Universal Downloader Plugin Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // The initial screen where download functionality is demonstrated.
      home: const DownloaderPage(),
    );
  }
}

/// A stateful widget to demonstrate file download functionality.
/// It manages UI state related to download progress, status messages, and button interactivity.
class DownloaderPage extends StatefulWidget {
  const DownloaderPage({super.key});

  @override
  State<DownloaderPage> createState() => _DownloaderPageState();
}

/// The state class for [DownloaderPage].
/// Manages all the logic for permission handling, download initiation, cancellation,
/// and updating the UI based on download progress from the plugin.
class _DownloaderPageState extends State<DownloaderPage> {
  // State variables to manage UI feedback and internal logic.
  bool _isOperationInProgress =
      false; // Controls button enablement and progress indicator visibility.
  String _status =
      'Ready to download!'; // Displays current download status messages to the user.
  double _currentProgress =
      0.0; // Represents download progress for LinearProgressIndicator (0.0 to 1.0).
  String?
  _currentDownloadingFileName; // Stores the name of the file currently being downloaded, if any.

  // Stores the Android SDK version, critical for dynamic permission handling logic.
  // Initialized to 0 and fetched on initState for Android devices.
  int _androidSdkVersion = 0;

  // A subscription to the download progress stream.
  // This allows the UI to react to real-time updates from the `flutter_universal_downloader` plugin.
  StreamSubscription<DownloadProgress>? _downloadProgressSubscription;

  /// Initializes the state of the widget.
  /// Fetches Android SDK version and sets up the listener for download progress.
  @override
  void initState() {
    super.initState();
    _fetchAndroidSdkVersion();
    _subscribeToDownloadProgress(); // Start listening to progress updates immediately.
  }

  /// Disposes of the state.
  /// Important: Cancels the stream subscription to prevent memory leaks and unnecessary processing
  /// when the widget is no longer in the widget tree.
  @override
  void dispose() {
    _downloadProgressSubscription?.cancel();
    super.dispose();
  }

  /// Fetches the Android SDK version using `device_info_plus`.
  ///
  /// This is crucial for determining which storage and notification permissions are needed
  /// on Android (e.g., MediaStore for Android 10+, Notification for Android 13+),
  /// as permission requirements change across Android versions.
  Future<void> _fetchAndroidSdkVersion() async {
    if (Platform.isAndroid) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        setState(() {
          _androidSdkVersion = androidInfo.version.sdkInt;
        });
        debugPrint('Fetched Android SDK Version: $_androidSdkVersion');
      } catch (e) {
        debugPrint('Error fetching Android SDK version: $e');
        // In a production app, consider showing a user-facing error message or
        // defaulting to a safe (e.g., most restrictive) permission handling logic.
      }
    } else {
      debugPrint('Not an Android device, skipping SDK version check.');
    }
  }

  /// Subscribes to the `flutter_universal_downloader`'s progress stream.
  ///
  /// This method sets up a listener that updates the UI (`_status`, `_currentProgress`, etc.)
  /// whenever a new download progress event is received from the native side.
  void _subscribeToDownloadProgress() {
    _downloadProgressSubscription = FlutterUniversalDownloader.progressStream.listen(
      (DownloadProgress progress) {
        debugPrint('Received progress update: $progress');
        setState(() {
          switch (progress.status) {
            case DownloadStatus.progress:
              // Update progress bar and status text during an ongoing download.
              _currentProgress =
                  progress.totalBytes > 0
                      ? progress.downloadedBytes / progress.totalBytes
                      : 0.0; // Avoid division by zero.
              _currentDownloadingFileName = progress.fileName;
              _status =
                  'Downloading "${progress.fileName}"... ${progress.progress}% '
                  '(${_formatBytes(progress.downloadedBytes)} / ${_formatBytes(progress.totalBytes)})';
              _isOperationInProgress =
                  true; // Indicate that an operation is active.
              break;
            case DownloadStatus.completed:
              // Handle successful download completion.
              _status =
                  '✅ Download of "${progress.fileName}" completed successfully!';
              _isOperationInProgress = false;
              _currentProgress = 1.0; // Ensure progress bar shows 100%.
              _currentDownloadingFileName = null;
              break;
            case DownloadStatus.failed:
              // Handle download failure, displaying the error message if available.
              _status =
                  '❌ Download of "${progress.fileName ?? 'file'}" failed: ${progress.message}';
              _isOperationInProgress = false;
              _currentProgress = 0.0;
              _currentDownloadingFileName = null;
              break;
            case DownloadStatus.cancelled:
              // Handle explicit download cancellation.
              _status =
                  '🚫 Download of "${progress.fileName ?? 'file'}" cancelled.';
              _isOperationInProgress = false;
              _currentProgress = 0.0;
              _currentDownloadingFileName = null;
              break;
            case DownloadStatus.invalidParams:
              // Handle cases where download parameters were invalid.
              _status = '⚠️ Invalid download parameters provided.';
              _isOperationInProgress = false;
              _currentProgress = 0.0;
              _currentDownloadingFileName = null;
              break;
            // Catch-all for various error states not explicitly handled above.
            case DownloadStatus.networkError:
            case DownloadStatus.ioError:
            case DownloadStatus.generalError:
            case DownloadStatus.unknown:
              _status =
                  '⚠️ Download error: ${progress.message ?? 'Unknown error'}.';
              _isOperationInProgress = false;
              _currentProgress = 0.0;
              _currentDownloadingFileName = null;
              break;
          }
        });
      },
      onError: (error) {
        // This handles errors emitted by the stream itself, not download failures.
        // E.g., if the native side sends malformed data that the Dart side cannot parse.
        debugPrint('Error on download progress stream: $error');
        setState(() {
          _status = 'Stream Error: $error';
          _isOperationInProgress = false;
          _currentProgress = 0.0;
          _currentDownloadingFileName = null;
        });
      },
    );
  }

  /// Helper function to convert a byte count into a human-readable string (e.g., "1.5 MB").
  /// It dynamically selects the appropriate unit (B, KB, MB, GB, TB) based on the size.
  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B'; // Handle zero or negative bytes.
    const units = ['B', 'KB', 'MB', 'GB', 'TB']; // Array of units.

    // Calculate the appropriate unit index using logarithm base 1024.
    // E.g., logBase(1023) is ~0 (for B), logBase(1024) is 1 (for KB), logBase(1MB) is 2 (for MB).
    final i =
        (bytes > 0 ? bytes.toDouble().abs().logBase(1024).floor() : 0).toInt();

    // Clamp the index to prevent out-of-bounds access if bytes are extremely large
    // and exceed the 'TB' unit defined.
    final clampedIndex = math.min(i, units.length - 1);

    // Format the number to two decimal places and append the unit.
    return '${(bytes / (1024.0.pow(clampedIndex))).toStringAsFixed(2)} ${units[clampedIndex]}';
  }

  /// Checks and requests necessary permissions based on the Android SDK version.
  ///
  /// Android permission requirements vary significantly across API levels:
  /// - **Android 13 (API 33+)**: Requires `Permission.notification` for foreground/background services with notifications.
  /// - **Android 10 (API 29) - Android 12 (API 32)**: Uses MediaStore for app-specific directories, typically no explicit storage permissions needed.
  /// - **Android 9 (API 28) and below**: Requires `Permission.storage` (WRITE_EXTERNAL_STORAGE).
  ///
  /// Returns `true` if permissions are granted or not needed for the current Android version,
  /// `false` otherwise (e.g., if the user denies a critical permission).
  Future<bool> _checkAndRequestPermissions() async {
    debugPrint('[Permissions] Checking for Android SDK $_androidSdkVersion.');

    // Permissions are primarily a concern for Android.
    if (!Platform.isAndroid) {
      debugPrint(
        '[Permissions] Not on Android, no explicit permissions needed for download location.',
      );
      return true; // No permissions needed on iOS or other platforms for this specific logic.
    }

    // Ensure SDK version is determined before applying permission logic.
    if (_androidSdkVersion == 0) {
      await _fetchAndroidSdkVersion(); // Attempt to fetch if not already done.
      // If still 0 after fetch, there was an issue, cannot proceed with version-specific logic.
      if (_androidSdkVersion == 0) {
        debugPrint(
          '[Permissions] Failed to determine Android SDK version. Cannot proceed.',
        );
        return false;
      }
    }

    // Handle Android 13 (API 33) and above: Request Notification permission.
    if (_androidSdkVersion >= 33) {
      debugPrint(
        '[Permissions] Android SDK >= 33, requesting Notification permission.',
      );
      final status = await Permission.notification.request();
      debugPrint('[Permissions] Notification permission status: $status');
      return status
          .isGranted; // Download requires notification permission to show progress.
    }

    // Handle Android 10 (API 29) to Android 12 (API 32): MediaStore.
    // For app-specific downloads (which this plugin generally targets by default),
    // explicit WRITE_EXTERNAL_STORAGE is usually not required.
    if (_androidSdkVersion >= 29) {
      debugPrint(
        '[Permissions] Android SDK 29-32, using MediaStore, no explicit storage permission needed.',
      );
      return true;
    }

    // Handle Android 9 (API 28) and below: Request WRITE_EXTERNAL_STORAGE.
    debugPrint(
      '[Permissions] Android SDK <= 28, requesting WRITE_EXTERNAL_STORAGE.',
    );
    final status = await Permission.storage.request();
    debugPrint('[Permissions] Storage permission status: $status');
    return status
        .isGranted; // Permission is mandatory for external storage access.
  }

  /// Initiates a file download for a given URL and file name.
  ///
  /// This method first checks for and requests necessary permissions,
  /// then calls the `flutter_universal_downloader` plugin to start the download.
  /// UI state is updated throughout the process to provide user feedback.
  Future<void> _startDownload(String url, String fileName) async {
    // Set UI state to indicate that an operation has begun.
    setState(() {
      _isOperationInProgress = true;
      _status = 'Checking permissions...';
      _currentProgress = 0.0;
      _currentDownloadingFileName = fileName;
    });
    debugPrint('[Download] Starting download for: $fileName from $url');

    try {
      // Step 1: Check and request necessary permissions.
      final hasPermission = await _checkAndRequestPermissions();
      if (!hasPermission) {
        setState(() {
          _status = '❌ Permissions denied. Cannot download.';
          _isOperationInProgress =
              false; // Operation failed due to permissions.
          _currentDownloadingFileName = null;
        });
        debugPrint('[Download] Permissions denied, download aborted.');
        return; // Stop execution if permissions are not granted.
      }

      // Step 2: Update UI and initiate the download via the plugin.
      setState(() {
        _status = '⬇️ Initiating download for "$fileName"...';
      });
      debugPrint('[Download] Permissions granted, initiating download.');

      // `downloadFile` starts the download, typically with a notification.
      // The actual progress updates are handled by the `_downloadProgressSubscription`.
      final success = await FlutterUniversalDownloader.foregroundDownload(
        url,
        fileName: fileName,
      );

      // This `success` indicates if the download was *initiated* successfully,
      // not if it completed. The stream listener handles completion/failure.
      if (!success) {
        setState(() {
          _status = '❌ Failed to initiate download. Check logs for details.';
          _isOperationInProgress = false; // Initiation failed.
          _currentDownloadingFileName = null;
        });
      }
      // Note: `_isOperationInProgress` is NOT set to false here if `success` is true,
      // because the stream listener will handle the final state (completed/failed/cancelled).
    } on PlatformException catch (e) {
      // Catch platform-specific errors (e.g., from Android/iOS native code).
      setState(() {
        _status = '⚠️ Platform Error: ${e.message} (Code: ${e.code})';
        _isOperationInProgress =
            false; // Operation terminated due to platform error.
        _currentProgress = 0.0;
        _currentDownloadingFileName = null;
      });
      debugPrint(
        '[Download] Platform Exception during download initiation: $e',
      );
    } catch (e) {
      // Catch any other unexpected errors during the download initiation process.
      setState(() {
        _status = '⚠️ Error: ${e.toString()}';
        _isOperationInProgress =
            false; // Operation terminated due to generic error.
        _currentProgress = 0.0;
        _currentDownloadingFileName = null;
      });
      debugPrint('[Download] Caught unexpected error: $e');
    }
  }

  /// Attempts to cancel the currently active download.
  ///
  /// This sends a cancellation request to the native download manager.
  /// The `_downloadProgressSubscription` will eventually receive a `cancelled` status.
  Future<void> _cancelCurrentDownload() async {
    if (!_isOperationInProgress) {
      debugPrint('[Cancel] No active download to cancel.');
      return; // No download running, nothing to do.
    }

    setState(() {
      _status =
          'Requesting cancellation...'; // Inform user of cancellation attempt.
    });
    debugPrint('[Cancel] Attempting to cancel download.');

    try {
      // The plugin's cancelDownload method returns true if the cancellation request was sent.
      final bool result = await FlutterUniversalDownloader.cancelDownload();
      if (result) {
        debugPrint('[Cancel] Cancellation request sent successfully.');
        // The stream listener will update the UI to "cancelled" status.
      } else {
        setState(() {
          _status = 'Failed to send cancellation request.';
        });
        debugPrint(
          '[Cancel] Failed to send cancellation request (native error or no active task).',
        );
      }
    } on PlatformException catch (e) {
      // Handle platform-specific errors during cancellation.
      setState(() {
        _status =
            '⚠️ Platform Error during cancel: ${e.message} (Code: ${e.code})';
      });
      debugPrint('[Cancel] Platform Exception during cancellation: $e');
    } catch (e) {
      // Handle any other unexpected errors during the cancellation process.
      setState(() {
        _status = '⚠️ Error during cancel: ${e.toString()}';
      });
      debugPrint('[Cancel] Caught unexpected error during cancellation: $e');
    }
  }

  /// Builds the UI of the DownloaderPage.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Universal File Downloader Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Informative text about the demo application.
            Text(
              'Demonstrates how to use the Flutter Universal Downloader plugin '
              'to download various file types with appropriate permission handling, '
              'progress updates, and cancellation.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 32),
            // Download buttons for various pre-defined file types.
            _buildDownloadButton(
              context,
              'Download Image',
              'https://picsum.photos/600/400',
              'sample_image.jpg',
            ),
            _buildDownloadButton(
              context,
              'Download Video',
              'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
              'sample_video.mp4',
            ),
            _buildDownloadButton(
              context,
              'Download Audio',
              'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
              'sample_audio.mp3',
            ),
            _buildDownloadButton(
              context,
              'Download PDF Document',
              'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
              'sample_document.pdf',
            ),
            const SizedBox(height: 24),
            // Display progress indicator and status text only when an operation is in progress.
            if (_isOperationInProgress) ...[
              LinearProgressIndicator(value: _currentProgress),
              const SizedBox(height: 8),
            ],
            // Displays the current status of downloads or operations.
            Text(
              _status,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Show the cancellation button only if a download is active.
            if (_isOperationInProgress)
              ElevatedButton.icon(
                onPressed: _cancelCurrentDownload,
                icon: const Icon(Icons.cancel),
                label: const Text('Cancel Current Download'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A helper widget to create a consistent elevated button for initiating downloads.
  /// The button is disabled (`onPressed: null`) if another operation is already in progress.
  Widget _buildDownloadButton(
    BuildContext context,
    String buttonText,
    String url,
    String fileName,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ElevatedButton(
        // The button is disabled if `_isOperationInProgress` is true, preventing multiple simultaneous downloads.
        onPressed:
            _isOperationInProgress ? null : () => _startDownload(url, fileName),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(
            double.infinity,
            50,
          ), // Make button full width.
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(buttonText, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

/// Extension methods on `num` to provide common mathematical operations like
/// natural logarithm (`log()`), logarithm to an arbitrary base (`logBase()`),
/// and power (`pow()`).
///
/// These wrap the functions from `dart:math` to provide a more convenient
/// method-chaining syntax on numbers.
extension on num {
  // `log()` extension method was removed as per `dart analyze` suggestion
  // if not explicitly used, favoring `logBase` for flexibility.

  /// Calculates the logarithm of this number to a specified base.
  ///
  /// Returns `double.negativeInfinity` if `this` number or `base` is not positive,
  /// consistent with mathematical definitions of logarithms.
  double logBase(num base) {
    // Check for non-positive numbers as logarithm is undefined for 0 or negative numbers.
    if (toDouble() <= 0 || base.toDouble() <= 0) {
      return double.negativeInfinity;
    }
    // Uses the change of base formula: log_b(x) = log_e(x) / log_e(b)
    return math.log(toDouble()) / math.log(base.toDouble());
  }

  /// Calculates this number raised to the power of `exponent`.
  ///
  /// This wraps `dart:math.pow` which handles various edge cases (e.g., 0 to the power of 0).
  num pow(num exponent) => math.pow(toDouble(), exponent.toDouble());
}
