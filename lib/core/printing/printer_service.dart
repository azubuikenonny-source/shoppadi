import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// Why a print did not happen, in words a shop owner can act on.
enum PrintOutcome { printed, noPrinter, bluetoothOff, notFound, failed }

String printOutcomeMessage(PrintOutcome outcome) => switch (outcome) {
      PrintOutcome.printed => 'Printed',
      PrintOutcome.noPrinter => 'No printer chosen yet — set one up first.',
      PrintOutcome.bluetoothOff => 'Turn Bluetooth on, then try again.',
      PrintOutcome.notFound =>
        'That printer is not paired any more. Pair it in Android settings.',
      PrintOutcome.failed => 'The printer did not respond. Is it switched on?',
    };

class PairedPrinter {
  const PairedPrinter({required this.name, required this.mac});

  final String name;
  final String mac;
}

/// Talks to cheap Bluetooth ESC/POS printers. Only paired devices are used, so
/// the app never scans and never needs location permission.
class PrinterService {
  Future<bool> get bluetoothOn async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  Future<List<PairedPrinter>> paired() async {
    try {
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      return [
        for (final device in devices)
          PairedPrinter(
            name: device.name.trim().isEmpty ? 'Unnamed printer' : device.name,
            // The package spells it "macAdress".
            mac: device.macAdress,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Connects if needed, sends the bytes, and leaves the connection open —
  /// reconnecting for every receipt is slow on these printers.
  Future<PrintOutcome> send(List<int> bytes, {required String? mac}) async {
    if (mac == null || mac.isEmpty) return PrintOutcome.noPrinter;
    if (!await bluetoothOn) return PrintOutcome.bluetoothOff;

    try {
      var connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        connected = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      }
      if (!connected) {
        final known = await paired();
        return known.any((printer) => printer.mac == mac)
            ? PrintOutcome.failed
            : PrintOutcome.notFound;
      }

      final written = await PrintBluetoothThermal.writeBytes(bytes);
      return written ? PrintOutcome.printed : PrintOutcome.failed;
    } catch (_) {
      return PrintOutcome.failed;
    }
  }

  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {
      // Nothing useful to do if the socket was already gone.
    }
  }
}
