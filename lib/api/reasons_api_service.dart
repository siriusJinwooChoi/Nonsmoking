import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class ReasonState {
  final List<Map<String, dynamic>> reasons;
  final String pinnedReasonText;
  final String? selectedReasonId;
  final String? selectedReasonText;

  const ReasonState({
    required this.reasons,
    required this.pinnedReasonText,
    required this.selectedReasonId,
    required this.selectedReasonText,
  });
}

class ReasonsApiService {
  const ReasonsApiService();

  Uri _uri(String path) {
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    return Uri.parse('$base$path');
  }

  Future<ReasonState?> fetchReasonState({
    required String accessToken,
  }) async {
    if (!ApiConfig.isConfigured) return null;
    final res = await http.get(
      _uri('/v1/reasons'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) return null;
    final Map<String, dynamic> body = jsonDecode(res.body) as Map<String, dynamic>;
    final text = (body['pinnedReasonText'] as String? ?? '').trim();
    final reasonsRaw = body['reasons'];
    final reasons = (reasonsRaw is List)
        ? reasonsRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    return ReasonState(
      reasons: reasons,
      pinnedReasonText: text,
      selectedReasonId: body['selectedReasonId'] as String?,
      selectedReasonText: body['selectedReasonText'] as String?,
    );
  }

  Future<String?> fetchPinnedReason({
    required String accessToken,
  }) async {
    final state = await fetchReasonState(accessToken: accessToken);
    if (state == null) return null;
    return state.pinnedReasonText.isEmpty ? null : state.pinnedReasonText;
  }

  Future<bool> savePinnedReason({
    required String accessToken,
    required String text,
  }) async {
    if (!ApiConfig.isConfigured) return false;
    final res = await http.put(
      _uri('/v1/reasons/pinned'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'text': text}),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<bool> syncReasonState({
    required String accessToken,
    required List<Map<String, dynamic>> reasons,
    required String pinnedReasonText,
    required String? selectedReasonId,
    required String? selectedReasonText,
  }) async {
    if (!ApiConfig.isConfigured) return false;
    final res = await http.put(
      _uri('/v1/reasons/sync'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'reasons': reasons,
        'pinnedReasonText': pinnedReasonText,
        'selectedReasonId': selectedReasonId,
        'selectedReasonText': selectedReasonText,
      }),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }
}

