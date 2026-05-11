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
                        '메인 화면',
                        '금연 시작일, 누적일, 목표일, 실시간 금연 시간, 총 절약 금액, 환전 가능 금액, 참은 담배 개수, 실패 횟수, 금연코인을 한눈에 볼 수 있습니다. 상단 가운데는 「금연 현황」이며, 왼쪽의 「금연코인」이나 환전 가능 금액을 누르면 환전 화면으로 이동해 절약 금액을 코인으로 바꿀 수 있습니다(100원당 1코인). 목표일·실패 횟수는 노란색 밑줄로 표시되며, 실패 횟수를 누르면 금연코인 5개로 1회 차감할 수 있습니다(코인 부족 시 불가). 상단 오른쪽의 공유 아이콘을 누르면 Android·iPhone 스토어 링크가 담긴 문구로 지인에게 앱을 추천할 수 있습니다. 메인에서 「알림 설정」으로 바로 알림 시간을 추가할 수 있고, 「방금 피움(패턴 기록)」으로 흡연 직후 시간대·상황·감정을 남기면 나의 레포트와 패턴 알림(아래 참고)에 반영됩니다. 「지금 너무 피우고싶을때」는 강한 유혹이 올 때 쓰는 안내 화면으로 연결되며, 이 버튼만으로는 실패 횟수가 늘지 않습니다. 금연할 이유, 마음 다잡기, 금연 도우미 등도 메인에서 바로 이용할 수 있으며, 하단 탭으로는 「메인」「게임」「성장시키기」「건강/커뮤니티」「레포트」「수집·도감」이 있습니다.',
                      ),
                      _manualSection(
                        '나의 레포트',
                        '하단 「레포트」 탭을 누르면 「나의 레포트」 화면이 열립니다. 「방금 피움(패턴 기록)」으로 쌓인 흡연 기록을 주간·월간 단위로 볼 수 있으며, 기간 화살표로 주·월을 바꿀 수 있습니다. 총 기록 횟수, 가장 많았던 시간대, 자주 겪은 상황·감정 등을 요약해 보여 주고, 시간대별 그래프로 패턴을 확인할 수 있습니다. 상단의 「카톡으로 공유」로 해당 기간 요약을 텍스트로 보내 가족·친구에게 응원을 받을 수 있습니다(카카오톡 등 설치된 앱의 공유 시트가 열립니다). 기록이 없는 주·월에는 안내 문구만 표시됩니다.',
                      ),
                      _manualSection(
                        '흡연 패턴 기록과 패턴 알림',
                        '흡연 직후 메인의 「방금 피움(패턴 기록)」을 눌러 시간대·상황·감정을 남기면 기기에 저장되며, 같은 방식으로 쌓인 최근 기록을 바탕으로 피크 시간대를 분석합니다. 최근 일정 기간 안에 흡연(패턴) 기록이 일정 개수(5건) 이상이 되면, 그 패턴에 맞춘 자동 알림(패턴 알림)이 생성·예약될 수 있습니다. 직접 추가한 「알림 설정」 시간과는 별도이며, 설정 > 알림 화면의 「패턴 알림」 탭에서 자동 생성된 항목을 확인할 수 있습니다. 패턴 기반 자동 알림을 끄고 싶다면 설정 > 알림 해지에서 해당 스위치를 끄면 됩니다. 알림 권한이 꺼져 있거나 OS 제한으로 예약이 실패해도 기록 자체는 저장됩니다.',
                      ),
                      _manualSection(
                        '금연코인',
                        '앱 실행 시 나오는 출석 화면에서 순서대로 출석하면 금연코인이 지급됩니다. 평일(월~금) 출석 시 +15코인, 토·일(주말)에 출석하면 +20코인입니다. 출석은 최대 28일 단위 그리드로 이어지며, 하루에 한 번 출석할 수 있습니다. 로그인한 상태에서 미니게임을 플레이하면 서버 검증을 거쳐 종목당 하루 한 번 금연코인 보상을 받을 수 있습니다(게임 메뉴 상단에 안내된 코인 수). 성장시키기 > 나의 성장 나무에서 나무를 보관한 뒤, 보관한 나무를 금연코인으로 바꿀 수 있습니다(나무 1그루당 500코인). 메인에서 절약 금액을 코인으로 환전(100원당 1코인)할 수 있으며, 환전 화면에서는 1·5·10·30·50·100·300·500·1000코인 또는 환전 가능 금액 전부 단위로 바꿀 수 있습니다. 금연코인은 도감 수집 1회 시도마다 2코인, 메인에서 실패 횟수 1회 차감 시 5코인, 나의 드림카 업그레이드 1회당 1,500코인이 소모됩니다. 코인이 부족하면 해당 기능을 사용할 수 없습니다.',
                      ),
                      _manualSection(
                        '알림',
                        '메인의 「알림 설정」 또는 설정 > 알림에서 원하는 시간대를 여러 개 추가해 금연 리마인드 알림을 받을 수 있습니다. 비접속·출석·수집 시간 알림과 패턴 기반 자동 알림의 켜기/끄기는 설정 > 알림 해지에서 관리합니다. 패턴 알림은 흡연(패턴) 기록이 충분히 쌓인 뒤 자동으로 만들어지며, 설정 > 알림의 「패턴 알림」 탭에서 예약된 시간을 확인할 수 있습니다. 또한 내가 선택한 금연 이유 알림(매일 12:01)도 함께 사용할 수 있습니다.',
                      ),
                      _manualSection(
                        '금연 이유',
                        '금연하는 개인적인 이유를 여러 개 작성하고, 별표로 고정하거나 종 아이콘으로 알림에 사용할 이유를 선택할 수 있습니다. 선택된 이유는 매일 12:01에 오는 금연 이유 알림 내용에 함께 표시되어 금연 의지를 유지하는 데 도움을 줍니다.',
                      ),
                      _manualSection(
                        '마음 다잡기',
                        '메인 화면의 마음 다잡기 버튼을 누르면 지금까지의 금연 시간, 절약 금액, 참은 담배 개수, 내가 선택한 금연 이유, 응원 문구가 함께 표시됩니다. 마음이 흔들릴 때마다 이 화면을 열어 현재 성과를 확인해 보세요.',
                      ),
                      _manualSection(
                        '실패 횟수와 폐 건강',
                        '메인에서 「방금 피움(패턴 기록)」을 끝까지 저장하면 실패 횟수가 1회 늘고, 폐 건강 수치가 10% 감소합니다. 건강/커뮤니티 > 나의 폐 건강 화면 아래 「흡연 시도 (-10%)」를 누르고 확인하면 역시 실패가 1회 늘고 폐가 10% 줄어듭니다. 실패 횟수는 메인 통계 카드에 노란색으로 표시되며, 누르면 금연코인 5개로 1회 줄일 수 있습니다(코인 부족 시 불가). 금연 시작 시각부터 이어지는 금연 시간(타이머)은 위 경우에도 초기화되지 않습니다. 「지금 너무 피우고싶을때」만으로는 실패 횟수가 늘지 않습니다.',
                      ),
                      _manualSection(
                        '수집·도감',
                        '「수집·도감」은 담배 패키지 도안을 모으는 화면입니다. 상단 오른쪽의 「도감」을 누르면 전체 도감(그리드) 화면으로 이동합니다. 도감 수집은 09:00~09:20, 12:00~12:20, 18:00~18:20, 22:00~22:20에만 가능하며, 각 시간대마다 한 번만 시도할 수 있습니다(성공 또는 5번 실패 후 해당 구간 종료). 1회 시도마다 금연코인 2개가 소모되고, 수집에 실패하면 안내 메시지가 표시됩니다. 위 시간이 아니거나 이미 사용한 경우 수집이 비활성화됩니다. 같은 패키지를 여러 번 수집하면 도감에서 개수(x2, x3 …)로 표시됩니다. 도감 화면에서는 타일을 눌러 이미지를 크게 보고, 손가락으로 확대·축소할 수 있습니다. 미수집 패키지는 잠금 표시와 함께 실루엣이 비치도록 보여, 어떤 도안이 있는지 확인할 수 있습니다. 도감 화면 상단의 「도감 교환하기」로, 동일 패키지를 5개 이상 보유한 경우 미수집 패키지 1개와 교환할 수 있습니다(사용한 5개는 차감되고, 교환한 패키지는 수집된 것처럼 표시됩니다). 09:00·12:00·18:00·22:00 정각에 수집 가능 시간 알림이 올 수 있습니다.',
                      ),
                      _manualSection(
                        '성장시키기 (나무·드림카)',
                        '하단 「성장시키기」 탭에서 「나의 성장 나무」와 「나의 드림카」를 선택할 수 있습니다. 나무는 2분마다 물이 1ml씩 쌓이고, 10ml·100ml 단위로 물을 주면 최대 5단계까지 성장합니다. 5단계까지 자란 나무는 「나무 보관하기」로 보관할 수 있고, 보관한 나무는 금연코인으로 바꿀 수 있습니다(나무 1그루당 500코인). 드림카는 H Company 또는 K Company를 선택한 뒤, 금연코인 1,500개를 모을 때마다 한 단계씩 최대 10단계까지 업그레이드할 수 있습니다. 금연코인은 출석·미니게임 보상·나무 환전·메인에서 절약 금액 환전(100원당 1코인) 등으로 모을 수 있습니다.',
                      ),
                      _manualSection(
                        '건강 / 커뮤니티',
                        '하단 「건강/커뮤니티」 탭에서 다음을 선택할 수 있습니다. 「나의 폐 건강」에서는 폐 회복 상태를 퍼센트로 확인할 수 있으며, 금연을 유지하면 시간이 지나며 서서히 회복됩니다. 「흡연 시도 (-10%)」로 기록하면 폐가 10% 감소하고 실패 횟수가 1회 증가합니다(수치는 참고용이며 의학적 진단이 아닙니다). 「건강 개선 현황」에서는 금연 경과 시간에 따른 대표적인 건강 개선 단계(20분, 8시간, 24시간, 48시간, 72시간, 2주~3개월, 1~9개월, 1년 등)와 몸의 변화 설명을 볼 수 있습니다. 「담타시간(커뮤니티)」에서는 담타 루틴을 체험하며 다시 복귀를 준비할 수 있습니다.',
                      ),
                      _manualSection(
                        '게임',
                        '하단 「게임」 탭에서 네 가지 미니게임을 즐길 수 있습니다. 「1부터 30까지 빠르게!」(숫자 순서 탭), 「단어맞추기」, 「낙하 맞추기」, 「완벽 타이밍」 순으로 목록에 표시됩니다. 우측 상단 「랭킹」에서 기록을 비교해 볼 수 있습니다. 점수·레벨은 기기에 저장되며, 로그인 시 서버와 맞춰질 수 있습니다. 로그인 상태에서는 종목당 하루 한 번 서버 검증 금연코인 보상을 받을 수 있습니다(화면 상단 안내). 금연 시간·절약 금액에는 직접적인 영향을 주지 않습니다.',
                      ),
                      _manualSection(
                        '위젯',
                        '홈 화면 위젯을 추가하면 앱을 열지 않아도 금연 시간, 절약 금액, 참은 담배 개수, 폐 건강을 바로 확인할 수 있습니다. 여러 크기의 위젯을 지원하며, 앱 내용이 변경되면 위젯에도 최대한 빠르게 반영됩니다.',
                      ),
                      _manualSection(
                        '설정',
                        '알림 시간은 설정 > 알림에서 관리하고, 비접속·출석·수집 시간·패턴 기반 자동 알림은 설정 > 알림 해지에서 켜고 끌 수 있습니다. 설정 > 설정 섹션에서 앱 업데이트 확인, 앱 정보, 도움말 외에 「튜토리얼 보기」를 누르면 메인 화면 튜토리얼을 다시 볼 수 있습니다. 또한 금연 뱃지, 초기 설정으로 돌아가기, 로그아웃(로그인 시) 등을 확인할 수 있습니다.',
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
          '설정 > 알림에서 원하는 시간대를 추가했는지, 설정 > 알림 해지에서 필요한 토글(비접속/출석/수집 시간/패턴 기반 자동 알림)이 켜져 있는지, 기기 알림 권한이 허용되어 있는지 확인해주세요. 배터리 최적화나 절전 모드, 백그라운드 제한으로 인해 알림이 지연될 수 있으므로 앱을 최적화 예외/제한 없음으로 설정하는 것을 권장합니다.'
    ),
    (
      question: '패턴 알림이란 무엇이고, 언제 생기나요?',
      answer:
          '흡연 직후 메인의 「방금 피움(패턴 기록)」으로 시간대·상황·감정을 남기면 기록이 쌓입니다. 최근 기간 안에 이런 흡연 기록이 5건 이상이 되면, 자주 겹치는 시간대를 분석해 자동으로 맞춤 알림(패턴 알림)이 만들어질 수 있습니다. 설정 > 알림의 「패턴 알림」 탭에서 예약된 시간을 확인할 수 있고, 끄고 싶다면 설정 > 알림 해지에서 「패턴 기반 자동 알림」을 꺼 주세요. 알림 예약만 실패해도 기록은 저장됩니다.'
    ),
    (
      question: '나의 레포트에서는 무엇을 볼 수 있나요?',
      answer:
          '하단 「레포트」 탭의 「나의 레포트」에서, 방금 피움(패턴 기록)으로 남긴 흡연 기록을 주간·월간으로 모아 볼 수 있습니다. 총 횟수, 가장 많았던 시간대, 자주 겪은 상황·감정 등이 요약됩니다. 상단 「카톡으로 공유」로 해당 기간 요약을 텍스트로 보내 지인에게 응원을 받을 수 있습니다.'
    ),
    (
      question: '앱을 지인에게 추천하고 싶어요.',
      answer:
          '메인 화면 상단 오른쪽의 공유(화살표) 아이콘을 누르면 Android·iPhone 스토어 링크가 포함된 문구가 준비됩니다. 카카오톡·문자 등 설치된 앱의 공유 화면에서 받는 사람을 선택해 보낼 수 있습니다.'
    ),
    (
      question: '3일 이상 앱을 열지 않았을 때 오는 비접속 알림을 끄고 싶어요.',
      answer:
          '설정 > 알림 해지 > 비접속 시 알림에서 스위치를 끄면 더 이상 “금연은 잘 하고 계신가요?” 알림이 오지 않습니다. 다시 동기부여가 필요할 때는 같은 메뉴에서 다시 켤 수 있습니다.'
    ),
    (
      question: '금연 이유 알림(매일 12:01) 내용을 바꾸고 싶어요.',
      answer:
          '메인 화면에서 「금연할 이유」로 들어가 새 이유를 작성한 뒤, 종 아이콘을 눌러 알림에 사용할 이유를 선택해 주세요. 선택된 이유는 매일 12:01에 오는 금연 이유 알림에 표시되며, 언제든지 다른 이유로 바꿀 수 있습니다.'
    ),
    (
      question: '나의 성장 나무는 어떻게 키우나요?',
      answer:
          '하단 「성장시키기」 탭에서 「나의 성장 나무」를 선택하세요. 2분마다 물이 1ml씩 자동으로 쌓이며, 10ml·100ml 버튼으로 나무에 물을 줄 수 있습니다. 5단계까지 자라면 「나무 보관하기」로 보관할 수 있고, 보관한 나무는 금연코인으로 바꿀 수 있습니다(나무 1그루당 500코인). 성장·보관 상태는 기기에 저장되어 유지됩니다.'
    ),
    (
      question: '방금 피움(또는 폐 화면 흡연 시도) 후에 실패만 늘고 금연 시간은 그대로예요.',
      answer:
          '금연뱅크는 “완벽한 금연”보다 “다시 시작하는 금연”에 초점을 두고 있습니다. 메인에서 「방금 피움(패턴 기록)」을 저장하거나, 건강/커뮤니티 > 나의 폐 건강에서 「흡연 시도 (-10%)」를 확인하면 실패 횟수와 폐 건강에만 반영되고, 금연 시작 시각부터 이어지는 금연 시간(타이머)은 초기화되지 않습니다. 「지금 너무 피우고싶을때」는 유혹 대처 화면으로만 연결되며 이 버튼만으로는 실패가 늘지 않습니다.'
    ),
    (
      question: '금연 뱃지는 어떻게 받나요?',
      answer:
          '설정 > 금연 뱃지에서 획득 조건을 확인할 수 있습니다. 참은 담배 개수(개비) 누적과 금연 일수 조건을 충족하면 해당 뱃지가 활성화됩니다. 앱을 꾸준히 사용하며 금연을 이어가면 더 많은 뱃지를 모을 수 있습니다.'
    ),
    (
      question: '금연코인은 어떻게 받고 어디에 쓰나요?',
      answer:
          '출석 화면에서 순서대로 출석하면 코인이 지급됩니다. 평일(월~금) 출석 시 +15코인, 토·일(주말) 출석 시 +20코인입니다. 로그인 후 미니게임을 하면 서버 검증으로 종목당 하루 한 번 보상 코인을 받을 수 있습니다(게임 화면 상단 안내). 성장시키기 > 나의 성장 나무에서 보관한 나무를 코인으로 바꿀 수도 있습니다(나무 1그루당 500코인). 메인에서 절약 금액을 환전할 수도 있습니다(100원당 1코인). 소모처는 도감 수집 시도마다 2코인, 실패 횟수 1회 차감 시 5코인, 드림카 업그레이드마다 1,500코인 등입니다. 코인이 부족하면 해당 기능을 사용할 수 없습니다.'
    ),
    (
      question: '도감 수집은 언제 할 수 있나요?',
      answer:
          '도감 수집은 09:00~09:20, 12:00~12:20, 18:00~18:20, 22:00~22:20에만 가능합니다. 각 시간대마다 한 번만 시도할 수 있고(성공 또는 5번 실패 후 종료), 1회 시도마다 금연코인 2개가 소모됩니다. 실패 시에도 안내 메시지가 표시됩니다. 위 시간이 아니면 "현재는 수집할 수 있는 시간이 아닙니다"라고 표시됩니다. 수집 화면 상단 오른쪽 「도감」에서 언제든 도감 목록을 열 수 있습니다.'
    ),
    (
      question: '도감 교환은 어떻게 하나요?',
      answer:
          '도감 화면 상단의 「도감 교환하기」에서 진행합니다. 동일 패키지를 5개 이상 보유한 경우에만 "낼 담배"로 선택할 수 있고, 아직 수집하지 않은 패키지만 "받을 담배"로 선택할 수 있습니다. 확인하면 사용한 패키지에서 5개가 차감되고(예: 7개 보유 시 2개 남음), 선택한 미수집 패키지는 1개 수집된 것처럼 표시됩니다. 교환에 성공하면 안내 메시지가 나옵니다.'
    ),
    (
      question: '게임은 기록에 어떤 영향을 주나요?',
      answer:
          '미니게임은 금연 스트레스를 줄이고 집중을 돌리는 역할을 합니다. 점수·레벨은 기기에 저장되고 로그인 시 서버와 맞춰질 수 있으며, 로그인 시 종목당 하루 한 번 코인 보상을 받을 수 있습니다. 금연 시간·절약 금액·실패 횟수에는 직접 반영되지 않습니다.'
    ),
    (
      question: '앱을 삭제하거나 기기를 바꾸면 데이터가 사라지나요?',
      answer:
          '로그인하지 않은 상태라면 데이터가 기기 중심으로 저장되어 앱 삭제/기기 교체 시 일부 기록이 사라질 수 있습니다. 로그인 상태에서는 설정/진행 기록이 서버와 동기화되므로 같은 계정으로 다시 로그인하면 복구되는 항목이 많습니다. 그래도 중요한 기록(금연 시작일, 누적 절약 금액 등)은 스크린샷이나 메모로 함께 보관하는 것을 권장합니다.'
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
