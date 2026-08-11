import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_storage_service.dart';

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

/// The JWT persisted from a previous `POST /api/auth/login` (`AUTH-002`), if
/// any. `null` means signed out. Phase 8 writes to this via
/// [SecureStorageService.writeToken]/`deleteToken` and invalidates this
/// provider afterward so the rest of the app shell reacts to sign-in/out.
final authTokenProvider = FutureProvider<String?>((ref) async {
  final storage = ref.watch(secureStorageServiceProvider);
  return storage.readToken();
});
