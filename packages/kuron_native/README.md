# Kuron Native

A powerhouse Flutter plugin providing premium native utilities and widgets.

## Features 🚀

-   **Wrapper Widgets**: High-quality, glassmorphism-styled widgets for PDF, Web, and Downloads.
-   **Ad-Blocking Web**: Built-in native ad-blocker for clean web browsing.
-   **SSO Login**: Robust OAuth/OIDC login flow with token interception.
-   **System Utilities**: Access Device RAM, Battery, and Storage stats.
-   **Backup & Restore**: Easy JSON export/import to local storage.

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  kuron_native:
    path: packages/kuron_native
```

## Android Release (R8/ProGuard) - Important

`kuron_native` uses FFmpegKit on Android. In release builds, R8/ProGuard can break JNI classes if keep rules are missing.

### Why rules are often added in app root

R8 runs on the **final app module** (`android/app`), so many projects place keep rules there.  
To make integration safer, `kuron_native` now also ships consumer rules at:

- `packages/kuron_native/android/proguard-rules.pro`
- `packages/kuron_native/android/build.gradle` via `consumerProguardFiles`

### Host app setup checklist

1. Ensure release build type enables proguard files:

```gradle
buildTypes {
  release {
    minifyEnabled true
    shrinkResources true
    proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
  }
}
```

2. If your app already has custom R8 rules, keep FFmpegKit rules in app root as fallback:

```proguard
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-keep class com.arthenica.ffmpegkit.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
-keepclassmembers class * {
    native <methods>;
}
```

3. Rebuild release and verify on-device:

```bash
cd android
./gradlew app:compileReleaseKotlin
```

If you still see `Bad JNI version returned from JNI_OnLoad`, keep the app-level rules and test without extra obfuscation temporarily to isolate shrinker side effects.

## Widgets Usage

### 1. SSO Login Button
Handle complex login flows effortlessly.

```dart
KuronSSOButton(
  label: 'Login with Kuron',
  loginUrl: 'https://example.com/login',
  redirectUrl: 'https://example.com/callback',
  onSuccess: (data) {
    print('Token: ${data['cookies']}');
  },
)
```

### 2. PDF & Downloads
Auto-handles permissions and file checks.

```dart
// Open PDF
KuronPdfButton(
  filePath: '/storage/.../file.pdf',
  label: 'Open Report',
);

// Download File
KuronDownloadCard(
  url: 'https://example.com/file.pdf',
  fileName: 'report.pdf',
  title: 'Annual Report',
);
```

### 3. Web & Ad-Block
Open web pages with built-in ad protection.

```dart
KuronWebButton(
  url: 'https://example.com',
  label: 'Browse',
  enableAdBlock: true, // Blocks ads natively!
);
```

### 4. System Info
Display device health stats.

```dart
KuronInfoCard(title: 'RAM Usage', type: 'ram');
KuronInfoCard(title: 'Battery', type: 'battery');
```

### 5. Backup & Restore
Export data to JSON file in Downloads.

```dart
// Export
KuronExportButton(
  data: '{"favorite": "manga"}', 
  fileName: 'backup.json'
);

// Import
KuronImportButton(
  onImport: (jsonString) {
    print('Restored: $jsonString');
  },
);
```

## ML model asset (download-at-build)

`bubble_detector.onnx` (~40 MB) is NOT tracked in git. It is fetched once
per machine by Gradle and cached under
`packages/kuron_native/android/src/main/assets/`.

- Pin: `packages/kuron_native/android/model.pin.json`
  (`file`, `version`, `url`, `sha256`). Bump `version` + `sha256` when the
  model changes; builds verify SHA256 on every run.
- Publish a new model version once:
  ```bash
  gh release upload kuron-models-v1 bubble_detector.onnx
  ```
  (tag `kuron-models-v1` must serve the exact `url` in the pin file).
- Verify the pipeline on a clean cache:
  ```bash
  rm packages/kuron_native/android/src/main/assets/bubble_detector.onnx
  cd android && ./gradlew :kuron_native:downloadBubbleModel
  ```
- Local override (no network): `KURON_MODEL_URL=file:///path/to/model.onnx`
  or `-PmodelUrl=file:///path/to/model.onnx`.
- Manual placement fallback: copy the file to `src/main/assets/` — the
  SHA256 check still applies. Offline builds with an empty cache fail loudly
  naming `model.pin.json`.

## Permissions
This package uses `permission_handler` to automatically request:
-   `storage` (for downloads/backup)

Ensure your `AndroidManifest.xml` includes:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
```

## DNS over HTTPS (DoH)

Bypass DNS censorship using native OkHttp with DoH support.

```dart
import 'package:kuron_native/kuron_native.dart';

// Enable Cloudflare DoH
await KuronNative.instance.setDohProvider(DohProvider.cloudflare);

// Make request with DoH
final response = await KuronNative.instance.makeHttpRequest(
  url: 'https://example.com/api',
  method: 'GET',
);
```

**Available Providers:**
- `DohProvider.disabled` - System DNS (default)
- `DohProvider.cloudflare` - Cloudflare (1.1.1.1)
- `DohProvider.google` - Google (8.8.8.8)
- `DohProvider.adguard` - AdGuard (unfiltered)
- `DohProvider.quad9` - Quad9 (9.9.9.9)

See [DOH_IMPLEMENTATION.md](DOH_IMPLEMENTATION.md) for detailed usage.
