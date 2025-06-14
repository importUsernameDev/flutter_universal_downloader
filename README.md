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
