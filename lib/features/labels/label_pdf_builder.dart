import 'dart:math' as math;
import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One millimetre expressed in PDF points (1 pt = 1/72 inch).
const double _mm = 72 / 25.4;

/// Unicode font bundled with the app. The built-in PDF fonts (Helvetica) have
/// no Cyrillic / Uzbek glyphs, so captions would come out empty without it.
const String captionFontAsset = 'assets/fonts/Roboto-Regular.ttf';

pw.Font? _captionFont;

Future<pw.Font> _loadCaptionFont() async {
  return _captionFont ??= pw.Font.ttf(await rootBundle.load(captionFontAsset));
}

// ---------------------------------------------------------------------------
// Sticker sheet geometry.
//
// These constants describe the self-adhesive A4 sticker paper bought in the
// local market. If a different sheet size is used, only this block has to be
// changed: `labelColumns` x `labelRows` stickers of `labelWidthMm` x
// `labelHeightMm` are placed on a centred A4 page.
// ---------------------------------------------------------------------------

/// Width of a single sticker, in millimetres.
const double labelWidthMm = 67.0;

/// Height of a single sticker, in millimetres.
const double labelHeightMm = 37.0;

/// Number of stickers on one horizontal line.
const int labelColumns = 3;

/// Number of sticker lines on one sheet.
const int labelRows = 7;

/// Smallest margin kept between the sheet border and the outer stickers, in
/// millimetres. Most desktop printers cannot print closer than this.
const double pageMarginMm = 3.0;

/// Cut gap between two neighbouring stickers, in millimetres.
const double labelGapMm = 1.0;

/// Line width of the light cut-guide frame drawn around every sticker.
const double cutLineWidthMm = 0.25;

/// Inner padding between the sticker border and its content.
const double cellPaddingMm = 2.5;

/// Edge length of the square QR code.
const double qrSizeMm = 27.0;

/// Font size of the human readable caption printed next to the QR code.
const double captionFontSize = 8.5;

/// Extra vertical space between caption lines, in points.
const double captionLineSpacing = 1.0;

/// Maximum number of caption lines before the text is clipped.
const int captionMaxLines = 3;

/// Number of stickers that fit on a single A4 sheet.
int get labelsPerPage => labelColumns * labelRows;

final Barcode _qrCode = Barcode.qrCode(
  errorCorrectLevel: BarcodeQRCorrectionLevel.medium,
);

/// A single sticker: a QR encoded [code] plus a readable [caption].
class LabelItem {
  const LabelItem({required this.code, required this.caption});

  /// Text encoded into the QR code, e.g. `A-03-02-01` or `CNT-00123`.
  final String code;

  /// Human readable text printed under/next to the QR code,
  /// e.g. `A-03-02-01` or `CNT-00123 / Oq shakar`.
  final String caption;
}

/// Builds an A4 sticker sheet PDF from [items].
///
/// Sticker content flows left to right, top to bottom, and automatically
/// continues on the next page once [labelsPerPage] stickers have been placed.
Future<Uint8List> buildLabelSheet(List<LabelItem> items) async {
  final captionFont = await _loadCaptionFont();
  final document = pw.Document();
  final perPage = labelsPerPage;
  final pageCount = math.max(1, (items.length / perPage).ceil());

  for (var page = 0; page < pageCount; page++) {
    final start = page * perPage;
    final slice = start >= items.length
        ? const <LabelItem>[]
        : items.sublist(start, math.min(start + perPage, items.length));
    document.addPage(_buildPage(slice, captionFont));
  }

  return document.save();
}

pw.Page _buildPage(List<LabelItem> items, pw.Font captionFont) {
  final pageWidth = PdfPageFormat.a4.width;
  final pageHeight = PdfPageFormat.a4.height;

  final cellWidth = labelWidthMm * _mm;
  final cellHeight = labelHeightMm * _mm;
  final gap = labelGapMm * _mm;
  final margin = pageMarginMm * _mm;

  final gridWidth = labelColumns * cellWidth + (labelColumns - 1) * gap;
  final gridHeight = labelRows * cellHeight + (labelRows - 1) * gap;
  final originX = math.max(margin, (pageWidth - gridWidth) / 2);
  final originY = math.max(margin, (pageHeight - gridHeight) / 2);

  // Absolute placement: `pw.Page` bottom-anchors its child and applies a
  // default margin, so every sticker is positioned explicitly instead.
  return pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.zero,
    build: (context) => pw.Stack(
      children: [
        for (var index = 0; index < items.length; index++)
          pw.Positioned(
            left: originX + (index % labelColumns) * (cellWidth + gap),
            top: originY + (index ~/ labelColumns) * (cellHeight + gap),
            child: pw.SizedBox(
              width: cellWidth,
              height: cellHeight,
              child: _buildSticker(items[index], captionFont),
            ),
          ),
      ],
    ),
  );
}

pw.Widget _buildSticker(LabelItem? item, pw.Font captionFont) {
  final padding = pw.EdgeInsets.all(cellPaddingMm * _mm);

  return pw.Container(
    padding: padding,
    decoration: pw.BoxDecoration(
      border: pw.Border.all(
        color: PdfColors.grey400,
        width: cutLineWidthMm * _mm,
      ),
    ),
    child: item == null
        ? pw.SizedBox()
        : pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(
                width: qrSizeMm * _mm,
                height: qrSizeMm * _mm,
                child: pw.BarcodeWidget(
                  barcode: _qrCode,
                  data: item.code,
                  width: qrSizeMm * _mm,
                  height: qrSizeMm * _mm,
                  color: PdfColors.black,
                  backgroundColor: PdfColors.white,
                  drawText: false,
                ),
              ),
              pw.SizedBox(width: 2 * _mm),
              pw.Expanded(
                child: pw.Text(
                  item.caption,
                  textAlign: pw.TextAlign.center,
                  maxLines: captionMaxLines,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    font: captionFont,
                    fontSize: captionFontSize,
                    lineSpacing: captionLineSpacing,
                    color: PdfColors.black,
                  ),
                ),
              ),
            ],
          ),
  );
}
