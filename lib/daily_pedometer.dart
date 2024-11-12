import 'dart:async';

import 'package:daily_pedometer/daily_pedometer_storage.dart';
import 'package:flutter/services.dart';
import 'package:daily_pedometer/value_objects.dart';

class DailyPedometer {
  static DailyPedometer? instance;

  final EventChannel _rawStepCountWithTimestampChannel =
      const EventChannel('daily_pedometer_raw_step_count');
  final StreamController<int> _dailyStepCountStreamController =
      StreamController<int>();
  final DailyPedometerStorage _storage = DailyPedometerStorage();
  final methodChannel = const MethodChannel('daily_pedometer');

  factory DailyPedometer() {
    instance ??= DailyPedometer._internal();
    return instance!;
  }

  DailyPedometer._internal();

  StepData? _lastStepData;
  StepData? get lastStepData => _lastStepData;
  int get steps => _lastStepData?.getDailySteps(DateTime.now()) ?? 0;
  Stream<int> get dailyStepCountStream =>
      _dailyStepCountStreamController.stream;

  var isInitialized = false;
  Future<void> initialize(bool isWriteMode) async {
    if (isInitialized) return;

    final bootCount = await getBootCount();

    _lastStepData = await _storage.read();
    _rawStepCountWithTimestampChannel
        .receiveBroadcastStream()
        .listen((event) async {
      final stepCountFromBoot = event as int;
      // bootCount는 안전을 위한 값이므로, 없어도 잘 동작해야함.
      // 따라서 bootCount가 null이면 0으로 가정한다.
      final stepCount = StepCountWithTimestamp(
          stepCountFromBoot, bootCount ?? 0, DateTime.now());
      final stepData = await _storage.read();
      _lastStepData = stepData.update(stepCount);

      if (isWriteMode && _lastStepData != stepData) {
        await _storage.debouncedSave(_lastStepData!);
      }
      _dailyStepCountStreamController
          .add(_lastStepData!.getDailySteps(stepCount.timeStamp));
    });
    isInitialized = true;
  }

  Future<int?> getBootCount() async {
    return await methodChannel.invokeMethod<int>('getBootCount');
  }

  Future<void> refreshSensorListener() async {
    return await methodChannel.invokeMethod<void>('refreshSensorListener');
  }
}
