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
              subtitle: '앱의 주요 기능과 사용 방법을 안내합니다.',
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
                        '메인 화면',
                        '금연 시작일, 누적일, 목표일, 실시간 금연 시간, 절약 금액, 안 핀 담배 수, 실패 횟수, 금연코인을 한눈에 볼 수 있습니다. 목표일·실패 횟수는 노란색 밑줄로 표시되며, 실패 횟수를 누르면 금연코인 5개로 1회 차감할 수 있습니다(코인 부족 시 불가). 금연 이유, 흡연 욕구, 담배 피움, 금연 리셋, 전체 알림 끄기, 건강·나무·폐·담배 수집 화면 등으로 이동할 수 있습니다.',
                      ),
                      _manualSection(
                        '금연코인',
                        '출석체크를 하면 매일 금연코인을 받을 수 있습니다(1~6일차 15코인, 7·14·21·28일차 20코인). 로그인한 상태에서 미니게임을 플레이하면 서버 검증을 거쳐 종목당 하루 한 번 금연코인 보상을 받을 수 있습니다. 금연코인은 담배 수집 시 1회 시도할 때마다 2코인이 소모되며, 메인 화면에서 실패 횟수를 1회 줄일 때 5코인이 소모됩니다. 코인이 부족하면 해당 기능을 사용할 수 없습니다.',
                      ),
                      _manualSection(
                        '알림',
                        '설정 > 알림에서 원하는 시간대를 여러 개 추가해 금연 리마인드 알림을 받을 수 있습니다. 또한 내가 선택한 금연 이유 알림(매일 12:00)과 3일 이상 앱에 접속하지 않았을 때 알려주는 비접속 알림을 각각 켜고 끌 수 있습니다.',
                      ),
                      _manualSection(
                        '금연 이유',
                        '금연하는 개인적인 이유를 여러 개 작성하고, 별표로 고정하거나 종 아이콘으로 알림에 사용할 이유를 선택할 수 있습니다. 선택된 이유는 매일 점심시간 알림 내용에 함께 표시되어 금연 의지를 유지하는 데 도움을 줍니다.',
                      ),
                      _manualSection(
                        '흡연 욕구',
                        '메인 화면의 흡연 욕구 버튼을 누르면 지금까지의 금연 시간, 절약 금액, 안 핀 담배 수, 내가 선택한 금연 이유, 응원 문구가 함께 표시됩니다. 흡연 욕구가 올라올 때마다 이 화면을 열어 현재 성과를 확인해 보세요.',
                      ),
                      _manualSection(
                        '담배 피움 / 실패 횟수',
                        '담배 피움 버튼이나 폐 화면의 흡연 버튼을 누르면 실패 횟수가 1회 증가하고 폐 건강이 감소합니다. 실패 횟수는 메인 화면에서 노란색 밑줄로 표시되며, 탭하면 금연코인 5개로 1회 차감할 수 있습니다(코인 부족 시 불가). 연속 금연 시간은 유지되어 “다시 시작하는 금연”에 집중할 수 있도록 설계되어 있습니다. 실패 후에는 위로 메시지와 함께 다시 시작을 도와줍니다.',
                      ),
                      _manualSection(
                        '담배 수집',
                        '담배 수집은 09:00~09:20, 12:00~12:20, 18:00~18:20, 22:00~22:20에만 가능합니다. 각 시간대마다 한 번만 시도할 수 있으며(성공 또는 5번 실패 후 해당 구간 종료), 1회 시도할 때마다 금연코인 2개가 소모됩니다. 위 시간이 아니거나 이미 사용한 경우 수집이 비활성화되며, 도감은 언제든 열 수 있습니다. 09:00·12:00·18:00·22:00 정각에 담배 수집 가능 알림이 옵니다.',
                      ),
                      _manualSection(
                        '나의 성장 나무',
                        '금연을 지키는 동안 2분마다 물이 1ml씩 자동으로 쌓입니다. 10ml·100ml 단위로 나무에 물을 줄 수 있고, 꾸준히 물을 주면 최대 5단계까지 성장합니다. 나무의 성장 과정을 통해 금연 기간을 시각적으로 느낄 수 있습니다.',
                      ),
                      _manualSection(
                        '나의 폐',
                        '금연 기간에 따라 폐 회복 상태를 퍼센트로 확인할 수 있습니다. 담배를 피우면 건강도가 일정 비율 감소하고, 금연을 유지하면 시간이 지나며 서서히 회복됩니다. 폐 그림과 애니메이션을 통해 변화 과정을 직관적으로 볼 수 있습니다.',
                      ),
                      _manualSection(
                        '건강',
                        '금연 경과 시간에 따른 대표적인 건강 개선 단계(20분, 8시간, 24시간, 48시간, 72시간, 2주~3개월, 1~9개월, 1년 등)를 확인할 수 있습니다. 각 단계별로 몸에서 일어나는 변화를 설명해 주어, 금연이 몸에 어떤 변화를 가져오는지 쉽게 이해할 수 있습니다.',
                      ),
                      _manualSection(
                        '게임',
                        '1부터 30까지 순서대로 숫자를 빠르게 누르는 숫자 게임, 섞인 글자를 연결해 찾는 단어맞추기, 움직이는 표시가 중앙에 올 때 탭하는 완벽 타이밍, 떨어지는 담배를 맞추는 담배맞추기 게임을 즐길 수 있습니다. 기록은 기기에 저장되며, 로그인 시 서버와 동기화됩니다. 간단한 조작으로 집중력을 높이고 금연 스트레스를 해소해 보세요.',
                      ),
                      _manualSection(
                        '위젯',
                        '홈 화면 위젯을 추가하면 앱을 열지 않아도 금연 시간, 절약 금액, 안 핀 담배 수, 폐 건강을 바로 확인할 수 있습니다. 여러 크기의 위젯을 지원하며, 앱 내용이 변경되면 위젯에도 최대한 빠르게 반영됩니다.',
                      ),
                      _manualSection(
                        '설정',
                        '알림 시간, 비접속 시 알림, 출석 알림(저녁 6시 미출석 시 10분마다) 설정, 초기 설정으로 돌아가기, 개인정보처리방침·이용약관, 금연 뱃지, 도움말 등을 확인할 수 있습니다. 추후 계정/백업 기능 추가 시에도 이 메뉴를 통해 관리하게 됩니다.',
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
          '설정 > 초기 설정으로 돌아가기를 선택하면 처음 설정 화면부터 다시 진행할 수 있습니다. 단, 진행 기록(나무, 폐 건강, 게임 기록 등)은 유지됩니다. 완전 초기화를 원하시면 앱을 삭제 후 재설치해야 합니다.'
    ),
    (
      question: '알림이 오지 않아요.',
      answer:
          '설정 > 알림에서 원하는 시간대를 추가했는지, 기기의 알림 권한이 허용되어 있는지 먼저 확인해주세요. 배터리 최적화나 절전 모드, 백그라운드 제한으로 인해 알림이 지연될 수 있으므로, 기기 설정에서 금연뱅크 앱을 최적화 예외/제한 없음으로 설정해 두는 것을 권장합니다.'
    ),
    (
      question: '3일 이상 앱을 열지 않았을 때 오는 비접속 알림을 끄고 싶어요.',
      answer:
          '설정 > 비접속 시 알림에서 스위치를 끄면 더 이상 “금연은 잘 하고 계신가요?” 알림이 오지 않습니다. 다시 동기부여가 필요할 때는 언제든지 같은 메뉴에서 다시 켤 수 있습니다.'
    ),
    (
      question: '금연 이유 알림(매일 12:00) 내용을 바꾸고 싶어요.',
      answer:
          '메인 화면에서 “금연할 이유”로 들어가 새 이유를 작성한 뒤, 종 아이콘을 눌러 알림에 사용할 이유를 선택해주세요. 선택된 이유는 매일 점심시간 알림에 함께 표시되며, 언제든지 다른 이유로 변경할 수 있습니다.'
    ),
    (
      question: '나의 성장 나무는 어떻게 키우나요?',
      answer:
          '2분마다 물이 1ml씩 자동으로 쌓입니다. 메인 화면이나 나무 화면에서 물이 충분히 쌓였는지 확인한 뒤, 10ml·100ml 버튼으로 나무에 물을 줄 수 있습니다. 꾸준히 물을 주면 5단계까지 성장하며, 성장 단계는 금연 기간과 함께 유지됩니다.'
    ),
    (
      question: '담배 피움 버튼을 눌렀는데 실패 횟수만 늘고 금연 시간이 초기화되지 않아요.',
      answer:
          '금연뱅크는 “완벽한 금연”보다 “다시 시작하는 금연”에 초점을 두고 있습니다. 담배 피움 버튼이나 폐 화면의 흡연 버튼을 눌러도 연속 금연 시간은 유지되고, 대신 실패 횟수와 폐 건강에만 반영됩니다. 부담을 줄이고 다시 시작하기 쉽게 하기 위한 의도입니다.'
    ),
    (
      question: '금연 뱃지는 어떻게 받나요?',
      answer:
          '설정 > 금연 뱃지에서 획득 조건을 확인할 수 있습니다. 피우지 않은 담배 개수, 금연 일수, 누적 절약 금액 등의 조건을 충족하면 자동으로 뱃지가 활성화됩니다. 앱을 꾸준히 사용하며 금연을 이어가면 더 많은 뱃지를 모을 수 있습니다.'
    ),
    (
      question: '금연코인은 어떻게 받고 어디에 쓰나요?',
      answer:
          '출석체크를 하면 매일 금연코인을 받습니다(1~6일차 15코인, 7·14·21·28일차 20코인). 로그인 후 미니게임을 하면 서버에서 종목당 하루 한 번 보상 코인을 지급할 수 있습니다. 금연코인은 담배 수집 시 1회 시도할 때마다 2코인, 메인 화면에서 실패 횟수를 1회 줄일 때 5코인이 소모됩니다. 코인이 부족하면 해당 기능을 사용할 수 없습니다.'
    ),
    (
      question: '담배 수집은 언제 할 수 있나요?',
      answer:
          '담배 수집은 09:00~09:20, 12:00~12:20, 18:00~18:20, 22:00~22:20에만 가능합니다. 각 시간대마다 한 번만 시도할 수 있고(성공 또는 5번 실패 후 종료), 1회 시도마다 금연코인 2개가 소모됩니다. 위 시간이 아니면 "현재는 담배를 수집할 수 있는 시간이 아닙니다"라고 표시되며, 도감은 언제든 열어볼 수 있습니다.'
    ),
    (
      question: '게임은 기록에 어떤 영향을 주나요?',
      answer:
          '게임(숫자 게임, 단어맞추기, 완벽 타이밍, 담배맞추기)은 금연 스트레스를 줄이고 집중을 돌리는 역할을 합니다. 점수와 레벨은 기기에 저장되고 로그인 시 서버와 맞춰집니다. 금연 시간·절약 금액에는 직접적인 영향을 주지 않습니다.'
    ),
    (
      question: '앱을 삭제하거나 기기를 바꾸면 데이터가 사라지나요?',
      answer:
          '네. 현재 버전에서는 데이터가 기기 안에만 저장됩니다. 앱을 삭제하거나 기기를 교체하면 기록은 복구할 수 없습니다. 중요한 기록(금연 시작일, 누적 절약 금액 등)은 스크린샷이나 메모로 따로 보관해 두시는 것을 권장합니다. 추후 계정/백업 기능을 지원할 경우 공지사항과 업데이트 내역을 통해 안내드릴 예정입니다.'
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
