import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import 'api_config.dart';
import '../auth/bff_auth_service.dart';

/// 서버(BFF /v1/quit-rooms)와 통신하는 API 서비스
abstract final class QuitRoomsApiService {
  static Uri _uri(String path) {
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    return Uri.parse('$base$path');
  }

  static Future<Map<String, String>> _headers() async {
    final t = await BffAuthService.instance.getValidAccessToken();
    if (t == null || t.isEmpty) return {};
    return {
      'Authorization': 'Bearer $t',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  // ─── 방 목록 / 생성 / 입장 ────────────────────────────────────────

  /// 내가 속한 방 목록 조회
  static Future<List<Map<String, dynamic>>?> fetchRooms() async {
    if (!ApiConfig.isConfigured) return null;
    final headers = await _headers();
    if (headers.isEmpty) return null;
    try {
      final res = await http
          .get(_uri('/v1/quit-rooms'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['rooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi fetchRooms error: $e');
      return null;
    }
  }

  /// 방 생성
  static Future<Map<String, dynamic>?> createRoom({
    required String name,
    required String roomType, // "solo" | "group"
    required String nickname,
    String goalType = 'none',
    int? goalDays,
    String? goalEndDate,
    String? pledgeText,
  }) async {
    if (!ApiConfig.isConfigured) return null;
    final headers = await _headers();
    if (headers.isEmpty) return null;
    try {
      final res = await http
          .post(
            _uri('/v1/quit-rooms'),
            headers: headers,
            body: jsonEncode({
              'name': name,
              'room_type': roomType,
              'nickname': nickname,
              if (goalType != 'none') 'goal_type': goalType,
              if (goalDays != null) 'goal_days': goalDays,
              if (goalEndDate != null) 'goal_end_date': goalEndDate,
              if (pledgeText != null && pledgeText.isNotEmpty)
                'pledge_text': pledgeText,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 201) {
        if (kDebugMode) debugPrint('QuitRoomsApi createRoom: HTTP ${res.statusCode} ${res.body}');
        return null;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['room'] as Map<String, dynamic>?;
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi createRoom error: $e');
      return null;
    }
  }

  /// 초대 코드로 방 입장
  static Future<({Map<String, dynamic>? room, String? error})> joinRoom({
    required String inviteCode,
    required String nickname,
  }) async {
    if (!ApiConfig.isConfigured) {
      return (room: null, error: '서버 연결 설정이 필요해요.');
    }
    final headers = await _headers();
    if (headers.isEmpty) {
      return (room: null, error: '로그인이 필요해요.');
    }
    try {
      final res = await http
          .post(
            _uri('/v1/quit-rooms/join'),
            headers: headers,
            body: jsonEncode({
              'invite_code': inviteCode.trim().toUpperCase(),
              'nickname': nickname,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('QuitRoomsApi joinRoom: HTTP ${res.statusCode} ${res.body}');
        }
        return (room: null, error: _joinErrorMessage(res.statusCode, res.body));
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (room: body['room'] as Map<String, dynamic>?, error: null);
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi joinRoom error: $e');
      return (room: null, error: '네트워크 오류가 발생했어요. 다시 시도해 주세요.');
    }
  }

  static String _joinErrorMessage(int statusCode, String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final code = json['error'] as String?;
      switch (code) {
        case 'NOT_FOUND':
          return '초대 코드를 찾을 수 없어요. 코드를 다시 확인해 주세요.';
        case 'ROOM_FULL':
          return '방이 가득 찼어요. (최대 10명)';
        case 'ALREADY_MEMBER':
          return '이미 참여 중인 방이에요.';
        case 'BAD_REQUEST':
          final msg = json['message'] as String? ?? '';
          if (msg.contains('solo')) {
            return '솔로 방은 초대 코드로 입장할 수 없어요.';
          }
          return '입력 정보를 확인해 주세요.';
      }
    } catch (_) {
      // fall through
    }
    if (statusCode == 404) {
      return '초대 코드를 찾을 수 없어요. 코드를 다시 확인해 주세요.';
    }
    return '입장에 실패했어요. 다시 시도해 주세요.';
  }

  /// 방 나가기 — 멤버가 0명이 되면 서버에서 자동 삭제
  static Future<bool> leaveRoom(String roomId) async {
    if (!ApiConfig.isConfigured) return false;
    final headers = await _headers();
    if (headers.isEmpty) return false;
    try {
      final res = await http
          .delete(_uri('/v1/quit-rooms/$roomId/leave'), headers: headers)
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi leaveRoom error: $e');
      return false;
    }
  }

  /// 방 전체 삭제 (관리자 전용) — 모든 멤버를 강제로 내보내고 서버에서 방 삭제
  static Future<bool> deleteRoom(String roomId) async {
    if (!ApiConfig.isConfigured) return false;
    final headers = await _headers();
    if (headers.isEmpty) return false;
    try {
      final res = await http
          .delete(_uri('/v1/quit-rooms/$roomId'), headers: headers)
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi deleteRoom error: $e');
      return false;
    }
  }

  /// 방 멤버 목록 조회
  static Future<List<Map<String, dynamic>>?> fetchMembers(String roomId) async {
    if (!ApiConfig.isConfigured) return null;
    final headers = await _headers();
    if (headers.isEmpty) return null;
    try {
      final res = await http
          .get(_uri('/v1/quit-rooms/$roomId/members'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['members'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi fetchMembers error: $e');
      return null;
    }
  }

  // ─── 게시물 ────────────────────────────────────────────────────────

  /// 방 피드 조회 (최신 50건)
  static Future<List<Map<String, dynamic>>?> fetchPosts(
    String roomId, {
    int limit = 50,
  }) async {
    if (!ApiConfig.isConfigured) return null;
    final headers = await _headers();
    if (headers.isEmpty) return null;
    try {
      final res = await http
          .get(
            _uri('/v1/quit-rooms/$roomId/posts?limit=$limit'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['posts'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi fetchPosts error: $e');
      return null;
    }
  }

  /// 방 stats
  static Future<Map<String, dynamic>?> fetchStats(String roomId) async {
    if (!ApiConfig.isConfigured) return null;
    final headers = await _headers();
    if (headers.isEmpty) return null;
    try {
      final res = await http
          .get(_uri('/v1/quit-rooms/$roomId/stats'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['stats'] as Map<String, dynamic>?;
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi fetchStats error: $e');
      return null;
    }
  }

  /// 방 목표·서약 수정
  static Future<Map<String, dynamic>?> updateRoom(
    String roomId, {
    String? goalType,
    int? goalDays,
    String? goalEndDate,
    String? pledgeText,
  }) async {
    if (!ApiConfig.isConfigured) return null;
    final headers = await _headers();
    if (headers.isEmpty) return null;
    try {
      final res = await http
          .patch(
            _uri('/v1/quit-rooms/$roomId'),
            headers: headers,
            body: jsonEncode({
              if (goalType != null) 'goal_type': goalType,
              if (goalDays != null) 'goal_days': goalDays,
              if (goalEndDate != null) 'goal_end_date': goalEndDate,
              if (pledgeText != null) 'pledge_text': pledgeText,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['room'] as Map<String, dynamic>?;
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi updateRoom error: $e');
      return null;
    }
  }

  /// 담타 시작
  static Future<({Map<String, dynamic>? session, Map<String, dynamic>? post, String? error})>
      startDamta(String roomId) async {
    if (!ApiConfig.isConfigured) {
      return (session: null, post: null, error: '서버 연결 설정이 필요해요.');
    }
    final headers = await _headers();
    if (headers.isEmpty) {
      return (session: null, post: null, error: '로그인이 필요해요.');
    }
    try {
      final res = await http
          .post(_uri('/v1/quit-rooms/$roomId/damta/start'), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 201) {
        return (session: null, post: null, error: _parseErrorMessage(res.body));
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (
        session: body['session'] as Map<String, dynamic>?,
        post: body['post'] as Map<String, dynamic>?,
        error: null,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi startDamta error: $e');
      return (session: null, post: null, error: '네트워크 오류가 발생했어요.');
    }
  }

  static Future<bool> joinDamta(String roomId, String sessionId) async {
    if (!ApiConfig.isConfigured) return false;
    final headers = await _headers();
    if (headers.isEmpty) return false;
    try {
      final res = await http
          .post(
            _uri('/v1/quit-rooms/$roomId/damta/join'),
            headers: headers,
            body: jsonEncode({'session_id': sessionId}),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi joinDamta error: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> completeDamta(
    String roomId,
    String sessionId,
  ) async {
    if (!ApiConfig.isConfigured) return null;
    final headers = await _headers();
    if (headers.isEmpty) return null;
    try {
      final res = await http
          .post(
            _uri('/v1/quit-rooms/$roomId/damta/complete'),
            headers: headers,
            body: jsonEncode({'session_id': sessionId}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 201) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['post'] as Map<String, dynamic>?;
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi completeDamta error: $e');
      return null;
    }
  }

  static String _parseErrorMessage(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['message'] as String? ?? '요청에 실패했어요.';
    } catch (_) {
      return '요청에 실패했어요.';
    }
  }

  /// 게시물 작성 (imageBase64 → 서버에서 Storage 업로드 후 image_url 저장)
  static Future<QuitRoomCreatePostResult> createPost(
    String roomId, {
    String? content,
    String? imageUrl,
    String? imageBase64,
    String imageContentType = 'image/jpeg',
    String postType = 'text',
    Map<String, dynamic>? metadata,
  }) async {
    if (!ApiConfig.isConfigured) {
      return QuitRoomCreatePostResult.failure();
    }
    final headers = await _headers();
    if (headers.isEmpty) {
      return QuitRoomCreatePostResult.failure();
    }
    final hasImage = imageBase64 != null && imageBase64.isNotEmpty;
    try {
      final res = await http
          .post(
            _uri('/v1/quit-rooms/$roomId/posts'),
            headers: headers,
            body: jsonEncode({
              if (content != null && content.isNotEmpty) 'content': content,
              if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
              if (hasImage) 'image_base64': imageBase64,
              if (hasImage) 'image_content_type': imageContentType,
              'post_type': postType,
              if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
            }),
          )
          .timeout(Duration(seconds: hasImage ? 60 : 15));
      if (res.statusCode != 201) {
        if (kDebugMode) {
          debugPrint('QuitRoomsApi createPost: HTTP ${res.statusCode} ${res.body}');
        }
        if (res.statusCode == 429) {
          try {
            final body = jsonDecode(res.body) as Map<String, dynamic>;
            final code = body['error'] as String? ?? '';
            final message = body['message'] as String?;
            if (code == 'CERTIFY_LIMIT') {
              return QuitRoomCreatePostResult.failure(
                errorMessage: message ?? '하루 3회까지 인증할 수 있어요.',
              );
            }
            final userMessage = _uploadLimitMessage(code, message);
            return QuitRoomCreatePostResult.failure(
              errorMessage: userMessage,
              isUploadLimit: true,
            );
          } catch (_) {
            return QuitRoomCreatePostResult.failure(
              errorMessage: '사진 업로드 한도를 초과했어요. 잠시 후 다시 시도해 주세요.',
              isUploadLimit: true,
            );
          }
        }
        try {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final message = body['message'] as String?;
          if (message != null && message.isNotEmpty) {
            return QuitRoomCreatePostResult.failure(errorMessage: message);
          }
        } catch (_) {}
        return QuitRoomCreatePostResult.failure();
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final post = body['post'] as Map<String, dynamic>?;
      if (post == null) return QuitRoomCreatePostResult.failure();
      return QuitRoomCreatePostResult.success(post);
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi createPost error: $e');
      return QuitRoomCreatePostResult.failure();
    }
  }

  static String _uploadLimitMessage(String code, String? serverMessage) {
    if (code == 'IMAGE_UPLOAD_LIMIT_USER_DAY') {
      return '오늘 사진 업로드 한도(10장)에 도달했어요. 내일 다시 시도해 주세요.';
    }
    if (code == 'IMAGE_UPLOAD_LIMIT_ROOM_MONTH') {
      return '이 방의 이번 달 사진 한도(300장)에 도달했어요.';
    }
    if (serverMessage != null && serverMessage.isNotEmpty) {
      return serverMessage;
    }
    return '사진 업로드 한도를 초과했어요. 잠시 후 다시 시도해 주세요.';
  }

  /// 게시물 삭제
  static Future<bool> deletePost(String roomId, String postId) async {
    if (!ApiConfig.isConfigured) return false;
    final headers = await _headers();
    if (headers.isEmpty) return false;
    try {
      final res = await http
          .delete(
            _uri('/v1/quit-rooms/$roomId/posts/$postId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi deletePost error: $e');
      return false;
    }
  }

  /// 이모지 반응 추가
  static Future<bool> addReaction(
    String roomId,
    String postId,
    String emoji,
  ) async {
    if (!ApiConfig.isConfigured) return false;
    final headers = await _headers();
    if (headers.isEmpty) return false;
    try {
      final res = await http
          .post(
            _uri('/v1/quit-rooms/$roomId/posts/$postId/reactions'),
            headers: headers,
            body: jsonEncode({'emoji': emoji}),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('QuitRoomsApi addReaction error: $e');
      return false;
    }
  }
}

/// 게시물 작성 결과 (업로드 한도 등 오류 구분)
class QuitRoomCreatePostResult {
  const QuitRoomCreatePostResult._({
    this.post,
    this.errorMessage,
    this.isUploadLimit = false,
  });

  final Map<String, dynamic>? post;
  final String? errorMessage;
  final bool isUploadLimit;

  bool get isSuccess => post != null;

  factory QuitRoomCreatePostResult.success(Map<String, dynamic> post) =>
      QuitRoomCreatePostResult._(post: post);

  factory QuitRoomCreatePostResult.failure({
    String? errorMessage,
    bool isUploadLimit = false,
  }) =>
      QuitRoomCreatePostResult._(
        errorMessage: errorMessage,
        isUploadLimit: isUploadLimit,
      );
}
