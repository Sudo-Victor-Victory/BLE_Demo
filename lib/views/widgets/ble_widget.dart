import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleScanner extends StatefulWidget {
  const BleScanner({super.key});

  @override
  State<BleScanner> createState() => _BleScannerState();
}

class _BleScannerState extends State<BleScanner> {
  // The list of devices
  List<ScanResult> _bluetoothDevices = [];

  // Used to prevent the Bluetooth adapter from duplicating resources
  bool _isScanningForBluetoothDevices = false;

  // Subscription to asynchronously retreive List<ScanResult> which has
  // Bluetooth devices. Will be initialized on retrival of BLE devices.
  late final StreamSubscription<List<ScanResult>> _scanSubscription;

  // Variables used in accessing a characteristic from the BLE perihperal
  String serviceUuid = "b64cfb1e-045c-4975-89d6-65949bcb35aa";
  String characteristicUuid = "33737322-fb5c-4a6f-a4d9-e41c1b20c30d";
  String? decodedValue;

  @override
  void initState() {
    super.initState();
    // Calls initBLE after Widget Tree has finished being built.
    // Without it, the BLE util will be inaccessible & cause errors.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initBle());
  }

  Future<void> _initBle() async {
    try {
      await _requestPermissions();
      // Allows us to scan for BLE dev. if the initial state
      // of the Bluetooth adapter is on. Otherwise the adapater has issues.
      final state = await FlutterBluePlus.adapterState.first;
      if (state == BluetoothAdapterState.on) {
        _listenScanResults();
        await _startScan();
      } else {
        print("Bluetooth is not ON");
      }
    } catch (e) {
      print("BLE init error: $e");
    }
  }

  Future<void> _requestPermissions() async {
    if (!await Permission.bluetoothScan.request().isGranted) {
      throw Exception("Bluetooth scan permission not granted");
    }

    if (!await Permission.bluetoothConnect.request().isGranted) {
      throw Exception("Bluetooth connect permission not granted");
    }

    if (!await Permission.location.request().isGranted) {
      throw Exception("Location permission not granted");
    }
  }

  void _listenScanResults() {
    // Updates _scanSubscription based on the stream of scan results
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (!listEquals(_bluetoothDevices, results)) {
        // Rebuilds the widget with the new list of devices
        setState(() => _bluetoothDevices = List.from(results));
      }
    });
  }

  Future<void> _startScan() async {
    if (_isScanningForBluetoothDevices) {
      return;
    }
    // A scan started - therefore we must set the bool to prevent dup. scans.
    setState(() => _isScanningForBluetoothDevices = true);
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e) {
      print("Scan failed: $e");
    } finally {
      setState(() => _isScanningForBluetoothDevices = false);
    }
  }

  @override
  void dispose() {
    // Stops the stream from receiving updates.
    _scanSubscription.cancel();
    // Stops the bluetooth scan.
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _connectToDevice(BluetoothDevice device, String name) async {
    try {
      if (_isScanningForBluetoothDevices) {
        await FlutterBluePlus.stopScan();
        setState(() => _isScanningForBluetoothDevices = false);
      }

      print('Connecting to ${device.remoteId}');
      await device.connect(timeout: const Duration(seconds: 10));
      print('Connected to ${device.remoteId}');

      // Ensures that user is still on the same page after waiting to
      // connect to the bluetooth device
      if (!mounted) {
        return;
      }
      List<BluetoothService> services = await device.discoverServices();
      BluetoothCharacteristic? targetCharacteristic;

      for (var service in services) {
        if (service.uuid.str == serviceUuid) {
          for (var c in service.characteristics) {
            if (c.uuid.str == characteristicUuid) {
              targetCharacteristic = c;
              break;
            }
          }
        }
      }
      if (targetCharacteristic != null) {
        List<int> value = await targetCharacteristic.read();
        print("Read value: $value");

        // 🧠 Convert value to string if applicable
        decodedValue = String.fromCharCodes(value);
      }
      decodedValue = decodedValue ?? "No data found";
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Connected'),
          content: SizedBox(
            width: 200.0,
            height: 100.0,
            child: Column(
              children: [
                Text('Successfully connected to $name'),
                Center(child: Text(decodedValue!)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('Connection failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to connect to $name')));
      }
    }
  }

  // Creates visual and ontap for a BLE scan result
  Widget _buildDeviceTile(ScanResult result) {
    final bluetoothDevice = result.device;
    final bluetoothDeviceName = bluetoothDevice.platformName.isNotEmpty
        ? bluetoothDevice.platformName
        : "Unnamed Device";

    return InkWell(
      onTap: () => _connectToDevice(bluetoothDevice, bluetoothDeviceName),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildText(bluetoothDeviceName, 16, FontWeight.bold),
                  const SizedBox(height: 4),
                  _buildText(
                    bluetoothDevice.remoteId.toString(),
                    14,
                    FontWeight.normal,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
            const Icon(Icons.bluetooth),
          ],
        ),
      ),
    );
  }

  // Extracted method to build Text widget
  Text _buildText(
    String text,
    double fontSize,
    FontWeight fontWeight, {
    Color color = Colors.black,
  }) {
    return Text(
      text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("BLE Scanner"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _startScan),
        ],
      ),
      body: _bluetoothDevices.isEmpty
          ? const Center(child: Text("No devices found."))
          : ListView.builder(
              itemCount: _bluetoothDevices.length,
              itemBuilder: (_, device) =>
                  _buildDeviceTile(_bluetoothDevices[device]),
            ),
    );
  }
}
