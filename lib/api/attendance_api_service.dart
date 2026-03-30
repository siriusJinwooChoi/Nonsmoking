import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class AttendanceState {
  final int coins;
  final int streakDay;
  final String? lastDate;

  const AttendanceState({
    required this.coins,
    required this.streakDay,
    required this.lastDate,
  });
}

class AttendanceCheckInResult {
  final bool alreadyAttended;
  final int awardedCoins;
  final int coins;
  final int streakDay;
  final String? lastDate;
  final int? attendedDay;

  const AttendanceCheckInResult({
    required this.alreadyAttended,
    required this.awardedCoins,
    required this.coins,
    required this.streakDay,
    required this.lastDate,
    required this.attendedDay,
  });
}

class AttendanceApiService {
  const AttendanceApiService();

  Uri _uri(String path) {
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    return Uri.parse('$base$path');
  }

  Future<AttendanceState?> fetchState({
    required String accessToken,
  }) async {
    if (!ApiConfig.isConfigured) return null;
    final res = await http
        .get(
          _uri('/v1/attendance/state'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return AttendanceState(
      coins: (body['coins'] as num?)?.toInt() ?? 0,
      streakDay: (body['streakDay'] as num?)?.toInt() ?? 1,
      lastDate: body['lastDate'] as String?,
    );
  }

  Future<AttendanceCheckInResult?> checkIn({
    required String accessToken,
    required int day,
  }) async {
    if (!ApiConfig.isConfigured) return null;
    final res = await http
        .post(
          _uri('/v1/attendance/check-in'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'day': day}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return AttendanceCheckInResult(
      alreadyAttended: body['alreadyAttended'] as bool? ?? false,
      awardedCoins: (body['awardedCoins'] as num?)?.toInt() ?? 0,
      coins: (body['coins'] as num?)?.toInt() ?? 0,
      streakDay: (body['streakDay'] as num?)?.toInt() ?? 1,
      lastDate: body['lastDate'] as String?,
      attendedDay: (body['attendedDay'] as num?)?.toInt(),
    );
  }
}

