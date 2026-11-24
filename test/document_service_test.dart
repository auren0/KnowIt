import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/services/document_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  const service = DocumentService();

  test('extracts UTF-8 text and Markdown', () {
    final txt = service.extractBytes(
      fileName: 'notes.txt',
      bytes: Uint8List.fromList(utf8.encode('Cellular respiration notes')),
    );
    expect(txt.text, 'Cellular respiration notes');
    expect(txt.truncated, isFalse);

    final md = service.extractBytes(
      fileName: 'notes.md',
      bytes: Uint8List.fromList(utf8.encode('# Biology\n- ATP')),
    );
    expect(md.text, contains('Biology'));
  });

  test('rejects empty, unsupported and invalid files clearly', () {
    expect(
      () => service.extractBytes(fileName: 'empty.txt', bytes: Uint8List(0)),
      throwsA(isA<DocumentExtractionException>()),
    );
    expect(
      () => service.extractBytes(
        fileName: 'notes.docx',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(isA<DocumentExtractionException>()),
    );
    expect(
      () => service.extractBytes(
        fileName: 'broken.pdf',
        bytes: Uint8List.fromList(utf8.encode('not a pdf')),
      ),
      throwsA(isA<DocumentExtractionException>()),
    );
  });

  test('truncates long input at a safe limit', () {
    final result = service.extractBytes(
      fileName: 'long.txt',
      bytes: Uint8List.fromList(
        utf8.encode(List<String>.filled(500, 'a').join()),
      ),
      maxCharacters: 100,
    );
    expect(result.text.length, 100);
    expect(result.truncated, isTrue);
    expect(result.warnings, isNotEmpty);
    expect(result.originalCharacters, 500);
  });

  test('extracts selectable text from a generated PDF', () {
    final document = PdfDocument();
    document.pages.add().graphics.drawString(
      'The mitochondrion produces ATP.',
      PdfStandardFont(PdfFontFamily.helvetica, 14),
    );
    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();

    final result = service.extractBytes(fileName: 'biology.pdf', bytes: bytes);

    expect(result.text, contains('mitochondrion'));
    expect(result.text, contains('ATP'));
  });
}
