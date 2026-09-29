import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('course geometry is available to the background receiver', () {
    final protocol = File('garmin/argus-data-field/source/ArgusProtocol.mc')
        .readAsStringSync();
    final geometry = File('garmin/argus-data-field/source/ArgusGeometry.mc')
        .readAsStringSync();

    expect(protocol, contains('new ArgusGeometry(data)'));
    expect(
      geometry,
      matches(RegExp(r'\(:background\)\s*class ArgusGeometry\b')),
      reason: 'ArgusProtocol.valid() runs in the phone-message background '
          'service; an unannotated class crashes before the storage ACK.',
    );
  });
}
