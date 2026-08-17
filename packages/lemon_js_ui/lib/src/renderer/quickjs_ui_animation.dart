// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'dart:math' as math;

final class JsUiAnimationTimeline {
  const JsUiAnimationTimeline({
    required this.hasAnimations,
    required this.isContinuous,
    required this.endMs,
  });

  factory JsUiAnimationTimeline.from(Object? value) {
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

      if (current['op'] == 'snapshotParticleGrid') {
        final bucketCount = jsUiRawNumber(current['bucketCount']);
        final staggerMs = jsUiRawNumber(current['staggerMs']);
        final travelMs = jsUiRawNumber(current['travelMs']);
        final fadeMs = jsUiRawNumber(current['fadeMs']);
        hasAnimations = true;
        endMs = math.max(
          endMs,
          math.max(0, bucketCount - 4) * staggerMs + math.max(travelMs, fadeMs),
        );
        return;
      }

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
          final delay = jsUiRawNumber(current['delayMs']);
          final phase = jsUiRawNumber(current['phaseMs']);
          endMs = math.max(endMs, math.max(0, delay - phase + duration));
        }
        return;
      }
      for (final child in current.values) {
        visit(child);
      }
    }

    visit(value);
    return JsUiAnimationTimeline(
      hasAnimations: hasAnimations,
      isContinuous: isContinuous,
      endMs: endMs,
    );
  }

  final bool hasAnimations;
  final bool isContinuous;
  final double endMs;
}

final class JsUiAnimationClock {
  const JsUiAnimationClock({required this.elapsedMs, required this.epochMs});

  final double elapsedMs;
  final double epochMs;
}

double? jsUiAnimatedNumber(Object? raw, JsUiAnimationClock clock) {
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
      source + jsUiRawNumber(raw['phaseMs']) - jsUiRawNumber(raw['delayMs']);
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
  progress = jsUiAnimationCurve(progress, raw['curve']);
  final keyframes = raw['keyframes'];
  if (keyframes != null) {
    return _sampleKeyframes(keyframes, progress);
  }
  return from + (to - from) * progress;
}

double _sampleKeyframes(Object? raw, double progress) {
  if (raw is! List || raw.length < 2) {
    throw const FormatException(
      'quickjs_ui animation keyframes requires at least two frames',
    );
  }
  var previousOffset = -1.0;
  final frames = <(double, double)>[];
  for (final frame in raw) {
    if (frame is! Map || frame['offset'] is! num || frame['value'] is! num) {
      throw const FormatException(
        'quickjs_ui animation keyframe requires numeric offset and value',
      );
    }
    final offset = (frame['offset'] as num).toDouble();
    final value = (frame['value'] as num).toDouble();
    if (offset < 0 || offset > 1 || offset <= previousOffset) {
      throw const FormatException(
        'quickjs_ui animation keyframe offsets must increase from 0 to 1',
      );
    }
    frames.add((offset, value));
    previousOffset = offset;
  }
  if (frames.first.$1 != 0 || frames.last.$1 != 1) {
    throw const FormatException(
      'quickjs_ui animation keyframes must start at 0 and end at 1',
    );
  }
  for (var index = 1; index < frames.length; index += 1) {
    final next = frames[index];
    if (progress > next.$1) continue;
    final previous = frames[index - 1];
    final local = (progress - previous.$1) / (next.$1 - previous.$1);
    return previous.$2 + (next.$2 - previous.$2) * local;
  }
  return frames.last.$2;
}

double jsUiRawNumber(Object? value) => value is num ? value.toDouble() : 0;

double jsUiAnimationCurve(double value, Object? curve) => switch (curve) {
  'easeIn' => value * value,
  'easeOut' => 1 - math.pow(1 - value, 2).toDouble(),
  'easeInOut' =>
    value < 0.5
        ? 2 * value * value
        : 1 - math.pow(-2 * value + 2, 2).toDouble() / 2,
  _ => value,
};

int jsUiValueHash(Object? value) {
  if (value is List) {
    return Object.hashAll(value.map(jsUiValueHash));
  }
  if (value is Map) {
    return Object.hashAll(
      value.entries.map(
        (entry) => Object.hash('${entry.key}', jsUiValueHash(entry.value)),
      ),
    );
  }
  return value.hashCode;
}
