# Building KnowIt

This guide covers setting up your development environment, running tests, and compiling production builds for Android and Windows.

---

## Prerequisites

- **Flutter SDK**: `^3.10.4` (Dart `^3.10.4`)
- **Android**:
  - Android Studio / Android SDK (API 34+)
  - JDK 17 or 21
- **Windows**:
  - Visual Studio 2022 with the "Desktop development with C++" workload
  - Windows desktop support enabled: `flutter config --enable-windows-desktop`
  - [Inno Setup 6](https://jrsoftware.org/isdl.php) (for packaging the Windows installer)

---

## Setup & Verification

Fetch dependencies and verify the codebase:

```bash
flutter pub get
flutter analyze
flutter test
```

---

## Building Android

### Debug APK
```bash
flutter build apk --debug
```
Output: `build/app/outputs/flutter-apk/app-debug.apk`

### Release APK
```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

---

## Building Windows

### Standalone Release Binary
```bash
flutter build windows --release
```
Output directory: `build/windows/x64/runner/Release/`
Contains `knowit.exe`, runtime DLLs, and the `data/` asset bundle.

### Packaging the Windows Installer
KnowIt includes an automated PowerShell build script that compiles the release binary and packages a self-contained Inno Setup installer.

Run the build script:
```powershell
.\build_installer.ps1
```

The script will:
1. Extract the application version from `pubspec.yaml`.
2. Compile the Flutter Windows release (`flutter build windows --release`).
3. Locate the Inno Setup compiler (`ISCC.exe`).
4. Compile `installer.iss` using solid LZMA2 compression.
5. Output the installer to `build\installer\KnowIt-Setup.exe`.

#### Build Options
If the Flutter Windows release is already built, skip re-compilation to assemble only the installer:
```powershell
.\build_installer.ps1 -SkipFlutterBuild
```

Alternatively, compile `installer.iss` directly:
```cmd
iscc /DMyAppVersion=1.0.0 installer.iss
```

---

## Windows Installer Details

- **Output:** `build\installer\KnowIt-Setup.exe`
- **Installation Mode:** Per-user installation without requiring administrator privileges (`PrivilegesRequired=lowest`).
- **Default Directory:** `%LOCALAPPDATA%\Programs\KnowIt`
- **Supported Languages:** English and Russian (automatically detected or user-selectable).
- **Shortcuts:** Start Menu and optional Desktop shortcut.
- **In-Place Updates:** Uses persistent `AppId={{B3A9B267-8F12-4C9D-9F77-4D9A0C3C9102}`. Re-running the installer upgrades binaries cleanly without leaving stale files.
- **Running Instance Protection:** Detects running KnowIt instances (`CloseApplications=yes`) and prompts to close them before replacing binaries.
- **User Data Isolation:** All user flashcards, Hive database boxes, media attachments, and review history are stored in the platform application support folder (`%APPDATA%` or `%LOCALAPPDATA%`). Installing, updating, or uninstalling KnowIt will **never** alter or delete user study data.
- **Code Signing:** Binaries are currently unsigned. On clean Windows machines, Windows SmartScreen may present an informational warning until a trusted certificate is configured.
