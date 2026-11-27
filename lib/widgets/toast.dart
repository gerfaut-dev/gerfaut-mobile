import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A benign confirmation — "Copied", "Setting saved" — gone after three
/// seconds, as on the desktop app. Never for an error or an alert: what
/// matters does not go away by itself.
class Toast extends SnackBar {
  Toast(String message, {super.key})
    : super(content: Text(message), duration: toastDuration);
}

/// How long a toast stays.
const Duration toastDuration = Duration(seconds: 3);

/// Every toast of the app goes through here: it arrives and leaves at
/// the pace of every surface.
extension ShowToast on ScaffoldMessengerState {
  void showToast(String message) => showSnackBar(
    Toast(message),
    snackBarAnimationStyle: GerfautMotion.toast,
  );
}
