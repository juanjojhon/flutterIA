import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import 'scan_screen.dart';

class StrokeDetectorScreen extends StatefulWidget {
  const StrokeDetectorScreen({super.key});

  @override
  State<StrokeDetectorScreen> createState() => _StrokeDetectorScreenState();
}

class _StrokeDetectorScreenState extends State<StrokeDetectorScreen> {
  Timer? _countdownTimer;
  int _remainingSeconds = kRecordingDurationSeconds;
  bool _wasRecording = false;

  @override
  void initState() {
    super.initState();
    // Listen to BleService changes to detect auto-stop
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bleService = context.read<BleService>();
      bleService.addListener(_onBleServiceChanged);
    });
  }

  void _onBleServiceChanged() {
    final bleService = context.read<BleService>();
    // Detect when recording stops (either manually or automatically)
    if (_wasRecording && !bleService.isRecording) {
      _stopCountdown();
    }
    _wasRecording = bleService.isRecording;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    final bleService = context.read<BleService>();
    bleService.removeListener(_onBleServiceChanged);
    super.dispose();
  }

  void _startCountdown() {
    _remainingSeconds = kRecordingDurationSeconds;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _remainingSeconds = kRecordingDurationSeconds;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1929),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A2F4A),
        elevation: 0,
        title: Consumer<BleService>(
          builder: (context, bleService, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: bleService.isConnected
                        ? const Color(0xFF4CAF50)
                        : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  bleService.connectedDevice?.platformName ?? 'TennisDetector',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            );
          },
        ),
        centerTitle: true,
        actions: [
          Consumer<BleService>(
            builder: (context, bleService, child) {
              return IconButton(
                icon: const Icon(Icons.bluetooth_disabled, color: Colors.white),
                onPressed: () async {
                  await bleService.disconnect();
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ScanScreen(),
                      ),
                    );
                  }
                },
                tooltip: 'Desconectar',
              );
            },
          ),
        ],
      ),
      body: Consumer<BleService>(
        builder: (context, bleService, child) {
          return Column(
            children: [
              // Last stroke display
              Expanded(
                flex: 2,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2F4A),
                    borderRadius: BorderRadius.circular(24),
                    border: bleService.isRecording
                        ? Border.all(
                            color: const Color(0xFF4CAF50),
                            width: 3,
                          )
                        : null,
                    boxShadow: bleService.isRecording
                        ? [
                            BoxShadow(
                              color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (bleService.isRecording)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'GRABANDO $_remainingSeconds s',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      _StrokeIcon(stroke: bleService.lastStroke),
                      const SizedBox(height: 20),
                      Text(
                        bleService.lastStroke == StrokeType.none
                            ? 'Esperando golpe...'
                            : bleService.lastStroke.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (bleService.lastStroke != StrokeType.none)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Ultimo golpe detectado',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              
              // Recording controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: bleService.isRecording
                            ? () {
                                bleService.stopRecording();
                                _stopCountdown();
                              }
                            : () {
                                bleService.startRecording();
                                _startCountdown();
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: bleService.isRecording
                              ? Colors.red
                              : const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: Icon(
                          bleService.isRecording ? Icons.stop : Icons.play_arrow,
                          size: 28,
                        ),
                        label: Text(
                          bleService.isRecording ? 'DETENER' : 'INICIAR GRABACION',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2F4A),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: IconButton(
                        onPressed: () => bleService.clearHistory(),
                        icon: const Icon(Icons.delete_outline),
                        color: Colors.white,
                        iconSize: 28,
                        padding: const EdgeInsets.all(14),
                        tooltip: 'Limpiar historial',
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Statistics
              Expanded(
                flex: 2,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2F4A),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Estadisticas',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Total: ${bleService.strokeHistory.length}',
                              style: const TextStyle(
                                color: Color(0xFF4CAF50),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _StrokeStatistics(
                          statistics: bleService.getStrokeStatistics(),
                          total: bleService.strokeHistory.length,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StrokeIcon extends StatelessWidget {
  final StrokeType stroke;

  const _StrokeIcon({required this.stroke});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    
    switch (stroke) {
      case StrokeType.ascendente:
        icon = Icons.arrow_upward;
        color = Colors.blue;
        break;
      case StrokeType.derecha:
        icon = Icons.arrow_forward;
        color = const Color(0xFF4CAF50);
        break;
      case StrokeType.remate:
        icon = Icons.bolt;
        color = Colors.orange;
        break;
      case StrokeType.reves:
        icon = Icons.arrow_back;
        color = Colors.purple;
        break;
      case StrokeType.saque:
        icon = Icons.sports_tennis;
        color = Colors.red;
        break;
      case StrokeType.none:
        icon = Icons.sports_tennis;
        color = Colors.white24;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 64,
        color: color,
      ),
    );
  }
}

class _StrokeStatistics extends StatelessWidget {
  final Map<StrokeType, int> statistics;
  final int total;

  const _StrokeStatistics({
    required this.statistics,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final strokeTypes = [
      StrokeType.ascendente,
      StrokeType.derecha,
      StrokeType.remate,
      StrokeType.reves,
      StrokeType.saque,
    ];

    return ListView.builder(
      itemCount: strokeTypes.length,
      itemBuilder: (context, index) {
        final type = strokeTypes[index];
        final count = statistics[type] ?? 0;
        final percentage = total > 0 ? (count / total) : 0.0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _getStrokeColor(type).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getStrokeIcon(type),
                  color: _getStrokeColor(type),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          type.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '$count',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: percentage,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getStrokeColor(type),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getStrokeColor(StrokeType type) {
    switch (type) {
      case StrokeType.ascendente:
        return Colors.blue;
      case StrokeType.derecha:
        return const Color(0xFF4CAF50);
      case StrokeType.remate:
        return Colors.orange;
      case StrokeType.reves:
        return Colors.purple;
      case StrokeType.saque:
        return Colors.red;
      case StrokeType.none:
        return Colors.grey;
    }
  }

  IconData _getStrokeIcon(StrokeType type) {
    switch (type) {
      case StrokeType.ascendente:
        return Icons.arrow_upward;
      case StrokeType.derecha:
        return Icons.arrow_forward;
      case StrokeType.remate:
        return Icons.bolt;
      case StrokeType.reves:
        return Icons.arrow_back;
      case StrokeType.saque:
        return Icons.sports_tennis;
      case StrokeType.none:
        return Icons.help_outline;
    }
  }
}
