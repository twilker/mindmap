import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'cloud_sync_models.dart';
import 'cloud_sync_provider.dart';

class _AuthenticatedClient extends http.BaseClient {
  _AuthenticatedClient(this._headers, this._inner);

  final Map<String, String> _headers;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class GoogleDriveSyncProvider implements CloudSyncProvider {
  GoogleDriveSyncProvider({GoogleSignIn? signIn})
      : _signIn = signIn ??
            GoogleSignIn(
              scopes: const [
                drive.DriveApi.driveFileScope,
                drive.DriveApi.driveMetadataScope,
              ],
            );

  final GoogleSignIn _signIn;

  static const _secureStorageKey = 'google_drive_auth';
  static const _folderName = 'mindkite';

  @override
  String get id => 'google_drive';

  @override
  String get name => 'Google Drive';

  @override
  Future<CloudAccountData?> connect(CloudProviderContext context) async {
    try {
      final account = await _signIn.signIn();
      if (account == null) {
        throw CloudSyncException.cancelled();
      }
      final api = await _driveApi(account, context);
      final folderId = await _ensureMindkiteFolder(api);
      final files = await _loadExistingFiles(api, folderId);
      final metadata = {
        'folderId': folderId,
        'files': files,
      };
      await context.secureStorage.write(
        key: _secureStorageKey,
        value: jsonEncode({
          'email': account.email,
          'displayName': account.displayName,
        }),
      );
      return CloudAccountData(
        providerId: id,
        displayName: account.displayName ?? account.email,
        metadata: metadata,
      );
    } on PlatformException catch (err) {
      throw CloudSyncException.authentication(err.message ?? 'Sign-in failed', err);
    } on SocketException catch (err) {
      throw CloudSyncException.offline(err.message, err);
    } catch (err) {
      if (err is CloudSyncException) {
        rethrow;
      }
      throw CloudSyncException.unknown('Unable to connect to Google Drive', err);
    }
  }

  @override
  Future<void> disconnect(
    CloudProviderContext context,
    CloudAccountData? existingAccount,
  ) async {
    try {
      await _signIn.disconnect();
    } catch (_) {
      // Swallow disconnect errors as we still clear local state.
    }
    await context.secureStorage.delete(key: _secureStorageKey);
  }

  @override
  Future<CloudAccountData?> restore(
    CloudProviderContext context,
    CloudAccountData account,
  ) async {
    try {
      final existing = _signIn.currentUser ?? await _signIn.signInSilently();
      if (existing == null) {
        return null;
      }
      final api = await _driveApi(existing, context);
      final folderId = await _ensureMindkiteFolder(api);
      final metadataFiles = await _loadExistingFiles(api, folderId);
      final metadata = {
        'folderId': folderId,
        'files': metadataFiles,
      };
      return account.copyWith(
        displayName: existing.displayName ?? existing.email,
        metadata: metadata,
      );
    } on SocketException catch (err) {
      throw CloudSyncException.offline(err.message, err);
    } catch (err) {
      if (err is CloudSyncException) {
        rethrow;
      }
      return null;
    }
  }

  @override
  Future<CloudAccountData> performOperation(
    CloudProviderContext context,
    CloudAccountData account,
    SyncQueueEntry entry,
  ) async {
    final googleAccount =
        _signIn.currentUser ?? await _signIn.signInSilently();
    if (googleAccount == null) {
      throw CloudSyncException.authentication(
        'Google Drive account is not available. Please sign in again.',
      );
    }
    try {
      final api = await _driveApi(googleAccount, context);
      final metadata = Map<String, dynamic>.from(account.metadata);
      final files = Map<String, String>.from(
        (metadata['files'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ) ??
            <String, String>{},
      );
      final folderId = metadata['folderId'] as String? ??
          await _ensureMindkiteFolder(api);
      String? fileId = files[entry.mapName];
      fileId ??= await _findFileId(api, folderId, entry.mapName);
      switch (entry.operation) {
        case SyncOperationType.create:
          if (fileId != null) {
            // File already exists, skip creation.
            break;
          }
          fileId = await _uploadFile(api, folderId, entry.mapName, entry.document);
          files[entry.mapName] = fileId;
          break;
        case SyncOperationType.update:
          if (fileId == null) {
            fileId = await _uploadFile(api, folderId, entry.mapName, entry.document);
            files[entry.mapName] = fileId;
          } else {
            await _updateFile(api, fileId, entry.document);
          }
          break;
        case SyncOperationType.delete:
          if (fileId != null) {
            await api.files.delete(fileId);
            files.remove(entry.mapName);
          }
          break;
      }
      final updatedMetadata = {
        'folderId': folderId,
        'files': files,
      };
      return account.copyWith(
        metadata: updatedMetadata,
      );
    } on SocketException catch (err) {
      throw CloudSyncException.offline(err.message, err);
    } on drive.DetailedApiRequestError catch (err) {
      if (err.message != null && err.message!.contains('Rate Limit Exceeded')) {
        throw CloudSyncException.unknown('Google Drive rate limit exceeded.', err);
      }
      throw CloudSyncException.unknown(err.message ?? 'Drive request failed', err);
    } catch (err) {
      if (err is CloudSyncException) {
        rethrow;
      }
      throw CloudSyncException.unknown('Failed to sync with Google Drive', err);
    }
  }

  Future<drive.DriveApi> _driveApi(
    GoogleSignInAccount account,
    CloudProviderContext context,
  ) async {
    final headers = await account.authHeaders;
    final baseClient = context.httpClientFactory();
    return drive.DriveApi(_AuthenticatedClient(headers, baseClient));
  }

  Future<String> _ensureMindkiteFolder(drive.DriveApi api) async {
    final query = "mimeType = 'application/vnd.google-apps.folder' and name = '$_folderName' and trashed = false";
    final folders = await api.files.list(
      q: query,
      spaces: 'drive',
      pageSize: 1,
    );
    final existing = folders.files;
    if (existing != null && existing.isNotEmpty) {
      return existing.first.id!;
    }
    final folder = drive.File(
      name: _folderName,
      mimeType: 'application/vnd.google-apps.folder',
    );
    final created = await api.files.create(folder);
    return created.id!;
  }

  Future<Map<String, String>> _loadExistingFiles(
    drive.DriveApi api,
    String folderId,
  ) async {
    final result = <String, String>{};
    String? nextPageToken;
    do {
      final response = await api.files.list(
        q: "'$folderId' in parents and trashed = false",
        spaces: 'drive',
        pageToken: nextPageToken,
      );
      final files = response.files ?? const [];
      for (final file in files) {
        final name = file.name;
        final id = file.id;
        if (name == null || id == null) {
          continue;
        }
        if (!name.endsWith('.json')) {
          continue;
        }
        final decoded = Uri.decodeComponent(
          name.substring(0, name.length - 5),
        );
        result[decoded] = id;
      }
      nextPageToken = response.nextPageToken;
    } while (nextPageToken != null && nextPageToken.isNotEmpty);
    return result;
  }

  String _sanitizedName(String mapName) => '${Uri.encodeComponent(mapName)}.json';

  Future<String?> _findFileId(
    drive.DriveApi api,
    String folderId,
    String mapName,
  ) async {
    final sanitized = _sanitizedName(mapName);
    final response = await api.files.list(
      q: "'$folderId' in parents and name = '$sanitized' and trashed = false",
      spaces: 'drive',
      pageSize: 1,
    );
    final files = response.files ?? const [];
    if (files.isEmpty) {
      return null;
    }
    return files.first.id;
  }

  Future<String> _uploadFile(
    drive.DriveApi api,
    String folderId,
    String mapName,
    String? document,
  ) async {
    final content = document ?? '';
    final bytes = utf8.encode(content);
    final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length);
    final file = drive.File(
      name: _sanitizedName(mapName),
      parents: [folderId],
      mimeType: 'application/json',
    );
    final created = await api.files.create(
      file,
      uploadMedia: media,
      supportsAllDrives: false,
    );
    return created.id!;
  }

  Future<void> _updateFile(
    drive.DriveApi api,
    String fileId,
    String? document,
  ) async {
    final content = document ?? '';
    final bytes = utf8.encode(content);
    final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length);
    await api.files.update(
      drive.File(),
      fileId,
      uploadMedia: media,
      supportsAllDrives: false,
    );
  }
}
