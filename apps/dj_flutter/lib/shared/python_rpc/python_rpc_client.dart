import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class PythonRpcClientException implements Exception {
  const PythonRpcClientException(this.code, this.message);

  final String code;
  final String message;
}

class PythonRpcClient {
  PythonRpcClient({
    required this.pythonExecutable,
    required this.workingDirectory,
    required this.scriptModule,
    this.requestTimeout = const Duration(seconds: 10),
    this.logStderrInDebugMode = false,
  });

  final String pythonExecutable;
  final String workingDirectory;
  final String scriptModule;
  final Duration requestTimeout;
  final bool logStderrInDebugMode;

  static final Map<_PythonRpcClientKey, _SharedPythonRpcConnection>
  _connections = <_PythonRpcClientKey, _SharedPythonRpcConnection>{};

  _SharedPythonRpcConnection? _connection;

  _PythonRpcClientKey get _key => _PythonRpcClientKey(
    pythonExecutable: pythonExecutable,
    workingDirectory: workingDirectory,
    scriptModule: scriptModule,
  );

  Future<void> ensureStarted() async {
    final _SharedPythonRpcConnection? existingConnection = _connection;
    if (existingConnection != null) {
      await existingConnection.start();
      return;
    }
    final _PythonRpcClientKey key = _key;
    final _SharedPythonRpcConnection connection =
        _connections[key] ??
        _SharedPythonRpcConnection(
          pythonExecutable: pythonExecutable,
          workingDirectory: workingDirectory,
          scriptModule: scriptModule,
        );
    _connections[key] = connection;
    connection.acquire(logStderrInDebugMode: logStderrInDebugMode);
    _connection = connection;
    try {
      await connection.start();
    } catch (_) {
      _connection = null;
      final bool removed = await connection.release(
        logStderrInDebugMode: logStderrInDebugMode,
      );
      if (removed && identical(_connections[key], connection)) {
        _connections.remove(key);
      }
      rethrow;
    }
  }

  Future<Map<String, Object?>> request({
    required String module,
    required String action,
    required Map<String, Object?> payload,
  }) async {
    await ensureStarted();
    return _connection!.request(
      module: module,
      action: action,
      payload: payload,
      timeout: requestTimeout,
    );
  }

  Future<void> close() async {
    final _SharedPythonRpcConnection? connection = _connection;
    _connection = null;
    if (connection == null) {
      return;
    }
    final bool removed = await connection.release(
      logStderrInDebugMode: logStderrInDebugMode,
    );
    if (removed && identical(_connections[_key], connection)) {
      _connections.remove(_key);
    }
  }
}

class _PythonRpcClientKey {
  const _PythonRpcClientKey({
    required this.pythonExecutable,
    required this.workingDirectory,
    required this.scriptModule,
  });

  final String pythonExecutable;
  final String workingDirectory;
  final String scriptModule;

