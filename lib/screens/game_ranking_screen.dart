import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_config.dart';
import '../theme/app_theme.dart';

/// 미니게임 4종 랭킹 (상위 10명 + 본인 순위).
/// DB의 [game_leaderboard_daily] 일일 스냅샷을 우선 사용하고, 없으면 game_stats 실시간 집계로 대체.
class GameRankingScreen extends StatefulWidget {
  const GameRankingScreen({super.key});

  @override
  State<GameRankingScreen> createState() => _GameRankingScreenState();
}

class _GameRankingScreenState extends State<GameRankingScreen> {
  bool _loading = true;
  String? _error;
  bool _usingDailySnapshot = false;

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

  /// 한국 날짜(UTC+9) 기준 오늘 — 스냅샷 snapshot_date와 동일
  static String _kstDateString() {
    final kst = DateTime.now().toUtc().add(const Duration(hours: 9));
    return '${kst.year}-${kst.month.toString().padLeft(2, '0')}-${kst.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!SupabaseConfig.isConfigured) {
      setState(() {
        _loading = false;
        _error = 'Supabase가 설정되지 않았습니다.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final client = Supabase.instance.client;
    final prefs = await SharedPreferences.getInstance();
    final uid = client.auth.currentUser?.id;

    final mySeq = prefs.getDouble('bestRecord');
    final myWord = prefs.getInt('word_game_level') ?? 1;
    final myCatch = prefs.getInt('cigarette_catch_best_score') ?? 0;
    final myTiming = prefs.getInt('timing_tap_best_score') ?? 0;

    final snapshotDate = _kstDateString();

    try {
      var hasDaily = false;
      try {
        final probe = await client
            .from('game_leaderboard_daily')
            .select('id')
            .eq('snapshot_date', snapshotDate)
            .limit(1);
        hasDaily = (probe as List).isNotEmpty;
      } catch (_) {
        hasDaily = false;
      }

      if (hasDaily) {
        await _loadFromDailySnapshot(
          client,
          snapshotDate: snapshotDate,
          prefs: prefs,
          uid: uid,
        );
      } else {
        await _loadFromLiveGameStats(
          client,
          prefs: prefs,
          uid: uid,
        );
      }

      if (!mounted) return;
      setState(() {
        _mySeqSec = mySeq;
        _myWordLevel = myWord;
        _myCatchScore = myCatch;
        _myTimingScore = myTiming;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '랭킹을 불러오지 못했습니다.';
        });
      }
    }
  }

  Future<void> _loadFromDailySnapshot(
    SupabaseClient client, {
    required String snapshotDate,
    required SharedPreferences prefs,
    required String? uid,
  }) async {
    Future<List<Map<String, dynamic>>> top10(String kind) async {
      final res = await client
          .from('game_leaderboard_daily')
          .select('user_id, rank, metric_value, display_name')
          .eq('snapshot_date', snapshotDate)
          .eq('game_kind', kind)
          .lte('rank', 10)
          .order('rank');
      return List<Map<String, dynamic>>.from(res as List);
    }

    _seqList = await top10('number_sequence');
    _wordList = await top10('word_game');
    _catchList = await top10('cigarette_catch');
    _timingList = await top10('timing_tap');

    _displayNames = {};
    for (final list in [_seqList, _wordList, _catchList, _timingList]) {
      for (final r in list) {
        final id = r['user_id'] as String?;
        final dn = r['display_name'] as String?;
        if (id != null) {
          _displayNames[id] = (dn != null && dn.trim().isNotEmpty) ? dn.trim() : null;
        }
      }
    }

    Future<int?> myRank(String kind) async {
      if (uid == null) return null;
      final row = await client
          .from('game_leaderboard_daily')
          .select('rank')
          .eq('snapshot_date', snapshotDate)
          .eq('game_kind', kind)
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      return (row['rank'] as num).toInt();
    }

    _mySeqRank = await myRank('number_sequence');
    _myWordRank = await myRank('word_game');
    _myCatchRank = await myRank('cigarette_catch');
    _myTimingRank = await myRank('timing_tap');

    _usingDailySnapshot = true;
  }

  Future<void> _loadFromLiveGameStats(
    SupabaseClient client, {
    required SharedPreferences prefs,
    required String? uid,
  }) async {
    final mySeq = prefs.getDouble('bestRecord');
    final myWord = prefs.getInt('word_game_level') ?? 1;
    final myCatch = prefs.getInt('cigarette_catch_best_score') ?? 0;
    final myTiming = prefs.getInt('timing_tap_best_score') ?? 0;

    final seqRes = await client
        .from('game_stats')
        .select('user_id, number_sequence_best_seconds')
        .not('number_sequence_best_seconds', 'is', null)
        .order('number_sequence_best_seconds', ascending: true)
        .limit(10);

    final wordRes = await client
        .from('game_stats')
        .select('user_id, word_game_level')
        .order('word_game_level', ascending: false)
        .limit(10);

    final catchRes = await client
        .from('game_stats')
        .select('user_id, cigarette_catch_best_score')
        .order('cigarette_catch_best_score', ascending: false)
        .limit(10);

    final timingRes = await client
        .from('game_stats')
        .select('user_id, timing_tap_best_score')
        .order('timing_tap_best_score', ascending: false)
        .limit(10);

    _seqList = List<Map<String, dynamic>>.from(seqRes as List);
    _wordList = List<Map<String, dynamic>>.from(wordRes as List);
    _catchList = List<Map<String, dynamic>>.from(catchRes as List);
    _timingList = List<Map<String, dynamic>>.from(timingRes as List);

    final ids = <String>{};
    for (final r in [..._seqList, ..._wordList, ..._catchList, ..._timingList]) {
      final id = r['user_id'] as String?;
      if (id != null) ids.add(id);
    }

    _displayNames = {};
    if (ids.isNotEmpty) {
      final profRes = await client
          .from('profiles')
          .select('id, display_name')
          .inFilter('id', ids.toList());
      for (final p in profRes as List) {
        final id = p['id'] as String;
        final dn = p['display_name'] as String?;
        _displayNames[id] = (dn != null && dn.trim().isNotEmpty) ? dn.trim() : null;
      }
    }

    int? seqRank;
    if (mySeq != null && mySeq.isFinite && !mySeq.isNaN) {
      final better = await client
          .from('game_stats')
          .select('user_id')
          .lt('number_sequence_best_seconds', mySeq)
          .not('number_sequence_best_seconds', 'is', null);
      seqRank = (better as List).length + 1;
    }

    final betterWord = await client
        .from('game_stats')
        .select('user_id')
        .gt('word_game_level', myWord);
    final wordRank = (betterWord as List).length + 1;

    final betterCatch = await client
        .from('game_stats')
        .select('user_id')
        .gt('cigarette_catch_best_score', myCatch);
    final catchRank = (betterCatch as List).length + 1;

    final betterTiming = await client
        .from('game_stats')
        .select('user_id')
        .gt('timing_tap_best_score', myTiming);
    final timingRank = (betterTiming as List).length + 1;

    _mySeqRank = seqRank;
    _myWordRank = wordRank;
    _myCatchRank = catchRank;
    _myTimingRank = timingRank;
    _usingDailySnapshot = false;
  }

  bool _inTop10(List<Map<String, dynamic>> list, String? uid) {
    if (uid == null) return false;
    return list.any((e) => e['user_id'] == uid);
  }

  String _nameFor(Map<String, dynamic> r, String userId) {
    if (_usingDailySnapshot) {
      final dn = r['display_name'] as String?;
      if (dn != null && dn.isNotEmpty) return dn;
      return '익명';
    }
    final n = _displayNames[userId];
    if (n != null && n.isNotEmpty) return n;
    return '익명';
  }

  int _rowRank(Map<String, dynamic> r, int index) {
    final rk = r['rank'];
    if (rk is num) return rk.toInt();
    return index + 1;
  }

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;

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
                          _usingDailySnapshot
                              ? '순위는 매일 한국 자정에 확정됩니다. 오늘 표시는 자정 스냅샷 기준입니다.'
                              : '오늘 스냅샷이 아직 없어 실시간 기록으로 표시 중입니다. (자정 이후 스냅샷 생성)',
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
                            Tab(text: '담배'),
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
                                if (_usingDailySnapshot) {
                                  final v = r['metric_value'];
                                  return '${(v as num).toDouble().toStringAsFixed(2)}초';
                                }
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
                                if (_usingDailySnapshot) {
                                  return 'Lv.${(r['metric_value'] as num).toInt()}';
                                }
                                return 'Lv.${(r['word_game_level'] as num).toInt()}';
                              },
                            ),
                            _rankingTab(
                              title: '담배맞추기',
                              subtitle: '최고 점수 기준',
                              rows: _catchList,
                              uid: uid,
                              myRank: _myCatchRank,
                              myValueText: '${_myCatchScore ?? 0}점',
                              showMyRankBanner: _myCatchRank != null && !_inTop10(_catchList, uid),
                              valueLabel: (r) {
                                if (_usingDailySnapshot) {
                                  return '${(r['metric_value'] as num).toInt()}점';
                                }
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
                                if (_usingDailySnapshot) {
                                  return '${(r['metric_value'] as num).toInt()}점';
                                }
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
              final rank = _rowRank(r, i);
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
                        _nameFor(r, userId),
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
