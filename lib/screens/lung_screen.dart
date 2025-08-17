import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';

class LungScreen extends StatefulWidget {
  const LungScreen({super.key});

  @override
  State<LungScreen> createState() => _LungScreenState();
}

class _LungScreenState extends State<LungScreen> with TickerProviderStateMixin {
  int lungHealth = 0; // 0 ~ 100
  late AnimationController _controller;
  Timer? _healTimer;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _loadLungHealth();
    _healTimer = Timer.periodic(const Duration(seconds: 1), (_) => _healLung());
  }

  Future<void> _loadLungHealth() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      lungHealth = prefs.getInt('lungHealth') ?? 0;
      _controller.value = lungHealth / 100;
    });
  }

  Future<void> _saveLungHealth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lungHealth', lungHealth);
  }

  void _healLung() {
    if (lungHealth < 100) {
      setState(() {
        lungHealth++;
        _controller.animateTo(lungHealth / 100, duration: const Duration(milliseconds: 500));
      });
      _saveLungHealth();
    } else {
      _healTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _healTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = lungHealth / 100;

    return Scaffold(
      appBar: AppBar(
        title: const Text('나의 폐 상태'),
        backgroundColor: Colors.redAccent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Center(
              child: SizedBox(
                height: 240,
                child: Lottie.asset(
                  'assets/lung_recover.json',
                  controller: _controller,
                  onLoaded: (composition) {
                    _controller.duration = composition.duration;
                  },
                  repeat: false,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 30),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '폐 회복 상태',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 12,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}% 완료',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}