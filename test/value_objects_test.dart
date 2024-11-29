import 'dart:convert';

import 'package:daily_pedometer/value_objects.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest_10y.dart';
import 'package:timezone/standalone.dart';

void main() {
  initializeTimeZones();
  final location = getLocation('Asia/Seoul');
  group('StepData', () {
    test('빈 StepData에 stepCount를 추가하면, 걸음수가 0부터 누적되어야 한다', () {
      final emptyStepData = StepData.empty();
      final firstDay = TZDateTime(location, 2024, 11, 12, 1, 0, 0);

      final stepCount = StepCountWithTimestamp(10, 0, firstDay);
      final stepData = emptyStepData.update(stepCount);
      expect(stepData.getDailySteps(firstDay), 0);

      final stepCount2 = StepCountWithTimestamp(
          12, 0, firstDay.add(const Duration(seconds: 1)));
      final stepData2 = stepData.update(stepCount2);
      expect(stepData2.getDailySteps(firstDay), 2);

      final stepCount3 = StepCountWithTimestamp(
          32, 0, firstDay.add(const Duration(seconds: 3)));
      final stepData3 = stepData2.update(stepCount3);
      expect(stepData3.getDailySteps(firstDay), 22);

      // 날짜가 바뀌었다면, 0부터 누적되어야 한다.
      final secondDay = firstDay.add(const Duration(days: 1));
      expect(stepData3.getDailySteps(secondDay), 0);

      // 날짜 변경 시, 전날 대비 올라간 걸음수가 누적되어야 한다.
      final stepCount4 = StepCountWithTimestamp(64, 0, secondDay);
      final stepData4 = stepData3.update(stepCount4);
      expect(stepData4.getDailySteps(secondDay), 32);

      final stepCount5 = StepCountWithTimestamp(
          128, 0, secondDay.add(const Duration(seconds: 10)));
      final stepData5 = stepData4.update(stepCount5);
      expect(stepData5.getDailySteps(secondDay), 96);
    });

    test('부팅 카운트가 변한 경우에도 걸음이 누적되어야한다.', () {
      final emptyStepData = StepData.empty();
      final firstDay = TZDateTime(location, 2024, 11, 12, 1, 0, 0);
      final stepCount = StepCountWithTimestamp(10, 0, firstDay);
      final stepData = emptyStepData.update(stepCount);
      expect(stepData.getDailySteps(firstDay), 0);

      final stepCount2 = StepCountWithTimestamp(
          32, 0, firstDay.add(const Duration(seconds: 1)));
      final stepData2 = stepData.update(stepCount2);
      expect(stepData2.getDailySteps(firstDay), 22);

      // 새로 부팅됨.
      final stepCount3 = StepCountWithTimestamp(34, 1, firstDay);
      final stepData3 = stepData2.update(stepCount3);
      expect(stepData3.getDailySteps(firstDay), 56);

      // 새로 부팅되었지만, 부팅 카운트가 누락
      final stepCount4 = StepCountWithTimestamp(32, 0, firstDay);
      final stepData4 = stepData3.update(stepCount4);
      expect(stepData4.getDailySteps(firstDay), 88);
    });

    test('json 형태로 변환/로드가 되어야한다', () {
      final emptyStepData = StepData.empty();
      final firstDay = TZDateTime(location, 2024, 11, 12, 1, 0, 0);
      final stepCount = StepCountWithTimestamp(10, 0, firstDay);
      final updatedStepCount = StepCountWithTimestamp(20, 0, firstDay);
      final rebootStepCount = StepCountWithTimestamp(100, 1, firstDay);
      final stepData = emptyStepData
          .update(stepCount)
          .update(updatedStepCount)
          .update(rebootStepCount);

      expect(stepData.getDailySteps(firstDay), 110);

      final json = stepData.toJson();
      expect(json['previousDate'], '2024-11-11');
      expect(json['previousStepCount'], 10);
      expect(json['todayDate'], '2024-11-12');
      expect(json['todayStepCount'], 100);
      expect(json['bootCount'], 1);
      expect(json['stack'], [20]);

      final stepData2 = StepData.fromJson(json);
      expect(stepData2.previousDate, '2024-11-11');
      expect(stepData2.previousStepCount, 10);
      expect(stepData2.todayDate, '2024-11-12');
      expect(stepData2.todayStepCount, 100);
      expect(stepData2.bootCount, 1);
      expect(stepData2.stack, [20]);

      expect(stepData, stepData2);
    });

    test('bootCount가 null이었던 경우에는 부팅 카운트가 변하지 않았다고 가정한다.', () {
      final day1 = TZDateTime(location, 2024, 11, 12, 1, 0, 0);
      final emptyStepData =
          StepData("2024-11-12", 10, "2024-11-12", 100, null, [], null, null);
      expect(emptyStepData.getDailySteps(day1), 90);
      final stepCount1 = StepCountWithTimestamp(110, 1, day1);
      final stepData1 = emptyStepData.update(stepCount1);
      expect(stepData1.getDailySteps(day1), 100);

      final day2 = day1.add(const Duration(days: 1));
      final stepCount2 = StepCountWithTimestamp(120, 1, day2);
      final stepData2 = stepData1.update(stepCount2);
      expect(stepData2.getDailySteps(day2), 10);
    });

    test('bootCount가 null인 상태에서 날짜가 바뀌어도 부팅 카운트가 변하지 않았다고 가정한다.', () {
      final day1 = TZDateTime(location, 2024, 11, 12, 1, 0, 0);
      final emptyStepData =
          StepData("2024-11-12", 10, "2024-11-12", 100, null, [], null, null);
      expect(emptyStepData.getDailySteps(day1), 90);

      final day2 = day1.add(const Duration(days: 1));
      final stepCount2 = StepCountWithTimestamp(110, 1, day2);
      final stepData2 = emptyStepData.update(stepCount2);
      expect(stepData2.getDailySteps(day2), 10);
    });

    test("기존 플러그인에서 새로운 플러그인으로 업데이트 된 경우", () {
      const json =
          '{"previousDate":"2024-11-24", "previousStepCount": 588682, "todayDate": "2024-11-25", "todayStepCount": 620085, "stack": [12]}';

      final stepData = StepData.fromJson(jsonDecode(json));
      expect(stepData.previousDate, '2024-11-24');
      expect(stepData.previousStepCount, 588682);
      expect(stepData.todayDate, '2024-11-25');
      expect(stepData.todayStepCount, 620085);
      expect(stepData.bootCount, null);
      expect(stepData.stack, [12]);
      expect(
          stepData.getDailySteps(TZDateTime(location, 2024, 11, 25, 13, 22, 0)),
          31415);
      expect(
          stepData.getDailySteps(TZDateTime(location, 2024, 11, 26, 13, 22, 0)),
          0);

      final stepCount = StepCountWithTimestamp(
          620086, 9999, TZDateTime(location, 2024, 11, 25, 13, 22, 0));
      final stepData2 = stepData.update(stepCount);
      expect(stepData2.previousDate, '2024-11-24');
      expect(stepData2.previousStepCount, 588682);
      expect(stepData2.todayDate, '2024-11-25');
      expect(stepData2.todayStepCount, 620086);
      expect(stepData2.bootCount, 9999);
      expect(stepData2.stack, [12]);
      expect(
          stepData2
              .getDailySteps(TZDateTime(location, 2024, 11, 25, 13, 22, 0)),
          31416);

      expect(
          stepData2
              .getDailySteps(TZDateTime(location, 2024, 11, 26, 13, 22, 0)),
          0);
    });
  });
}
