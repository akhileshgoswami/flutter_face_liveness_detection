import 'dart:io';

import 'package:flutter_face_liveness_detection/flutter_face_liveness_detection.dart';
import 'package:flutter/material.dart';

void main() => runApp(const DemoApp());

const _accent = Color(0xFF4ADE80);
const _danger = Color(0xFFF87171);
const _bgTop = Color(0xFF0B0F17);
const _bgBottom = Color(0xFF151B27);
const _mono = TextStyle(fontFamily: 'monospace');

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
        title: 'Liveness demo',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _bgTop,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _accent,
            brightness: Brightness.dark,
          ),
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  LivenessResult? _last;

  final Set<LivenessChallenge> _selected = {LivenessChallenge.blink,LivenessChallenge.turnRight};

  void _toggleChallenge(LivenessChallenge challenge) {
    setState(() {
      if (_selected.contains(challenge)) {
        if (_selected.length > 1) _selected.remove(challenge);
      } else {
        _selected.add(challenge);
      }
    });
  }

  Future<void> _verify() async {
    final pool = _selected.toList();
    final config = LivenessConfig(
      challengePool: pool,
      challengeCount: pool.length,
      // Selection is exact - don't let the engine force a turn challenge in
      // when the user didn't pick one.
      alwaysIncludeYawSweep: false,
      livenessThreshold: 0.62,
      captureFinalImage: true,
      challengeTimeout: const Duration(seconds: 20),
    );

    final result = await Navigator.of(context).push<LivenessResult>(
      MaterialPageRoute(
        builder: (_) => LivenessScreen(config: config),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _last = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              _Hero(onVerify: _verify),
              const SizedBox(height: 18),
              _ChallengePicker(selected: _selected, onToggle: _toggleChallenge),
              const SizedBox(height: 24),
              if (_last != null) _LastResultCard(result: _last!),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onVerify});
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accent.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0.03)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_moon_rounded, color: _accent, size: 26),
              ),
              const Spacer(),
              const _Badge(text: 'ON-DEVICE'),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Face Guard Liveness',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Liveness check powered by Google ML Kit face detection — randomized '
            'challenges plus passive anti-spoof signals. Nothing leaves the device.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onVerify,
              icon: const Icon(Icons.videocam_rounded),
              label: const Text('Verify face'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: _bgTop,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: _mono.copyWith(
          color: _accent,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

const _challengeLabels = {
  LivenessChallenge.blink: ('Blink', Icons.visibility_rounded),
  LivenessChallenge.smile: ('Smile', Icons.emoji_emotions_rounded),
  LivenessChallenge.turnLeft: ('Turn left', Icons.arrow_back_rounded),
  LivenessChallenge.turnRight: ('Turn right', Icons.arrow_forward_rounded),
  LivenessChallenge.nodDown: ('Nod down', Icons.expand_more_rounded),
  LivenessChallenge.holdStill: ('Hold still', Icons.pan_tool_rounded),
};

/// Lets the user pick which challenge(s) a session should ask for, instead
/// of hard-coding [LivenessConfig.challengePool] in source.
class _ChallengePicker extends StatelessWidget {
  const _ChallengePicker({required this.selected, required this.onToggle});
  final Set<LivenessChallenge> selected;
  final ValueChanged<LivenessChallenge> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CHALLENGES  ·  ${selected.length} selected',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.4),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final challenge in LivenessChallenge.values)
                _ChallengeChip(
                  label: _challengeLabels[challenge]!.$1,
                  icon: _challengeLabels[challenge]!.$2,
                  active: selected.contains(challenge),
                  onTap: () => onToggle(challenge),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChallengeChip extends StatelessWidget {
  const _ChallengeChip(
      {required this.label, required this.icon, required this.active, required this.onTap});
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active ? _accent.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? _accent.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? _accent : Colors.white54),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? _accent : Colors.white70,
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LastResultCard extends StatelessWidget {
  const _LastResultCard({required this.result});
  final LivenessResult result;

  @override
  Widget build(BuildContext context) {
    final good = result.isLive;
    final color = good ? _accent : _danger;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 26, spreadRadius: -8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(good ? Icons.verified_rounded : Icons.gpp_bad_rounded, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  good ? 'Live face confirmed' : 'Failed · ${result.failure.name}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
              Text(
                result.livenessScore.toStringAsFixed(2),
                style: _mono.copyWith(color: color, fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
          if (result.capturedImagePath != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                File(result.capturedImagePath!),
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in result.signals)
                _SignalChip(name: s.name, available: s.available, score: s.score),
            ],
          ),
        ],
      ),
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip(
      {required this.name, required this.available, required this.score});
  final String name;
  final bool available;
  final double score;

  @override
  Widget build(BuildContext context) {
    final color = !available
        ? Colors.white30
        : Color.lerp(_danger, _accent, score.clamp(0.0, 1.0))!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        available ? '$name ${score.toStringAsFixed(2)}' : '$name n/a',
        style: _mono.copyWith(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
