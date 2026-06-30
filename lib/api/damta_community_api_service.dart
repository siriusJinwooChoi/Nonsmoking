import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import '../auth/bff_auth_service.dart';

enum DamtaPostFailure {
  notConfigured,
  notLoggedIn,
  rateLimited,
  emptyAfterFilter,
  serverError,
  serviceUnavailable,
}

class DamtaCommunityMessage {
  final String id;
  final String text;
  final Color color;
  final String authorName;
  /// 서버 수신 시각(ms).
  final int tsMs;

  const DamtaCommunityMessage({
    required this.id,
    required this.text,
    required this.color,
    required this.authorName,
    required this.tsMs,
  });
}

class DamtaCommunityApiService {
  const DamtaCommunityApiService();

  Uri _uri(String path) {
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    return Uri.parse('$base$path');
  }

  Future<Map<String, String>?> _authHeaders() async {
    final token = await BffAuthService.instance.getValidAccessToken();
    if (token == null || token.isEmpty) return null;
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };
  }

  static Color _parseColor(String? hex) {
    if (hex == null || hex.length < 7 || !hex.startsWith('#')) {
      return const Color(0xFF22D3EE);
    }
    try {
      final v = int.parse(hex.substring(1), radix: 16);
      return Color(0xFF000000 | v);
    } catch (_) {
      return const Color(0xFF22D3EE);
    }
  }

  static String colorToHex(Color c) {
    final r = ((c.r * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0');
    final g = ((c.g * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0');
    final b = ((c.b * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0');
    return '#$r$g$b'.toUpperCase();
  }

  /// 담타 화면 하트비트. 성공 시 서버가 집계한 동시 접속자 수(대략).
  Future<int?> postPresence() async {
    if (!ApiConfig.isConfigured) return null;
    try {
      final headers = await _authHeaders();
      if (headers == null) return null;
      final res = await http
          .post(
            _uri('/v1/community/damta/presence'),
            headers: {
              ...headers,
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['ok'] != true) return null;
      final c = body['count'];
      if (c is num) return c.toInt();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<DamtaCommunityMessage>?> fetchMessages() async {
    if (!ApiConfig.isConfigured) return null;
    try {
      final headers = await _authHeaders();
      if (headers == null) return null;
      final res = await http
          .get(
            _uri('/v1/community/damta/messages'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = body['items'];
      if (raw is! List) return [];
      final out = <DamtaCommunityMessage>[];
      for (final e in raw) {
        if (e is! Map<String, dynamic>) continue;
        final id = e['id']?.toString();
        final text = e['text']?.toString();
        if (id == null || text == null) continue;
        final authorName = e['authorName']?.toString().trim();
        final ts = e['ts'];
        final tsMs = ts is num ? ts.toInt() : 0;
        out.add(DamtaCommunityMessage(
          id: id,
          text: text,
          color: _parseColor(e['color']?.toString()),
          authorName: (authorName == null || authorName.isEmpty) ? '익명' : authorName,
          tsMs: tsMs,
        ));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<DamtaCommunityMessage?> postMessage({
    required String text,
    required Color color,
    String? authorName,
  }) async {
    final result = await postMessageDetailed(
      text: text,
      color: color,
      authorName: authorName,
    );
    return result.message;
  }

  Future<({DamtaCommunityMessage? message, DamtaPostFailure? failure})>
      postMessageDetailed({
    required String text,
    required Color color,
    String? authorName,
  }) async {
    if (!ApiConfig.isConfigured) {
      return (message: null, failure: DamtaPostFailure.notConfigured);
    }
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return (message: null, failure: DamtaPostFailure.notLoggedIn);
      }
      final res = await http
          .post(
            _uri('/v1/community/damta/messages'),
            headers: {
              ...headers,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'text': text,
              'color': colorToHex(color),
              if (authorName != null && authorName.trim().isNotEmpty)
                'authorName': authorName.trim(),
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 429) {
        return (message: null, failure: DamtaPostFailure.rateLimited);
      }
      if (res.statusCode == 401) {
        return (message: null, failure: DamtaPostFailure.notLoggedIn);
      }
      if (res.statusCode == 400) {
        return (message: null, failure: DamtaPostFailure.emptyAfterFilter);
      }
      if (res.statusCode == 503) {
        return (message: null, failure: DamtaPostFailure.serviceUnavailable);
      }
      if (res.statusCode != 201 && res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            'DamtaCommunityApi postMessage: HTTP ${res.statusCode} ${res.body}',
          );
        }
        return (message: null, failure: DamtaPostFailure.serverError);
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final item = body['item'];
      if (item is! Map<String, dynamic>) {
        return (message: null, failure: DamtaPostFailure.serverError);
      }
      final id = item['id']?.toString();
      final t = item['text']?.toString();
      if (id == null || t == null) {
        return (message: null, failure: DamtaPostFailure.serverError);
      }
      final authorFromServer = item['authorName']?.toString().trim();
      final ts = item['ts'];
      final tsMs = ts is num ? ts.toInt() : DateTime.now().millisecondsSinceEpoch;
      return (
        message: DamtaCommunityMessage(
          id: id,
          text: t,
          color: _parseColor(item['color']?.toString()),
          authorName: (authorFromServer == null || authorFromServer.isEmpty)
              ? '익명'
              : authorFromServer,
          tsMs: tsMs,
        ),
        failure: null,
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('DamtaCommunityApi postMessage error: $e\n$st');
      return (message: null, failure: DamtaPostFailure.serverError);
    }
  }
}
