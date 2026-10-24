import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists Cognito session data in platform-backed secure storage.
class SecureCognitoStorage extends CognitoStorage {
  SecureCognitoStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Namespaced so this instance's keys never clash.
            aOptions: AndroidOptions(storageNamespace: 'noisesense_auth'),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> getItem(String key) => _storage.read(key: key);

  @override
  Future<String> setItem(String key, dynamic value) async {
    // Dynamic because the package stores strings and numbers.
    final encoded = value.toString();
    await _storage.write(key: key, value: encoded);
    return encoded;
  }

  @override
  Future<String?> removeItem(String key) async {
    // Returns the previous value, which the package's interface expects.
    final existing = await getItem(key);
    await _storage.delete(key: key);
    return existing;
  }

  /// Wipes the stored session.
  @override
  Future<void> clear() => _storage.deleteAll();
}
