import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/pages/settings/sync_config_qr.dart';
import 'package:venera/utils/sync_config_transfer.dart';
import 'package:venera/utils/translations.dart';

/// Regression guard for the desktop "render box with no size" crash: ContentDialog
/// wraps its content in an IntrinsicWidth, and QrImageView uses a LayoutBuilder
/// which has no intrinsic width. Without the fixed-width box around the content,
/// measuring the dialog throws during layout. Pumping the dialog reproduces that
/// path headlessly.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppTranslation.init();
  });

  testWidgets('showSyncConfigQrDialog lays out without error', (tester) async {
    const payload = SyncConfigPayload(
      url: 'https://dav.example.com/venera/',
      user: 'alice',
      pass: 'secret',
      autoSync: true,
      disableSyncFields: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showSyncConfigQrDialog(context, payload),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The dialog actually rendered (the literal, locale-independent PIN label).
    expect(find.text('PIN'), findsOneWidget);
  });
}
