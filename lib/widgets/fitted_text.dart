import 'dart:math';

import 'package:flutter/widgets.dart';

import '../src/format.dart';

/// Width one line of [text] takes in the style it will be drawn in, at
/// the reader's text scale.
double textWidth(String text, TextStyle style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Height one line takes in [style], at the reader's text scale.
double lineHeight(TextStyle style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: '0', style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Whether one line of [text] fits [room], a pixel to spare: a
/// measurement that lands a hair under the paint costs the last glyph,
/// and half a character of an address is worse than one fewer.
bool fitsLine(String text, double room, TextStyle style, TextScaler scaler) =>
    textWidth(text, style, scaler) <= room - 1;

/// The width at which [text], an identifier in a monospaced [style],
/// wraps into the lines it needs in [room] with every line the same
/// length, give or take a character. Null when it fits one line, or
/// when [room] is unbounded: then nothing needs narrowing.
double? balancedWidth(
  String text,
  double room,
  TextStyle style,
  TextScaler scaler,
) {
  if (text.isEmpty || !room.isFinite) return null;
  final whole = textWidth(text, style, scaler);
  if (whole <= room - 1) return null;
  final glyph = whole / text.length;
  if (glyph <= 0) return null;
  // Half a glyph past the last one of a line: wide enough for the few
  // pixels a selectable text keeps for its caret, too narrow for one
  // more character, whichever way the measure rounds.
  final margin = glyph / 2;
  final perLine = ((room - margin) / glyph).floor();
  if (perLine < 1) return null;
  final lines = (text.length / perLine).ceil();
  final balanced = (text.length / lines).ceil();
  return min(room, balanced * glyph + margin);
}

/// [child], which draws [text] in [style], narrowed so that its lines
/// come out the same length: an address over two lines reads as two
/// halves to compare, not as a full line and a stray tail of a few
/// characters. The text itself is untouched, so what is selected,
/// copied or read aloud is the whole value.
class BalancedLines extends StatelessWidget {
  const BalancedLines({
    super.key,
    required this.text,
    required this.style,
    required this.child,
    this.alignment = AlignmentDirectional.centerStart,
  });

  final String text;
  final TextStyle style;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = balancedWidth(text, constraints.maxWidth, style, scaler);
        if (width == null) return child;
        return Align(
          alignment: alignment,
          heightFactor: 1,
          child: SizedBox(width: width, child: child),
        );
      },
    );
  }
}

/// The longest middle truncation of [value] that fits [room], both ends
/// kept: it drops a whole character from the longer end until it does.
/// Under an unbounded width the asked-for truncation stands. It stops
/// at [floor] characters kept in all: below that there is nothing left
/// worth comparing.
String fitMiddle(
  String value,
  double room,
  TextStyle style,
  TextScaler scaler, {
  required int head,
  required int tail,
  int floor = 8,
}) {
  var shown = truncateMiddle(value, head: head, tail: tail);
  if (!room.isFinite) return shown;
  while (!fitsLine(shown, room, style, scaler) && head + tail > floor) {
    if (head > tail) {
      head--;
    } else {
      tail--;
    }
    shown = truncateMiddle(value, head: head, tail: tail);
  }
  return shown;
}
