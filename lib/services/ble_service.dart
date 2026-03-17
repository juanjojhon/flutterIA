import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const int kRecordingDurationSeconds = 3;

/// UUIDs matching the Arduino code
class BleUuids {
  static const String serviceUuid = "180c";
  static const String strokeCharacteristicUuid = "2a56";
  static const String controlCharacteristicUuid = "2a57"; // For start/stop commands
}

/// Enum for stroke types detected by Arduino
enum StrokeType {
  none(0, "Ninguno", ""),
  ascendente(1, "Ascendente", "assets/icons/ascendente.png"),
  derecha(2, "Derecha", "assets/icons/derecha.png"),
  remate(3, "Remate", "assets/icons/remate.png"),
  reves(4, "Reves", "assets/icons/reves.png"),
  saque(5, "Saque", "assets/icons/saque.png");

  final int code;
  final String name;
  final String iconPath;
  
  const StrokeType(this.code, this.name, this.iconPath);
  
  static StrokeType fromCode(int code) {
    return StrokeType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => StrokeType.none,
    );
  }
}

/// Connection state enum
enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  recording,
}

/// BLE Service for managing connection with Arduino Nano 33 BLE
class BleService extends ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _strokeCharacteristic;
  BluetoothCharacteristic? _controlCharacteristic;
  
  BleConnectionState _connectionState = BleConnectionState.disconnected;
  List<ScanResult> _scanResults = [];
  StrokeType _lastStroke = StrokeType.none;
  List<StrokeType> _strokeHistory = [];
  bool _isRecording = false;
  
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _strokeSubscription;
  StreamSubscription? _controlSubscription;
  Timer? _recordingTimer;
  
  // Getters
  BleConnectionState get connectionState => _connectionState;
  List<ScanResult> get scanResults => _scanResults;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  StrokeType get lastStroke => _lastStroke;
  List<StrokeType> get strokeHistory => _strokeHistory;
  bool get isRecording => _isRecording;
  bool get isConnected => _connectionState == BleConnectionState.connected || 
                          _connectionState == BleConnectionState.recording;
  
  /// Initialize and check Bluetooth availability
  Future<bool> initialize() async {
    if (await FlutterBluePlus.isSupported == false) {
      debugPrint("Bluetooth not supported on this device");
      return false;
    }
    
    // Turn on Bluetooth if it's off (Android only)
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      // On Android, you might want to request the user to turn on Bluetooth
      debugPrint("Bluetooth is not enabled");
      return false;
    }
    
    return true;
  }
  
  /// Start scanning for BLE devices
  Future<void> startScan() async {
    if (_connectionState == BleConnectionState.scanning) return;
    
    _scanResults.clear();
    _connectionState = BleConnectionState.scanning;
    notifyListeners();
    
    // Cancel any existing subscription
    await _scanSubscription?.cancel();
    
    // Listen for scan results
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      _scanResults = results.where((r) {
        // Filter for devices with the name "TennisDetector" or showing our service
        return r.device.platformName.isNotEmpty ||
               r.advertisementData.serviceUuids.any(
                 (uuid) => uuid.toString().toLowerCase().contains(BleUuids.serviceUuid)
               );
      }).toList();
      notifyListeners();
    });
    
    // Start scanning
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      androidScanMode: AndroidScanMode.lowLatency,
    );
    
    // When scan completes
    FlutterBluePlus.isScanning.where((val) => val == false).first.then((_) {
      if (_connectionState == BleConnectionState.scanning) {
        _connectionState = BleConnectionState.disconnected;
        notifyListeners();
      }
    });
  }
  
  /// Stop scanning
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _connectionState = BleConnectionState.disconnected;
    notifyListeners();
  }
  
  /// Connect to a device
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      _connectionState = BleConnectionState.connecting;
      notifyListeners();
      
      // Stop scanning first
      await stopScan();
      
      // Connect to device
      await device.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = device;
      
      // Listen for disconnection
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });
      
      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      
      // Find our tennis service
      for (BluetoothService service in services) {
        if (service.uuid.toString().toLowerCase().contains(BleUuids.serviceUuid)) {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            String charUuid = characteristic.uuid.toString().toLowerCase();
            
            if (charUuid.contains(BleUuids.strokeCharacteristicUuid)) {
              _strokeCharacteristic = characteristic;
              
              // Subscribe to notifications
              await characteristic.setNotifyValue(true);
              _strokeSubscription = characteristic.onValueReceived.listen((value) {
                if (value.isNotEmpty && _isRecording) {
                  _handleStrokeReceived(value[0]);
                }
              });
            }
            
            if (charUuid.contains(BleUuids.controlCharacteristicUuid)) {
              _controlCharacteristic = characteristic;
              
              // Subscribe to control notifications to detect when Arduino stops recording
              await characteristic.setNotifyValue(true);
              _controlSubscription = characteristic.onValueReceived.listen((value) {
                if (value.isNotEmpty && value[0] == 0 && _isRecording) {
                  // Arduino signaled that recording stopped
                  _handleRecordingStopped();
                }
              });
            }
          }
        }
      }
      
      _connectionState = BleConnectionState.connected;
      notifyListeners();
      return true;
      
    } catch (e) {
      debugPrint("Connection error: $e");
      _connectionState = BleConnectionState.disconnected;
      notifyListeners();
      return false;
    }
  }
  