  static String _normalizePath(String path) {
    String normalized = path.replaceAll('/', '\\');
    while (normalized.endsWith('\\') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  @override
  bool operator ==(Object other) {
    if (other is! _PythonRpcClientKey) return false;
    return _normalizePath(other.pythonExecutable) ==
            _normalizePath(pythonExecutable) &&
        _normalizePath(other.workingDirectory) ==
            _normalizePath(workingDirectory) &&
        other.scriptModule == scriptModule;
  }

  @override
  int get hashCode => Object.hash(
    _normalizePath(pythonExecutable),
    _normalizePath(workingDirectory),
    scriptModule,
  );
}

class _SharedPythonRpcConnection {
  _SharedPythonRpcConnection({
    required this.pythonExecutable,
    required this.workingDirectory,
    required this.scriptModule,
  });

  final String pythonExecutable;
  final String workingDirectory;
  final String scriptModule;

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  final StreamController<Map<String, Object?>> _lineController =
      StreamController<Map<String, Object?>>.broadcast();
  Future<void>? _startFuture;
  Future<void> _writeQueue = Future<void>.value();
  int _requestSeed = 0;
  int _referenceCount = 0;
  int _debugLoggingReferenceCount = 0;
  bool _processDead = false;

  void acquire({required bool logStderrInDebugMode}) {
    _referenceCount += 1;
    if (logStderrInDebugMode) {
      _debugLoggingReferenceCount += 1;
    }
  }

  Future<void> start() {
    if (_processDead) {
      return _startFuture ??= _restart();
    }
    return _startFuture ??= _doStart();
  }

  Future<void> _restart() async {
    await _disposeProcess(closeLineController: false);
    _processDead = false;
    _startFuture = null;
    return start();
  }

  Future<void> _doStart() async {
    if (_process != null) {
      return;
    }
    late final Process process;
    try {
      final Map<String, String> environment = Map<String, String>.from(
        Platform.environment,
      );
      environment['PYTHONIOENCODING'] = 'utf-8';
      environment['PYTHONUTF8'] = '1';
      process = await Process.start(
        pythonExecutable,
        <String>['-m', scriptModule],
        workingDirectory: workingDirectory,
        environment: environment,
      );
    } on ProcessException catch (error) {
      throw const PythonRpcClientException(
        'INTERNAL_ERROR',
        '无法启动 Python 运行时，请检查运行环境是否完整。',
      );
    }
    _process = process;
    process.exitCode.then((int exitCode) {
      _processDead = true;
      _startFuture = null;
      _process = null;
      if (!_lineController.isClosed) {
        _lineController.addError(
          PythonRpcClientException('PROCESS_EXITED', 'Python 运行时已退出，请重新操作。'),
        );
      }
    });
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
          if (line.trim().isEmpty) {
            return;
          }
          try {
            final Object? decoded = jsonDecode(line);
            if (decoded is Map<String, Object?>) {
              _lineController.add(decoded);
            }
          } on FormatException catch (_) {
            if (kDebugMode && _debugLoggingReferenceCount > 0) {
              debugPrint('RPC stdout parse error: $line');
            }
          }
        });
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
          if (kDebugMode &&
              _debugLoggingReferenceCount > 0 &&
              line.trim().isNotEmpty) {
            debugPrint(line);
          }
        });
  }

  Future<void> _disposeProcess({required bool closeLineController}) async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    final Process? process = _process;
    _process = null;
    if (process != null) {
      await process.stdin.close();
      process.kill();
    }
    _startFuture = null;
    _writeQueue = Future<void>.value();
    if (closeLineController && !_lineController.isClosed) {
      await _lineController.close();
    }
  }

  Future<Map<String, Object?>> request({
    required String module,
    required String action,
    required Map<String, Object?> payload,
    required Duration timeout,
  }) async {
    await start();
    final Process? process = _process;
    if (_processDead || process == null) {
      throw const PythonRpcClientException(
        'PROCESS_EXITED',
        'Python 运行时已退出，请重新操作。',
      );
    }
    final String requestId = 'req_${++_requestSeed}';
    final Future<Map<String, Object?>> responseFuture = _lineController.stream
        .firstWhere(
          (Map<String, Object?> data) => data['request_id'] == requestId,
        );
    final String requestBody = jsonEncode(<String, Object?>{
      'request_id': requestId,
      'module': module,
      'action': action,
      'payload': payload,
    });
    final Future<void> writeFuture = _writeQueue = _writeQueue
        .catchError((Object _) {})
        .then((_) async {
          try {
            process.stdin.writeln(requestBody);
            await process.stdin.flush();
          } catch (error) {
            _processDead = true;
            throw const PythonRpcClientException(
              'WRITE_ERROR',
              '写入请求失败，请稍后重试。',
            );
          }
        });
    await writeFuture;
    try {
      final Map<String, Object?> response = await responseFuture.timeout(
        timeout,
      );
      final bool ok = response['ok'] as bool? ?? false;
      if (!ok) {
        final Map<String, Object?> error =
            response['error'] as Map<String, Object?>? ?? <String, Object?>{};
        throw PythonRpcClientException(
          error['code'] as String? ?? 'INTERNAL_ERROR',
          error['message'] as String? ?? '未知错误',
        );
      }
      return response['data'] as Map<String, Object?>? ?? <String, Object?>{};
    } on TimeoutException {
      throw PythonRpcClientException('TIMEOUT', '请求超时，Python 运行时可能无响应。');
    } on PythonRpcClientException {
      rethrow;
    }
  }

  Future<bool> release({required bool logStderrInDebugMode}) async {
    if (_referenceCount > 0) {
      _referenceCount -= 1;
    }
    if (logStderrInDebugMode && _debugLoggingReferenceCount > 0) {
      _debugLoggingReferenceCount -= 1;
    }
    if (_referenceCount > 0) {
      return false;
    }
    await _disposeProcess(closeLineController: true);
    return true;
  }
}
