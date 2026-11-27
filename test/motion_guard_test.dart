import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every duration, curve and distance of an animation lives in
/// `GerfautMotion` (lib/theme/tokens.dart). A screen that writes its own
/// drifts from the rest of the app one value at a time, so this reads
/// every Dart file of lib/ and fails on a literal curve or a literal
/// duration handed to an animation.
///
/// Durations that are not animation (timers, polling, the frame rate of
/// the animated backup QR, how long a toast stays) are named constants
/// and are not caught by these patterns.
void main() {
  // A literal that is legitimately outside the tokens, keyed by
  // `path:pattern`, with the reason it stays.
  const allowed = <String, String>{};

  final patterns = <String, RegExp>{
    'literal curve': RegExp(r'\bCurves\.'),
    'literal cubic curve': RegExp(r'\bCubic\('),
    'literal animation duration': RegExp(
      r'\b(duration|reverseDuration|transitionDuration|reverseTransitionDuration|animationDuration)\s*:\s*(const\s+)?Duration\(',
    ),
  };

  test('no animation writes its own duration or curve', () {
    final offences = <String>[];
    final files =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .map((f) => f.path.replaceAll(r'\', '/'))
            .where(
              (path) =>
                  path != 'lib/theme/tokens.dart' &&
                  !path.startsWith('lib/src/rust/'),
            )
            .toList()
          ..sort();
    expect(files, isNotEmpty);

    for (final path in files) {
      final lines = File(path).readAsLinesSync();
      // Joined, so a call broken over two lines is still caught; each
      // comment line is blanked first so prose can name a curve.
      final code = lines
          .map((line) => line.trimLeft().startsWith('//') ? '' : line)
          .join('\n');
      for (final entry in patterns.entries) {
        for (final match in entry.value.allMatches(code)) {
          final key = '$path:${entry.key}';
          if (allowed.containsKey(key)) continue;
          final line = '\n'.allMatches(code.substring(0, match.start)).length;
          offences.add(
            '$path:${line + 1}: ${entry.key}: ${lines[line].trim()}',
          );
        }
      }
    }

    expect(
      offences,
      isEmpty,
      reason:
          'Name a GerfautMotion token instead (lib/theme/tokens.dart):\n'
          '${offences.join('\n')}',
    );
  });
}
