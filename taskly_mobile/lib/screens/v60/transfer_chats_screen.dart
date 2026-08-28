import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../backup/local_transfer_service.dart';

class TransferChatsSourceScreen extends StatefulWidget {
  const TransferChatsSourceScreen({
    super.key,
    required this.transfer,
  });

  final LocalTransferService transfer;

  @override
  State<TransferChatsSourceScreen> createState() =>
      _TransferChatsSourceScreenState();
}

class _TransferChatsSourceScreenState
    extends State<TransferChatsSourceScreen> {
  TransferSession? _session;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final session = await widget.transfer.startSource();
      if (!mounted) {
        await session.close();
        return;
      }
      setState(() => _session = session);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _session?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer chats')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _error != null
            ? Center(child: Text('$_error'))
            : _session == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Keep this phone unlocked',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'On the new phone, choose “Transfer from old phone” '
                        'and scan this QR. Keep both phones on the same Wi-Fi.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: QrImageView(
                          data: _session!.qrPayload,
                          size: 260,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_rounded, size: 18),
                          SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              'Encrypted one-time device transfer',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }
}

class TransferChatsReceiveScreen extends StatefulWidget {
  const TransferChatsReceiveScreen({
    super.key,
    required this.transfer,
    required this.onRestored,
  });

  final LocalTransferService transfer;
  final Future<void> Function() onRestored;

  @override
  State<TransferChatsReceiveScreen> createState() =>
      _TransferChatsReceiveScreenState();
}

class _TransferChatsReceiveScreenState
    extends State<TransferChatsReceiveScreen> {
  bool _working = false;
  bool _handled = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_working || _handled) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .where((value) => value.startsWith('taskly://transfer'))
        .firstOrNull;
    if (value == null) return;

    _handled = true;
    setState(() => _working = true);
    try {
      await widget.transfer.receiveFromQr(value);
      await widget.onRestored();
    } catch (error) {
      _handled = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan old phone')),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          Center(
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
          ),
          if (_working)
            const ColoredBox(
              color: Colors.black54,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
