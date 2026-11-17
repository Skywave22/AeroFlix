import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show RootIsolateToken;

import 'package:flutter/services.dart' show BackgroundIsolateBinaryMessenger;

import 'js_runtime.dart';

/// Runs one provider in a **background isolate**.
///
/// Scraping a provider means executing several hundred KB of JavaScript
/// (AES/SHA decryption, HTML parsing) plus dozens of HTTP round-trips. Doing
/// that on the UI isolate — which is what a plain [JsRuntime] call does — makes
/// the whole app stutter and, on slower phones, appear frozen for tens of
/// seconds while a provider works. QuickJS is reached over FFI and the bridge
/// only needs the background-isolate messenger, so it runs fine off the main
/// thread.
///
/// Every failure (platform restriction, isolate spawn error, timeout) is
/// surfaced to the caller so it can fall back to running in-process.
class IsolateProviderRunner {
  /// Executes `getStreams()` for [providerCode] and returns the raw JSON array.
  ///
  /// Throws [TimeoutException] when the provider exceeds [timeout] — the
  /// isolate is killed, so a runaway script can never wedge the app.
  static Future<String> run({
    required String providerCode,
    required String providerId,
    required String tmdbApiKey,
    required String tmdbId,
    required String mediaType,
    required String polyfillCode,
    required String callCode,
    required String cryptoJsCode,
    int? season,
    int? episode,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final args = <String, dynamic>{
      'providerCode': providerCode,
      'providerId': providerId,
      'tmdbApiKey': tmdbApiKey,
      'tmdbId': tmdbId,
      'mediaType': mediaType,
      'polyfillCode': polyfillCode,
      'callCode': callCode,
      'cryptoJsCode': cryptoJsCode,
      'season': season,
      'episode': episode,
      'token': RootIsolateToken.instance,
    };

    final receive = ReceivePort();
    final errors = ReceivePort();
    final done = Completer<String>();
    Isolate? isolate;

    void finish(String? value, Object? error) {
      if (done.isCompleted) return;
      if (error != null) {
        done.completeError(error);
      } else {
        done.complete(value ?? '[]');
      }
    }

    receive.listen((message) {
      if (message is Map && message['ok'] == true) {
        finish(message['json'] as String?, null);
      } else if (message is Map) {
        finish(null, Exception('${message['error']}'));
      }
    });
    errors.listen((message) {
      finish(null, Exception('provider isolate error: $message'));
    });

    try {
      isolate = await Isolate.spawn(
        _providerMain,
        {'args': args, 'send': receive.sendPort},
        onError: errors.sendPort,
        debugName: 'tj-provider-$providerId',
      );
    } catch (e) {
      receive.close();
      errors.close();
      throw IsolateUnavailable(e.toString());
    }

    try {
      return await done.future.timeout(timeout);
    } on TimeoutException {
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      isolate.kill(priority: Isolate.immediate);
      receive.close();
      errors.close();
    }
  }
}

/// The platform refused to run a provider off the main isolate.
class IsolateUnavailable implements Exception {
  IsolateUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'IsolateUnavailable($reason)';
}

Future<void> _providerMain(Map<String, dynamic> message) async {
  final args = message['args'] as Map;
  final send = message['send'] as SendPort;

  final token = args['token'] as RootIsolateToken?;
  if (token != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }

  JsRuntime? runtime;
  try {
    runtime = JsRuntime(
      tmdbApiKey: args['tmdbApiKey'] as String,
      scraperId: args['providerId'] as String,
      polyfillCode: args['polyfillCode'] as String,
      callCode: args['callCode'] as String,
      cryptoJsCode: args['cryptoJsCode'] as String,
    );
    final json = await runtime.getStreamsJson(
      providerCode: args['providerCode'] as String,
      providerId: args['providerId'] as String,
      tmdbId: args['tmdbId'] as String,
      mediaType: args['mediaType'] as String,
      season: args['season'] as int?,
      episode: args['episode'] as int?,
    );
    send.send({'ok': true, 'json': json});
  } catch (e) {
    send.send({'ok': false, 'error': e.toString()});
  } finally {
    runtime?.dispose();
  }
}
