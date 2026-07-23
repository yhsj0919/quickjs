import 'dart:math' as math;

final class QuickjsUiAnimationTimeline {
  const QuickjsUiAnimationTimeline({
    required this.hasAnimations,
    required this.isContinuous,
    required this.endMs,
  });

  factory QuickjsUiAnimationTimeline.from(Object? value) {
    var hasAnimations = false;
    var isContinuous = false;
    var endMs = 0.0;

    void visit(Object? current) {
      if (current is List) {
        for (final child in current) {
          visit(child);
        }
        return;
      }
      if (current is! Map) return;

      final from = current['from'];
      final to = current['to'];
      final duration = current['durationMs'];
      if (from is num && to is num && duration is num) {
        hasAnimations = true;
        if (current['repeat'] == true || current['timeSource'] == 'epoch') {
          isContinuous = true;
          endMs = double.infinity;
          return;
        }
        if (!isContinuous) {
          final delay = quickjsUiRawNumber(current['delayMs']);
          final phase = quickjsUiRawNumber(current['phaseMs']);
          endMs = math.max(endMs, math.max(0, delay - phase + duration));
        }
        return;
      }
      for (final child in current.values) {
        visit(child);
      }
    }

    visit(value);
    return QuickjsUiAnimationTimeline(
      hasAnimations: hasAnimations,
      isContinuous: isContinuous,
      endMs: endMs,
    );
  }

  final bool hasAnimations;
  final bool isContinuous;
  final double endMs;
}

final class QuickjsUiAnimationClock {
  const QuickjsUiAnimationClock({
    required this.elapsedMs,
    required this.epochMs,
  });

  final double elapsedMs;
  final double epochMs;
}

double? quickjsUiAnimatedNumber(Object? raw, QuickjsUiAnimationClock clock) {
  if (raw is num) return raw.toDouble();
  if (raw is! Map) return null;
  final from = raw['from'];
  final to = raw['to'];
  final duration = raw['durationMs'];
  if (from is! num || to is! num || duration is! num || duration <= 0) {
    throw const FormatException(
      'quickjs_ui animation requires from, to and durationMs',
    );
  }
  final source = raw['timeSource'] == 'epoch' ? clock.epochMs : clock.elapsedMs;
  final time =
      source +
      quickjsUiRawNumber(raw['phaseMs']) -
      quickjsUiRawNumber(raw['delayMs']);
  var progress = 0.0;
  if (time > 0) {
    if (raw['repeat'] == true) {
      final cycle = time / duration;
      progress = cycle - cycle.floorToDouble();
      if (raw['autoreverse'] == true && cycle.floor().isOdd) {
        progress = 1 - progress;
      }
    } else {
      progress = (time / duration).clamp(0.0, 1.0);
    }
  }
  progress = quickjsUiAnimationCurve(progress, raw['curve']);
  return from + (to - from) * progress;
}

double quickjsUiRawNumber(Object? value) => value is num ? value.toDouble() : 0;

double quickjsUiAnimationCurve(double value, Object? curve) => switch (curve) {
  'easeIn' => value * value,
  'easeOut' => 1 - math.pow(1 - value, 2).toDouble(),
  'easeInOut' =>
    value < 0.5
        ? 2 * value * value
        : 1 - math.pow(-2 * value + 2, 2).toDouble() / 2,
  _ => value,
};

int quickjsUiValueHash(Object? value) {
  if (value is List) {
    return Object.hashAll(value.map(quickjsUiValueHash));
  }
  if (value is Map) {
    return Object.hashAll(
      value.entries.map(
        (entry) => Object.hash('${entry.key}', quickjsUiValueHash(entry.value)),
      ),
    );
  }
  return value.hashCode;
}
