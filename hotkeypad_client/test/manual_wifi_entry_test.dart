import 'package:hotkeypad_client/src/deck_page.dart';
import 'package:hotkeypad_client/src/link_target.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('manualWifiHostId', () {
    test('combines the address and port', () {
      expect(
        manualWifiHostId(address: '192.168.1.23', port: 54871),
        'manual:192.168.1.23:54871',
      );
    });

    test('different addresses or ports get different ids', () {
      expect(
        manualWifiHostId(address: '192.168.1.23', port: 54871),
        isNot(manualWifiHostId(address: '192.168.1.24', port: 54871)),
      );
      expect(
        manualWifiHostId(address: '192.168.1.23', port: 54871),
        isNot(manualWifiHostId(address: '192.168.1.23', port: 9999)),
      );
    });
  });

  group('resolveManualPort', () {
    test('parses a valid port', () {
      expect(resolveManualPort('12345'), 12345);
    });

    test('falls back to the default port when blank', () {
      expect(resolveManualPort(''), WifiLink.tcpPort);
      expect(resolveManualPort('   '), WifiLink.tcpPort);
    });

    test('falls back to the default port for non-numeric input', () {
      expect(resolveManualPort('abc'), WifiLink.tcpPort);
    });

    test('falls back to the default port for a non-positive number', () {
      expect(resolveManualPort('0'), WifiLink.tcpPort);
      expect(resolveManualPort('-5'), WifiLink.tcpPort);
    });

    test('trims surrounding whitespace before parsing', () {
      expect(resolveManualPort('  8080  '), 8080);
    });
  });

  group('looksLikeIpv4', () {
    test('accepts a plain IPv4 address', () {
      expect(looksLikeIpv4('192.168.1.23'), isTrue);
      expect(looksLikeIpv4('10.0.2.2'), isTrue);
    });

    test('rejects text with no digit groups at all', () {
      expect(looksLikeIpv4('not-an-ip-address'), isFalse);
      expect(looksLikeIpv4(''), isFalse);
    });

    test('rejects a hostname mixed with letters', () {
      expect(looksLikeIpv4('MacBook.local'), isFalse);
    });

    test('rejects the wrong number of groups', () {
      expect(looksLikeIpv4('192.168.1'), isFalse);
      expect(looksLikeIpv4('192.168.1.2.3'), isFalse);
    });
  });
}
