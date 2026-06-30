import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/quit_rooms_api_service.dart';
import '../../theme/app_theme.dart';
import 'quit_room_models.dart';

class QuitRoomDetailScreen extends StatefulWidget {
  const QuitRoomDetailScreen({super.key, required this.room});
  final QuitRoom room;

  @override
  State<QuitRoomDetailScreen> createState() => _QuitRoomDetailScreenState();
}

class _QuitRoomDetailScreenState extends State<QuitRoomDetailScreen> {
  late QuitRoom _room;
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _posting = false;
  bool _loadingPosts = false;
  bool _postsLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    unawaited(_hydratePostsFromCacheIfNeeded());
    _refreshRoomMeta();
    _loadPosts();
  }

  /// 목록 새로고침 등으로 posts 가 비어 들어온 경우 로컬 캐시에서 먼저 복원
  Future<void> _hydratePostsFromCacheIfNeeded() async {
    if (_room.posts.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final cached = decodeRooms(prefs.getString(kQuitRoomsKey));
    final match = cached.where((r) => r.id == _room.id).firstOrNull;
    if (match == null || match.posts.isEmpty || !mounted) return;
    setState(() => _room = _room.copyWith(posts: match.posts));
  }

  /// 서버에서 방 정보(초대 코드, 멤버 수, 관리자 여부 등) 최신화
  Future<void> _refreshRoomMeta() async {
    final serverRooms = await QuitRoomsApiService.fetchRooms();
    if (serverRooms == null || !mounted) return;

    final match = serverRooms
        .map((j) => QuitRoom.fromServerJson(j))
        .where((r) => r.id == _room.id)
        .firstOrNull;
    if (match == null) return;

    final updated = _room.copyWith(
      inviteCode: match.inviteCode,
      memberCount: match.memberCount,
      isAdmin: match.isAdmin,
    );
    await _saveRoom(updated);
    if (mounted) setState(() => _room = updated);
  }

  /// 서버에서 최신 게시물 목록을 가져와 로컬 상태에 반영 (실패 시 최대 3회 재시도)
  Future<void> _loadPosts({bool userInitiated = false}) async {
    if (_loadingPosts && !userInitiated) return;

    final hadCachedPosts = _room.posts.isNotEmpty;
    if (!hadCachedPosts) {
      setState(() {
        _loadingPosts = true;
        _postsLoadFailed = false;
      });
    } else if (userInitiated) {
      setState(() => _postsLoadFailed = false);
    }

    const maxAttempts = 3;
    List<Map<String, dynamic>>? serverPosts;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      serverPosts = await QuitRoomsApiService.fetchPosts(_room.id);
      if (serverPosts != null) break;
      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }

    if (!mounted) return;

    if (serverPosts == null) {
      setState(() {
        _loadingPosts = false;
        _postsLoadFailed = true;
      });
      if (userInitiated && !hadCachedPosts) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('글 목록을 불러오지 못했어요. 다시 시도해 주세요.')),
        );
      }
      return;
    }

    final posts = serverPosts.map((j) => RoomPost.fromServerJson(j)).toList();
    final updated = _room.copyWith(posts: posts);
    await _saveRoom(updated);
    if (!mounted) return;
    setState(() {
      _room = updated;
      _loadingPosts = false;
      _postsLoadFailed = false;
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _post({String? imageBase64}) async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty && imageBase64 == null) return;
    setState(() => _posting = true);

    // 서버에 게시물 생성 (이미지는 base64 → Storage 업로드 → image_url 저장)
    final result = await QuitRoomsApiService.createPost(
      _room.id,
      content: text.isNotEmpty ? text : null,
      imageBase64: imageBase64,
      postType: 'text',
    );

    if (!result.isSuccess) {
      if (!mounted) return;
      setState(() => _posting = false);
      final message = result.errorMessage ??
          (result.isUploadLimit
              ? '사진 업로드 한도를 초과했어요.'
              : '서버 연결에 실패했어요. 다시 시도해 주세요.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    final post = RoomPost.fromServerJson(result.post!);

    final updated = _room.copyWith(posts: [..._room.posts, post]);
    await _saveRoom(updated);

    if (!mounted) return;
    _textCtrl.clear();
    setState(() {
      _room = updated;
      _posting = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _saveRoom(QuitRoom updated) async {
    final prefs = await SharedPreferences.getInstance();
    final rooms = decodeRooms(prefs.getString(kQuitRoomsKey));
    final idx = rooms.indexWhere((r) => r.id == updated.id);
    if (idx >= 0) rooms[idx] = updated;
    await prefs.setString(kQuitRoomsKey, encodeRooms(rooms));
  }

  Future<void> _addReaction(int postIdx, String emoji) async {
    final post = _room.posts[postIdx];
    final reactions = [...post.reactions];
    if (reactions.contains(emoji)) {
      reactions.remove(emoji);
    } else {
      reactions.add(emoji);
    }
    final updatedPost = post.copyWith(reactions: reactions);
    final updatedPosts = [..._room.posts];
    updatedPosts[postIdx] = updatedPost;
    final updated = _room.copyWith(posts: updatedPosts);
    await _saveRoom(updated);
    if (!mounted) return;
    setState(() => _room = updated);

    // 서버에 반응 동기화 (로컬 이미 반영됨 — 백그라운드)
    QuitRoomsApiService.addReaction(_room.id, post.id, emoji);
  }

  void _showReactionPicker(int postIdx) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).padding.bottom;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '반응 남기기',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['❤️', '💪', '👏', '🔥', '😢'].map((emoji) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _addReaction(postIdx, emoji);
                    },
                    child: Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(emoji, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showMemberList() async {
    // 서버에서 멤버 목록 가져오기 (바텀시트 열기 전에 로딩)
    List<RoomMember>? serverMembers;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return _MemberListSheet(
          room: _room,
          fetchMembers: () async {
            if (serverMembers != null) return serverMembers!;
            final raw = await QuitRoomsApiService.fetchMembers(_room.id);
            if (raw != null) {
              serverMembers = raw.map(RoomMember.fromServerJson).toList();
            } else {
              // 폴백: 로컬 캐시 멤버 또는 내 닉네임만
              final cached = _room.members.isNotEmpty
                  ? _room.members
                  : [_room.myName];
              serverMembers = cached
                  .map((n) => RoomMember(nickname: n, isAdmin: n == _room.myName && _room.isAdmin))
                  .toList();
            }
            return serverMembers!;
          },
          onDeleteRoom: _room.isAdmin ? _deleteRoomAsAdmin : null,
        );
      },
    );
  }

  /// 관리자가 방을 삭제 (서버에서 방 전체 삭제 → 모든 멤버 강제 퇴장)
  Future<void> _deleteRoomAsAdmin() async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEDED),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete_forever_rounded, color: AppTheme.error, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('방 삭제', style: TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
        content: Text(
          '「${_room.name}」 방을 삭제하면\n모든 멤버가 강제로 퇴장되고\n모든 기록이 영구 삭제됩니다.\n\n정말 삭제하시겠어요?',
          style: const TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('방 삭제'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final ok = await QuitRoomsApiService.deleteRoom(_room.id);
    if (!mounted) return;

    if (ok) {
      // 로컬 캐시에서 방 제거
      final prefs = await SharedPreferences.getInstance();
      final rooms = decodeRooms(prefs.getString(kQuitRoomsKey));
      final updated = rooms.where((r) => r.id != _room.id).toList();
      await prefs.setString(kQuitRoomsKey, encodeRooms(updated));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('방이 삭제되었어요.')),
        );
        Navigator.pop(context); // 목록 화면으로 돌아가기
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('방 삭제에 실패했어요. 다시 시도해 주세요.')),
      );
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 80,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await _post(imageBase64: base64Encode(bytes));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사진을 불러올 수 없어요: $e')),
      );
    }
  }

  void _showPhotoOption() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(context).padding.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text('사진 추가', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: AppTheme.primarySurface,
                leading: const Icon(Icons.camera_alt_rounded, color: AppTheme.primary),
                title: const Text('카메라로 찍기', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: AppTheme.surface,
                leading: const Icon(Icons.photo_library_rounded, color: AppTheme.primary),
                title: const Text('갤러리에서 선택', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showInviteCode() {
    final code = _room.inviteCode;
    if (code == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('초대 코드를 불러오는 중이에요. 잠시 후 다시 시도해 주세요.')),
      );
      _refreshRoomMeta();
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('초대 코드'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              code,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '이 코드를 공유하면 친구가 방에 참여할 수 있어요.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('초대 코드를 클립보드에 복사했어요')),
              );
            },
            child: const Text('코드 복사'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_room.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_rounded),
            tooltip: '멤버',
            onPressed: _showMemberList,
          ),
          if (_room.type == 'group')
            IconButton(
              icon: const Icon(Icons.person_add_rounded),
              tooltip: '초대 코드',
              onPressed: _room.inviteCode != null ? _showInviteCode : null,
            ),
        ],
      ),
      body: Column(
        children: [
          // 상단 방 정보
          Container(
            color: AppTheme.primary,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _room.type == 'solo' ? Icons.person_rounded : Icons.groups_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _room.type == 'solo' ? '솔로' : '그룹 ${_room.memberCount}명',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '개설일 ${_fmtDate(_room.createdAt)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),

          if (_room.type == 'group') _InviteCodeBanner(
            inviteCode: _room.inviteCode,
            onCopy: () {
              final code = _room.inviteCode;
              if (code == null) {
                _refreshRoomMeta();
                return;
              }
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('초대 코드를 복사했어요')),
              );
            },
            onTap: _showInviteCode,
          ),

          // 피드
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadPosts(userInitiated: true),
              child: _buildFeed(),
            ),
          ),

          // 입력창
          _PostInput(
            controller: _textCtrl,
            posting: _posting,
            onSend: () => _post(),
            onPhotoTap: _showPhotoOption,
          ),
        ],
      ),
    );
  }

  Widget _buildFeed() {
    final posts = _room.posts;

    if (_loadingPosts && posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 16),
          Center(
            child: Text(
              '글 목록을 불러오는 중…',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ],
      );
    }

    if (posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        children: [
          if (_postsLoadFailed) ...[
            Icon(Icons.cloud_off_rounded, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              '글 목록을 불러오지 못했어요.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '아래로 당겨 새로고침하거나 다시 시도해 주세요.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => _loadPosts(userInitiated: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('다시 시도'),
              ),
            ),
            const SizedBox(height: 32),
          ] else ...[
            const Icon(Icons.chat_bubble_outline_rounded, size: 48, color: AppTheme.border),
            const SizedBox(height: 12),
            Text('첫 기록을 남겨 보세요!', style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
          ],
        ],
      );
    }

    return ListView.separated(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: posts.length + (_postsLoadFailed ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        if (_postsLoadFailed && i == 0) {
          return Material(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              leading: const Icon(Icons.cloud_off_rounded, color: Color(0xFFC47A12)),
              title: const Text('최신 글을 불러오지 못했어요', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('아래로 당기거나 탭해서 다시 시도', style: TextStyle(fontSize: 12)),
              trailing: IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => _loadPosts(userInitiated: true),
              ),
              onTap: () => _loadPosts(userInitiated: true),
            ),
          );
        }
        final postIdx = _postsLoadFailed ? i - 1 : i;
        final post = posts[postIdx];
        return _PostCard(
          post: post,
          isMe: post.authorName == _room.myName,
          onReact: () => _showReactionPicker(postIdx),
        );
      },
    );
  }

  String _fmtDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.isMe, required this.onReact});
  final RoomPost post;
  final bool isMe;
  final VoidCallback onReact;

  @override
  Widget build(BuildContext context) {
    final img = post.imageBase64;
    Uint8List? imageBytes;
    if (img != null && img.isNotEmpty) {
      try {
        imageBytes = base64Decode(img);
      } catch (_) {}
    }
    final imageUrl = post.imageUrl;
    final hasNetworkImage =
        imageUrl != null && imageUrl.isNotEmpty && imageBytes == null;
    final imageExpired = imageBytes == null &&
        !hasNetworkImage &&
        post.content.contains('사진을 공유했어요');

    return Align(
      alignment: post.isSosAlert ? Alignment.center : (isMe ? Alignment.centerRight : Alignment.centerLeft),
      child: post.isSosAlert
          ? _SosAlertChip(post: post)
          : ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      child: Text(
                        post.authorName,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                    ),
                  GestureDetector(
                    onLongPress: onReact,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isMe ? AppTheme.primary : AppTheme.surfaceCard,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 16),
                        ),
                        boxShadow: AppTheme.cardShadowSubtle,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (imageBytes != null)
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                              child: Image.memory(
                                imageBytes,
                                width: double.infinity,
                                height: 180,
                                fit: BoxFit.cover,
                              ),
                            )
                          else if (hasNetworkImage)
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                              child: Image.network(
                                imageUrl!,
                                width: double.infinity,
                                height: 180,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return Container(
                                    width: double.infinity,
                                    height: 180,
                                    color: AppTheme.surface,
                                    child: const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                },
                                errorBuilder: (_, __, ___) => _ExpiredImagePlaceholder(
                                  isMe: isMe,
                                ),
                              ),
                            )
                          else if (imageExpired)
                            const _ExpiredImagePlaceholder(),
                          if (post.content.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Text(
                                post.content,
                                style: TextStyle(
                                  color: isMe ? Colors.white : AppTheme.textPrimary,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (post.reactions.isNotEmpty) ...[
                          Text(post.reactions.join(' '), style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          _fmtTime(post.createdAt),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _fmtTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${local.month}/${local.day}';
  }
}

class _ExpiredImagePlaceholder extends StatelessWidget {
  const _ExpiredImagePlaceholder({this.isMe = false});

  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 180,
      color: isMe ? Colors.white.withValues(alpha: 0.15) : AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_outlined,
            color: isMe ? Colors.white70 : AppTheme.textMuted,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            '보관 기간(90일)이 지나\n사진이 삭제되었어요',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: isMe ? Colors.white70 : AppTheme.textMuted,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}

class _SosAlertChip extends StatelessWidget {
  const _SosAlertChip({required this.post});
  final RoomPost post;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🆘', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              post.content,
              style: const TextStyle(fontSize: 13, color: Color(0xFF92400E)),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteCodeBanner extends StatelessWidget {
  const _InviteCodeBanner({
    required this.inviteCode,
    required this.onCopy,
    required this.onTap,
  });

  final String? inviteCode;
  final VoidCallback onCopy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasCode = inviteCode != null && inviteCode!.isNotEmpty;

    return Material(
      color: const Color(0xFFEDE9FE),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.vpn_key_rounded,
                  color: Color(0xFF7C3AED),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasCode ? '초대 코드' : '초대 코드 불러오는 중…',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6D28D9),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasCode ? inviteCode! : '탭해서 다시 시도',
                      style: TextStyle(
                        fontSize: hasCode ? 18 : 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: hasCode ? 4 : 0,
                        color: hasCode
                            ? const Color(0xFF5B21B6)
                            : const Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasCode)
                IconButton(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  color: const Color(0xFF7C3AED),
                  tooltip: '복사',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostInput extends StatelessWidget {
  const _PostInput({
    required this.controller,
    required this.posting,
    required this.onSend,
    this.onPhotoTap,
  });
  final TextEditingController controller;
  final bool posting;
  final VoidCallback onSend;
  final VoidCallback? onPhotoTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceCard,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        12, 8, 12,
        MediaQuery.of(context).viewInsets.bottom + 8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_rounded),
            color: AppTheme.textSecondary,
            onPressed: onPhotoTap,
            tooltip: '사진 추가',
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '오늘의 금연 기록을 남겨요 ✍️',
                filled: true,
                fillColor: AppTheme.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(posting: posting, onTap: onSend),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.posting, required this.onTap});
  final bool posting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: posting ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: posting ? AppTheme.border : AppTheme.primary,
          shape: BoxShape.circle,
        ),
        child: posting
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}

// ─── 멤버 목록 바텀시트 ──────────────────────────────────────────────

class _MemberListSheet extends StatefulWidget {
  const _MemberListSheet({
    required this.room,
    required this.fetchMembers,
    this.onDeleteRoom,
  });

  final QuitRoom room;
  final Future<List<RoomMember>> Function() fetchMembers;
  final VoidCallback? onDeleteRoom;

  @override
  State<_MemberListSheet> createState() => _MemberListSheetState();
}

class _MemberListSheetState extends State<_MemberListSheet> {
  late Future<List<RoomMember>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetchMembers();
  }

  static const _avatarColors = [
    AppTheme.primary,
    Color(0xFF7C3AED),
    Color(0xFFC47A12),
    Color(0xFF0284C7),
    Color(0xFF059669),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final room = widget.room;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<RoomMember>>(
            future: _future,
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '멤버 ${room.memberCount}명',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 24),
                  ],
                );
              }
              final members = snap.data!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '멤버 ${members.length}명',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ...members.map((m) {
                    final isMe = m.nickname == room.myName;
                    final color = _avatarColors[m.nickname.hashCode.abs() % _avatarColors.length];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: color.withValues(alpha: 0.15),
                        child: Text(
                          m.nickname.isNotEmpty ? m.nickname[0].toUpperCase() : '?',
                          style: TextStyle(color: color, fontWeight: FontWeight.w700),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(m.nickname, style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (m.isAdmin) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3CD),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '👑 관리자',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: isMe
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primarySurface,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                '나',
                                style: TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w700),
                              ),
                            )
                          : null,
                    );
                  }),
                ],
              );
            },
          ),
          if (room.type == 'group') ...[
            const Divider(),
            if (room.inviteCode != null)
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: room.inviteCode!));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('초대 코드를 복사했어요')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: Text('초대 코드 복사 (${room.inviteCode})'),
              ),
            if (widget.onDeleteRoom != null)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppTheme.error),
                onPressed: () {
                  Navigator.pop(context);
                  widget.onDeleteRoom!();
                },
                icon: const Icon(Icons.delete_forever_rounded, size: 16),
                label: const Text('방 삭제 (관리자)'),
              ),
          ],
        ],
      ),
    );
  }
}
