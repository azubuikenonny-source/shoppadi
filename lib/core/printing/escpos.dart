import 'dart:convert';

/// ESC/POS command builder.
///
/// Written by hand rather than pulled from a package: the command set we need
/// is a dozen bytes, and owning it means the output is unit-testable without
/// loading printer capability profiles from package assets.
enum PosAlign { left, center, right }

class EscPos {
  final List<int> _bytes = [];

  static const _esc = 0x1B;
  static const _gs = 0x1D;

  /// Wakes the printer and clears whatever the last job left set.
  EscPos init() {
    _bytes.addAll([_esc, 0x40]);
    return codepage(0); // CP437, the safe default on cheap clones
  }

  /// ESC t n — character code table.
  EscPos codepage(int n) {
    _bytes.addAll([_esc, 0x74, n]);
    return this;
  }

  EscPos align(PosAlign alignment) {
    _bytes.addAll([_esc, 0x61, alignment.index]);
    return this;
  }

  EscPos bold(bool on) {
    _bytes.addAll([_esc, 0x45, on ? 1 : 0]);
    return this;
  }

  /// GS ! n — 0x11 is double width + double height.
  EscPos big(bool on) {
    _bytes.addAll([_gs, 0x21, on ? 0x11 : 0x00]);
    return this;
  }

  EscPos underline(bool on) {
    _bytes.addAll([_esc, 0x2D, on ? 1 : 0]);
    return this;
  }

  /// Writes a line of text. Anything the printer cannot represent is
  /// transliterated first — see [sanitize].
  EscPos line([String text = '']) {
    _bytes.addAll(latin1.encode(sanitize(text)));
    _bytes.add(0x0A);
    return this;
  }

  EscPos feed(int lines) {
    if (lines > 0) _bytes.addAll([_esc, 0x64, lines]);
    return this;
  }

  /// GS V 1 — partial cut. Printers without a cutter ignore it.
  EscPos cut() {
    _bytes.addAll([_gs, 0x56, 0x01]);
    return this;
  }

  /// Opens a cash drawer wired to the printer's kick port.
  EscPos kickDrawer() {
    _bytes.addAll([_esc, 0x70, 0x00, 0x19, 0xFA]);
    return this;
  }

  List<int> build() => List.unmodifiable(_bytes);

  /// Thermal printers speak 8-bit code pages, and **no common code page has
  /// the ₦ sign** (U+20A6) — sending it prints a random glyph or a blank. So
  /// naira becomes "NGN", and anything else outside Latin-1 is stripped rather
  /// than printed as garbage.
  static String sanitize(String input) {
    final swapped = input
        .replaceAll('₦', 'NGN')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('…', '...');

    final buffer = StringBuffer();
    for (final rune in swapped.runes) {
      if (rune == 0x0A || (rune >= 0x20 && rune <= 0xFF)) {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }
}
