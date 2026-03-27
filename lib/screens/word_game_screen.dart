import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../ad_manager.dart';
import '../widgets/banner_ad_bar.dart';
import '../api/game_sync_helper.dart';

/// 7x8 그리드에 들어갈 수 있는 단어만 사용 (최대 길이 7)
class _WordPool {
  static const List<String> words3 = [
    'cat', 'dog', 'sun', 'run', 'man', 'car', 'day', 'way', 'boy', 'toy',
    'box', 'key', 'sea', 'tea', 'bed', 'red', 'big', 'hot', 'cut', 'get',
    'sit', 'eat', 'see', 'one', 'two', 'new', 'old', 'bad', 'good', 'top',
  ];
  static const List<String> words4 = [
    'book', 'tree', 'fish', 'bird', 'moon', 'star', 'fire', 'water', 'wind', 'snow',
    'love', 'home', 'work', 'play', 'time', 'life', 'hand', 'head', 'face', 'door',
    'room', 'wall', 'desk', 'ball', 'game', 'name', 'year', 'week', 'hour', 'food',
  ];
  static const List<String> words5 = [
    'apple', 'water', 'happy', 'light', 'night', 'right', 'black', 'white', 'green', 'brown',
    'table', 'chair', 'house', 'horse', 'music', 'paper', 'phone', 'world', 'heart', 'earth',
    'smile', 'cloud', 'river', 'beach', 'bread', 'fruit', 'grape', 'lemon', 'melon', 'peach',
  ];
  static const List<String> words6 = [
    'orange', 'purple', 'yellow', 'silver', 'garden', 'flower', 'summer', 'winter', 'spring', 'autumn',
    'dragon', 'castle', 'window', 'button', 'camera', 'guitar', 'dinner', 'friend', 'parent', 'animal',
    'number', 'letter', 'pencil', 'school', 'doctor', 'engine', 'pocket', 'bottle', 'circle',
  ];
  static const List<String> words7 = [
    'morning', 'evening', 'weather', 'kitchen', 'bicycle', 'holiday', 'picture', 'village', 'capital', 'history',
    'country', 'company', 'problem', 'example', 'machine', 'message', 'program', 'project', 'nothing', 'perfect',
  ];

  static List<String> getPoolForLevel(int level) {
    if (level <= 20) return [...words3, ...words4];
    if (level <= 50) return [...words4, ...words5];
    if (level <= 80) return [...words5, ...words6];
    return [...words6, ...words7];
  }

  static String getWord(int level, Random random) {
    final pool = getPoolForLevel(level);
    return pool[random.nextInt(pool.length)].toUpperCase();
  }

  /// 레벨별 단어 개수: 최소 4 ~ 최대 10
  static int wordsPerLevel(int level) {
    final n = 4 + ((level - 1) * 6 / 99).clamp(0, 6).toInt();
    return n.clamp(4, 10);
  }

  /// 그리드에 들어가는 단어만 (길이 ≤ maxLen)
  static String getWordForGrid(int level, Random random, int maxLen) {
    final pool = getPoolForLevel(level).where((w) => w.length <= maxLen).toList();
    if (pool.isEmpty) return getWord(level, random);
    return pool[random.nextInt(pool.length)].toUpperCase();
  }
}

/// 레벨별 그리드 크기 (cols, rows)
int _getGridCols(int level) {
  if (level <= 9) return 5;
  if (level <= 20) return 5;
  if (level <= 40) return 6;
  if (level <= 60) return 6;
  if (level <= 80) return 7;
  return 7;
}

int _getGridRows(int level) {
  if (level <= 9) return 4;
  if (level <= 20) return 5;
  if (level <= 40) return 5;
  if (level <= 60) return 6;
  if (level <= 80) return 6;
  return 7;
}

/// 8방향: 동서남북 + 대각선 (dr, dc)
const List<List<int>> _directions = [
  [0, 1],   // E
  [0, -1],  // W
  [1, 0],   // S
  [-1, 0],  // N
  [1, 1],   // SE
  [1, -1],  // SW
  [-1, 1],  // NE
  [-1, -1], // NW
];

class WordGameScreen extends StatefulWidget {
  const WordGameScreen({super.key});

  @override
  State<WordGameScreen> createState() => _WordGameScreenState();
}