/// Disconnect from device
  Future<void> disconnect() async {
    await stopRecording();
    await _strokeSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _controlSubscription?.cancel();
    _recordingTimer?.cancel();
    await _connectedDevice?.disconnect();
    _handleDisconnection();
  }

  void _handleDisconnection() {
    _connectedDevice = null;
    _strokeCharacteristic = null;
    _controlCharacteristic = null;
    _isRecording = false;
    _recordingTimer?.cancel();
    _connectionState = BleConnectionState.disconnected;
    notifyListeners();
  }
  
  /// Handle when recording is stopped (by Arduino or timer)
  void _handleRecordingStopped() {
    _recordingTimer?.cancel();
    _isRecording = false;
    _connectionState = BleConnectionState.connected;
    notifyListeners();
  }
  
  /// Start recording strokes
  Future<bool> startRecording() async {
    if (!isConnected) return false;
    
    try {
      // Send start command (1) to Arduino
      if (_controlCharacteristic != null) {
        await _controlCharacteristic!.write([1], withoutResponse: false);
      }
      
      _isRecording = true;
      _connectionState = BleConnectionState.recording;
      notifyListeners();
      
      // Start a timer that auto-stops after 4 seconds (backup in case Arduino doesn't notify)
      _recordingTimer?.cancel();
      _recordingTimer = Timer(const Duration(seconds: kRecordingDurationSeconds), () {
        if (_isRecording) {
          debugPrint("Recording timer expired - stopping");
          stopRecording();
        }
      });
      
      return true;
    } catch (e) {
      debugPrint("Error starting recording: $e");
      return false;
    }
  }
  
  /// Stop recording strokes
  Future<bool> stopRecording() async {
    _recordingTimer?.cancel();
    
    if (!_isRecording) return true;
    
    try {
      // Send stop command (0) to Arduino
      if (_controlCharacteristic != null) {
        await _controlCharacteristic!.write([0], withoutResponse: false);
      }
      
      _isRecording = false;
      _connectionState = BleConnectionState.connected;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Error stopping recording: $e");
      return false;
    }
  }
  
  /// Handle received stroke data
  void _handleStrokeReceived(int strokeCode) {
    StrokeType stroke = StrokeType.fromCode(strokeCode);
    if (stroke != StrokeType.none) {
      _lastStroke = stroke;
      _strokeHistory.add(stroke);
      notifyListeners();
    }
  }
  
  /// Clear stroke history
  void clearHistory() {
    _strokeHistory.clear();
    _lastStroke = StrokeType.none;
    notifyListeners();
  }
  
  /// Get statistics for each stroke type
  Map<StrokeType, int> getStrokeStatistics() {
    Map<StrokeType, int> stats = {};
    for (var type in StrokeType.values) {
      if (type != StrokeType.none) {
        stats[type] = _strokeHistory.where((s) => s == type).length;
      }
    }
    return stats;
  }
  
  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
