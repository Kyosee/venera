import 'dart:typed_data';

/// Raw RGBA bitmap that can cross isolate boundaries.
class RgbaImage {
  RgbaImage(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;
}

/// Integer rectangle (isolate-friendly, no dart:ui types).
class IntRect {
  IntRect(this.left, this.top, this.right, this.bottom);

  int left, top, right, bottom;

  int get width => right - left;
  int get height => bottom - top;
  int get area => width * height;

  bool intersects(IntRect other) {
    return left < other.right &&
        other.left < right &&
        top < other.bottom &&
        other.top < bottom;
  }

  IntRect inflated(int dx, int dy, int maxW, int maxH) {
    return IntRect(
      (left - dx).clamp(0, maxW),
      (top - dy).clamp(0, maxH),
      (right + dx).clamp(0, maxW),
      (bottom + dy).clamp(0, maxH),
    );
  }
}

/// One recognized text block, produced by the worker isolate.
class OcrBlock {
  OcrBlock({
    required this.rect,
    required this.text,
    required this.language,
    required this.backgroundColor,
    required this.textColor,
  });

  final IntRect rect;

  /// Recognized source text.
  final String text;

  /// Detected source language ('ja', 'zh', 'ko', 'en').
  final String language;

  final int backgroundColor;
  final int textColor;
}

/// A translated text block ready for rendering.
class TranslatedRegion {
  TranslatedRegion({
    required this.rect,
    required this.text,
    required this.backgroundColor,
    required this.textColor,
  });

  final IntRect rect;
  final String text;
  final int backgroundColor;
  final int textColor;

  /// Compact JSON for the text-level result cache: lets a page be re-rendered
  /// after the rendered image was evicted, without re-running OCR or paying
  /// for another translation request.
  Map<String, dynamic> toJson() => {
    'l': rect.left,
    't': rect.top,
    'r': rect.right,
    'b': rect.bottom,
    'text': text,
    'bg': backgroundColor,
    'fg': textColor,
  };

  factory TranslatedRegion.fromJson(Map<String, dynamic> json) {
    return TranslatedRegion(
      rect: IntRect(json['l'], json['t'], json['r'], json['b']),
      text: json['text'],
      backgroundColor: json['bg'],
      textColor: json['fg'],
    );
  }
}

class PipelineCanceled implements Exception {
  const PipelineCanceled();
}
