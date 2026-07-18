import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 도움말 화면: 사용 설명서 + 자주 묻는 질문
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('도움말'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const SizedBox(height: 8),
            _sectionTitle('사용 설명서'),
            _helpCard(
              context,
              icon: Icons.menu_book_rounded,
              title: '금연 앱 사용 설명서',
              subtitle: '메인·레포트·패턴 알림·공유 등 주요 기능을 안내합니다.',
              onTap: () => _showManualContent(context),
            ),
            const SizedBox(height: 24),
            _sectionTitle('자주 묻는 질문'),
            ..._faqItems.map((item) => _FaqTile(question: item.question, answer: item.answer)),
          ],
        ),
      ),
    );
  }

  void _showManualContent(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    MediaQuery.of(context).padding.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('금연 앱 사용 설명서', style: AppTheme.titleLarge),
                      const SizedBox(height: 16),
                      _manualSection(
                        '홈 화면',
                        '「홈」 탭에서 금연 일수·시간·절약 금액·참은 개비를 한 카드로 확인합니다. 「이대로 유지하면」에서 1주~20년 미래 절약 시뮬레이션을 볼 수 있어요. 「흡연 기록」「욕구 기록」으로 패턴을 남기고, 「알림 설정」에서 리마인드를 추가할 수 있습니다. 상단 공유 버튼으로 금연 현황을 지인에게 보낼 수 있어요.',
                      ),
                      _manualSection(
                        '나의 레포트',
                        '「레포트」 탭에서 흡연·욕구 기록을 주간·월간으로 확인합니다. 전체/흡연/욕구 필터로 패턴을 나눠 볼 수 있고, 시간대·상황·감정 차트와 「카톡으로 공유」로 응원을 받을 수 있어요.',
                      ),
                      _manualSection(
                        '흡연·욕구 기록과 패턴 알림',
                        '흡연 후 「흡연 기록」, 강한 욕구가 올 때 「욕구 기록」, 못참겠어요에서 「결국 피웠어요」로 남긴 기록이 패턴 알림 분석에 반영됩니다. 최근 30일 안에 3건 이상 쌓이면 평균 시간대로 자동 알림이 예약될 수 있습니다. 설정 > 알림 해지에서 패턴 알림을 끌 수 있어요.',
                      ),
                      _manualSection(
                        '더보기',
                        '「더보기」 탭에서 담타시간(커뮤니티), 건강 개선 현황, 금연할 이유 목록에 들어갈 수 있습니다.',
                      ),
                      _manualSection(
                        '알림',
                        '홈의 「알림 설정」 또는 설정 > 알림에서 원하는 시간을 추가할 수 있습니다. 비접속·출석·패턴 알림은 설정 > 알림 해지에서 관리합니다. 금연 이유 알림(매일 12:01)도 함께 사용할 수 있어요.',
                      ),
                      _manualSection(
                        '목표일 달성',
                        '홈 히어로 카드에서 목표일을 설정하면 진행률이 표시됩니다. 목표에 도달하면 앱 안 축하 메시지와 알림이 한 번 표시됩니다.',
                      ),
                      _manualSection(
                        '그룹 금연방',
                        '더보기 > 금연방에서 혼자 또는 그룹으로 금연방을 만들 수 있어요. 사진은 업로드 후 90일 동안 보관되며, 이후에는 글은 남고 사진만 삭제됩니다. 글은 최대 1년까지 보관됩니다. 방당 월 300장, 하루 10장까지 사진을 올릴 수 있어요.',
                      ),
                      _manualSection(
                        '설정',
                        '알림, 튜토리얼 다시 보기, 내 설정값 변경, 처음부터 다시 시작, 도움말, 앱 정보 등을 설정에서 관리합니다.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _manualSection(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.titleMedium.copyWith(fontSize: 16)),
          const SizedBox(height: 6),
          Text(body, style: AppTheme.bodyMedium),
        ],
      ),
    );
  }

  static final List<({String question, String answer})> _faqItems = [
    (
      question: '금연 시작일을 바꾸고 싶어요.',
      answer:
          '설정 > 내 설정값 변경에서 흡연량·가격 등을 바꿀 수 있으며, 금연 기록은 유지됩니다. 처음부터 다시 시작하면 모든 기록이 초기화되고 처음 설정 화면부터 다시 진행합니다.'
    ),
    (
      question: '알림이 오지 않아요.',
      answer:
          '홈의 「알림 설정」 또는 설정 > 알림에서 시간을 추가했는지, 설정 > 알림 해지에서 비접속·출석·패턴 알림이 켜져 있는지, 기기 알림 권한이 허용되어 있는지 확인해 주세요.'
    ),
    (
      question: '패턴 알림이란 무엇이고, 언제 생기나요?',
      answer:
          '「흡연 기록」「욕구 기록」, 못참겠어요의 「결국 피웠어요」 기록으로 시간대·상황·감정을 남기면 패턴이 쌓입니다. 최근 30일 안에 3건 이상이면 평균 시간대로 자동 알림이 예약될 수 있습니다. 설정 > 알림 해지에서 끌 수 있어요.'
    ),
    (
      question: '나의 레포트에서는 무엇을 볼 수 있나요?',
      answer:
          '「레포트」 탭에서 흡연·욕구 기록을 주간·월간으로 모아 볼 수 있습니다. 전체/흡연/욕구 필터와 시간대·상황·감정 차트, 「카톡으로 공유」를 이용할 수 있어요.'
    ),
    (
      question: '앱을 지인에게 추천하고 싶어요.',
      answer:
          '홈 상단 공유 아이콘을 누르면 금연 일수·절약 금액이 담긴 문구와 스토어 링크가 준비됩니다.'
    ),
    (
      question: '금연 이유 알림(매일 12:01) 내용을 바꾸고 싶어요.',
      answer:
          '더보기 > 금연할 이유에서 새 이유를 작성한 뒤, 종 아이콘으로 알림에 사용할 이유를 선택해 주세요.'
    ),
    (
      question: '연속 모드와 재시작 모드 차이는?',
      answer:
          '연속 모드(기본)는 흡연 기록을 남겨도 금연일·절약·개비가 유지됩니다. 재시작 모드는 흡연 기록 시 금연일·절약·개비·목표 진행률이 0부터 다시 시작됩니다. 패턴·레포트 기록은 두 모드 모두 유지돼요. 설정 > 금연 모드에서 변경할 수 있으며, 7일에 한 번 변경할 수 있습니다.'
    ),
    (
      question: '흡연 기록 후에 금연 시간은 그대로인가요?',
      answer:
          '금연 모드에 따라 달라요. 연속 모드에서는 금연 시작 시각부터 이어지는 타이머가 유지됩니다. 재시작 모드에서는 흡연 기록 시 금연일·절약·개비가 0부터 다시 시작됩니다. 「욕구 기록」만으로는 흡연 횟수가 늘지 않습니다.'
    ),
    (
      question: '금연방 사진은 얼마나 보관되나요?',
      answer:
          '금연방에 올린 사진은 90일 동안 보관된 뒤 삭제되고, 글 내용은 그대로 남습니다. 글 전체는 최대 1년까지 보관됩니다. 방당 한 달 300장, 하루 10장까지 업로드할 수 있어요.'
    ),
    (
      question: '앱을 삭제하거나 기기를 바꾸면 데이터가 사라지나요?',
      answer:
          '로그인하지 않은 상태라면 데이터가 기기에 저장되어 앱 삭제·기기 교체 시 일부 기록이 사라질 수 있습니다. 로그인 상태에서는 서버 동기화로 복구되는 항목이 많습니다.'
    ),
  ];

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: AppTheme.labelMedium.copyWith(
          color: AppTheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _helpCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.cardShadowSubtle,
      ),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primary, size: 28),
        title: Text(title, style: AppTheme.titleMedium.copyWith(fontSize: 16)),
        subtitle: Text(subtitle, style: AppTheme.bodyMedium),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.cardShadowSubtle,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: AppTheme.titleMedium.copyWith(fontSize: 15),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                widget.answer,
                style: AppTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}
