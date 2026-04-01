import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class DamtaCommunityMessage {
  final String id;
  final String text;
  final Color color;
  /// 서버 수신 시각(ms). 세션 시작 이전 메시지 필터에 사용합니다.
  final int tsMs;

  const DamtaCommunityMessage({
    required this.id,
    required this.text,
    required this.color,
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

  Future<List<DamtaCommunityMessage>?> fetchMessages() async {
    if (!ApiConfig.isConfigured) return null;
    try {
      final res = await http
          .get(
            _uri('/v1/community/damta/messages'),
            headers: {'Accept': 'application/json'},
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
        final ts = e['ts'];
        final tsMs = ts is num ? ts.toInt() : 0;
        out.add(DamtaCommunityMessage(
          id: id,
          text: text,
          color: _parseColor(e['color']?.toString()),
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
  }) async {
    if (!ApiConfig.isConfigured) return null;
    try {
      final res = await http
          .post(
            _uri('/v1/community/damta/messages'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'text': text,
              'color': colorToHex(color),
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 201 && res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final item = body['item'];
      if (item is! Map<String, dynamic>) return null;
      final id = item['id']?.toString();
      final t = item['text']?.toString();
      if (id == null || t == null) return null;
      final ts = item['ts'];
      final tsMs = ts is num ? ts.toInt() : DateTime.now().millisecondsSinceEpoch;
      return DamtaCommunityMessage(
        id: id,
        text: t,
        color: _parseColor(item['color']?.toString()),
        tsMs: tsMs,
      );
    } catch (_) {
      return null;
    }
  }
}
