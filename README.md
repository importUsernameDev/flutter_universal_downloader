# Flutter Universal Downloader

[![pub package](https://img.shields.io/pub/v/flutter_universal_downloader.svg)](https://pub.dev/packages/flutter_universal_downloader)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![pub points](https://img.shields.io/pub/points/flutter_universal_downloader?color=2E8B57&label=pub%20points)](https://pub.dev/packages/flutter_universal_downloader/score)

---

## 📱 Screenshot

<!-- Replace the link below with your actual screenshot or GIF -->
<p align="center">
  <img src="https://raw.githubusercontent.com/importUsernameDev/flutter_universal_downloader/refs/heads/main/main/example/screenshots/IMG_20250614_193823.jpg" width="200"/>
  <img src="https://raw.githubusercontent.com/importUsernameDev/flutter_universal_downloader/main/main/example/screenshots/Screenshot_2025-06-14-19-33-39-24_57be3378ac0cedb7a6848329a3b308c3.jpg" width="200"/>
  <img src="https://raw.githubusercontent.com/importUsernameDev/flutter_universal_downloader/main/main/example/screenshots/Screenshot_2025-06-14-19-33-25-57_57be3378ac0cedb7a6848329a3b308c3.jpg" width="200"/>
</p>

---

## 📖 Table of Contents

- [Overview](#-overview)
- [Supported Platforms](#-supported-platforms)
- [Features](#-features)
- [Installation](#-installation)
  - [Android Specific Setup & Permissions](#android-specific-setup--permissions)
    - [AndroidManifest.xml Configuration](#androidmanifestxml-configuration)
    - [Runtime Permissions](#runtime-permissions)
- [Basic Usage Flow](#basic-usage-flow)
  - [Simple Download Button Example](#simple-download-button-example)
  - [Progress Tracking Example](#progress-tracking-example)
  - [Start a Download](#start-a-download)
  - [Cancel a Download](#cancel-a-download)
- [API Reference](#️-api-reference--attributes)
- [Example](#-example)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

---

## 📝 Overview

A robust Flutter plugin designed for universal file downloading, offering reliable background operations with **Android foreground service support**. This plugin empowers your applications to handle various file types (images, videos, documents, archives) seamlessly, providing users with **real-time progress updates** and the ability to **cancel** ongoing transfers. It abstracts away the complexities of native download managers and Android permission handling across different API levels, making file management in your app straightforward and efficient.

---

## 🖥️ Supported Platforms

- **Android:** Full support, including background and foreground service downloads.
- **iOS:** Downloads are performed on the main thread (no background/foreground download support yet).
- **Other platforms:** Plugin will not throw, but only Android is fully supported at this time.

> **Minimum Requirements:**
>
> - Flutter: 3.10 or above
> - Dart: 3.0 or above
> - Android: minSdkVersion 21+
> - iOS: Not officially supported for background/foreground downloads

---

## ✨ Features

- **Universal File Support:** Download any file type from a URL.
- **Reliable Background Downloads (Android):** Utilizes Android's Foreground Service to keep downloads running even if your app is backgrounded or closed.
- **Real-time Progress Stream:** Provides a stream of `DownloadProgress` objects for UI updates.
- **Initiation & Cancellation:** Simple methods to start or cancel downloads.
- **Comprehensive Status Reporting:** Detailed `DownloadStatus` enum describes download lifecycle.
- **Platform Exception Handling:** Exposes native platform errors for robust error management.

---

## 🚀 Installation

To integrate `flutter_universal_downloader` into your Flutter project, add it to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_universal_downloader: ^0.0.3 # Use the latest version from pub.dev

  # Recommended for runtime permissions and device info (used in the example)
  permission_handler: ^11.0.0 # Check pub.dev for the latest stable version
  device_info_plus: ^10.0.0 # Check pub.dev for the latest stable version
```

After updating your `pubspec.yaml`, run:

```shell
flutter pub get
```

### Android Specific Setup & Permissions

#### AndroidManifest.xml Configuration

Open your `android/app/src/main/AndroidManifest.xml` and add these permissions inside the `<manifest>` tag:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
```

#### Runtime Permissions

Even with `AndroidManifest.xml` entries, you must request some permissions at runtime. This is best done with `permission_handler` and `device_info_plus`:

```dart
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

Future<bool> checkAndRequestPermissions() async {
  if (!Platform.isAndroid) {
    return true;
  }
  int androidSdkVersion = 0;
  try {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    androidSdkVersion = androidInfo.version.sdkInt;
  } catch (e) {
    print('Error fetching Android SDK version: $e');
    return false;
  }
  if (androidSdkVersion >= 33) {
    var status = await Permission.notification.request();
    return status.isGranted;
  } else if (androidSdkVersion >= 29) {
    return true;
  } else {
    var status = await Permission.storage.request();
    return status.isGranted;
  }
}
```

---

## Basic Usage Flow

### Simple Download Button Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_universal_downloader/flutter_universal_downloader.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class DownloadBtn extends StatefulWidget {
  final String buttonText;
  final String? fileName;
  final String url;

  const DownloadBtn({
    Key? key,
    required this.url,
    required this.buttonText,
    this.fileName,
  }) : super(key: key);

  @override
  State<DownloadBtn> createState() => _DownloadBtnState();
}

class _DownloadBtnState extends State<DownloadBtn> {
  bool _isOperationInProgress = false;
  int _androidSdkVersion = 0;

  @override
  void initState() {
    super.initState();
    _getAndroidSdkVersion();
  }

  Future<void> _getAndroidSdkVersion() async {
    if (Platform.isAndroid) {
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (mounted) {
          setState(() => _androidSdkVersion = androidInfo.version.sdkInt);
        }
      } catch (e) {
        debugPrint('Error fetching Android SDK version: $e');
      }
    }
  }

  Future<void> _handleDownload() async {
    if (_isOperationInProgress) return;

    if (mounted) setState(() => _isOperationInProgress = true);
    debugPrint(
      '[Download] Attempting download for: ${widget.fileName ?? "file"} from ${widget.url}',
    );

    try {
      if (Platform.isAndroid) {
        final PermissionStatus status;
        if (_androidSdkVersion >= 33) {
          status = await Permission.notification.request();
        } else if (_androidSdkVersion >= 29) {
          status = PermissionStatus.granted;
        } else {
          status = await Permission.storage.request();
        }

        if (!status.isGranted) {
          _showSnackBar('❌ Permissions denied. Cannot download.');
          return;
        }
      }

      debugPrint(
        '[Download] Permissions granted, initiating download.',
      );
      final success = await FlutterUniversalDownloader.foregroundDownload(
        widget.url,
        fileName: widget.fileName ?? 'downloaded_file',
      );

      _showSnackBar(
        success
            ? '⬇️ Download for "${widget.fileName ?? "file"}" started!'
            : '❌ Failed to start download for "${widget.fileName ?? "file"}".',
      );
    } on PlatformException catch (e) {
      debugPrint(
        '[Download] Platform Exception: ${e.message} (Code: ${e.code})',
      );
      _showSnackBar('⚠️ Download Error: ${e.message}');
    } catch (e) {
      debugPrint('[Download] Caught unexpected error: $e');
      _showSnackBar('⚠️ An unexpected error occurred: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isOperationInProgress = false);
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ElevatedButton(
        onPressed: _isOperationInProgress ? null : _handleDownload,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(50, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _isOperationInProgress
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(widget.buttonText, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
```

Usage in your main widget:

```dart
import 'package:flutter/material.dart';
import 'package:your_app_name/widgets/download_button.dart';

class MyHomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Universal Downloader Demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            DownloadBtn(
              buttonText: 'Download PDF',
              url: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
              fileName: 'sample_document.pdf',
            ),
            DownloadBtn(
              buttonText: 'Download Image',
              url: 'https://upload.wikimedia.org/wikipedia/commons/4/47/PNG_transparency_demonstration_1.png',
              fileName: 'sample_image.png',
            ),
            DownloadBtn(
              buttonText: 'Download Video (Small)',
              url: 'https://file-examples.com/storage/fe94537233649e7f53a1a45/2017/04/file_example_MP4_480_1_5MG.mp4',
              fileName: 'sample_video.mp4',
            ),
          ],
        ),
      ),
    );
  }
}
```

---

### Progress Tracking Example

You can listen to download progress and status with the `progressStream`:

```dart
import 'dart:async';
import 'dart:math' as math;

class MyDownloadScreen extends StatefulWidget {
  @override
  _MyDownloadScreenState createState() => _MyDownloadScreenState();
}

class _MyDownloadScreenState extends State<MyDownloadScreen> {
  StreamSubscription<DownloadProgress>? _downloadProgressSubscription;
  String _downloadStatusMessage = 'Ready to download';
  double _currentDownloadProgress = 0.0; // 0.0 to 1.0
  bool _isDownloadActive = false;

  @override
  void initState() {
    super.initState();
    _downloadProgressSubscription = FlutterUniversalDownloader.progressStream.listen(
      (DownloadProgress progress) {
        setState(() {
          switch (progress.status) {
            case DownloadStatus.progress:
              _isDownloadActive = true;
              _currentDownloadProgress = progress.totalBytes > 0
                  ? progress.downloadedBytes / progress.totalBytes
                  : 0.0;
              _downloadStatusMessage = 'Downloading "${progress.fileName}"... ${progress.progress}% '
                '(${_formatBytes(progress.downloadedBytes)} / ${_formatBytes(progress.totalBytes)})';
              break;
            case DownloadStatus.completed:
              _isDownloadActive = false;
              _currentDownloadProgress = 1.0;
              _downloadStatusMessage = '✅ Download of "${progress.fileName}" completed!';
              break;
            case DownloadStatus.failed:
              _isDownloadActive = false;
              _currentDownloadProgress = 0.0;
              _downloadStatusMessage = '❌ Download of "${progress.fileName ?? 'file'}" failed: ${progress.message}';
              break;
            case DownloadStatus.cancelled:
              _isDownloadActive = false;
              _currentDownloadProgress = 0.0;
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
        setState(() {
          _downloadStatusMessage = 'Critical Stream Error: $error';
          _currentDownloadProgress = 0.0;
          _isDownloadActive = false;
        });
      },
      onDone: () {
        print('Download progress stream has closed.');
      }
    );
  }

  @override
  void dispose() {
    _downloadProgressSubscription?.cancel();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (bytes.toDouble().abs().logBase(1024)).floor().toInt();
    final clampedIndex = (i < units.length ? i : units.length - 1);
    return '${(bytes / (1024.0.pow(clampedIndex))).toStringAsFixed(2)} ${units[clampedIndex]}';
  }
}

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

---

### Start a Download

```dart
import 'package:flutter/services.dart';

Future<void> initiateDownload(String url, String fileName) async {
  bool hasPermissions = await checkAndRequestPermissions();
  if (!hasPermissions) {
    print('Permissions denied. Cannot start download for $fileName.');
    // Show a Snackbar or AlertDialog to inform the user.
    return;
  }

  try {
    print('Attempting to initiate download for "$fileName" from "$url"...');
    final bool downloadInitiated = await FlutterUniversalDownloader.foregroundDownload(
      url,
      fileName: fileName,
    );

    if (downloadInitiated) {
      print('Download request successfully sent to native side for "$fileName"!');
      // The progressStream listener will now provide updates.
    } else {
      print('Failed to initiate download for "$fileName". Check native logs for more details.');
    }
  } on PlatformException catch (e) {
    print('Platform Exception during download initiation: ${e.code} - ${e.message}');
  } catch (e) {
    print('An unexpected error occurred during download initiation: $e');
  }
}

// Example usage (e.g., attached to a button):
// ElevatedButton(
//   onPressed: () => initiateDownload('https://example.com/large_document.pdf', 'my_report.pdf'),
//   child: Text('Start Download'),
// ),
```

---

### Cancel a Download

```dart
import 'package:flutter/services.dart';

Future<void> cancelCurrentDownload() async {
  try {
    print('Attempting to cancel current download...');
    final bool cancelled = await FlutterUniversalDownloader.cancelDownload();

    if (cancelled) {
      print('Cancellation request sent successfully.');
      // The progressStream listener will report DownloadStatus.cancelled.
    } else {
      print('No active download to cancel or cancellation request failed.');
      // Show a toast or Snackbar: "No download active".
    }
  } on PlatformException catch (e) {
    print('Platform Exception during cancellation: ${e.code} - ${e.message}');
  } catch (e) {
    print('An unexpected error occurred during cancellation: $e');
  }
}

// Example usage (e.g., attach to a button, enabled only when a download is active):
// ElevatedButton(
//   onPressed: _isDownloadActive ? cancelCurrentDownload : null,
//   child: Text('Cancel Download'),
// ),
```

---

## ⚙️ API Reference / Attributes

### FlutterUniversalDownloader Class

| Method / Getter                                                          | Description                                                 | Parameters                                                                               | Returns                                                                      |
| ------------------------------------------------------------------------ | ----------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `static Future<bool> foregroundDownload(String url, {String? fileName})` | Initiate a file download via foreground service on Android. | `url` (String, required): file URL<br>`fileName` (String, optional): name for saved file | `true` if the download request was sent to native; `false` otherwise         |
| `static Future<bool> cancelDownload()`                                   | Cancel the currently active download.                       | None                                                                                     | `true` if cancellation request sent; `false` if no active download or failed |
| `static Stream<DownloadProgress> get progressStream`                     | Broadcast stream emitting download progress and status.     | None                                                                                     | Stream of `DownloadProgress` objects                                         |

**DownloadProgress Class**

| Attribute         | Type             | Description                                              |
| ----------------- | ---------------- | -------------------------------------------------------- |
| `status`          | `DownloadStatus` | Current status (e.g., progress, completed, failed)       |
| `progress`        | `int`            | Download progress (0-100, valid if status is `progress`) |
| `downloadedBytes` | `int`            | Bytes downloaded so far                                  |
| `totalBytes`      | `int`            | Total file size in bytes (-1 if unknown)                 |
| `fileName`        | `String?`        | Name of the file being downloaded                        |
| `message`         | `String?`        | Optional message for failed/cancelled statuses           |

**DownloadStatus Enum**

- `progress`
- `completed`
- `failed`
- `cancelled`
- `invalidParams`
- `networkError`
- `ioError`
- `generalError`
- `unknown`

---

## 🔬 Example

A comprehensive, runnable example app is available in the [`example/`](example/) directory, featuring:

- Dynamic Android permission handling
- Real-time UI updates with download progress
- Initiation and cancellation of downloads
- Display of download statuses

To run the example:

```shell
git clone https://github.com/importUsernameDev/flutter_universal_downloader.git
cd flutter_universal_downloader/example
flutter pub get
flutter run
```

(Background download/foreground service features are Android-specific.)

---

## ❓ Troubleshooting

### Download Does Not Start / Foreground Service Error on Android 13+

**Symptom:** Downloads fail to start, or you see `ForegroundServiceStartNotAllowedException` on Android 13+.

**Solution:**

- Ensure `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>` is in your manifest.
- Request `Permission.notification` at runtime before `foregroundDownload()`.

### Download Fails with Storage/Permission Denied on Older Android (API <= 28)

**Symptom:** Fails with permission errors.

**Solution:**

- Ensure `<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />` is present.
- Request `Permission.storage` at runtime for these Android versions.

### Download Fails with "Invalid URL" or "Network Error"

**Symptom:** `DownloadStatus.failed` with `networkError` or `invalidParams`.

**Solution:**

- Double-check the download URL.
- Verify device’s internet.
- Test the URL in a browser.

### Progress Stream Doesn't Update or Stops Unexpectedly

**Symptom:** UI doesn’t update, or stops mid-download.

**Solution:**

- Ensure `StreamSubscription` is managed properly.
- Add `onError`/`onDone` to your stream listener.
- Check native logs (e.g., via `adb logcat`).

---

## 🤝 Contributing

Contributions are warmly welcomed and greatly appreciated!  
If you have suggestions, find bugs, or want to add features:

- **Open an Issue:** Clearly describe the problem or feature.
- **Submit a Pull Request:** Fork, make your changes, and create a PR. Please follow code style, include tests, and ensure all tests pass.
