import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmnotes_app/core/storage/secure_storage_service.dart';

/// Verifies [SecureStorageService] wires correctly to the
/// flutter_secure_storage plugin channel (`MOBILE-005`). Mocks the plugin's
/// method channel with an in-memory store — no real Keychain/Keystore is
/// available under `flutter test`, so this is the standard way plugin
/// authors themselves smoke-test the channel contract.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{};

  setUp(() {
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      switch (call.method) {
        case 'write':
          store[call.arguments['key'] as String] = call.arguments['value'] as String;
          return null;
        case 'read':
          return store[call.arguments['key'] as String];
        case 'delete':
          store.remove(call.arguments['key'] as String);
          return null;
        default:
          throw MissingPluginException();
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('writeToken persists and readToken retrieves it', () async {
    final service = SecureStorageService(storage: const FlutterSecureStorage());

    expect(await service.readToken(), isNull);

    await service.writeToken('sample.jwt.token');
    expect(await service.readToken(), 'sample.jwt.token');
  });

  test('deleteToken clears the stored value', () async {
    final service = SecureStorageService(storage: const FlutterSecureStorage());

    await service.writeToken('sample.jwt.token');
    await service.deleteToken();

    expect(await service.readToken(), isNull);
  });
}
