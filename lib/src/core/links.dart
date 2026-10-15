final _urlPattern = RegExp(r'''https?://[^\s<>"'`]+''', caseSensitive: false);

/// Pulls the first http(s) link out of text shared from another app, e.g.
/// "Check this out! https://vm.tiktok.com/ZMabc/ #fyp" → "https://vm.tiktok.com/ZMabc/".
String? extractUrl(String? text) {
  if (text == null) return null;
  final match = _urlPattern.firstMatch(text);
  if (match == null) return null;
  var url = match.group(0)!;
  // Trailing punctuation from the surrounding sentence is not part of the link.
  while (url.isNotEmpty && '.,;:!?)]}…'.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) return null;
  return url;
}
