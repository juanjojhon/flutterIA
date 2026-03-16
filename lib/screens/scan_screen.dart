import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import 'stroke_detector_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  @override
  void initState() {
    super.initState();
    _initializeBle();
  }

  Future<void> _initializeBle() async {
    final bleService = context.read<BleService>();
    await bleService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1929),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A2F4A),
        elevation: 0,
        title: const Text(
          'Tennis Stroke Detector',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Consumer<BleService>(
        builder: (context, bleService, child) {
          return Column(
            children: [
              // Header with connection status
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A2F4A),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _getStatusIcon(bleService.connectionState),
                      size: 60,
                      color: _getStatusColor(bleService.connectionState),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _getStatusText(bleService.connectionState),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Busca tu Arduino Nano 33 BLE',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Scan button
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: bleService.connectionState == BleConnectionState.scanning
                        ? () => bleService.stopScan()
                        : () => bleService.startScan(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: bleService.connectionState == BleConnectionState.scanning
                          ? Colors.orange
                          : const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: bleService.connectionState == BleConnectionState.scanning
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.bluetooth_searching),
                    label: Text(
                      bleService.connectionState == BleConnectionState.scanning
                          ? 'Buscando...'
                          : 'Buscar Dispositivos',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              
              // Device list header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Dispositivos encontrados',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${bleService.scanResults.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 10),
              
              // Device list
              Expanded(
                child: bleService.scanResults.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.bluetooth_disabled,
                              size: 60,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No se encontraron dispositivos',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Presiona buscar para encontrar tu Arduino',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: bleService.scanResults.length,
                        itemBuilder: (context, index) {
                          return _DeviceCard(
                            scanResult: bleService.scanResults[index],
                            onTap: () => _connectToDevice(
                              bleService.scanResults[index].device,
                            ),
                            isConnecting: bleService.connectionState == 
                                BleConnectionState.connecting,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    final bleService = context.read<BleService>();
    
    final success = await bleService.connectToDevice(device);
    
    if (success && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const StrokeDetectorScreen(),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al conectar con el dispositivo'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  IconData _getStatusIcon(BleConnectionState state) {
    switch (state) {
      case BleConnectionState.scanning:
        return Icons.bluetooth_searching;
      case BleConnectionState.connecting:
        return Icons.bluetooth_connected;
      case BleConnectionState.connected:
      case BleConnectionState.recording:
        return Icons.bluetooth_connected;
      case BleConnectionState.disconnected:
        return Icons.bluetooth;
    }
  }

  Color _getStatusColor(BleConnectionState state) {
    switch (state) {
      case BleConnectionState.scanning:
        return Colors.blue;
      case BleConnectionState.connecting:
        return Colors.orange;
      case BleConnectionState.connected:
      case BleConnectionState.recording:
        return const Color(0xFF4CAF50);
      case BleConnectionState.disconnected:
        return Colors.white.withValues(alpha: 0.5);
    }
  }

  String _getStatusText(BleConnectionState state) {
    switch (state) {
      case BleConnectionState.scanning:
        return 'Buscando dispositivos...';
      case BleConnectionState.connecting:
        return 'Conectando...';
      case BleConnectionState.connected:
        return 'Conectado';
      case BleConnectionState.recording:
        return 'Grabando movimientos';
      case BleConnectionState.disconnected:
        return 'Desconectado';
    }
  }
}

class _DeviceCard extends StatelessWidget {
  final ScanResult scanResult;
  final VoidCallback onTap;
  final bool isConnecting;

  const _DeviceCard({
    required this.scanResult,
    required this.onTap,
    required this.isConnecting,
  });

  @override
  Widget build(BuildContext context) {
    final deviceName = scanResult.device.platformName.isNotEmpty
        ? scanResult.device.platformName
        : 'Dispositivo desconocido';
    final isTennisDetector = deviceName.toLowerCase().contains('tennis');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF1A2F4A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isTennisDetector
            ? const BorderSide(color: Color(0xFF4CAF50), width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: isConnecting ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isTennisDetector
                      ? const Color(0xFF4CAF50).withValues(alpha: 0.2)
                      : Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isTennisDetector ? Icons.sports_tennis : Icons.bluetooth,
                  color: isTennisDetector ? const Color(0xFF4CAF50) : Colors.blue,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            deviceName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isTennisDetector)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Tennis',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      scanResult.device.remoteId.toString(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.signal_cellular_alt,
                          size: 14,
                          color: _getSignalColor(scanResult.rssi),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${scanResult.rssi} dBm',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              isConnecting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.chevron_right,
                      color: Colors.white54,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getSignalColor(int rssi) {
    if (rssi >= -50) return const Color(0xFF4CAF50);
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }
}