class _WordGameScreenState extends State<WordGameScreen> {
  static const String _levelKey = 'word_game_level';
  static const double _cellGap = 6.0;
  final Random _random = Random();

  int _level = 1;
  int _rows = 4;
  int _cols = 5;
  List<String> _targetWords = [];
  Set<String> _foundWords = {};
  List<List<List<int>>> _foundPaths = []; // 맞춘 단어별 경로 → 그리드에 표시 유지
  List<List<String>> _grid = [];
  List<List<int>> _selectedPath = [];
  bool _isLevelAdShowing = false;

  @override
  void initState() {
    super.initState();
    _loadLevel();
  }

  Future<void> _loadLevel() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _level = (prefs.getInt(_levelKey) ?? 1).clamp(1, 100));
      _buildPuzzle();
    }
  }

  Future<void> _saveLevel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_levelKey, _level);
    unawaitedSyncGameStatsToApiIfAvailable();
  }

  void _buildPuzzle() {
    final effectiveLevel = _level.clamp(1, 100);
    _cols = _getGridCols(effectiveLevel);
    _rows = _getGridRows(effectiveLevel);
    final count = _WordPool.wordsPerLevel(effectiveLevel);
    final result = _generateGridWithWords(count, effectiveLevel);
    setState(() {
      _targetWords = result.$1;
      _foundWords = {};
      _foundPaths = [];
      _grid = result.$2;
      _selectedPath = [];
    });
  }

  /// 그리드 생성 시 배치에 성공한 단어만 목록에 넣어, 풀 수 없는 퍼즐이 나오지 않도록 함.
  (List<String>, List<List<String>>) _generateGridWithWords(int count, int level) {
    final maxLen = _rows < _cols ? _rows : _cols;
    final grid = List.generate(_rows, (_) => List.filled(_cols, ''));
    final targetList = <String>[];
    var attempts = 0;
    const maxAttempts = 500;
    while (targetList.length < count && attempts < maxAttempts) {
      attempts++;
      final word = _WordPool.getWordForGrid(level, _random, maxLen);
      if (targetList.contains(word)) continue;
      final placed = _placeWord(grid, word, _rows, _cols);
      if (placed) {
        targetList.add(word);
      }
    }
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        if (grid[r][c].isEmpty) {
          grid[r][c] = letters[_random.nextInt(26)];
        }
      }
    }
    return (targetList, grid);
  }

  /// 단어를 그리드에 배치 시도. 성공 시 true.
  bool _placeWord(List<List<String>> grid, String word, int rows, int cols) {
    final w = word.toUpperCase();
    final len = w.length;
    for (var attempt = 0; attempt < 80; attempt++) {
      final dr = _directions[_random.nextInt(_directions.length)];
      final r0 = _random.nextInt(rows);
      final c0 = _random.nextInt(cols);
      final r1 = r0 + (len - 1) * dr[0];
      final c1 = c0 + (len - 1) * dr[1];
      if (r1 < 0 || r1 >= rows || c1 < 0 || c1 >= cols) continue;
      bool ok = true;
      for (var i = 0; i < len; i++) {
        final r = r0 + i * dr[0];
        final c = c0 + i * dr[1];
        final current = grid[r][c];
        if (current.isNotEmpty && current != w[i]) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      for (var i = 0; i < len; i++) {
        grid[r0 + i * dr[0]][c0 + i * dr[1]] = w[i];
      }
      return true;
    }
    return false;
  }

  bool _isAdjacent(int r1, int c1, int r2, int c2) {
    final dr = (r2 - r1).abs();
    final dc = (c2 - c1).abs();
    return (dr <= 1 && dc <= 1) && (dr != 0 || dc != 0);
  }

  void _onPanStart(DragStartDetails details, int r, int c) {
    setState(() {
      _selectedPath = [[r, c]];
    });
  }

  void _onPanUpdate(DragUpdateDetails details, double cellSize, double offsetX, double offsetY) {
    if (_selectedPath.isEmpty) return;
    final local = details.localPosition;
    final step = cellSize + _cellGap;
    var c = ((local.dx - offsetX) / step).floor();
    var r = ((local.dy - offsetY) / step).floor();
    final inCellX = (local.dx - offsetX) - c * step < cellSize;
    final inCellY = (local.dy - offsetY) - r * step < cellSize;
    if (!inCellX || !inCellY) return;
    c = c.clamp(0, _cols - 1);
    r = r.clamp(0, _rows - 1);
    final last = _selectedPath.last;
    if (last[0] == r && last[1] == c) return;
    final existingIndex = _selectedPath.indexWhere((e) => e[0] == r && e[1] == c);
    if (existingIndex >= 0) {
      setState(() => _selectedPath = _selectedPath.sublist(0, existingIndex + 1));
      return;
    }
    if (!_isAdjacent(last[0], last[1], r, c)) return;
    // 동서남북/대각선 한 방향으로만 이어지도록: 이미 2칸 이상이면 방향이 같아야 함
    if (_selectedPath.length >= 2) {
      final dr0 = _selectedPath[1][0] - _selectedPath[0][0];
      final dc0 = _selectedPath[1][1] - _selectedPath[0][1];
      final dr = r - last[0];
      final dc = c - last[1];
      if (dr != dr0 || dc != dc0) return;
    }
    setState(() {
      _selectedPath = [..._selectedPath, [r, c]];
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_selectedPath.isEmpty) return;
    final word = _selectedPath.map((e) => _grid[e[0]][e[1]]).join();
    if (_targetWords.contains(word) && !_foundWords.contains(word)) {
      setState(() {
        _foundWords = {..._foundWords, word};
        _foundPaths = [..._foundPaths, List.from(_selectedPath)];
      });
      if (_foundWords.length == _targetWords.length) {
        _showCompleteDialog();
      }
    }
    setState(() => _selectedPath = []);
  }

  bool _isCellInFoundPaths(int r, int c) {
    for (final path in _foundPaths) {
      if (path.any((e) => e[0] == r && e[1] == c)) return true;
    }
    return false;
  }

  void _resetLevel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('레벨 초기화'),
        content: const Text('레벨 1부터 다시 시작하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _level = 1);
      await _saveLevel();
      _buildPuzzle();
    }
  }

  void _showCompleteDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('축하합니다!'),
        content: Text(
          '레벨 $_level 완료!\n\n다음 레벨에 도전해 보세요.',
          textAlign: TextAlign.center,
          style: AppTheme.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('나가기'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () {
              Navigator.pop(context);
              _goToNextLevel();
            },
            child: const Text('다음 레벨'),
          ),
        ],
      ),
    );
  }

  /// 5판마다 한 번씩만 광고 노출 후 다음 레벨로
  void _goToNextLevel() {
    final shouldShowAd = _level % 5 == 0;
    if (shouldShowAd) {
      if (_isLevelAdShowing) return;
      _isLevelAdShowing = true;
      AdManager.showAd(onAdClosed: () {
        if (!mounted) return;
        _isLevelAdShowing = false;
        setState(() => _level = (_level + 1).clamp(1, 100));
        _saveLevel();
        _buildPuzzle();
      });
    } else {
      setState(() => _level = (_level + 1).clamp(1, 100));
      _saveLevel();
      _buildPuzzle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLevel = _level.clamp(1, 100);
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('단어맞추기'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star_rounded, color: AppTheme.warning, size: 22),
                const SizedBox(width: 6),
                Text(
                  'Level ${effectiveLevel.toString().padLeft(2, '0')}',
                  style: AppTheme.titleLarge.copyWith(color: AppTheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _resetLevel,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('레벨 초기화'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_foundWords.length} / ${_targetWords.length}',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: _targetWords.map((w) {
                  final found = _foundWords.contains(w);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: found ? AppTheme.success.withOpacity(0.15) : AppTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: found ? AppTheme.success : AppTheme.textMuted.withOpacity(0.3),
                        width: found ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (found)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 18),
                          ),
                        Text(
                          w,
                          style: AppTheme.titleMedium.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: found ? AppTheme.success : AppTheme.textPrimary,
                            decoration: found ? TextDecoration.lineThrough : null,
                            decorationColor: AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _grid.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        const pad = 16.0;
                        final availableW = constraints.maxWidth - pad * 2;
                        final availableH = constraints.maxHeight;
                        final totalWWithGap = availableW;
                        final totalHWithGap = availableH;
                        final cellW = (totalWWithGap - (_cols - 1) * _cellGap) / _cols;
                        final cellH = (totalHWithGap - (_rows - 1) * _cellGap) / _rows;
                        final cellSize = cellW < cellH ? cellW : cellH;
                        final totalW = _cols * cellSize + (_cols - 1) * _cellGap;
                        final totalH = _rows * cellSize + (_rows - 1) * _cellGap;
                        final step = cellSize + _cellGap;
                        // 터치 좌표: GestureDetector localPosition은 그리드 Container 기준 (0,0)~(totalW,totalH)
                        const touchOffsetX = 0.0;
                        const touchOffsetY = 0.0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (d) {
                              final local = d.localPosition;
                              var c = ((local.dx - touchOffsetX) / step).floor();
                              var r = ((local.dy - touchOffsetY) / step).floor();
                              final inCellX = (local.dx - touchOffsetX) - c * step < cellSize && (local.dx - touchOffsetX) >= c * step;
                              final inCellY = (local.dy - touchOffsetY) - r * step < cellSize && (local.dy - touchOffsetY) >= r * step;
                              if (!inCellX || !inCellY) return;
                              c = c.clamp(0, _cols - 1);
                              r = r.clamp(0, _rows - 1);
                              if (r >= 0 && r < _rows && c >= 0 && c < _cols) {
                                _onPanStart(d, r, c);
                              }
                            },
                            onPanUpdate: (d) => _onPanUpdate(d, cellSize, touchOffsetX, touchOffsetY),
                            onPanEnd: _onPanEnd,
                            child: Container(
                              width: totalW,
                              height: totalH,
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Stack(
                                children: [
                                  CustomPaint(
                                    size: Size(totalW, totalH),
                                    painter: _GridPainter(
                                      grid: _grid,
                                      selectedPath: _selectedPath,
                                      foundPaths: _foundPaths,
                                      cellSize: cellSize,
                                      cellGap: _cellGap,
                                    ),
                                  ),
                                  for (var r = 0; r < _rows; r++)
                                    for (var c = 0; c < _cols; c++)
                                      Positioned(
                                        left: c * step + 2,
                                        top: r * step + 2,
                                        width: cellSize - 4,
                                        height: cellSize - 4,
                                        child: Center(
                                          child: Text(
                                            _grid[r][c],
                                            style: TextStyle(
                                              fontSize: (cellSize - 10).clamp(12.0, 22.0),
                                              fontWeight: FontWeight.w600,
                                              color: _selectedPath.any((e) => e[0] == r && e[1] == c)
                                                  ? Colors.white
                                                  : _isCellInFoundPaths(r, c)
                                                      ? AppTheme.success
                                                      : AppTheme.textPrimary,
                                            ),
                                          ),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              '손가락으로 드래그해서 알파벳을 연결하세요',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            const BannerAdBar(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 그리드 배경 + 선택/맞춘 경로 하이라이트 (칸 사이 여백 적용)
class _GridPainter extends CustomPainter {
  final List<List<String>> grid;
  final List<List<int>> selectedPath;
  final List<List<List<int>>> foundPaths;
  final double cellSize;
  final double cellGap;

  _GridPainter({
    required this.grid,
    required this.selectedPath,
    required this.foundPaths,
    required this.cellSize,
    required this.cellGap,
  });

  bool _isFound(int r, int c) {
    for (final path in foundPaths) {
      if (path.any((e) => e[0] == r && e[1] == c)) return true;
    }
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final step = cellSize + cellGap;
    for (var r = 0; r < grid.length; r++) {
      for (var c = 0; c < grid[r].length; c++) {
        final x = c * step;
        final y = r * step;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 1, y + 1, cellSize - 2, cellSize - 2),
          const Radius.circular(10),
        );
        final isSelected = selectedPath.any((e) => e[0] == r && e[1] == c);
        final isFound = _isFound(r, c);
        Color fill;
        if (isSelected) {
          fill = AppTheme.primary;
        } else if (isFound) {
          fill = AppTheme.success.withOpacity(0.25);
        } else {
          fill = Colors.white;
        }
        canvas.drawRRect(rect, Paint()..color = fill);
        canvas.drawRRect(
          rect,
          Paint()
            ..color = isFound
                ? AppTheme.success.withOpacity(0.5)
                : isSelected
                    ? AppTheme.primary
                    : AppTheme.textMuted.withOpacity(0.2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = isFound ? 1.5 : 1,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) {
    return old.selectedPath.length != selectedPath.length ||
        old.foundPaths.length != foundPaths.length ||
        old.grid != grid;
  }
}
