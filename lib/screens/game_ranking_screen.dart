import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/bff_auth_service.dart';
import '../supabase/supabase_config.dart';
import '../theme/app_theme.dart';
import '../api/api_config.dart';
import '../api/games_api_service.dart';

/// 미니게임 4종 랭킹 (상위 10명 + 본인 순위) — BFF `/v1/games/rankings` 만 사용.
class GameRankingScreen extends StatefulWidget {
  const GameRankingScreen({super.key});

  @override
  State<GameRankingScreen> createState() => _GameRankingScreenState();
}

class _GameRankingScreenState extends State<GameRankingScreen> {
  final GamesApiService _gamesApi = const GamesApiService();
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _seqList = [];
  List<Map<String, dynamic>> _wordList = [];
  List<Map<String, dynamic>> _catchList = [];
  List<Map<String, dynamic>> _timingList = [];

  Map<String, String?> _displayNames = {};

  int? _mySeqRank;
  int? _myWordRank;
  int? _myCatchRank;
  int? _myTimingRank;

  double? _mySeqSec;
  int? _myWordLevel;
  int? _myCatchScore;
  int? _myTimingScore;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!SupabaseConfig.isConfigured) {
      setState(() {
        _loading = false;
        _error = '클라우드 연동(API)이 설정되지 않았습니다.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final mySeq = prefs.getDouble('bestRecord');
    final myWord = prefs.getInt('word_game_level') ?? 1;
    final myCatch = prefs.getInt('cigarette_catch_best_score') ?? 0;
    final myTiming = prefs.getInt('timing_tap_best_score') ?? 0;

    try {
      final token = await BffAuthService.instance.getValidAccessToken();
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = '로그인이 필요합니다.';
        });
        return;
      }
      if (!ApiConfig.isConfigured) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'API 주소가 설정되지 않았습니다.';
        });
        return;
      }

      final payload = await _gamesApi.fetchRankings(accessToken: token, limit: 10);
      if (payload == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = '랭킹을 불러오지 못했습니다.';
        });
        return;
      }

      final top = payload['top'] as Map<String, dynamic>? ?? const {};
      final my = payload['my'] as Map<String, dynamic>? ?? const {};

      _seqList = List<Map<String, dynamic>>.from((top['numberSequence'] as List?) ?? const []);
      _wordList = List<Map<String, dynamic>>.from((top['wordGame'] as List?) ?? const []);
      _catchList = List<Map<String, dynamic>>.from((top['cigaretteCatch'] as List?) ?? const []);
      _timingList = List<Map<String, dynamic>>.from((top['timingTap'] as List?) ?? const []);

      _displayNames = {};
      for (final r in [..._seqList, ..._wordList, ..._catchList, ..._timingList]) {
        final id = r['user_id'] as String?;
        final dn = r['display_name'] as String?;
        if (id != null) {
          _displayNames[id] = (dn != null && dn.trim().isNotEmpty) ? dn.trim() : null;
        }
      }

      _mySeqRank = (my['numberSequenceRank'] as num?)?.toInt();
      _myWordRank = (my['wordGameRank'] as num?)?.toInt();
      _myCatchRank = (my['cigaretteCatchRank'] as num?)?.toInt();
      _myTimingRank = (my['timingTapRank'] as num?)?.toInt();

      if (!mounted) return;
      setState(() {
        _mySeqSec = (my['numberSequenceBestSeconds'] as num?)?.toDouble() ?? mySeq;
        _myWordLevel = (my['wordGameLevel'] as num?)?.toInt() ?? myWord;
        _myCatchScore = (my['cigaretteCatchBestScore'] as num?)?.toInt() ?? myCatch;
        _myTimingScore = (my['timingTapBestScore'] as num?)?.toInt() ?? myTiming;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '랭킹을 불러오지 못했습니다.';
      });
    }
  }

  bool _inTop10(List<Map<String, dynamic>> list, String? uid) {
    if (uid == null) return false;
    return list.any((e) => e['user_id'] == uid);
  }

  String _nameFor(String userId) {
    final n = _displayNames[userId];
    if (n != null && n.isNotEmpty) return n;
    return '익명';
  }

  @override
  Widget build(BuildContext context) {
    final uid = BffAuthService.instance.userId;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('게임 랭킹'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : DefaultTabController(
                  length: 4,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                        child: Text(
                          '서버에 동기화된 최고 기록 기준 실시간 랭킹입니다.',
                          style: AppTheme.bodyMedium.copyWith(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceCard,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: AppTheme.cardShadowSubtle,
                        ),
                        child: TabBar(
                          labelPadding: const EdgeInsets.symmetric(vertical: 8),
                          indicatorSize: TabBarIndicatorSize.tab,
                          tabs: const [
                            Tab(text: '1~30'),
                            Tab(text: '단어'),
                            Tab(text: '낙하'),
                            Tab(text: '타이밍'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _rankingTab(
                              title: '1부터 30까지 빠르게!',
                              subtitle: '최단 기록(초) 기준',
                              rows: _seqList,
                              uid: uid,
                              myRank: _mySeqRank,
                              myValueText: _mySeqSec != null && _mySeqSec!.isFinite
                                  ? '${_mySeqSec!.toStringAsFixed(2)}초'
                                  : '기록 없음',
                              showMyRankBanner: _mySeqRank != null && !_inTop10(_seqList, uid),
                              valueLabel: (r) {
                                final v = r['number_sequence_best_seconds'];
                                if (v == null) return '-';
                                return '${(v as num).toDouble().toStringAsFixed(2)}초';
                              },
                            ),
                            _rankingTab(
                              title: '단어맞추기',
                              subtitle: '최고 레벨 기준',
                              rows: _wordList,
                              uid: uid,
                              myRank: _myWordRank,
                              myValueText: 'Lv.${_myWordLevel ?? 1}',
                              showMyRankBanner: _myWordRank != null && !_inTop10(_wordList, uid),
                              valueLabel: (r) {
                                return 'Lv.${(r['word_game_level'] as num).toInt()}';
                              },
                            ),
                            _rankingTab(
                              title: '낙하 맞추기',
                              subtitle: '최고 점수 기준',
                              rows: _catchList,
                              uid: uid,
                              myRank: _myCatchRank,
                              myValueText: '${_myCatchScore ?? 0}점',
                              showMyRankBanner: _myCatchRank != null && !_inTop10(_catchList, uid),
                              valueLabel: (r) {
                                final v = r['cigarette_catch_best_score'];
                                return '${(v as num?)?.toInt() ?? 0}점';
                              },
                            ),
                            _rankingTab(
                              title: '완벽 타이밍',
                              subtitle: '최고 점수 기준',
                              rows: _timingList,
                              uid: uid,
                              myRank: _myTimingRank,
                              myValueText: '${_myTimingScore ?? 0}점',
                              showMyRankBanner: _myTimingRank != null && !_inTop10(_timingList, uid),
                              valueLabel: (r) {
                                final v = r['timing_tap_best_score'];
                                return '${(v as num?)?.toInt() ?? 0}점';
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _rankingTab({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> rows,
    required String? uid,
    required String Function(Map<String, dynamic>) valueLabel,
    required int? myRank,
    required String myValueText,
    required bool showMyRankBanner,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(title, style: AppTheme.titleMedium.copyWith(color: AppTheme.textPrimary)),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted, fontSize: 12),
          ),
          if (showMyRankBanner && myRank != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_rounded, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '내 순위: $myRank위 · $myValueText',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.primaryDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                '아직 기록이 없습니다.',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
                textAlign: TextAlign.center,
              ),
            )
          else
            ...List.generate(rows.length, (i) {
              final r = rows[i];
              final userId = r['user_id'] as String;
              final rank = i + 1;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppTheme.cardShadowSubtle,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '$rank',
                        style: AppTheme.titleMedium.copyWith(color: AppTheme.primary),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _nameFor(userId),
                        style: AppTheme.titleMedium.copyWith(fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      valueLabel(r),
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
