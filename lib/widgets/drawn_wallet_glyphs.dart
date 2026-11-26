// The wallet icons drawn for this app, one path each, in Lucide's grammar:
// a 24 unit box, stroked at 1.5 with round caps and joins, never filled.
// The same drawings as the desktop app's, written out as path calls.

import 'dart:ui';

/// Each drawn wallet glyph as a path in a 24 unit box, for
/// [StrokeGlyph] to stroke. Built once, on first use.
abstract final class DrawnWalletGlyphs {
  /// Swivel key.
  static final Path swivelKey = Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(2, 12, 20, 8), Radius.circular(2)),
    )
    ..addOval(Rect.fromCircle(center: Offset(6, 16), radius: 1))
    ..moveTo(11, 16)
    ..lineTo(17, 16)
    ..moveTo(4.5, 12)
    ..lineTo(12.6, 6)
    ..arcToPoint(
      Offset(14.7, 6.3),
      radius: Radius.circular(1.5),
      clockwise: true,
    )
    ..lineTo(15.2, 7)
    ..arcToPoint(
      Offset(14.9, 9.1),
      radius: Radius.circular(1.5),
      clockwise: true,
    )
    ..lineTo(10.5, 12);

  /// Slim stick.
  static final Path slimStick = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 8.5, 20, 7),
        Radius.circular(3.5),
      ),
    )
    ..moveTo(6.5, 12)
    ..lineTo(13.5, 12)
    ..moveTo(17.5, 12)
    ..lineTo(17.51, 12);

  /// USB stick.
  static final Path usbStick = Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(2, 7.5, 15, 9), Radius.circular(3)),
    )
    ..moveTo(17, 10.5)
    ..lineTo(20.5, 10.5)
    ..arcToPoint(
      Offset(21.5, 11.5),
      radius: Radius.circular(1),
      clockwise: true,
    )
    ..lineTo(21.5, 12.5)
    ..arcToPoint(
      Offset(20.5, 13.5),
      radius: Radius.circular(1),
      clockwise: true,
    )
    ..lineTo(17, 13.5)
    ..moveTo(6, 12)
    ..lineTo(13, 12);

  /// Two-button device.
  static final Path twoButtonDevice = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(6.5, 2, 11, 20),
        Radius.circular(2),
      ),
    )
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(9.5, 5, 5, 4), Radius.circular(1)),
    )
    ..moveTo(10, 16)
    ..lineTo(10.01, 16)
    ..moveTo(14, 16)
    ..lineTo(14.01, 16);

  /// Square touchscreen.
  static final Path squareTouchscreen = Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(5, 2, 14, 20), Radius.circular(2)),
    )
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(8, 5, 8, 8), Radius.circular(1)),
    );

  /// Scroll wheel device.
  static final Path wheelDevice = Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(2, 8, 20, 10), Radius.circular(2)),
    )
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(5, 11, 9, 4), Radius.circular(1)),
    )
    ..moveTo(15, 8)
    ..arcToPoint(Offset(20, 8), radius: Radius.circular(2.5), clockwise: true)
    ..moveTo(18, 13)
    ..lineTo(18.01, 13);

  /// Pocket screen.
  static final Path pocketScreen = Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(2, 5, 20, 14), Radius.circular(2)),
    )
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(5, 8, 11, 8), Radius.circular(1)),
    )
    ..moveTo(19, 12)
    ..lineTo(19.01, 12);

  /// Wide screen bar.
  static final Path wideScreenBar = Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(2, 7, 20, 10), Radius.circular(2)),
    )
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(5, 10, 9, 4), Radius.circular(1)),
    )
    ..addOval(Rect.fromCircle(center: Offset(18, 12), radius: 1.5));

  /// Curved slate.
  static final Path curvedSlate = Path()
    ..moveTo(11, 2)
    ..lineTo(17, 2)
    ..arcToPoint(Offset(19, 4), radius: Radius.circular(2), clockwise: true)
    ..lineTo(19, 20)
    ..arcToPoint(Offset(17, 22), radius: Radius.circular(2), clockwise: true)
    ..lineTo(11, 22)
    ..cubicTo(7.5, 22, 5, 17.5, 5, 12)
    ..cubicTo(5, 6.5, 7.5, 2, 11, 2)
    ..close()
    ..moveTo(11, 5)
    ..lineTo(16, 5)
    ..lineTo(16, 19)
    ..lineTo(11, 19);

  /// Framed slate.
  static final Path framedSlate = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3.5, 3, 17, 18),
        Radius.circular(3),
      ),
    )
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(7, 6.5, 10, 11),
        Radius.circular(1),
      ),
    );

  /// Keypad bar.
  static final Path keypadBar = Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(7, 2, 10, 20), Radius.circular(2)),
    )
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(10, 5, 4, 4), Radius.circular(1)),
    )
    ..moveTo(10.5, 13)
    ..lineTo(10.51, 13)
    ..moveTo(13.5, 13)
    ..lineTo(13.51, 13)
    ..moveTo(10.5, 16)
    ..lineTo(10.51, 16)
    ..moveTo(13.5, 16)
    ..lineTo(13.51, 16)
    ..moveTo(10.5, 19)
    ..lineTo(10.51, 19)
    ..moveTo(13.5, 19)
    ..lineTo(13.51, 19);

  /// Calculator.
  static final Path calculator = Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(5, 2, 14, 20), Radius.circular(2)),
    )
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(8, 5, 8, 3), Radius.circular(1)),
    )
    ..moveTo(9, 12)
    ..lineTo(9.01, 12)
    ..moveTo(12, 12)
    ..lineTo(12.01, 12)
    ..moveTo(15, 12)
    ..lineTo(15.01, 12)
    ..moveTo(9, 15)
    ..lineTo(9.01, 15)
    ..moveTo(12, 15)
    ..lineTo(12.01, 15)
    ..moveTo(15, 15)
    ..lineTo(15.01, 15)
    ..moveTo(9, 18)
    ..lineTo(9.01, 18)
    ..moveTo(12, 18)
    ..lineTo(12.01, 18)
    ..moveTo(15, 18)
    ..lineTo(15.01, 18);

  /// Keyboard device.
  static final Path keyboardDevice = Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(2, 4, 20, 16), Radius.circular(2)),
    )
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(5, 7, 14, 4), Radius.circular(1)),
    )
    ..moveTo(6, 14)
    ..lineTo(6.01, 14)
    ..moveTo(9, 14)
    ..lineTo(9.01, 14)
    ..moveTo(12, 14)
    ..lineTo(12.01, 14)
    ..moveTo(15, 14)
    ..lineTo(15.01, 14)
    ..moveTo(18, 14)
    ..lineTo(18.01, 14)
    ..moveTo(8, 17)
    ..lineTo(16, 17);

  /// Touch phone.
  static final Path touchPhone = Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(6, 2, 12, 20), Radius.circular(2)),
    )
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(9, 5, 6, 10), Radius.circular(1)),
    )
    ..moveTo(10.5, 18.5)
    ..lineTo(13.5, 18.5);

  /// Air-gapped phone.
  static final Path airGappedPhone = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(5.5, 2, 13, 20),
        Radius.circular(2),
      ),
    )
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(8.5, 6, 3.5, 3.5),
        Radius.circular(1),
      ),
    )
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(8.5, 13.5, 3.5, 3.5),
        Radius.circular(1),
      ),
    )
    ..moveTo(15, 7.75)
    ..lineTo(15.01, 7.75)
    ..moveTo(15, 15.25)
    ..lineTo(15.01, 15.25);

  /// Screen card.
  static final Path screenCard = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 5.5, 20, 13),
        Radius.circular(2),
      ),
    )
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(5, 8.5, 7, 7), Radius.circular(1)),
    )
    ..moveTo(16, 12)
    ..lineTo(16.01, 12)
    ..moveTo(19, 12)
    ..lineTo(19.01, 12);

  /// NFC card.
  static final Path nfcCard = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 5.5, 20, 13),
        Radius.circular(2),
      ),
    )
    ..moveTo(13, 10)
    ..arcToPoint(Offset(13, 14), radius: Radius.circular(3), clockwise: true)
    ..moveTo(15.5, 8.5)
    ..arcToPoint(
      Offset(15.5, 15.5),
      radius: Radius.circular(5),
      clockwise: true,
    );

  /// Chip card.
  static final Path chipCard = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 5.5, 20, 13),
        Radius.circular(2),
      ),
    )
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(5, 8.5, 7, 7),
        Radius.circular(1.5),
      ),
    )
    ..moveTo(5, 12)
    ..lineTo(12, 12);

  /// Card set.
  static final Path cardSet = Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(2, 9, 16, 11), Radius.circular(2)),
    )
    ..moveTo(6, 9)
    ..lineTo(6, 6)
    ..arcToPoint(Offset(8, 4), radius: Radius.circular(2), clockwise: true)
    ..lineTo(20, 4)
    ..arcToPoint(Offset(22, 6), radius: Radius.circular(2), clockwise: true)
    ..lineTo(22, 14)
    ..arcToPoint(Offset(20, 16), radius: Radius.circular(2), clockwise: true)
    ..lineTo(18, 16)
    ..moveTo(8, 12.5)
    ..arcToPoint(Offset(8, 16.5), radius: Radius.circular(2.5), clockwise: true)
    ..moveTo(10.5, 11)
    ..arcToPoint(Offset(10.5, 18), radius: Radius.circular(5), clockwise: true);

  /// Device and cards.
  static final Path deviceWithCards = Path()
    ..moveTo(11, 15)
    ..lineTo(4, 15)
    ..arcToPoint(Offset(2, 13), radius: Radius.circular(2), clockwise: true)
    ..lineTo(2, 5)
    ..arcToPoint(Offset(4, 3), radius: Radius.circular(2), clockwise: true)
    ..lineTo(18, 3)
    ..arcToPoint(Offset(20, 5), radius: Radius.circular(2), clockwise: true)
    ..lineTo(20, 8)
    ..moveTo(5.5, 7)
    ..arcToPoint(Offset(5.5, 11), radius: Radius.circular(2.5), clockwise: true)
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(13, 9, 9, 13), Radius.circular(2)),
    )
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(15.5, 11.5, 4, 3.5),
        Radius.circular(1),
      ),
    )
    ..moveTo(17.5, 18.5)
    ..lineTo(17.51, 18.5);

  /// NFC paddle.
  static final Path nfcPaddle = Path()
    ..addOval(Rect.fromCircle(center: Offset(8.5, 12), radius: 6.5))
    ..moveTo(13.5, 8)
    ..lineTo(20, 8)
    ..arcToPoint(Offset(22, 10), radius: Radius.circular(2), clockwise: true)
    ..lineTo(22, 14)
    ..arcToPoint(Offset(20, 16), radius: Radius.circular(2), clockwise: true)
    ..lineTo(13.5, 16)
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(16, 10.5, 4, 3),
        Radius.circular(1),
      ),
    )
    ..moveTo(7, 10.5)
    ..arcToPoint(Offset(7, 13.5), radius: Radius.circular(2), clockwise: true)
    ..moveTo(9.5, 9)
    ..arcToPoint(
      Offset(9.5, 15),
      radius: Radius.circular(4.5),
      clockwise: true,
    );

  /// Fingerprint pebble.
  static final Path fingerprintPebble = Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(3, 3, 18, 18), Radius.circular(7)),
    )
    ..moveTo(9.5, 15)
    ..arcToPoint(
      Offset(14.5, 15),
      radius: Radius.circular(3),
      largeArc: true,
      clockwise: true,
    )
    ..moveTo(7.5, 14.5)
    ..arcToPoint(
      Offset(16.5, 14.5),
      radius: Radius.circular(5),
      largeArc: true,
      clockwise: true,
    )
    ..moveTo(12, 12.5)
    ..lineTo(12, 15.5);

  /// Camera stick.
  static final Path cameraStick = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(6, 2, 12, 20),
        Radius.circular(2.5),
      ),
    )
    ..addOval(Rect.fromCircle(center: Offset(12, 7), radius: 2.5))
    ..moveTo(12, 7)
    ..lineTo(12.01, 7)
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(9, 12, 6, 7), Radius.circular(1)),
    );

  /// Joystick board.
  static final Path joystickBoard = Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(2, 5, 20, 14), Radius.circular(1)),
    )
    ..moveTo(6, 10.5)
    ..lineTo(6, 13.5)
    ..moveTo(4.5, 12)
    ..lineTo(7.5, 12)
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(10, 8, 6, 8), Radius.circular(1)),
    )
    ..moveTo(19, 9)
    ..lineTo(19.01, 9)
    ..moveTo(19, 12)
    ..lineTo(19.01, 12)
    ..moveTo(19, 15)
    ..lineTo(19.01, 15);

  /// Scanner board.
  static final Path scannerBoard = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(5, 7, 14, 15),
        Radius.circular(1.5),
      ),
    )
    ..moveTo(8.5, 7)
    ..lineTo(8.5, 4)
    ..arcToPoint(Offset(10, 2.5), radius: Radius.circular(1.5), clockwise: true)
    ..lineTo(14, 2.5)
    ..arcToPoint(Offset(15.5, 4), radius: Radius.circular(1.5), clockwise: true)
    ..lineTo(15.5, 7)
    ..moveTo(10.5, 4.75)
    ..lineTo(13.5, 4.75)
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(8, 10, 8, 9), Radius.circular(1)),
    );
}
