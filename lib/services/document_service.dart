import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/utils/import_progress.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class DocumentExtractionException implements Exception {
  final String message;

  const DocumentExtractionException(this.message);

  @override
  String toString() => message;
}

class DocumentExtractResult {
  final String fileName;
  final String text;
  final int originalCharacters;
  final bool truncated;
  final List<String> warnings;

  const DocumentExtractResult({
    required this.fileName,
    required this.text,
    required this.originalCharacters,
    this.truncated = false,
    this.warnings = const [],
  });

  int get characters => text.length;
}

/// Extracts plain text from TXT, Markdown and PDF study material.
///
/// Documents are processed locally and are never uploaded unless the user
/// explicitly runs AI generation on the extracted text.
class DocumentService {
  static const int maxFileBytes = 25 * 1024 * 1024;
  static const int defaultMaxCharacters = 50000;
  static const List<String> supportedExtensions = [
    'pdf',
    'txt',
    'md',
    'markdown',
  ];

  const DocumentService();

  Future<DocumentExtractResult?> pickAndExtract({
    int maxCharacters = defaultMaxCharacters,
    void Function(ImportProgress progress)? onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    final l10n = AppLocalizations.current;
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: l10n.bi(
          'Choose study material',
          'Выберите учебный материал',
        ),
        type: FileType.custom,
        allowedExtensions: supportedExtensions,
      );
      if (files.isEmpty) return null;
      final file = files.first;
      final bytes = await file.readAsBytes();
      return extractBytes(
        fileName: file.name,
        bytes: bytes,
        maxCharacters: maxCharacters,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    } on DocumentExtractionException {
      rethrow;
    } on Object catch (error) {
      throw DocumentExtractionException(
        l10n.bi(
          'Could not open that document: $error',
          'Не удалось открыть документ: $error',
        ),
      );
    }
  }

  DocumentExtractResult extractBytes({
    required String fileName,
    required Uint8List bytes,
    int maxCharacters = defaultMaxCharacters,
    void Function(ImportProgress progress)? onProgress,
    ImportCancellationToken? cancellationToken,
  }) {
    final l10n = AppLocalizations.current;
    cancellationToken?.throwIfCancelled();
    onProgress?.call(
      const ImportProgress(fraction: 0.05, stage: 'Reading document…'),
    );

    if (bytes.isEmpty) {
      throw DocumentExtractionException(
        l10n.bi('The selected file is empty.', 'Выбранный файл пуст.'),
      );
    }
    if (bytes.length > maxFileBytes) {
      throw DocumentExtractionException(
        l10n.bi(
          'That document is too large (limit 25 MB). Try a smaller file or '
              'paste just the relevant section.',
          'Документ слишком большой (лимит 25 МБ). Попробуйте файл меньше или '
              'вставьте только нужный раздел.',
        ),
      );
    }
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';

    String text;
    switch (extension) {
      case 'txt':
      case 'md':
      case 'markdown':
        onProgress?.call(
          const ImportProgress(fraction: 0.40, stage: 'Decoding text file…'),
        );
        text = _decodeText(bytes);
      case 'pdf':
        text = _extractPdf(
          bytes,
          onProgress: onProgress,
          cancellationToken: cancellationToken,
        );
      default:
        throw DocumentExtractionException(
          l10n.bi(
            'Unsupported file type "$extension". Use PDF, TXT or Markdown.',
            'Неподдерживаемый тип файла "$extension". Используйте PDF, TXT или '
                'Markdown.',
          ),
        );
    }

    cancellationToken?.throwIfCancelled();
    onProgress?.call(
      const ImportProgress(fraction: 0.95, stage: 'Formatting text…'),
    );

    text = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{4,}'), '\n\n\n')
        .trim();
    if (text.isEmpty) {
      throw DocumentExtractionException(
        extension == 'pdf'
            ? l10n.bi(
                'No selectable text was found in this PDF. It may be a scanned '
                    'document; OCR is not supported. Try a text-based PDF or '
                    'paste the content instead.',
                'В этом PDF не найден выделяемый текст. Возможно, это скан; OCR '
                    'не поддерживается. Попробуйте текстовый PDF или вставьте '
                    'содержимое вручную.',
              )
            : l10n.bi(
                'No readable text was found in this document.',
                'В этом документе не найден читаемый текст.',
              ),
      );
    }

    final originalLength = text.length;
    final warnings = <String>[];
    var truncated = false;
    if (text.length > maxCharacters) {
      text = text.substring(0, maxCharacters);
      final lastParagraph = text.lastIndexOf('\n\n');
      if (lastParagraph > maxCharacters ~/ 2) {
        text = text.substring(0, lastParagraph);
      }
      truncated = true;
      warnings.add(
        l10n.bi(
          'Only the first ${text.length} characters were kept so the provider '
              'receives a manageable prompt.',
          'Сохранены только первые ${text.length} символов, чтобы запрос к '
              'провайдеру оставался управляемым.',
        ),
      );
    }

    return DocumentExtractResult(
      fileName: fileName,
      text: text,
      originalCharacters: originalLength,
      truncated: truncated,
      warnings: warnings,
    );
  }

  String _decodeText(Uint8List bytes) {
    try {
      var text = utf8.decode(bytes, allowMalformed: true);
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      return text;
    } on Object {
      throw DocumentExtractionException(
        AppLocalizations.current.bi(
          'This text file is not valid UTF-8 and could not be read.',
          'Этот текстовый файл не является корректным UTF-8 и не может быть '
              'прочитан.',
        ),
      );
    }
  }

  String _extractPdf(
    Uint8List bytes, {
    void Function(ImportProgress progress)? onProgress,
    ImportCancellationToken? cancellationToken,
  }) {
    PdfDocument? document;
    try {
      cancellationToken?.throwIfCancelled();
      onProgress?.call(
        const ImportProgress(fraction: 0.15, stage: 'Parsing PDF structure…'),
      );
      document = PdfDocument(inputBytes: bytes);
      final pageCount = document.pages.count;
      final extractor = PdfTextExtractor(document);
      if (pageCount <= 1) {
        cancellationToken?.throwIfCancelled();
        return extractor.extractText();
      }

      final buffer = StringBuffer();
      final eta = EtaEstimator();
      for (var i = 0; i < pageCount; i++) {
        cancellationToken?.throwIfCancelled();
        final fraction = 0.15 + 0.75 * ((i + 1) / pageCount);
        if (onProgress != null) {
          onProgress(
            ImportProgress(
              fraction: fraction,
              stage: 'Extracting PDF pages…',
              detail: 'Page ${i + 1} / $pageCount',
              eta: eta.update(fraction),
            ),
          );
        }
        final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
        buffer.writeln(pageText);
      }
      return buffer.toString();
    } on Object catch (error) {
      if (error is ImportCancelledException) rethrow;
      throw DocumentExtractionException(
        AppLocalizations.current.bi(
          'This PDF could not be read. It may be encrypted, damaged or use an '
              'unsupported format. ($error)',
          'Не удалось прочитать этот PDF. Возможно, он зашифрован, повреждён '
              'или использует неподдерживаемый формат. ($error)',
        ),
      );
    } finally {
      document?.dispose();
    }
  }
}
