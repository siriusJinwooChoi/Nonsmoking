/// 공개 채팅용: 금칙어를 [replacement]로 치환합니다. 목록은 정책에 맞게 확장하세요.
abstract final class ProfanityFilter {
  static const String replacement = '나쁜말';

  static const List<String> _badWords = [
    '시발',
    '씨발',
    '시팔',
    'ㅅㅂ',
    'ㅆㅂ',
    '개새끼',
    '개새',
    '병신',
    'ㅂㅅ',
    '지랄',
    'ㅈㄹ',
    '좆',
    '좃',
    '섹스',
    '섹1스',
    '성관계',
    '보지',
    '자지',
    '뷰지',
    '쥬지',
    '야동',
    '야사',
    '자위',
    '딸딸이',
    '꼴림',
    '꼴려',
    'fuck',
    'shit',
    'porn',
    'bitch',
    'dick',
    'cock',
    'asshole',
    'nazi',
    'fuk',
    'fck',
  ];

  /// 금칙어 부분을 [replacement]로 바꾼 문자열을 반환합니다.
  static String sanitize(String input) {
    var out = input;
    final sorted = [..._badWords]..sort((a, b) => b.length.compareTo(a.length));
    for (final w in sorted) {
      if (w.isEmpty) continue;
      final isAscii = RegExp(r'^[a-zA-Z]+$').hasMatch(w);
      final pattern = isAscii
          ? RegExp(RegExp.escape(w), caseSensitive: false)
          : RegExp(RegExp.escape(w));
      out = out.replaceAll(pattern, replacement);
    }
    return out;
  }
}
