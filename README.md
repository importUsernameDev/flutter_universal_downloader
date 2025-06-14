# Flutter Universal Downloader

[![pub package](https://img.shields.io/pub/v/flutter_universal_downloader.svg)](https://pub.dev/packages/flutter_universal_downloader)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## 📝 Overview

A robust Flutter plugin designed for universal file downloading, offering reliable background operations with **Android foreground service support**. This plugin empowers your applications to handle various file types (images, videos, documents, archives) seamlessly, providing users with **real-time progress updates** and the ability to **cancel** ongoing transfers. It abstracts away the complexities of native download managers and Android permission handling across different API levels, making file management in your app straightforward and efficient.

---

## ✨ Features

- **Universal File Support:** Capable of downloading any file type from a given URL.
- **Reliable Background Downloads (Android):** Utilizes Android's Foreground Service to ensure downloads persist and continue uninterrupted even if the user navigates away from your app or the app is closed. This provides a resilient download experience.
- **Real-time Progress Stream:** Offers a continuous stream of `DownloadProgress` objects, allowing your Flutter UI to dynamically update with the current download percentage, downloaded bytes, total file size, and status (progress, completed, failed, cancelled).
- **Initiation & Cancellation:** Provides clear methods to start a new download and to request the cancellation of an active download.
- **Comprehensive Status Reporting:** Detailed `DownloadStatus` enum (e.g., `completed`, `failed`, `cancelled`, `networkError`, `ioError`, `invalidParams`) provides precise feedback on the download's lifecycle.
- **Platform Exception Handling:** Catches and exposes native platform errors (e.g., missing permissions, service errors) for robust error management in your Dart code.

---

## 🚀 Installation

To integrate `flutter_universal_downloader` into your Flutter project, add it to your `pubspec.yaml` file under the `dependencies` section:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_universal_downloader: ^0.0.1 # Use the latest version from pub.dev


  # The packages below are used in the example app for demonstrating permissions and device info.
  # If your app needs similar functionality, add them to your app's pubspec.yaml:
  # permission_handler: ^11.0.0 # Check pub.dev for the latest stable version
  # device_info_plus: ^10.0.0 # Check pub.dev for the latest stable version
```

After updating your `pubspec.yaml`, run `flutter pub get` in your project's root directory to fetch the package.

## Android Specific Setup & Permissions

For robust background downloading, proper configuration of your Android project's AndroidManifest.xml and runtime permission handling in your Dart code are essential.

### 2.1. `AndroidManifest.xml` Configuration

Open your android/app/src/main/AndroidManifest.xml file.

#### A. Add Essential Permissions:

Place these permissions just inside the `<manifest>` tag (usually at the very top of the file):

```xml
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
```

### 2.2. Runtime Permissions (Flutter Side)

Even with `AndroidManifest.xml` entries, Android requires certain permissions to be explicitly requested from the user at runtime. It's best practice to handle these dynamically based on the user's Android version. The `permission_handler` and `device_info_plus` packages (used in the example) are very helpful here.

```dart
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

/// Checks and requests necessary permissions based on the Android SDK version.
/// Returns `true` if permissions are granted or not needed, `false` otherwise.
Future<bool> checkAndRequestPermissions() async {
  // Permissions are primarily an Android concern for this plugin.
  if (!Platform.isAndroid) {
    return true; // No specific permissions needed for other platforms for this plugin.
  }

  int androidSdkVersion = 0;
  try {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    androidSdkVersion = androidInfo.version.sdkInt;
  } catch (e) {
    print('Error fetching Android SDK version: $e');
    // Handle this error in your app (e.g., show a dialog).
    return false;
  }

  // Android 13 (API 33) and above requires POST_NOTIFICATIONS for foreground service notifications.
  if (androidSdkVersion >= 33) {
    var status = await Permission.notification.request();
    return status.isGranted;
  }
  // Android 10 (API 29) to Android 12 (API 32):
  // Downloads to app-specific directories typically don't need explicit storage permission due to MediaStore API.
  else if (androidSdkVersion >= 29) {
    return true;
  }
  // Android 9 (API 28) and below: Requires WRITE_EXTERNAL_STORAGE for saving files.
  else {
    var status = await Permission.storage.request();
    return status.isGranted;
  }
}
```

## 3. Basic Usage Flow

Here's how to integrate and use the flutter_universal_downloader in your Dart code.

### 3.1. Import the Plugin

Start by importing the plugin in your Dart file:

```dart
import 'package:flutter_universal_downloader/flutter_universal_downloader.dart';
import 'dart:async'; // Needed for StreamSubscription
import 'dart:math' as math; // For the _formatBytes helper (if you copy it)
```

### 3.2. Listening to Download Progress & Status Updates

The plugin provides a `progressStream` that emits `DownloadProgress` objects as the download proceeds and when its status changes (completed, failed, cancelled). It's crucial to listen to this stream to update your UI and handle outcomes.

Recommended Setup in a `StatefulWidget`:

```dart
import 'dart:async'; // Required for StreamSubscription
import 'dart:math' as math; // Required for the _formatBytes helper (logBase and pow)

class MyDownloadScreen extends StatefulWidget {
  @override
  _MyDownloadScreenState createState() => _MyDownloadScreenState();
}

class _MyDownloadScreenState extends State<MyDownloadScreen> {
  StreamSubscription<DownloadProgress>? _downloadProgressSubscription;
  String _downloadStatusMessage = 'Ready to download';
  double _currentDownloadProgress = 0.0; // From 0.0 to 1.0

  @override
  void initState() {
    super.initState();
    // Subscribe to the download progress stream
    _downloadProgressSubscription = FlutterUniversalDownloader.progressStream.listen(
      (DownloadProgress progress) {
        setState(() {
          switch (progress.status) {
            case DownloadStatus.progress:
              _currentDownloadProgress = progress.totalBytes > 0
                  ? progress.downloadedBytes / progress.totalBytes
                  : 0.0;
              _downloadStatusMessage = 'Downloading "${progress.fileName}"... ${progress.progress}% '
                                       '(${_formatBytes(progress.downloadedBytes)} / ${_formatBytes(progress.totalBytes)})';
              break;
            case DownloadStatus.completed:
              _currentDownloadProgress = 1.0; // Ensure 100% on completion
              _downloadStatusMessage = '✅ Download of "${progress.fileName}" completed!';
              break;
            case DownloadStatus.failed:
              _currentDownloadProgress = 0.0; // Reset progress on failure
              _downloadStatusMessage = '❌ Download of "${progress.fileName ?? 'file'}" failed: ${progress.message}';
              break;
            case DownloadStatus.cancelled:
              _currentDownloadProgress = 0.0; // Reset progress on cancellation
              _downloadStatusMessage = '🚫 Download of "${progress.fileName ?? 'file'}" cancelled.';
              break;
            case DownloadStatus.invalidParams:
              _downloadStatusMessage = '⚠️ Download failed: Invalid parameters provided.';
              break;
            case DownloadStatus.networkError:
              _downloadStatusMessage = '⚠️ Download failed: Network connection error.';
              break;
            case DownloadStatus.ioError:
              _downloadStatusMessage = '⚠️ Download failed: File I/O error.';
              break;
            case DownloadStatus.generalError:
            case DownloadStatus.unknown:
              _downloadStatusMessage = '⚠️ Download failed: ${progress.message ?? 'Unknown error'}.';
              break;
          }
        });
      },
      onError: (error) {
        // Handle errors emitted by the stream itself (e.g., internal plugin issues).
        setState(() {
          _downloadStatusMessage = 'Critical Stream Error: $error';
          _currentDownloadProgress = 0.0;
        });
      },
      onDone: () {
        print('Download progress stream has closed.');
      }
    );
  }

  @override
  void dispose() {
    // IMPORTANT: Always cancel your stream subscription to prevent memory leaks!
    _downloadProgressSubscription?.cancel();
    super.dispose();
  }

  // --- Example UI Snippet (assuming these state variables exist) ---
  // @override
  // Widget build(BuildContext context) {
  //   return Scaffold(
  //     appBar: AppBar(title: Text('File Downloader')),
  //     body: Center(
  //       child: Column(
  //         mainAxisAlignment: MainAxisAlignment.center,
  //         children: [
  //           LinearProgressIndicator(value: _currentDownloadProgress),
  //           SizedBox(height: 10),
  //           Text(_downloadStatusMessage),
  //           // ... Add buttons for initiateDownload and cancelCurrentDownload
  //         ],
  //       ),
  //     ),
  //   );
  // }

  // --- Helper function (can be a top-level function or method) ---
  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (bytes.toDouble().abs().logBase(1024)).floor().toInt();
    final clampedIndex = (i < units.length ? i : units.length - 1);
    return '${(bytes / (1024.0.pow(clampedIndex))).toStringAsFixed(2)} ${units[clampedIndex]}';
  }
}

// Extensions for logBase and pow (if you use _formatBytes helper)
extension on num {
  double logBase(num base) {
    if (toDouble() <= 0 || base.toDouble() <= 0) {
      return double.negativeInfinity;
    }
    return math.log(toDouble()) / math.log(base.toDouble());
  }

  num pow(num exponent) => math.pow(toDouble(), exponent.toDouble());
}
```

### 3.3. Start a Download

Call `FlutterUniversalDownloader.foregroundDownload()` to begin a download. This function returns `true` if the download initiation request was successfully sent to the native side, and `false` otherwise (e.g., if the service couldn't be started).

```dart
import 'package:flutter/services.dart'; // For PlatformException

/// Initiates a file download for a given URL and desired file name.
/// Performs necessary permission checks beforehand.
Future<void> initiateDownload(String url, String fileName) async {
  // **Critical Step:** Ensure permissions are granted before attempting to download.
  bool hasPermissions = await checkAndRequestPermissions(); // Use the helper function from section 2.2
  if (!hasPermissions) {
    print('Permissions denied. Cannot start download for $fileName.');
    // Inform the user why the download cannot start (e.g., show a Snackbar or AlertDialog).
    return;
  }

  try {
    print('Attempting to initiate download for "$fileName" from "$url"...');
    final bool downloadInitiated = await FlutterUniversalDownloader.foregroundDownload(
      url,
      fileName: fileName, // The name the downloaded file will have on the device.
                          // If omitted, the native side might generate a name from the URL.
    );

    if (downloadInitiated) {
      print('Download request successfully sent to native side for "$fileName"!');
      // The progressStream listener will now start providing updates as the download proceeds.
    } else {
      print('Failed to initiate download for "$fileName". Check native logs for more details.');
      // Inform the user that the download couldn't be started.
    }
  } on PlatformException catch (e) {
    // Catches errors thrown from the native platform (e.g., invalid URL, service error).
    print('Platform Exception during download initiation: ${e.code} - ${e.message}');
    // Show a user-friendly message based on the error.
  } catch (e) {
    // Catches any other unexpected Dart errors.
    print('An unexpected error occurred during download initiation: $e');
  }
}

// Example usage (e.g., attached to a button):
// ElevatedButton(
//   onPressed: () => initiateDownload('[https://example.com/large_document.pdf](https://example.com/large_document.pdf)', 'my_report.pdf'),
//   child: Text('Start Download'),
// ),
```

### 3.4. Cancel a Download

You can request to cancel the currently active download at any time using `cancelDownload()`. This function returns `true` if a cancellation request was successfully sent, and `false` if no download was active or the request failed.

```dart
import 'package:flutter/services.dart'; // For PlatformException

/// Requests the cancellation of the currently active download.
Future<void> cancelCurrentDownload() async {
  try {
    print('Attempting to cancel current download...');
    final bool cancelled = await FlutterUniversalDownloader.cancelDownload();

    if (cancelled) {
      print('Cancellation request sent successfully.');
      // The progressStream listener will eventually report DownloadStatus.cancelled.
    } else {
      print('No active download to cancel or cancellation request failed.');
      // Inform the user (e.g., show a toast "No download active").
    }
  } on PlatformException catch (e) {
    // Handle specific native errors during the cancellation attempt.
    print('Platform Exception during cancellation: ${e.code} - ${e.message}');
  } catch (e) {
    // Catch any other unexpected Dart errors.
    print('An unexpected error occurred during cancellation: $e');
  }
}

// Example usage (e.g., attached to a button, enabled only when a download is active):
// ElevatedButton(
//   onPressed: _isDownloadActive ? cancelCurrentDownload : null, // _isDownloadActive would be a state variable you manage
//   child: Text('Cancel Download'),
// ),
```

## ⚙️ API Reference / Attributes

`FlutterUniversalDownloader` Class
The main class providing the plugin's functionality.

#### Methods:

`static Future<bool> foregroundDownload(String url, {String? fileName})`
Initiates a file download.

- `url`: The direct URL of the file to download (e.g., `https://example.com/file.jpg`).
- `fileName` (optional): The desired name for the downloaded file. If `null` or omitted, the native platform might infer a filename from the URL or - generate a unique one.

Returns: `true` if the download request was successfully sent to the native platform; `false` otherwise (e.g., invalid parameters, service not available).
Note: `true` only indicates initiation, not completion.

`static Future<bool> cancelDownload()`
Requests the cancellation of the currently active download operation.
Returns: true if a cancellation request was successfully sent; false if no download was active or the cancellation command failed.

#### Streams:

`static Stream<DownloadProgress> get progressStream`
A broadcast stream that emits DownloadProgress objects as the download progresses or changes status. Subscribe to this stream to receive real-time updates and final results.

`DownloadProgress` Class
Represents the current state of a download operation.

#### Attributes:

- `status`: (`DownloadStatus`) The current status of the download (e.g., `progress`, `completed`, `failed`).
- `progress`: (`int`) The download progress as a percentage (0-100). Only valid when `status` is `DownloadStatus.progress`.
- `downloadedBytes`: (`int`) The number of bytes downloaded so far.
- `totalBytes`: (`int`) The total size of the file in bytes. Returns `-1` if the total size is unknown.
- `fileName`: (`String?`) The name of the file being downloaded.
- `message`: (`String?`) An optional message providing more details, especially useful for failed or cancelled statuses.

`DownloadStatus` Enum
Defines the possible states of a download operation.

- `progress`: Download is ongoing.
- `completed`: Download finished successfully.
- `failed`: Download failed (check `message` for details).
- `cancelled`: Download was explicitly cancelled.
- `invalidParams`: Download failed due to invalid input parameters.
- `networkError`: Download failed due to a network issue.
- `ioError`: Download failed due to a file input/output error.
- `generalError`: A general, unclassified error occurred during download.
- `unknown`: An unknown status.

## 🔬 Example

A comprehensive and runnable example application demonstrating the full capabilities of `flutter_universal_downloader` is available in the `example/` directory of this repository. This example includes:

Dynamic Android permission handling (using `permission_handler` and `device_info_plus`).
A user interface that updates in real-time with download progress.
Functionality to initiate and cancel downloads.
Display of various download statuses (completion, failure, cancellation).
To run the example:

1.Clone the flutter_universal_downloader repository:

```shell
git clone [https://github.com/importUsernameDev/flutter_universal_downloader.git](https://github.com/importUsernameDev/flutter_universal_downloader.git)
```

2.Navigate into the example/ directory:

```shell
cd flutter_universal_downloader/example
```

3.Fetch the example project's dependencies:

```shell
flutter pub get
```

4.Run the application on a connected Android device or emulator (recommended to experience foreground service functionality):

```shell
flutter run
```

You can also run it on other platforms, but the background download/foreground service features are specific to Android.

## ❓ Troubleshooting

Here are solutions to some common issues you might encounter:

#### Download Does Not Start / Foreground Service Error on Android 13+

Symptom: Downloads fail to start, or you see errors related to `ForegroundServiceStartNotAllowedException` on Android 13 (API 33) and above.
Cause: Android 13+ requires the `POST_NOTIFICATIONS` permission to display notifications from foreground services. Without this, the service cannot run correctly.

Solution:

- Ensure you have `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>` in your `AndroidManifest.xml`.
  Implement runtime permission request for `Permission.notification` in your Dart code using `permission_handler` before calling `foregroundDownload()`. (Refer to "2.2. Runtime Permissions" section).

#### Download Fails with Storage/Permission Denied on Older Android (API <= 28)

Symptom: Downloads fail on older Android versions with messages indicating permission issues or inability to write to storage.
Cause: Android 9 (API 28) and below require `WRITE_EXTERNAL_STORAGE` permission for writing files to external storage.
Solution:
Ensure you have `<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />` in your `AndroidManifest.xml`.
Implement runtime permission request for `Permission.storage` in your Dart code for these older Android versions. (Refer to "2.2. Runtime Permissions" section).

#### Download Fails with "Invalid URL" or "Network Error"

Symptom: `DownloadStatus.failed` with `networkError` or `invalidParams` status, or generic error messages.
Cause:
The provided URL is incorrect, malformed, or points to a non-existent file.
The device has no internet connection, or the connection is unstable.
The server hosting the file might be down or blocking the request.

Solution:
Double-check the `url` passed to `foregroundDownload()`.
Verify the device's internet connection.
Test the URL directly in a web browser to confirm accessibility.

#### Progress Stream Doesn't Update or Stops Unexpectedly

Symptom: The UI doesn't update, or updates stop mid-download, but the download might still be running natively.

Cause:
The `StreamSubscription` might have been cancelled prematurely.
There might be an unhandled error in the stream's `onError` callback.
Native code is not correctly emitting progress events or the native service was unexpectedly terminated.
Solution:
Ensure your `StreamSubscription` is correctly managed (subscribed in `initState`, cancelled in `dispose`).
Add comprehensive `onError` and `onDone` callbacks to your `progressStream.listen()` to log or handle stream lifecycle events.
Check native Android logs (using `adb logcat`) for any errors from the `FlutterUniversalDownloaderService`.

## 🤝 Contributing

Contributions are warmly welcomed and greatly appreciated! If you have suggestions for improvements, find a bug, or wish to add new features, please don't hesitate to:

- Open an Issue: Describe the bug or feature request in detail. Provide clear steps to reproduce any bugs, if applicable.
- Submit a Pull Request: Fork the repository, make your changes, and create a pull request. Please ensure your code adheres to the project's style, includes relevant tests for new functionality, and passes all existing tests.
