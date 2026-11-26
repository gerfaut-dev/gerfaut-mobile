import 'package:flutter/material.dart';

import '../src/models.dart';
import '../theme/tokens.dart';
import 'fitted_text.dart';

/// The payload of an OP_RETURN output under its tag, on the transaction
/// detail and in the Broadcast preview alike: the protocol's name when
/// the core recognised one, else the decoded text, else the hex. The
/// text and the hex are cut in the middle to the room the row leaves:
/// like any identifier, both of their ends stay, and a payload too long
/// for the line loses characters from its middle, never its tail behind
/// an ellipsis. A long press shows the whole payload.
class OpReturnPreview extends StatelessWidget {
  const OpReturnPreview({super.key, required this.data});

  final OpReturnData data;

  /// How much of each end the cut keeps at most: more of the head of a
  /// text, which reads from its start, than of a hex excerpt.
  static const ({int head, int tail}) textEnds = (head: 22, tail: 6);
  static const ({int head, int tail}) hexEnds = (head: 12, tail: 6);

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final style = tokens.data.copyWith(color: tokens.textMuted);
    final scaler = MediaQuery.textScalerOf(context);
    final label = data.label;
    final text = data.text;
    return Tooltip(
      message: text ?? data.hex,
      triggerMode: TooltipTriggerMode.longPress,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.maxWidth;
          final shown =
              label ??
              (text != null
                  ? fitMiddle(
                      text,
                      room,
                      style,
                      scaler,
                      head: textEnds.head,
                      tail: textEnds.tail,
                    )
                  : fitMiddle(
                      data.hex,
                      room,
                      style,
                      scaler,
                      head: hexEnds.head,
                      tail: hexEnds.tail,
                    ));
          return Text(
            shown,
            style: style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          );
        },
      ),
    );
  }
}
