import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/notifications.dart';

/// What the native side of the plugin keeps of what is on screen, and
/// answers the way each platform does: Android knows a notification by
/// its id and tag and hands the tag back, iOS by its id alone and hands
/// the payload back.
class _Screen {
  _Screen({required this.android});

  final bool android;
  final List<({int id, String? tag, String? payload})> up = [];

  Future<Object?> call(MethodCall call) async {
    switch (call.method) {
      case 'show':
        final args = call.arguments as Map<Object?, Object?>;
        final id = args['id']! as int;
        final specifics = args['platformSpecifics'] as Map<Object?, Object?>?;
        final tag = android ? (specifics?['tag'] as String?) : null;
        final payload = args['payload'] as String?;
        up.removeWhere((n) => n.id == id && n.tag == tag);
        up.add((id: id, tag: tag, payload: payload));
      case 'cancel':
        if (android) {
          final args = call.arguments as Map<Object?, Object?>;
          up.removeWhere(
            (n) => n.id == args['id'] && n.tag == args['tag'] as String?,
          );
        } else {
          up.removeWhere((n) => n.id == call.arguments);
        }
      case 'getActiveNotifications':
        return [
          for (final n in up)
            {
              'id': n.id,
              if (android) 'tag': n.tag,
              if (!android && n.payload != '') 'payload': n.payload,
            },
        ];
      case 'initialize':
        return true;
    }
    return null;
  }
}

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

Future<_Screen> _on(TargetPlatform platform) async {
  debugDefaultTargetPlatformOverride = platform;
  // Unset until something registers one, as in a test that never did.
  FlutterLocalNotificationsPlatform? previous;
  try {
    previous = FlutterLocalNotificationsPlatform.instance;
  } on Error {
    previous = null;
  }
  final android = platform == TargetPlatform.android;
  if (android) {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  } else {
    IOSFlutterLocalNotificationsPlugin.registerWith();
  }
  final screen = _Screen(android: android);
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, screen.call);
  addTearDown(() {
    debugDefaultTargetPlatformOverride = null;
    if (previous != null) FlutterLocalNotificationsPlatform.instance = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });
  return screen;
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('notifications of a wallet on $platform', () {
      test('are taken off, the others stay', () async {
        final screen = await _on(platform);
        final service = LocalNotificationService();
        await service.show(1, 'Cold', 'a', walletId: 'w1');
        await service.show(2, 'Cold', 'b', walletId: 'w1');
        await service.show(3, 'Spending', 'c', walletId: 'w2');
        await service.show(4, 'Gerfaut', 'More is coming');

        await service.cancelForWallet('w1');

        expect(screen.up.map((n) => n.id), [3, 4]);
      });

      test('a payment between two wallets is taken off for one only', () async {
        final screen = await _on(platform);
        final service = LocalNotificationService();
        // The same transaction, said in each wallet under its own id.
        await service.show(
          postedId(
            const TxNotice(
              title: 't',
              body: 'b',
              kind: NoticeKind.transaction,
              payment: (walletId: 'w1', txid: 'move'),
            ),
          ),
          'Cold',
          'Sent',
          walletId: 'w1',
        );
        await service.show(
          postedId(
            const TxNotice(
              title: 't',
              body: 'b',
              kind: NoticeKind.transaction,
              payment: (walletId: 'w2', txid: 'move'),
            ),
          ),
          'Spending',
          'Received',
          walletId: 'w2',
        );

        await service.cancelForWallet('w2');

        expect(screen.up, hasLength(1));
      });

      test('nothing happens when none is on screen', () async {
        final screen = await _on(platform);
        await LocalNotificationService().cancelForWallet('w1');
        expect(screen.up, isEmpty);
      });
    });
  }
}
