// Shared text normalization for content titles and other user-facing strings.
//
// `library;` keeps this a pure-Dart utility (no Flutter, no codegen). The
// regex is hoisted because title normalization runs on every list row.

/// Collapses every run of whitespace (including `\n`, `\t` and non-breaking
/// spaces) into a single space, then trims the edges.
///
/// HTML/CSS extraction (`element.text`) and JSON APIs both commonly carry
/// newlines and repeated spaces from the source markup. A title normalized
/// here renders on one line in Detail and in the Reader app bar regardless
/// of which source produced it.
String normalizeWhitespace(String value) {
  if (value.isEmpty) return value;
  return value.replaceAll(_whitespaceRegExp, ' ').trim();
}

final RegExp _whitespaceRegExp = RegExp(r'\s+');
