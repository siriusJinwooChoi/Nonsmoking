import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/remote_assets.dart';
import '../data/savings_coin_exchange.dart';
import '../supabase/supabase_sync_service.dart';
import '../theme/app_theme.dart';
import 'attendance_screen.dart';

/// 절약 금액(원)을 금연코인으로 환전 (100원 = 1코인).
class SavingsCoinExchangeScreen extends StatefulWidget {
  const SavingsCoinExchangeScreen({
    super.key,
    required this.dailyCigarettes,
    required this.cigarettesPerPack,
    required this.pricePerPack,
  });

  final int dailyCigarettes;
  final int cigarettesPerPack;
  final int pricePerPack;

  @override
  State<SavingsCoinExchangeScreen> createState() =>
      _SavingsCoinExchangeScreenState();
}

class _SavingsCoinExchangeScreenState extends State<SavingsCoinExchangeScreen> {
  final _moneyFormatter = NumberFormat.decimalPattern('ko_KR');
  Timer? _tick;
  int? _startMs;
  int _exchangedWon = 0;
  int _coinBalance = 0;

  static const List<int> _coinOptions = [1, 5, 10, 30, 50, 100, 300, 500, 1000];

  @override
  void initState() {
    super.initState();
    unawaited(_refreshFromPrefs());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refreshFromPrefs());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _refreshFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final coins = await getGoldenCoins();
    if (!mounted) return;
    setState(() {
      _startMs = prefs.getInt('startTime');
      _exchangedWon = prefs.getInt(kSavingsExchangedToCoinsWonKey) ?? 0;
      _coinBalance = coins;
    });
  }

  int get _theoreticalWon {
    final ms = _startMs;
    if (ms == null) return 0;
    return computeTheoreticalSavedWon(
      startTime: DateTime.fromMillisecondsSinceEpoch(ms),
      dailyCigarettes: widget.dailyCigarettes,
      cigarettesPerPack: widget.cigarettesPerPack,
      pricePerPack: widget.pricePerPack,
    );
  }

  int get _exchangeableWon =>
      (_theoreticalWon - _exchangedWon).clamp(0, 0x7fffffff);

  Future<void> _exchangeByCoins(int coinAmount) async {
    final won = coinAmount * kWonPerSavingsCoin;
    final exchangeable = _exchangeableWon;
    if (won <= 0 || won > exchangeable) return;
    final ok = await _confirmExchange(won: won, coins: coinAmount);
    if (!ok) return;
    await _exchangeWon(won, coinAmount);
  }

  Future<void> _exchangeAllPossible() async {
    final exchangeable = _exchangeableWon;
    final won = (exchangeable ~/ kWonPerSavingsCoin) * kWonPerSavingsCoin;
    if (won < kWonPerSavingsCoin) return;
    final coins = won ~/ kWonPerSavingsCoin;
    final ok = await _confirmExchange(won: won, coins: coins);
    if (!ok) return;
    await _exchangeWon(won, coins);
  }

  Future<bool> _confirmExchange({
    required int won,
    required int coins,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('환전 확인'),
        content: Text(
          '₩${_moneyFormatter.format(won)}을(를) 금연코인 $coins개로 환전할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('환전'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _exchangeWon(int won, int addCoins) async {
    final prefs = await SharedPreferences.getInstance();
    final exchanged = prefs.getInt(kSavingsExchangedToCoinsWonKey) ?? 0;
    final newCoins = _coinBalance + addCoins;
    await setGoldenCoins(newCoins);
    await prefs.setInt(kSavingsExchangedToCoinsWonKey, exchanged + won);

    if (mounted) {
      setState(() {
        _exchangedWon = exchanged + won;
        _coinBalance = newCoins;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('금연코인 +$addCoins (보유 $_coinBalance개)')),
      );
    }
    unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());
  }

  @override
  Widget build(BuildContext context) {
    final exchangeable = _exchangeableWon;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('금연코인(환전)'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            8 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppTheme.cardShadowSubtle,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RemoteAssetImage(
                      assetKey: 'scoin.png',
                      width: 22,
                      height: 22,
                      error: const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 22),
                    ),
                    const SizedBox(width: 8),
                    Text('현재 보유 금연코인 $_coinBalance개', style: AppTheme.titleMedium.copyWith(fontSize: 17)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '환전 가능 금액: ₩${_moneyFormatter.format(exchangeable)}',
                  style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w700, color: AppTheme.primaryDark),
                ),
                const SizedBox(height: 4),
                Text(
                  '100원 = 1코인',
                  style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ..._coinOptions.map((coins) {
            final won = coins * kWonPerSavingsCoin;
            final enabled = exchangeable >= won;
            return _ExchangeRow(
              label: '금연코인 $coins개',
              priceLabel: '${_moneyFormatter.format(won)}원',
              enabled: enabled,
              onTap: enabled ? () => _exchangeByCoins(coins) : null,
            );
          }),
            _ExchangeRow(
              label: '환전 가능 금액 전부',
              priceLabel: '${_moneyFormatter.format((exchangeable ~/ kWonPerSavingsCoin) * kWonPerSavingsCoin)}원',
              enabled: exchangeable >= kWonPerSavingsCoin,
              onTap: exchangeable >= kWonPerSavingsCoin ? _exchangeAllPossible : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExchangeRow extends StatelessWidget {
  const _ExchangeRow({
    required this.label,
    required this.priceLabel,
    required this.enabled,
    this.onTap,
  });

  final String label;
  final String priceLabel;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadowSubtle,
      ),
      child: ListTile(
        leading: RemoteAssetImage(
          assetKey: 'scoin.png',
          width: 20,
          height: 20,
          error: const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 20),
        ),
        title: Text(label, style: AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
        trailing: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: enabled ? const Color(0xFF5CCB5F) : AppTheme.textMuted,
            minimumSize: const Size(96, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: Text(priceLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
