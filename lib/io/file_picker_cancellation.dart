import 'package:flutter/services.dart';

/// Pickers normally return null on cancellation. Some platform implementations
/// report a cancellation code instead; error messages and paths are not codes.
bool isFilePickerCancellation(Object error) {
  if (error is! PlatformException) return false;
  return const {
    'cancel',
    'canceled',
    'cancelled',
    'user_canceled',
    'user_cancelled',
  }.contains(error.code.toLowerCase());
}
