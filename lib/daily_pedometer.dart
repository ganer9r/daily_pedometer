import 'dart:async';

import 'package:daily_pedometer/daily_pedometer_storage.dart';
import 'package:flutter/services.dart';
import 'package:daily_pedometer/value_objects.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:rxdart/rxdart.dart';
import 'package:timezone/data/latest.dart';
import 'package:timezone/standalone.dart' as tz;

class DailyPedometer {
  static DailyPedometer? instance;

  final EventChannel _rawStepCountWithTimestampChannel =
      const EventChannel('daily_pedometer_raw_step_count');
  final StreamController<int> _dailyStepCountStreamController =
      StreamController<int>();
  final methodChannel = const MethodChannel('daily_pedometer');
  DailyPedometerStorage? _storage;

  get storage => _storage;

  tz.Location? _timezone;

  factory DailyPedometer() {
    instance ??= DailyPedometer._internal();
    return instance!;
  }

  DailyPedometer._internal();

  StepData? _lastStepData;
  StepData? get lastStepData => _lastStepData;
  int get steps =>
      _lastStepData?.getDailySteps(tz.TZDateTime.now(_timezone!)) ?? 0;
  Stream<int> get dailyStepCountStream =>
      _dailyStepCountStreamController.stream;

  var isInitialized = false;
  Future<void> initialize(bool isWriteMode,
      [String? timezone, bool initTimeZoneDB = true]) async {
    if (isInitialized) return;

    // 중복 초기화 방지
    isInitialized = true;

    if (initTimeZoneDB) {
      initializeTimeZones();
    }
    if (timezone != null) {
      _timezone = tz.getLocation(timezone);
    } else {
      _timezone = tz.getLocation(await FlutterTimezone.getLocalTimezone());
    }

    _storage = DailyPedometerStorage(_timezone!);

    final bootCount = await getBootCount();

    _lastStepData = await _storage!.read();

    final now = tz.TZDateTime.now(_timezone!);

    final nextMidnight = now.add(const Duration(days: 1)).subtract(Duration(
        hours: now.hour,
        minutes: now.minute,
        seconds: now.second,
        milliseconds: now.millisecond,
        microseconds: now.microsecond));
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
      if (stepCountFromBoot == null && _lastStepData != null) {
        _dailyStepCountStreamController
            .add(_lastStepData!.getDailySteps(tz.TZDateTime.now(_timezone!)));
        return;
      }

      // bootCount는 안전을 위한 값이므로, 없어도 잘 동작해야함.
      // 따라서 bootCount가 null이면 0으로 가정한다.
      final stepCount = StepCountWithTimestamp(
          stepCountFromBoot!, bootCount ?? 0, tz.TZDateTime.now(_timezone!));
      final stepData = await _storage!.read();
      _lastStepData = stepData.update(stepCount);

      if (isWriteMode && _lastStepData != stepData) {
        await _storage!.debouncedSave(_lastStepData!);
      }
      _dailyStepCountStreamController
          .add(_lastStepData!.getDailySteps(stepCount.timeStamp));
    });
  }

  Future<int?> getBootCount() async {
    return await methodChannel.invokeMethod<int>('getBootCount');
  }

  Future<void> refreshSensorListener() async {
    return await methodChannel.invokeMethod<void>('refreshSensorListener');
  }
}
