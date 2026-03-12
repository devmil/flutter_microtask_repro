import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

int _nestingDepth = 0;

final errorLogStreamController = StreamController<List<String>>.broadcast();
final errorList = List<String>.empty(growable: true);

void clearErrors() {
  errorList.clear();
  errorLogStreamController.add([]);
}

void addError(String error) {
  errorList.add(error);
  errorLogStreamController.add(List<String>.from(errorList, growable: false));
}

void main() {
  // Catch Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    final errorMsg = 'FlutterError: ${details.exception}';
    addError(errorMsg);
    logMessage('$errorMsg\n${details.stack}');
  };

  // Catch platform/VM-level errors (including Stack Overflow)
  PlatformDispatcher.instance.onError = (error, stack) {
    final errorMsg = 'PlatformError: $error';
    addError(errorMsg);
    logMessage('$errorMsg\n$stack');
    return true; // Handled
  };

  runZonedGuarded(
    () {
      runApp(const MyApp());
    },
    (e, s) {
      final errorMsg = 'ZoneError: $e';
      addError(errorMsg);
      logMessage('$errorMsg\n$s');
    },
  );
}

void logMessage(String message) {
  debugPrint(message);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Microtask Loop Repro',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _heartbeat = false;
  int _tickCount = 0;
  int _widgetKey = 0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    // Periodic timer to check if microtask system is responsive
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      scheduleMicrotask(() {
        setState(() {
          _heartbeat = !_heartbeat;
        });
      });
      setState(() {
        _tickCount++;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Microtask Loop Repro'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Heartbeat indicator - should keep blinking if microtask system works
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite, color: _heartbeat ? Colors.red : Colors.grey, size: 32),
                const SizedBox(width: 8),
                Text('Heartbeat: $_tickCount', style: const TextStyle(fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _heartbeat ? '● ALIVE' : '○ ALIVE',
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            AnimatedProgressBar(key: ValueKey(_widgetKey)),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _widgetKey++;
                  logMessage("#### Force dispose & recreate (key: $_widgetKey)");
                });
              },
              child: const Text('Dispose & Recreate'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Dispose & Recreate: forces new State\n'
              'If heartbeat and alive toggling stops, microtask loop is blocked\n'
              'wait till depth is > 2000 and then tap "Dispose & Recreate".',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Error log panel
            Container(
              width: 350,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Error Log', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        GestureDetector(
                          onTap: () => clearErrors(),
                          child: const Text('Clear', style: TextStyle(color: Colors.blue, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: StreamBuilder<List<String>>(
                      stream: errorLogStreamController.stream,
                      initialData: [],
                      builder: (ctx, snapshot) {
                        final errors = snapshot.data ?? [];
                        if (errors.isEmpty) {
                          return const Center(
                            child: Text('No errors', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.all(4),
                          itemCount: errors.length,
                          itemBuilder: (context, index) =>
                              Text(errors[index], style: const TextStyle(fontSize: 10, color: Colors.red)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnimatedProgressBar extends StatefulWidget {
  const AnimatedProgressBar({super.key});

  @override
  State<AnimatedProgressBar> createState() => _AnimatedProgressBarState();
}

class _AnimatedProgressBarState extends State<AnimatedProgressBar> {
  static const Duration animDuration = Duration(milliseconds: 10);

  bool _isAnimated = true;
  int _currentDepth = 0;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    logMessage("#### Animation started");
    refreshBars();
  }

  @override
  void dispose() {
    logMessage("#### Animation stopped");
    _isAnimated = false;
    super.dispose();
  }

  /// Endless Future loop - potentially problematic pattern.
  /// This may cause microtask loop issues when widget is disposed
  /// if the pending Future chain is too long causing a Stack Overflow exception
  Future<void> refreshBars() async {
    _nestingDepth++;
    _currentDepth++;
    setState(() {
      _progress += 0.02;
      if (_progress > 1.0) _progress = 0.0;
    });

    await Future<void>.delayed(animDuration + const Duration(milliseconds: 5));

    if (_isAnimated) {
      await refreshBars();
    }
    _nestingDepth--;
    _currentDepth--;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 350,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Loading...',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
              ),
              Text(
                'Depth: $_currentDepth / $_nestingDepth',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 12,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text('${(_progress * 100).toInt()}%', style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}
