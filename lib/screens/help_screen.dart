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
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          const SizedBox(height: 8),
          _sectionTitle('사용 설명서'),
          _helpCard(
            context,
            icon: Icons.menu_book_rounded,
            title: '금연 앱 사용 설명서',
            subtitle: '앱의 주요 기능과 사용 방법을 안내합니다.',
            onTap: () => _showManualContent(context),
          ),
          const SizedBox(height: 24),
          _sectionTitle('자주 묻는 질문'),
          ..._faqItems.map((item) => _FaqTile(question: item.question, answer: item.answer)),
        ],
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
                      _manualSection('메인 화면', '금연 시작일, 누적 일수, 금연 시간, 절약 금액, 안 핀 담배 수를 한눈에 볼 수 있습니다. 알림 설정과 욕구 참기, 금연 리셋, 금연할 이유·금연 도우미로 이동할 수 있습니다.'),
                      _manualSection('게임', '1부터 30까지 숫자를 순서대로 빠르게 누르는 게임입니다. 집중력을 키우고 금연 스트레스를 풀 수 있습니다.'),
                      _manualSection('나의 성장 나무', '금연을 지키는 동안 물을 주면 나무가 자랍니다. 2분마다 물이 1ml씩 차며, 10ml·100ml 단위로 나무에 줄 수 있습니다. 5단계까지 성장합니다.'),
                      _manualSection('나의 폐', '금연 기간에 따라 폐 회복 상태를 확인할 수 있습니다. 흡연 시 건강도가 감소하고, 금연을 유지하면 1시간마다 1%씩 회복됩니다.'),
                      _manualSection('흡연하지 마세요', '흡연 습관을 되새기기 위한 화면입니다. 버튼을 누르면 애니메이션이 재생되며, 건강을 위해 흡연을 멈추자는 메시지를 전달합니다.'),
                      _manualSection('건강', '금연 경과 시간에 따른 건강 개선 단계(20분, 8시간, 24시간, 48시간, 72시간, 2주~3개월, 1~9개월, 1년)를 확인할 수 있습니다.'),
                      _manualSection('설정', '알림 시간 설정, 초기 설정으로 돌아가기, 앱 정보, 도움말, 개인정보처리방침, 금연 뱃지 등을 이용할 수 있습니다.'),
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
    (question: '금연 시작일을 바꾸고 싶어요.', answer: '설정 > 초기 설정으로 돌아가기를 선택하면 처음 설정 화면부터 다시 진행할 수 있습니다. 단, 진행 기록(나무, 폐 건강, 게임 기록 등)은 유지됩니다. 완전 초기화를 원하시면 앱을 삭제 후 재설치해야 합니다.'),
    (question: '알림이 오지 않아요.', answer: '설정 > 알림에서 원하는 시간을 선택한 뒤, 기기의 알림 권한이 허용되어 있는지 확인해주세요. 배터리 최적화로 인해 알림이 지연될 수 있으므로, 앱에 배터리 제한 예외를 두는 것을 권장합니다.'),
    (question: '나의 성장 나무는 어떻게 키우나요?', answer: '2분마다 물이 1ml씩 자동으로 쌓입니다. 메인 화면이나 나무 화면을 자주 열어두면 물이 차고, 10ml·100ml 버튼으로 나무에 물을 줄 수 있습니다. 꾸준히 물을 주면 5단계까지 성장합니다.'),
    (question: '금연 뱃지는 어떻게 받나요?', answer: '설정 > 금연 뱃지에서 확인할 수 있습니다. 피우지 않은 담배 개수나 금연 일수가 조건을 충족하면 자동으로 뱃지가 활성화됩니다. 앱을 사용하며 금연을 이어가면 더 많은 뱃지를 획득할 수 있습니다.'),
    (question: '앱을 삭제하거나 기기를 바꾸면 데이터가 사라지나요?', answer: '네. 현재 데이터는 기기 안에만 저장됩니다. 앱을 삭제하거나 기기를 교체하면 기록은 복구할 수 없습니다. 중요한 기록은 스크린샷 등으로 따로 보관해 두시는 것을 권장합니다.'),
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
