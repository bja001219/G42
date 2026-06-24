import 'package:flutter/material.dart';

import '../app.dart';
import '../theme.dart';
import 'home_screen.dart';

/// 최초 실행 시 닉네임을 입력받는 로그인 화면.
///
/// identity.confirmName 으로 닉네임을 저장하면 nameConfirmed=true 가 되어
/// 다음 실행부터는 곧바로 홈으로 진입한다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _controller;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _busy) return;
    final services = AppServices.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    await services.identity.confirmName(name);
    if (!mounted) return;
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: Colors.white,
                  ),
                  children: [
                    TextSpan(text: 'G'),
                    TextSpan(
                      text: '42',
                      style: TextStyle(color: G42Colors.accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '둘이서 즐기는 미니게임 모음',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 15),
              ),
              const SizedBox(height: 40),
              const Text(
                '닉네임을 정해주세요',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 12,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: '예: 말간',
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _start(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: (_busy || _controller.text.trim().isEmpty)
                    ? null
                    : _start,
                child: const Text('시작'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
