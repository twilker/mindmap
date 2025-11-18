import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'cloud_connector.dart';
import 'cloud_service.dart';
import 'cloud_sync_operation.dart';
import 'cloud_sync_state.dart';
import 'secure_storage.dart';

class GoogleDriveConnector implements CloudConnector {
  GoogleDriveConnector({required SecureStore secureStorage})
    : _secureStorage = secureStorage,
      _googleSignIn = GoogleSignIn(
        scopes: const ['https://www.googleapis.com/auth/drive.file'],
      ),
      _client = http.Client(),
      _state = CloudServiceState(
        service: cloudServices[CloudServiceType.googleDrive]!,
        connected: false,
      );

  static const _accountKey = 'google_drive_account';
  static const _folderKey = 'google_drive_folder';

  final SecureStore _secureStorage;
  final GoogleSignIn _googleSignIn;
  final http.Client _client;
  CloudServiceState _state;
  String? _folderId;

  @override
  CloudServiceType get type => CloudServiceType.googleDrive;

  @override
  CloudServiceState get state => _state;

  @override
  Future<void> initialize() async {
    _folderId = await _secureStorage.read(_folderKey);
    final cachedUser = await _secureStorage.read(_accountKey);
    try {
      await _googleSignIn.signInSilently();
    } catch (_) {
      // Ignore silent sign-in failures and wait for explicit user action.
    }
    final current = _googleSignIn.currentUser;
    if (current != null) {
      _state = _state.copyWith(
        connected: true,
        userLabel: current.displayName ?? current.email,
        error: null,
      );
    } else if (cachedUser != null) {
      _state = _state.copyWith(
        connected: false,
        userLabel: cachedUser,
        error: null,
      );
    }
  }

  @override
  Future<void> connect() async {
    _state = _state.copyWith(connecting: true, error: null);
    try {
      final account =
          await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
      if (account == null) {
        _state = _state.copyWith(connecting: false);
        return;
      }
      _state = _state.copyWith(
        connected: true,
        connecting: false,
        userLabel: account.displayName ?? account.email,
      );
      await _secureStorage.write(key: _accountKey, value: account.email);
    } catch (err) {
      _state = _state.copyWith(connecting: false, error: '$err');
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
    } catch (_) {}
    await _secureStorage.delete(_accountKey);
    await _secureStorage.delete(_folderKey);
    _folderId = null;
    _state = _state.copyWith(connected: false, userLabel: null, error: null);
  }

  @override
  Future<bool> applyOperation(CloudSyncOperation operation) async {
    if (!_state.connected) {
      return false;
    }
    try {
      final token = await _accessToken();
      if (token == null) {
        _state = _state.copyWith(
          connected: false,
          error: 'Google Drive session expired. Please reconnect.',
        );
        return false;
      }
      final folderId = await _ensureFolder(token);
      if (folderId == null) {
        _state = _state.copyWith(
          error: 'Unable to create sync folder in Drive.',
        );
        return false;
      }
      final filename = '${operation.mapName}.json';
      switch (operation.type) {
        case CloudSyncOperationType.create:
          return await _createIfMissing(token, folderId, filename, operation);
        case CloudSyncOperationType.update:
          return await _updateFile(token, folderId, filename, operation);
        case CloudSyncOperationType.delete:
          return await _deleteIfExists(token, folderId, filename);
      }
    } catch (err) {
      _state = _state.copyWith(error: '$err');
      return false;
    }
  }

  Future<String?> _accessToken() async {
    final account = _googleSignIn.currentUser;
    if (account == null) {
      return null;
    }
    final auth = await account.authentication;
    return auth.accessToken;
  }

  Map<String, String> _headers(String token, {String? contentType}) => {
    'Authorization': 'Bearer $token',
    if (contentType != null) 'Content-Type': contentType,
  };

