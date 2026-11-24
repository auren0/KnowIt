import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/utils/id_generator.dart';
import 'package:path_provider/path_provider.dart';

enum AudioVerificationStatus {
  valid,
  missingFile,
  unsupportedFormat,
  corruptedFile,
}

class MediaPickResult {
  final String? path;
  final String? error;

  const MediaPickResult._({this.path, this.error});

  const MediaPickResult.success(String path) : this._(path: path);
  const MediaPickResult.cancelled() : this._();
  const MediaPickResult.failure(String message) : this._(error: message);

  bool get isSuccess => path != null;
  bool get isCancelled => path == null && error == null;
}

/// Copies user-selected media into the app's private support directory so
/// cards keep working if the original file is moved, updated, or deleted.
class MediaService {
  /// Tests and headless imports can point media storage at a temporary folder.
  static Directory? documentsDirectoryOverride;
  static Directory? _cachedDirectory;

  static const List<String> supportedAudioExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.ogg',
    '.opus',
    '.aac',
    '.flac',
  ];

  static Future<Directory> _documentsDirectory() async {
    final override = documentsDirectoryOverride;
    if (override != null) return override;
    final cached = _cachedDirectory;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    _cachedDirectory = dir;
    return dir;
  }

  /// Returns the persistent application-managed media directory (`knowit_media`).
  static Future<Directory> getMediaDirectory() async {
    final base = await _documentsDirectory();
    final mediaDirectory = Directory('${base.path}/knowit_media');
    if (!mediaDirectory.existsSync()) {
      await mediaDirectory.create(recursive: true);
    }
    return mediaDirectory;
  }

  /// Resolves a media path or filename to a concrete existing file path.
  /// Handles absolute paths, managed relative paths, and platform sandbox UUID
  /// updates (e.g. across app updates or backup restores).
  static Future<String?> resolvePath(String? path) async {
    if (path == null || path.trim().isEmpty) return null;
    final raw = path.trim();

    // 1. Direct file check
    final direct = File(raw);
    if (direct.existsSync()) return direct.path;

    // 2. Resolve relative to managed media directory
    final mediaDir = await getMediaDirectory();
    final baseName = sanitizeFileName(raw);
    if (baseName.isNotEmpty) {
      final managed = File('${mediaDir.path}/$baseName');
      if (managed.existsSync()) return managed.path;
    }

    // 3. Check raw base name directly (in case sanitization altered it)
    final simpleName = raw.split(RegExp(r'[/\\]')).last.trim();
    if (simpleName.isNotEmpty) {
      final inMedia = File('${mediaDir.path}/$simpleName');
      if (inMedia.existsSync()) return inMedia.path;

      final baseDir = await _documentsDirectory();
      final inBase = File('${baseDir.path}/$simpleName');
      if (inBase.existsSync()) return inBase.path;
    }

    return null;
  }

  /// Resolves the file reference asynchronously.
  static Future<File?> resolveFile(String? path) async {
    final resolved = await resolvePath(path);
    return resolved != null ? File(resolved) : null;
  }

  /// Verifies an audio path and distinguishes failure root causes.
  static Future<AudioVerificationStatus> verifyAudio(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return AudioVerificationStatus.missingFile;
    }
    final resolved = await resolvePath(path);
    if (resolved == null) {
      return AudioVerificationStatus.missingFile;
    }
    final file = File(resolved);
    if (!file.existsSync()) {
      return AudioVerificationStatus.missingFile;
    }
    try {
      if (file.lengthSync() == 0) {
        return AudioVerificationStatus.corruptedFile;
      }
    } on Object {
      return AudioVerificationStatus.corruptedFile;
    }

    final ext = _extension(resolved);
    if (ext.isEmpty || !supportedAudioExtensions.contains(ext)) {
      return AudioVerificationStatus.unsupportedFormat;
    }
    return AudioVerificationStatus.valid;
  }

  static Future<MediaPickResult> pickImage() =>
      _pick(FileType.image, null, 'image');

  static Future<MediaPickResult> pickAudio() => _pick(FileType.custom, const [
    'mp3',
    'm4a',
    'wav',
    'ogg',
    'aac',
    'flac',
    'opus',
  ], 'audio');

  static Future<MediaPickResult> _pick(
    FileType type,
    List<String>? allowedExtensions,
    String kind,
  ) async {
    try {
      final result = await FilePicker.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
      );
      if (result.isEmpty) {
        return const MediaPickResult.cancelled();
      }
      final sourcePath = result.first.path;
      if (sourcePath == null) {
        return MediaPickResult.failure(
          AppLocalizations.current.bi(
            'Selecting $kind files is not supported on this platform. '
                'You can paste a file path instead.',
            'Выбор файлов ($kind) не поддерживается на этой платформе. '
                'Можно вставить путь к файлу.',
          ),
        );
      }

      final mediaDirectory = await getMediaDirectory();
      final safeName = sanitizeFileName(sourcePath);
      final ext = _extension(sourcePath);
      final base = ext.isNotEmpty && safeName.endsWith(ext)
          ? safeName.substring(0, safeName.length - ext.length)
          : (safeName.isEmpty ? newId() : safeName);

      final target = '${mediaDirectory.path}/${base}_${newId().substring(0, 8)}$ext';
      await File(sourcePath).copy(target);
      return MediaPickResult.success(target);
    } on Object catch (error) {
      return MediaPickResult.failure(
        AppLocalizations.current.bi(
          'Could not attach $kind: $error',
          'Не удалось прикрепить файл ($kind): $error',
        ),
      );
    }
  }

  /// Copies a user-selected media file into managed storage.
  static Future<MediaPickResult> importPath(String rawPath) async {
    try {
      final file = File(rawPath.trim());
      if (!file.existsSync()) {
        return MediaPickResult.failure(
          AppLocalizations.current.bi(
            'That file does not exist.',
            'Этот файл не существует.',
          ),
        );
      }
      final mediaDirectory = await getMediaDirectory();
      final safeName = sanitizeFileName(file.path);
      final ext = _extension(file.path);
      final base = ext.isNotEmpty && safeName.endsWith(ext)
          ? safeName.substring(0, safeName.length - ext.length)
          : (safeName.isEmpty ? newId() : safeName);

      final target = '${mediaDirectory.path}/${base}_${newId().substring(0, 8)}$ext';
      await file.copy(target);
      return MediaPickResult.success(target);
    } on Object catch (error) {
      return MediaPickResult.failure(
        AppLocalizations.current.bi(
          'Could not attach file: $error',
          'Не удалось прикрепить файл: $error',
        ),
      );
    }
  }

  /// Sanitizes a media filename while preserving Unicode, spaces, and safe names.
  /// Prevents path traversal and strips query params/protocols.
  static String sanitizeFileName(String fileName) {
    var name = fileName.split(RegExp(r'[/\\]')).last.trim();
    if ((name.startsWith('"') && name.endsWith('"')) ||
        (name.startsWith("'") && name.endsWith("'"))) {
      name = name.substring(1, name.length - 1).trim();
    }
    try {
      if (name.contains('%')) {
        name = Uri.decodeFull(name);
      }
    } on Object {
      // Keep name as-is if decoding fails.
    }
    final queryIndex = name.indexOf('?');
    if (queryIndex > 0) {
      name = name.substring(0, queryIndex);
    }
    name = name.replaceAll(RegExp(r'[\x00/\\:*?"<>|]'), '_').trim();
    while (name.startsWith('.')) {
      name = name.substring(1).trim();
    }
    return name;
  }

  /// Writes bytes from an imported package into managed storage and returns the
  /// stored path, or null when storage is unavailable.
  /// Preserves safe filenames, handles Unicode and collisions, and reuses identical files.
  static Future<String?> storeBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final mediaDirectory = await getMediaDirectory();
      final safeName = sanitizeFileName(fileName);
      final extension = _extension(safeName);
      final baseWithoutExt = extension.isNotEmpty && safeName.endsWith(extension)
          ? safeName.substring(0, safeName.length - extension.length)
          : (safeName.isEmpty ? newId() : safeName);

      String targetPath;
      final directCandidate = File('${mediaDirectory.path}/$safeName');
      if (safeName.isNotEmpty && directCandidate.existsSync()) {
        final existingLength = directCandidate.lengthSync();
        if (existingLength == bytes.length) {
          final existingBytes = await directCandidate.readAsBytes();
          if (_bytesEqual(existingBytes, bytes)) {
            return directCandidate.path;
          }
        }
        // Different content with same filename: append short unique hash to prevent overwrite
        targetPath =
            '${mediaDirectory.path}/${baseWithoutExt}_${newId().substring(0, 8)}$extension';
      } else if (safeName.isNotEmpty) {
        targetPath = directCandidate.path;
      } else {
        targetPath = '${mediaDirectory.path}/${newId()}$extension';
      }

      await File(targetPath).writeAsBytes(bytes, flush: true);
      return targetPath;
    } on Object {
      return null;
    }
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Deletes a managed media file. Paths outside the app directory are ignored.
  static Future<void> deleteManaged(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    try {
      final resolved = await resolvePath(path);
      if (resolved == null) return;
      final directory = await _documentsDirectory();
      final mediaRoot = '${directory.path}/knowit_media/';
      if (!resolved.startsWith(mediaRoot)) return;
      final file = File(resolved);
      if (file.existsSync()) await file.delete();
    } on Object {
      // Media cleanup must never break card editing.
    }
  }

  static bool exists(String? path) {
    if (path == null || path.isEmpty) return false;
    try {
      final file = File(path);
      if (file.existsSync()) return true;

      // Fallback check in cached documents / override directory
      final baseDir = documentsDirectoryOverride ?? _cachedDirectory;
      if (baseDir != null) {
        final simpleName = path.split(RegExp(r'[/\\]')).last.trim();
        if (simpleName.isNotEmpty) {
          final inMedia = File('${baseDir.path}/knowit_media/$simpleName');
          if (inMedia.existsSync()) return true;
          final inBase = File('${baseDir.path}/$simpleName');
          if (inBase.existsSync()) return true;
        }
      }
      return false;
    } on Object {
      return false;
    }
  }

  static String _extension(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    final extension = name.substring(dot).toLowerCase();
    return extension.length <= 10 ? extension : '';
  }

  static String extensionOf(String path) => _extension(path);

  static String displayName(String? path) {
    if (path == null || path.isEmpty) return '';
    return sanitizeFileName(path);
  }
}
