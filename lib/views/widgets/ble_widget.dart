import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

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

  final String serviceUuid = "b64cfb1e-045c-4975-89d6-65949bcb35aa";
  final String characteristicUuid = "33737322-fb5c-4a6f-a4d9-e41c1b20c30d";

  List<EcgDataPoint> ecgSpots = [];
  BluetoothDevice? _connectedDevice;

  int? startTimestampMs;
  double runningX = 0;
  late ZoomPanBehavior _zoomPanBehavior;
  static const double fixedWindowSize = 3500.0;

  late ChartSeriesController _chartSeriesController;
  @override
  void initState() {
    super.initState();
    // Calls initBLE after Widget Tree has finished being built.
    // Without it, the BLE util will be inaccessible & cause errors.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initBle());
    _zoomPanBehavior = ZoomPanBehavior(enablePanning: true);
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
      setState(() {
        _connectedDevice = device;
        _resetData();
      });
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
        await targetCharacteristic.setNotifyValue(true);
        targetCharacteristic.onValueReceived.listen(
          (value) => handleNotification(Uint8List.fromList(value)),
        );
      }

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Connected'),
          content: SizedBox(
            width: 200.0,
            height: 100.0,
            child: Column(children: [Text('Successfully connected to $name')]),
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

  void _resetData() {
    ecgSpots.clear();
    startTimestampMs = null;
    runningX = 0;
  }

  @override
  Widget build(BuildContext context) {
    // Define the visible window using absolute time on X axis:
    double maxX = runningX;
    double minX = maxX - fixedWindowSize;
    if (minX < 0) minX = 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("BLE Scanner"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _startScan),
        ],
      ),
      body: _connectedDevice == null
          ? (_bluetoothDevices.isEmpty
                ? const Center(child: Text("No devices found."))
                : ListView.builder(
                    itemCount: _bluetoothDevices.length,
                    itemBuilder: (_, index) =>
                        _buildDeviceTile(_bluetoothDevices[index]),
                  ))
          : Column(
              children: [
                const Text("Connected to ECG device apple"),
                Expanded(
                  child: SfCartesianChart(
                    backgroundColor: Colors.black,
                    plotAreaBorderWidth: 0,
                    primaryXAxis: NumericAxis(
                      minimum: minX,
                      maximum: maxX,
                      interval: 500, // optional, makes ticks every 500ms
                      edgeLabelPlacement: EdgeLabelPlacement.shift,
                    ),
                    primaryYAxis: NumericAxis(
                      minimum: 0,
                      maximum: 4096,
                      interval: 512,
                    ),
                    series: [
                      LineSeries<EcgDataPoint, double>(
                        dataSource: ecgSpots,
                        xValueMapper: (EcgDataPoint dp, _) => dp.x,
                        yValueMapper: (EcgDataPoint dp, _) => dp.y,
                        animationDuration: 0,
                        onRendererCreated: (controller) =>
                            _chartSeriesController = controller,
                      ),
                    ],
                    zoomPanBehavior: _zoomPanBehavior,
                  ),
                ),
              ],
            ),
    );
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
                  Text(
                    bluetoothDeviceName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    bluetoothDevice.remoteId.toString(),
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
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

  void handleNotification(List<int> value) {
    final packet = decodeEcgData(value);
    if (packet == null) return;

    startTimestampMs ??= packet.timestamp;

    _updateDataSource(packet);
  }

  /// Continuously updating the data source based on timer.
  void _updateDataSource(EcgPacket packet) {
    for (int i = 0; i < packet.samples.length; i++) {
      double x =
          (packet.timestamp - (startTimestampMs ?? packet.timestamp))
              .toDouble() +
          i * 4;
      double y = packet.samples[i].toDouble();

      ecgSpots.add(EcgDataPoint(x, y));

      // Update `runningX` to reflect most recent x value
      runningX = x;

      _chartSeriesController.updateDataSource(
        addedDataIndexes: [ecgSpots.length - 1],
      );
    }

    // Remove old data
    double cutoff = ecgSpots.last.x - fixedWindowSize;
    int removedCount = 0;

    while (ecgSpots.isNotEmpty && ecgSpots.first.x < cutoff) {
      ecgSpots.removeAt(0);
      removedCount++;
    }

    if (removedCount > 0) {
      _chartSeriesController.updateDataSource(
        removedDataIndexes: List.generate(removedCount, (index) => index),
      );
    }

    setState(() {});
  }
}

class EcgPacket {
  final List<int> samples;
  final int timestamp;
  EcgPacket(this.samples, this.timestamp);
}

class EcgDataPoint {
  final double x;
  final double y;
  EcgDataPoint(this.x, this.y);

  double getX() {
    return x;
  }
}

EcgPacket? decodeEcgData(List<int> value) {
  if (value.length != 24) {
    print("Unexpected packet size: ${value.length}");
    return null;
  }

  final bytes = Uint8List.fromList(value);
  final byteData = ByteData.sublistView(bytes);

  // 10 samples
  List<int> samples = [];
  for (int i = 0; i < 10; i++) {
    int sample = byteData.getUint16(i * 2, Endian.little);
    samples.add(sample);
  }
  // Timestamp is at byte 20
  int timestamp = byteData.getUint32(20, Endian.little);
  return EcgPacket(samples, timestamp);
}
