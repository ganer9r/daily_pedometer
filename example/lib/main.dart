import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:daily_pedometer/daily_pedometer.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeService();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    // String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    // try {
    //   platformVersion = await _dailyPedometerPlugin.getPlatformVersion() ??
    //       'Unknown platform version';
    // } on PlatformException {
    //   platformVersion = 'Failed to get platform version.';
    // }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    final pedometer = DailyPedometer();
    await pedometer.initialize(false);
    setState(() {
      _platformVersion = " ${pedometer.steps} 걸음이다앗!";
    });

    pedometer.dailyStepCountStream.listen((event) async {
      setState(() {
        print("stepCountStream : $event");
        _platformVersion = " $event 걸음이다앗!";
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Text('Running on: $_platformVersion\n'),
        ),
      ),
    );
  }
}

const notificationChannelId = 'my_foreground';
Future<void> initializeService() async {
  if (!Platform.isAndroid) return;

  final service = FlutterBackgroundService();
  service.invoke("stopService");

  /// OPTIONAL, using custom notification channel id
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId, // id
    'MY FOREGROUND SERVICE', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isIOS || Platform.isAndroid) {
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        iOS: DarwinInitializationSettings(),
        android: AndroidInitializationSettings('ic_bg_service_small'),
      ),
    );
  }

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      // this will be executed when app is in foreground or background in separated isolate
      onStart: onStart,

      // auto start service
      autoStart: true,
      isForegroundMode: true,

      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'AWESOME SERVICE',
      initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      // auto start service
      autoStart: true,

      // this will be executed when app is in foreground in separated isolate
      onForeground: onStart,

      // you have to enable background fetch capability on xcode project
      // onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  print("111111 : 11");
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      print("111111 : 1");
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      print("111111 : 2");
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    print("111111 : 3");
    service.stopSelf();
  });

  if (service is AndroidServiceInstance) {
    DailyPedometer pedometer = DailyPedometer();
    await pedometer.initialize(true);
    print("DailyPedometer foregrondService ${pedometer.steps}");

    flutterLocalNotificationsPlugin.show(
      888,
      'test steps',
      'today steps : ${pedometer.steps}',
      const NotificationDetails(
        android: AndroidNotificationDetails(
            notificationChannelId, notificationChannelId,
            icon: 'ic_bg_service_small', ongoing: true),
      ),
    );

    pedometer.dailyStepCountStream.listen((event) async {
      print("DailyPedometer foregrondService $event");
      // 여기서 push 처리 하는게 더 좋지만 현재는 백그라운드 제어 불가능..
      flutterLocalNotificationsPlugin.show(
        888,
        'test steps',
        'today steps : $event',
        const NotificationDetails(
          android: AndroidNotificationDetails(
              notificationChannelId, notificationChannelId,
              icon: 'ic_bg_service_small', ongoing: true),
        ),
      );
    });

    // pedometer.setMode(true);
    // pedometer.stepCountStream.listen((event) async {
    //   // 여기서 push 처리 하는게 더 좋지만 현재는 백그라운드 제어 불가능..
    //   service.setForegroundNotificationInfo(
    //     title: 'test steps',
    //     content: 'today steps : $event',
    //   );
    // });
  }

  // 나중에 백그라운드 제어가 되면, 이 부분을 제거하고 DailyPedometer.stepCountStream.listen( 에서 처리하면 좋음!
  // if (service is AndroidServiceInstance) {
  //   if (!await service.isForegroundService()) return;

  //   Timer.periodic(const Duration(seconds: 1), (timer) async {
  //     int step = pedometer.steps;

  //     // if you don't using custom notification, uncomment this
  //     service.setForegroundNotificationInfo(
  //       title: '${timer}',
  //       content: 'today steps : $step',
  //     );
  //   });
  // }
}
