/// Removes only the final dot and suffix for display, preserving the filename
/// used for storage, sharing, and QR encoding.
String fileDisplayName(String fileName) {
  final lastDot = fileName.lastIndexOf('.');
  return lastDot < 0 ? fileName : fileName.substring(0, lastDot);
}