  Future<String?> _ensureFolder(String token) async {
    if (_folderId != null) {
      return _folderId;
    }
    final query =
        "name='mindkite' and mimeType='application/vnd.google-apps.folder' and trashed=false";
    final response = await _client.get(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': query,
        'fields': 'files(id,name)',
      }),
      headers: _headers(token),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final files = (data['files'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      if (files.isNotEmpty) {
        _folderId = files.first['id'] as String?;
      }
    }
    if (_folderId != null) {
      await _secureStorage.write(key: _folderKey, value: _folderId);
      return _folderId;
    }

    final createResponse = await _client.post(
      Uri.https('www.googleapis.com', '/drive/v3/files'),
      headers: _headers(token, contentType: 'application/json'),
      body: jsonEncode({
        'name': 'mindkite',
        'mimeType': 'application/vnd.google-apps.folder',
      }),
    );
    if (createResponse.statusCode >= 200 && createResponse.statusCode < 300) {
      final data = jsonDecode(createResponse.body) as Map<String, dynamic>;
      _folderId = data['id'] as String?;
      if (_folderId != null) {
        await _secureStorage.write(key: _folderKey, value: _folderId);
      }
      return _folderId;
    }
    return null;
  }

  Future<bool> _createIfMissing(
    String token,
    String folderId,
    String filename,
    CloudSyncOperation operation,
  ) async {
    final fileId = await _findFile(token, folderId, filename);
    if (fileId != null) {
      // Already exists; nothing to do.
      return true;
    }
    return _createFile(token, folderId, filename, operation.document);
  }

  Future<bool> _updateFile(
    String token,
    String folderId,
    String filename,
    CloudSyncOperation operation,
  ) async {
    final fileId = await _findFile(token, folderId, filename);
    if (fileId == null) {
      return _createFile(token, folderId, filename, operation.document);
    }
    final response = await _client.patch(
      Uri.https('www.googleapis.com', '/upload/drive/v3/files/$fileId', {
        'uploadType': 'media',
      }),
      headers: _headers(token, contentType: 'application/json'),
      body: operation.document,
    );
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  Future<bool> _deleteIfExists(
    String token,
    String folderId,
    String filename,
  ) async {
    final fileId = await _findFile(token, folderId, filename);
    if (fileId == null) {
      return true;
    }
    final response = await _client.delete(
      Uri.https('www.googleapis.com', '/drive/v3/files/$fileId'),
      headers: _headers(token),
    );
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  Future<bool> _createFile(
    String token,
    String folderId,
    String filename,
    String content,
  ) async {
    final metadataResponse = await _client.post(
      Uri.https('www.googleapis.com', '/drive/v3/files'),
      headers: _headers(token, contentType: 'application/json'),
      body: jsonEncode({
        'name': filename,
        'mimeType': 'application/json',
        'parents': [folderId],
      }),
    );
    if (metadataResponse.statusCode < 200 ||
        metadataResponse.statusCode >= 300) {
      return false;
    }
    final metadata = jsonDecode(metadataResponse.body) as Map<String, dynamic>;
    final fileId = metadata['id'] as String?;
    if (fileId == null) {
      return false;
    }
    final uploadResponse = await _client.patch(
      Uri.https('www.googleapis.com', '/upload/drive/v3/files/$fileId', {
        'uploadType': 'media',
      }),
      headers: _headers(token, contentType: 'application/json'),
      body: content,
    );
    return uploadResponse.statusCode >= 200 && uploadResponse.statusCode < 300;
  }

  Future<String?> _findFile(
    String token,
    String folderId,
    String filename,
  ) async {
    final escapedName = filename.replaceAll("'", "\\'");
    final query =
        "name='$escapedName' and '$folderId' in parents and trashed=false";
    final response = await _client.get(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': query,
        'fields': 'files(id,name)',
      }),
      headers: _headers(token),
    );
    if (response.statusCode != 200) {
      return null;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final files = (data['files'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    if (files.isEmpty) {
      return null;
    }
    return files.first['id'] as String?;
  }

  @override
  void dispose() {
    _client.close();
  }
}
