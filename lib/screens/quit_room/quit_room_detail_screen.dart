import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/quit_rooms_api_service.dart';
import '../../data/quit_mode_prefs.dart';
import '../../services/quit_room_stats_loader.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import 'quit_room_models.dart';
import 'quit_room_post_cards.dart';

class QuitRoomDetailScreen extends StatefulWidget {
  const QuitRoomDetailScreen({super.key, required this.room});
  final QuitRoom room;

  @override
  State<QuitRoomDetailScreen> createState() => _QuitRoomDetailScreenState();
}

class _QuitRoomDetailScreenState extends State<QuitRoomDetailScreen> {
  late QuitRoom _room;
  RoomStats? _stats;
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _posting = false;
  bool _loadingPosts = false;
  bool _postsLoadFailed = false;
  bool _bannerCollapsed = false;
  bool _inputPanelExpanded = false;
  bool _inputFocused = false;
  final _collapsedDates = <String>{};

  static const _cheerChips = [
    ('👏', 'cheer', '응원해요!'),
    ('💪', 'cheer', '힘내요, 같이 버텨요!'),
    ('🌱', 'cheer', '잘하고 있어요 🌱'),
    ('🆘', 'sos', '지금 힘들어요…'),
  ];

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    unawaited(_hydratePostsFromCacheIfNeeded());
    _refreshRoomMeta();
    _loadPosts();
    _loadStats();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _hydratePostsFromCacheIfNeeded() async {
    if (_room.posts.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final cached = decodeRooms(prefs.getString(kQuitRoomsKey));
    final match = cached.where((r) => r.id == _room.id).firstOrNull;
    if (match == null || match.posts.isEmpty || !mounted) return;
    setState(() => _room = _room.copyWith(posts: match.posts));
  }

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
      goalType: match.goalType,
      goalDays: match.goalDays,
      goalEndDate: match.goalEndDate,
      pledgeText: match.pledgeText,
    );
    await _saveRoom(updated);
    if (mounted) setState(() => _room = updated);
  }

  Future<void> _loadStats() async {
    if (_room.id.startsWith('local_')) return;
    final raw = await QuitRoomsApiService.fetchStats(_room.id);
    if (raw == null || !mounted) return;
    setState(() => _stats = RoomStats.fromServerJson(raw));
  }

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

    List<Map<String, dynamic>>? serverPosts;
    for (var attempt = 0; attempt < 3; attempt++) {
      serverPosts = await QuitRoomsApiService.fetchPosts(_room.id, limit: 100);
      if (serverPosts != null) break;
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }

    if (!mounted) return;

    if (serverPosts == null) {
      setState(() {
        _loadingPosts = false;
        _postsLoadFailed = true;
      });
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
    unawaited(_loadStats());
  }

  Future<void> _saveRoom(QuitRoom updated) async {
    final prefs = await SharedPreferences.getInstance();
    final rooms = decodeRooms(prefs.getString(kQuitRoomsKey));
    final idx = rooms.indexWhere((r) => r.id == updated.id);
    if (idx >= 0) rooms[idx] = updated;
    await prefs.setString(kQuitRoomsKey, encodeRooms(rooms));
  }

  Future<void> _appendPost(RoomPost post) async {
    final updated = _room.copyWith(posts: [..._room.posts, post]);
    await _saveRoom(updated);
    if (!mounted) return;
    setState(() => _room = updated);
    _scrollToBottom();
    unawaited(_loadStats());
  }

  void _scrollToBottom() {
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

  Future<void> _createPost({
    required String postType,
    String? content,
    Map<String, dynamic>? metadata,
    String? imageBase64,
  }) async {
    if (_room.id.startsWith('local_')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오프라인 방은 서버 동기화 후 이용할 수 있어요.')),
      );
      return;
    }

    setState(() => _posting = true);
    final result = await QuitRoomsApiService.createPost(
      _room.id,
      content: content,
      postType: postType,
      metadata: metadata,
      imageBase64: imageBase64,
    );

    if (!mounted) return;
    setState(() => _posting = false);

    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? '전송에 실패했어요. 다시 시도해 주세요.'),
        ),
      );
      return;
    }

    await _appendPost(RoomPost.fromServerJson(result.post!));
  }

  Future<void> _showCertifyPreview() async {
    if (_stats?.myCertifyLimitReached == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('오늘 인증은 ${_stats!.myCertifyLimit}회까지 가능해요.'),
        ),
      );
      return;
    }

    final stats = await QuitRoomStatsLoader.loadFromPrefs();
    final msgCtrl = TextEditingController();
    final bottom = MediaQuery.of(context).padding.bottom;
    var message = '';

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            Text('오늘의 금연 인증', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('${stats.quitDays}', style: AppTheme.heroNumber.copyWith(fontSize: 36)),
                  Text(
                    '일째${stats.quitMode == QuitMode.restart ? ' · 이번 시도' : ''}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${formatSavedMoney(stats.savedMoney)} · ${formatSkippedCigs(stats.skippedCigs)}',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: msgCtrl,
              maxLength: 80,
              decoration: const InputDecoration(
                hintText: '한 줄 메시지 (선택)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      message = msgCtrl.text.trim();
                      Navigator.pop(ctx, true);
                    },
                    child: const Text('방에 올리기'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    msgCtrl.dispose();
    if (ok != true || !mounted) return;

    await _createPost(
      postType: 'certify',
      content: message.isEmpty ? null : message,
      metadata: stats.toMetadata(),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('인증했어요 🌱')),
      );
    }
  }

  Future<void> _sendCheerChip(String emoji, String postType, String text) async {
    if (postType == 'sos') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('SOS 알리기'),
          content: const Text('방에 SOS를 알릴까요?\n파트너에게 응원을 요청해요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('알리기')),
          ],
        ),
      );
      if (confirm != true) return;
      final stats = await QuitRoomStatsLoader.loadFromPrefs();
      await _createPost(
        postType: 'sos',
        content: text,
        metadata: stats.toMetadata(),
      );
      return;
    }

    await _createPost(
      postType: 'cheer',
      content: text,
      metadata: {'cheer_kind': emoji},
    );
  }

  Future<void> _postText({String? imageBase64}) async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty && imageBase64 == null) return;
    await _createPost(content: text.isNotEmpty ? text : null, postType: 'text', imageBase64: imageBase64);
    _textCtrl.clear();
  }

  Future<void> _addReaction(int postIdx, String emoji) async {
    final post = _room.posts[postIdx];
    final reactions = [...post.reactions];
    if (reactions.contains(emoji)) {
      reactions.remove(emoji);
    } else {
      reactions.add(emoji);
    }
    final updatedPosts = [..._room.posts];
    updatedPosts[postIdx] = post.copyWith(reactions: reactions);
    final updated = _room.copyWith(posts: updatedPosts);
    await _saveRoom(updated);
    if (!mounted) return;
    setState(() => _room = updated);
    QuitRoomsApiService.addReaction(_room.id, post.id, emoji);
  }

  Future<void> _cheerSosPost(int postIdx) async {
    await _sendCheerChip('💪', 'cheer', '힘내요, 같이 버텨요!');
    await _addReaction(postIdx, '💪');
  }

  void _showReactionPicker(int postIdx) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
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
              const Text('반응 남기기', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['❤️', '💪', '👏', '🔥', '🌱'].map((emoji) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _addReaction(postIdx, emoji);
                    },
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _MemberListSheet(
        room: _room,
        fetchMembers: () async {
          final raw = await QuitRoomsApiService.fetchMembers(_room.id);
          if (raw != null) return raw.map(RoomMember.fromServerJson).toList();
          return [RoomMember(nickname: _room.myName, isAdmin: _room.isAdmin)];
        },
        onDeleteRoom: _room.isAdmin ? _deleteRoomAsAdmin : null,
      ),
    );
  }

  Future<void> _deleteRoomAsAdmin() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('방 삭제'),
        content: Text('「${_room.name}」 방을 삭제할까요?\n모든 기록이 사라져요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await QuitRoomsApiService.deleteRoom(_room.id);
    if (!mounted) return;
    if (ok) {
      final prefs = await SharedPreferences.getInstance();
      final rooms = decodeRooms(prefs.getString(kQuitRoomsKey));
      await prefs.setString(
        kQuitRoomsKey,
        encodeRooms(rooms.where((r) => r.id != _room.id).toList()),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 80,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    await _postText(imageBase64: base64Encode(bytes));
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final certifiedToday = (stats?.myCertifyToday ?? 0) > 0;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compactChrome = keyboardOpen || _inputFocused;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(_room.name),
        toolbarHeight: compactChrome ? 48 : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.group_rounded),
            onPressed: _showMemberList,
          ),
          if (_room.type == 'group')
            IconButton(
              icon: const Icon(Icons.vpn_key_rounded),
              onPressed: _showInviteCode,
            ),
        ],
      ),
      body: Column(
        children: [
          if (!compactChrome) ...[
            _StatusBanner(
              room: _room,
              stats: stats,
              collapsed: _bannerCollapsed,
              onToggle: () => setState(() => _bannerCollapsed = !_bannerCollapsed),
            ),
            if (_room.pledgeText != null && _room.pledgeText!.isNotEmpty)
              _PledgePin(text: _room.pledgeText!),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '오늘의 기록',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ] else
            _CompactStatusStrip(
              room: _room,
              stats: stats,
              certifiedToday: certifiedToday,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _loadPosts(userInitiated: true);
                await _loadStats();
              },
              child: _buildFeed(
                certifiedToday: certifiedToday,
              ),
            ),
          ),
          _RoomInputBar(
            controller: _textCtrl,
            posting: _posting,
            panelExpanded: _inputPanelExpanded,
            certifiedToday: certifiedToday,
            certifyLimitReached: stats?.myCertifyLimitReached ?? false,
            onTogglePanel: () =>
                setState(() => _inputPanelExpanded = !_inputPanelExpanded),
            onFocusChanged: (focused) {
              setState(() {
                _inputFocused = focused;
                if (focused) _inputPanelExpanded = false;
              });
            },
            onCertify: _showCertifyPreview,
            onCheer: _sendCheerChip,
            onSend: () => _postText(),
            onPhoto: () => _showPhotoOption(),
            cheerChips: _cheerChips,
          ),
        ],
      ),
    );
  }

  Widget _buildFeed({required bool certifiedToday}) {
    final posts = _room.posts;

    if (_loadingPosts && posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const Icon(Icons.eco_rounded, size: 48, color: AppTheme.primary),
          const SizedBox(height: 12),
          Text(
            '아직 기록이 없어요',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '「오늘 인증하기」로 첫 금연 인증을 남겨 보세요.\n일수·절약이 자동으로 붙어요.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _showCertifyPreview,
            icon: const Icon(Icons.eco_rounded, size: 18),
            label: const Text('오늘 인증'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
          ),
        ],
      );
    }

    final sections = _groupPostsByDate(posts);
    final items = <Widget>[];

    if (_postsLoadFailed) {
      items.add(
        ListTile(
          leading: const Icon(Icons.cloud_off_rounded),
          title: const Text('최신 글을 불러오지 못했어요'),
          trailing: IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _loadPosts(userInitiated: true),
          ),
        ),
      );
    }

    for (final section in sections) {
      final dateKey = section.dateKey;
      final collapsed = _collapsedDates.contains(dateKey);
      items.add(
        QuitRoomDateHeader(
          date: section.date,
          certifySummary: section.certifySummary,
          collapsed: collapsed,
          onTap: () {
            setState(() {
              if (collapsed) {
                _collapsedDates.remove(dateKey);
              } else {
                _collapsedDates.add(dateKey);
              }
            });
          },
        ),
      );
      if (!collapsed) {
        for (final entry in section.entries) {
          final post = entry.post;
          final postIdx = entry.index;
          items.add(
            QuitRoomPostTile(
              post: post,
              isMe: post.authorName == _room.myName,
              onReact: () => _showReactionPicker(postIdx),
              onCheerSos: post.postType == 'sos'
                  ? () => _cheerSosPost(postIdx)
                  : null,
            ),
          );
          items.add(const SizedBox(height: 8));
        }
      }
    }

    return ListView(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: items,
    );
  }

  List<_DateSection> _groupPostsByDate(List<RoomPost> posts) {
    final map = <String, _DateSection>{};
    for (var i = 0; i < posts.length; i++) {
      final post = posts[i];
      final local = post.createdAt.toLocal();
      final key = '${local.year}-${local.month}-${local.day}';
      map.putIfAbsent(
        key,
        () => _DateSection(
          dateKey: key,
          date: DateTime(local.year, local.month, local.day),
          entries: [],
        ),
      );
      map[key]!.entries.add(_IndexedPost(index: i, post: post));
    }

    final sections = map.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    for (final s in sections) {
      if (_room.type == 'group') {
        final authors = s.entries
            .where((e) =>
                e.post.postType == 'certify' || e.post.postType == 'share')
            .map((e) => e.post.authorName)
            .toSet();
        s.certifySummary = '인증 ${authors.length}/${_room.memberCount}명';
      }
    }
    return sections;
  }

  void _showInviteCode() {
    final code = _room.inviteCode;
    if (code == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('초대 코드를 불러오는 중이에요.')),
      );
      _refreshRoomMeta();
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).padding.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text('초대 코드', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              Text(
                code,
                style: AppTheme.heroNumber.copyWith(
                  fontSize: 32,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '이 코드를 공유하면 친구가 방에 참여할 수 있어요.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('초대 코드를 복사했어요')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('코드 복사'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPhotoOption() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('카메라'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('갤러리'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DateSection {
  _DateSection({
    required this.dateKey,
    required this.date,
    required this.entries,
    this.certifySummary,
  });

  final String dateKey;
  final DateTime date;
  final List<_IndexedPost> entries;
  String? certifySummary;
}

class _IndexedPost {
  _IndexedPost({required this.index, required this.post});
  final int index;
  final RoomPost post;
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.room,
    required this.stats,
    required this.collapsed,
    required this.onToggle,
  });

  final QuitRoom room;
  final RoomStats? stats;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final challengeStats = stats;
    return Material(
      color: AppTheme.primary,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: collapsed
              ? Row(
                  children: [
                    Icon(
                      room.type == 'solo' ? Icons.person_rounded : Icons.groups_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        room.type == 'solo'
                            ? '오늘 인증 ${stats?.myCertifyToday ?? 0}회'
                            : '오늘 ${stats?.todayCertifyCount ?? 0}/${stats?.memberCount ?? room.memberCount}명 인증',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                    Icon(Icons.expand_more_rounded, color: Colors.white.withValues(alpha: 0.7)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          room.type == 'solo' ? '🌿 나의 금연' : '👥 우리 방',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.expand_less_rounded, color: Colors.white.withValues(alpha: 0.7)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (room.type == 'solo') ...[
                      Text(
                        '오늘 인증 ${stats?.myCertifyToday ?? 0}/${stats?.myCertifyLimit ?? 3}회',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                      ),
                    ] else ...[
                      Text(
                        '${room.memberCount}명 · 오늘 ${stats?.todayCertifyCount ?? 0}명 인증',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                      ),
                      if ((stats?.longestQuitDays ?? 0) > 0)
                        Text(
                          '가장 긴 금연: ${stats?.longestNickname ?? ''} ${stats?.longestQuitDays}일',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                        ),
                    ],
                    if (room.hasChallenge &&
                        challengeStats != null &&
                        challengeStats.challengeTargetDays != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (challengeStats.challengePercent / 100)
                              .clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: Colors.white24,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '챌린지 ${challengeStats.challengeProgressDays}/${challengeStats.challengeTargetDays}일 (${challengeStats.challengePercent}%)',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _PledgePin extends StatelessWidget {
  const _PledgePin({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primarySurface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
      ),
      child: Row(
        children: [
          const Text('📌', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryDark,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactStatusStrip extends StatelessWidget {
  const _CompactStatusStrip({
    required this.room,
    required this.stats,
    required this.certifiedToday,
  });

  final QuitRoom room;
  final RoomStats? stats;
  final bool certifiedToday;

  @override
  Widget build(BuildContext context) {
    final label = room.type == 'solo'
        ? (certifiedToday ? '오늘 인증 완료' : '오늘 인증 전')
        : '오늘 ${stats?.todayCertifyCount ?? 0}/${stats?.memberCount ?? room.memberCount}명 인증';

    return Material(
      color: AppTheme.primary.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}

class _RoomInputBar extends StatefulWidget {
  const _RoomInputBar({
    required this.controller,
    required this.posting,
    required this.panelExpanded,
    required this.certifiedToday,
    required this.certifyLimitReached,
    required this.onTogglePanel,
    required this.onFocusChanged,
    required this.onCertify,
    required this.onCheer,
    required this.onSend,
    required this.onPhoto,
    required this.cheerChips,
  });

  final TextEditingController controller;
  final bool posting;
  final bool panelExpanded;
  final bool certifiedToday;
  final bool certifyLimitReached;
  final VoidCallback onTogglePanel;
  final ValueChanged<bool> onFocusChanged;
  final VoidCallback onCertify;
  final Future<void> Function(String emoji, String type, String text) onCheer;
  final VoidCallback onSend;
  final VoidCallback onPhoto;
  final List<(String, String, String)> cheerChips;

  @override
  State<_RoomInputBar> createState() => _RoomInputBarState();
}

class _RoomInputBarState extends State<_RoomInputBar> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    widget.controller.removeListener(_onTextChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    widget.onFocusChanged(_focusNode.hasFocus);
  }

  void _onTextChange() => setState(() {});

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final bottomPad = keyboardOpen ? 6.0 : 6.0 + safeBottom;

    return Material(
      color: AppTheme.surfaceCard,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.panelExpanded) ...[
              GestureDetector(
                onVerticalDragUpdate: (d) {
                  if (d.delta.dy > 4) widget.onTogglePanel();
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              _ExpandedTools(
                certifiedToday: widget.certifiedToday,
                certifyLimitReached: widget.certifyLimitReached,
                posting: widget.posting,
                onCertify: widget.onCertify,
                onPhoto: widget.onPhoto,
                onCheer: widget.onCheer,
                cheerChips: widget.cheerChips,
              ),
              const Divider(height: 1, color: AppTheme.border),
            ] else if (!keyboardOpen) ...[
              GestureDetector(
                onTap: widget.onTogglePanel,
                onVerticalDragUpdate: (d) {
                  if (d.delta.dy < -4) widget.onTogglePanel();
                },
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(
                  height: 12,
                  child: Center(
                    child: _DragHandle(),
                  ),
                ),
              ),
            ],
            Padding(
              padding: EdgeInsets.fromLTRB(4, 2, 4, bottomPad),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      widget.panelExpanded
                          ? Icons.close_rounded
                          : Icons.add_circle_outline_rounded,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: widget.onTogglePanel,
                    tooltip: widget.panelExpanded ? '닫기' : '인증·응원',
                  ),
                  Expanded(
                    child: TextField(
                      focusNode: _focusNode,
                      controller: widget.controller,
                      minLines: 1,
                      maxLines: keyboardOpen ? 4 : 3,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: '메시지 입력',
                        isDense: true,
                        filled: true,
                        fillColor: AppTheme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.posting || !_hasText ? null : widget.onSend,
                    icon: widget.posting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.send_rounded,
                            color: _hasText ? AppTheme.primary : AppTheme.textMuted,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 3,
      decoration: BoxDecoration(
        color: AppTheme.border,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _ExpandedTools extends StatelessWidget {
  const _ExpandedTools({
    required this.certifiedToday,
    required this.certifyLimitReached,
    required this.posting,
    required this.onCertify,
    required this.onPhoto,
    required this.onCheer,
    required this.cheerChips,
  });

  final bool certifiedToday;
  final bool certifyLimitReached;
  final bool posting;
  final VoidCallback onCertify;
  final VoidCallback onPhoto;
  final Future<void> Function(String emoji, String type, String text) onCheer;
  final List<(String, String, String)> cheerChips;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: certifiedToday && !certifyLimitReached
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_rounded,
                                size: 16, color: AppTheme.primary),
                            SizedBox(width: 6),
                            Text(
                              '오늘 인증 완료',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : certifyLimitReached
                        ? Center(
                            child: Text(
                              '오늘 인증 3회 완료',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: AppTheme.textMuted),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: posting ? null : onCertify,
                            icon: const Icon(Icons.eco_rounded, size: 18),
                            label: const Text('오늘 인증하기'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              side: const BorderSide(color: AppTheme.primary),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
              ),
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                onPressed: posting ? null : onPhoto,
                tooltip: '사진',
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: cheerChips.map((c) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(
                      '${c.$1} ${c.$3.split('!').first}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: posting ? null : () => onCheer(c.$1, c.$2, c.$3),
                    backgroundColor: AppTheme.primarySurface,
                    side: BorderSide(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
      child: FutureBuilder<List<RoomMember>>(
        future: _future,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
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
              const SizedBox(height: 12),
              ...members.map((m) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(m.nickname.isNotEmpty ? m.nickname[0] : '?'),
                  ),
                  title: Row(
                    children: [
                      Text(m.nickname, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (m.isAdmin) ...[
                        const SizedBox(width: 6),
                        const Text('👑', style: TextStyle(fontSize: 12)),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${m.quitDays}일째${m.quitMode == 'restart' ? ' · 이번 시도' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: m.certifiedToday
                      ? const Icon(Icons.eco_rounded, color: AppTheme.primary, size: 18)
                      : null,
                );
              }),
              if (widget.onDeleteRoom != null) ...[
                const Divider(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onDeleteRoom!();
                  },
                  icon: const Icon(Icons.delete_forever_rounded, color: AppTheme.error),
                  label: const Text('방 삭제', style: TextStyle(color: AppTheme.error)),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
