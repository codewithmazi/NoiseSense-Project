import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists Cognito session data in platform-backed secure storage.
///
/// The Cognito package keeps tokens through a [CognitoStorage] interface and
/// defaults to an in-memory implementation, which would force the user to sign
/// in again on every launch. This implementation is backed by the Android
/// Keystore instead, so tokens survive restarts without sitting in plain
/// SharedPreferences where they would be readable on a rooted device
/// (603: NFR-05).
///
/// Encryption is the plugin's default for Android: AES-256-GCM for the data,
/// with the data key wrapped by an RSA-OAEP key held in the Keystore. In
/// version 11 of the plugin this is no longer configurable, which removed the
/// older and weaker options.
///
/// Biometric unlock is deliberately not enabled. It would add a prompt to
/// every app launch for a tool whose value depends on being unobtrusive, and
/// the threat it defends against, someone holding the unlocked phone, is not
/// the one this app is exposed to.
class SecureCognitoStorage extends CognitoStorage {
  SecureCognitoStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Namespacing isolates this instance's preferences, config
            // markers and Keystore aliases, so [clear] cannot disturb any
            // other secure value the app stores.
            aOptions: AndroidOptions(storageNamespace: 'noisesense_auth'),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> getItem(String key) => _storage.read(key: key);

  @override
  Future<String> setItem(String key, dynamic value) async {
    // The interface is dynamic because the package stores both strings and
    // numbers; secure storage holds strings only.
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

  /// Wipes the stored session. Scoped to this namespace, so other secure
  /// values belonging to the app are untouched.
  @override
  Future<void> clear() => _storage.deleteAll();
}
