import 'dart:async';

import 'package:daily_pedometer/daily_pedometer_storage.dart';
import 'package:flutter/services.dart';
import 'package:daily_pedometer/value_objects.dart';
import 'package:rxdart/rxdart.dart';

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

    final now = DateTime.now();

    final nextMidnight = now.add(const Duration(days: 1)).subtract(Duration(
        hours: now.hour,
        minutes: now.minute,
        seconds: now.second,
        milliseconds: now.millisecond));
    final durationToMidnight = nextMidnight.difference(now);
    final midnightStream = ConcatStream([
      Stream.value(1),
      TimerStream(1, durationToMidnight + const Duration(seconds: 1)),
      Stream.periodic(const Duration(days: 1)),
    ]);

    final stepStream = Stream<dynamic>.value(null).concatWith(
        [_rawStepCountWithTimestampChannel.receiveBroadcastStream()]);

    final stream = CombineLatestStream(
        [stepStream, midnightStream], (values) => values.first as int?);

    stream.listen((stepCountFromBoot) async {
      if (stepCountFromBoot == null) {
        _dailyStepCountStreamController
            .add(_lastStepData!.getDailySteps(DateTime.now()));
        return;
      }

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
