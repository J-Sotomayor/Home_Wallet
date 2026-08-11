import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/transactions/domain/finance_balances.dart';
import '../../features/transactions/domain/finance_models.dart';

class NotificationService {
  NotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    FlutterLocalNotificationsPlugin? localNotifications,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _local = localNotifications ?? FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'homewallet_smart_alerts',
    'Alertas inteligentes',
    description: 'Presupuestos, metas, recurrencias y actividad del hogar.',
    importance: Importance.high,
  );

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FlutterLocalNotificationsPlugin _local;
  String? _currentUid;
  String? _currentToken;
  StreamSubscription<String>? _tokenSubscription;

  Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _local.initialize(settings);
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      show(
        title: notification.title ?? 'HomeWallet',
        body: notification.body ?? 'Tienes una novedad en tu hogar.',
      );
    });
  }

  Future<bool> isEnabled(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    // Ask for notification permission only after the user enables the feature.
    // Cada instalación debe registrar su propio token. El usuario todavía
    // puede desactivar la función explícitamente desde Perfil.
    return preferences.getBool(_enabledKey(uid)) ?? true;
  }

  Future<bool> setEnabled(String uid, bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey(uid), enabled);
    if (enabled) {
      return registerUser(uid);
    } else {
      await unregisterUser(uid);
      return false;
    }
  }

  Future<bool> registerUser(String uid) async {
    _currentUid = uid;
    if (!await isEnabled(uid)) return false;
    final permission = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_enabledKey(uid), false);
      return false;
    }
    if (!kIsWeb && Platform.isAndroid) {
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    final token = await _messaging.getToken();
    if (token == null) return false;
    await _saveToken(uid, token);
    await _tokenSubscription?.cancel();
    _tokenSubscription = _messaging.onTokenRefresh.listen(
      (value) => _saveToken(uid, value),
    );
    return true;
  }

  Future<void> unregisterUser(String uid) async {
    final token = _currentToken;
    if (token != null) {
      final id = await _tokenId(token);
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(id)
          .delete();
    }
    if (_currentUid == uid) {
      await _tokenSubscription?.cancel();
      _tokenSubscription = null;
      _currentUid = null;
      _currentToken = null;
    }
  }

  Future<void> evaluateSmartAlerts({
    required String uid,
    required String householdId,
    required List<FinanceTransaction> transactions,
    required List<FinancePlan> plans,
  }) async {
    if (!await isEnabled(uid)) return;
    final preferences = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final balances = FinanceBalances.calculate(transactions, plans);
    if (balances.uncoveredExpenses > 0) {
      await _showOnce(
        preferences,
        '$householdId-empty-$monthKey',
        title: 'Tu saldo disponible se agotó',
        body: 'Hay gastos sin cubrir. Revisa su origen y tus próximos pagos.',
      );
    }
    for (final plan in plans.where((item) => item.isActive)) {
      final current = automaticPlanProgress(plan, transactions, now);
      final progress = plan.targetMinor == 0 ? 0.0 : current / plan.targetMinor;
      if (plan.kind == FinancePlanKind.budget &&
          progress >= plan.alertThreshold) {
        final level = progress >= 1 ? 'limit' : 'warning';
        await _showOnce(
          preferences,
          '$householdId-budget-${plan.id}-$monthKey-$level',
          title:
              progress >= 1
                  ? 'Presupuesto agotado'
                  : 'Presupuesto por llegar al límite',
          body:
              '${plan.name}: ${(progress * 100).round()}% utilizado este mes.',
        );
      }
      if (plan.kind == FinancePlanKind.goal && progress >= 1) {
        await _showOnce(
          preferences,
          '$householdId-goal-${plan.id}-complete',
          title: '¡Meta alcanzada!',
          body: 'Completaste ${plan.name}.',
        );
      } else if (plan.kind == FinancePlanKind.goal &&
          plan.deadline != null &&
          plan.deadline!.difference(now).inDays <= 7 &&
          !plan.deadline!.isBefore(now)) {
        await _showOnce(
          preferences,
          '$householdId-goal-${plan.id}-deadline-${plan.deadline!.toIso8601String()}',
          title: 'Tu meta se acerca a la fecha límite',
          body:
              '${plan.name}: faltan ${(100 - progress * 100).clamp(0, 100).round()}%.',
        );
      }
    }
  }

  Future<void> show({required String title, required String body}) async {
    await _local.show(
      DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'homewallet_smart_alerts',
          'Alertas inteligentes',
          channelDescription:
              'Presupuestos, metas, recurrencias y actividad del hogar.',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> _showOnce(
    SharedPreferences preferences,
    String key, {
    required String title,
    required String body,
  }) async {
    final storageKey = 'notification.shown.$key';
    if (preferences.getBool(storageKey) == true) return;
    await show(title: title, body: body);
    await preferences.setBool(storageKey, true);
  }

  Future<void> _saveToken(String uid, String token) async {
    _currentToken = token;
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc(await _tokenId(token))
        .set({
          'token': token,
          'platform':
              kIsWeb
                  ? 'web'
                  : Platform.isIOS
                  ? 'ios'
                  : 'android',
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<String> _tokenId(String token) async {
    final hash = await Sha256().hash(utf8.encode(token));
    return hash.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String _enabledKey(String uid) => 'notifications.enabled.$uid';
}
