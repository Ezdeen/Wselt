import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

// ============================ الإعدادات ============================
const String kStartUrl = 'https://app.futureroots.site/wa/';
const Set<String> kAllowedDomains = {
  'futureroots.site',
  'app.futureroots.site',
  'www.futureroots.site',
};

/// الاسم الظاهر للمستخدم (شريط المهام + عنوان الإشعار الافتراضي)
const String kAppTitle = 'تطبيق وصلت';
const Color kBrandColor = Color(0xFF6A2C91);
const String kTopic = 'all'; // اشتراك تلقائي لإرسال إشعار لكل المستخدمين

/// قناة الإشعارات العاجلة.
/// مهم: أهمية القناة في أندرويد لا يمكن تغييرها بعد إنشائها، لذلك استُخدم معرّف
/// جديد (v2). يجب أن يطابق المعرّف في AndroidManifest.xml و server/send_fcm.php.
const String kUrgentChannelId = 'wasalt_urgent_v2';
const String kNotificationIcon = 'ic_stat_wasalt';
const AndroidNotificationChannel kUrgentChannel = AndroidNotificationChannel(
  kUrgentChannelId,
  'إشعارات وصلت العاجلة',
  description: 'إشعارات مهمة تظهر فوراً أمام المستخدم حتى لو كان داخل تطبيق آخر.',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  enableLights: true,
  showBadge: true,
);

/// قناة الإشعارات العادية (تصل بصمت نسبي بدون ظهور منبثق) — للإشعارات غير المستعجلة.
const String kNormalChannelId = 'wasalt_normal_v1';
const AndroidNotificationChannel kNormalChannel = AndroidNotificationChannel(
  kNormalChannelId,
  'إشعارات وصلت العامة',
  description: 'إشعارات عامة وتنبيهات غير مستعجلة.',
  importance: Importance.defaultImportance,
);

/// القناة القديمة التي كانت تُنشأ في الإصدارات السابقة (تُحذف تلقائياً).
const String kLegacyChannelId = 'high_importance_channel';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// رابط ينتظر الفتح داخل الـ WebView (عند الضغط على إشعار محلي).
final ValueNotifier<String?> kPendingUrl = ValueNotifier<String?>(null);
// ===================================================================

void _handleNotificationTap(String? payload) {
  if (payload == null || payload.isEmpty) return;
  kPendingUrl.value = null; // لضمان إطلاق الحدث حتى لو تكرر نفس الرابط
  kPendingUrl.value = payload;
}

NotificationDetails _urgentDetails(String body) {
  return NotificationDetails(
    android: AndroidNotificationDetails(
      kUrgentChannel.id,
      kUrgentChannel.name,
      channelDescription: kUrgentChannel.description,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      icon: kNotificationIcon,
      color: kBrandColor,
      // يعرض النص الكامل عند توسيع الإشعار بدل اقتطاعه
      styleInformation: BigTextStyleInformation(body),
    ),
  );
}

/// معالج الرسائل عندما يكون التطبيق في الخلفية أو مغلقاً.
/// - رسائل (notification): يعرضها النظام تلقائياً على القناة العاجلة
///   (المحددة في الـ payload من السيرفر وفي AndroidManifest).
/// - رسائل (data فقط) تحتوي title/body: نعرضها نحن هنا بنفس القناة العاجلة.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.notification != null) return;

  final title = message.data['title'] as String?;
  final body = message.data['body'] as String?;
  if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
    return;
  }

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings(kNotificationIcon),
    ),
  );
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(kUrgentChannel);

  await plugin.show(
    message.messageId.hashCode,
    title ?? kAppTitle,
    body ?? '',
    _urgentDetails(body ?? ''),
    payload: message.data['url'] as String? ?? '',
  );
}

Future<void> _initLocalNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings(kNotificationIcon);
  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    // الضغط على الإشعار المحلي يفتح الصفحة داخل التطبيق (وليس المتصفح الخارجي)
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      _handleNotificationTap(response.payload);
    },
  );

  final android = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await android?.deleteNotificationChannel(kLegacyChannelId);
  await android?.createNotificationChannel(kUrgentChannel);
  await android?.createNotificationChannel(kNormalChannel);

  // التطبيق كان مغلقاً وفُتح بالضغط على إشعار محلي
  final launch =
      await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
  if (launch?.didNotificationLaunchApp ?? false) {
    _handleNotificationTap(launch!.notificationResponse?.payload);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await _initLocalNotifications();
  FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: kBrandColor),
      // واجهة التطبيق عربية: اتجاه من اليمين لليسار
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const WebShell(),
    );
  }
}

class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  late final WebViewController _controller;
  String? _fcmToken;
  int _progress = 0;
  bool _hasError = false;
  bool _firstLoadDone = false;
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _initFirebase();
    kPendingUrl.addListener(_onPendingUrl);
    // رابط وصل قبل بناء الواجهة (فتح التطبيق من إشعار محلي)
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingUrl());
  }

  @override
  void dispose() {
    kPendingUrl.removeListener(_onPendingUrl);
    super.dispose();
  }

  void _onPendingUrl() {
    final url = kPendingUrl.value;
    if (url == null || url.isEmpty) return;
    kPendingUrl.value = null;
    _openUrl(url);
  }

  bool _isInternalHost(String host) {
    final normalizedHost = host.toLowerCase();
    return kAllowedDomains.contains(normalizedHost) ||
        kAllowedDomains.any(
          (domain) =>
              normalizedHost == domain || normalizedHost.endsWith('.$domain'),
        );
  }

  /// يفتح رابطاً داخل الـ WebView (مسموح فقط لنطاقات الموقع، ويدعم المسارات النسبية).
  void _openUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return;
    final uri = parsed.hasScheme ? parsed : Uri.parse(kStartUrl).resolveUri(parsed);
    if (uri.scheme == 'https' && _isInternalHost(uri.host)) {
      _controller.loadRequest(uri);
    }
  }

  // ------------------------------ WebView ------------------------------
  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      // يمكن للموقع طلب التوكن عبر: FlutterApp.postMessage('getToken')
      ..addJavaScriptChannel(
        'FlutterApp',
        onMessageReceived: (msg) {
          if (msg.message == 'getToken') _sendTokenToPage();
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _hasError = false);
          },
          onPageFinished: (_) {
            if (mounted && !_firstLoadDone) {
              setState(() => _firstLoadDone = true);
            }
            _sendTokenToPage();
          },
          onWebResourceError: (e) {
            if ((e.isForMainFrame ?? true) && mounted) {
              setState(() {
                _hasError = true;
                _firstLoadDone = true;
              });
            }
          },
          onNavigationRequest: (req) async {
            final uri = Uri.tryParse(req.url);
            if (uri == null) return NavigationDecision.prevent;

            if (uri.scheme == 'http' || uri.scheme == 'https') {
              if (_isInternalHost(uri.host)) return NavigationDecision.navigate;
              await _launchExternal(uri);
              return NavigationDecision.prevent;
            }
            if (['about', 'data', 'blob', 'javascript'].contains(uri.scheme)) {
              return NavigationDecision.navigate;
            }
            // tel: mailto: whatsapp: intent: ...
            await _launchExternal(uri);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(kStartUrl));

    // iOS: تفعيل السحب من الحافة للرجوع (لا يوجد زر رجوع في آيفون)
    final platform = _controller.platform;
    if (platform is WebKitWebViewController) {
      platform.setAllowsBackForwardNavigationGestures(true);
    }
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// يمرّر توكن FCM للصفحة ليتمكن الموقع من حفظه في قاعدة بياناته.
  Future<void> _sendTokenToPage() async {
    final t = _fcmToken;
    if (t == null || t.isEmpty) return;
    final js = "(function(){try{"
        "window.FCM_TOKEN='$t';"
        "window.FCM_PLATFORM='${Platform.isIOS ? 'ios' : 'android'}';"
        "localStorage.setItem('fcm_token','$t');"
        "window.dispatchEvent(new CustomEvent('fcmToken',{detail:'$t'}));"
        "if(typeof window.onFcmToken==='function'){window.onFcmToken('$t');}"
        "}catch(e){}})();";
    try {
      await _controller.runJavaScript(js);
    } catch (_) {}
  }

  // ------------------------------ Firebase ------------------------------
  Future<void> _initFirebase() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // يطلب إذن الإشعارات (أندرويد 13+)
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // iOS: يجب انتظار توكن APNs قبل طلب توكن FCM
      if (Platform.isIOS) {
        String? apns;
        for (var i = 0; i < 10 && apns == null; i++) {
          apns = await messaging.getAPNSToken();
          if (apns == null) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
        debugPrint('APNS TOKEN: $apns');
      }

      _fcmToken = await messaging.getToken();
      debugPrint('FCM TOKEN: $_fcmToken');
      _sendTokenToPage();

      messaging.onTokenRefresh.listen((t) {
        _fcmToken = t;
        _sendTokenToPage();
      });

      await messaging.subscribeToTopic(kTopic);

      // التطبيق مفتوح (Foreground): يظهر شريط داخل التطبيق.
      // (لا نُنشئ إشعار نظام إضافي حتى لا يتكرر نفس الإشعار مرتين)
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // المستخدم ضغط على الإشعار والتطبيق في الخلفية
      FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);

      // المستخدم ضغط على الإشعار والتطبيق كان مغلقاً
      final initial = await messaging.getInitialMessage();
      if (initial != null) _openFromMessage(initial);
    } catch (e) {
      debugPrint('Firebase init error: $e');
    }
  }

  void _openFromMessage(RemoteMessage m) {
    final url = m.data['url'] as String?;
    if (url == null || url.isEmpty) return;
    _openUrl(url);
  }

  void _onForegroundMessage(RemoteMessage m) {
    if (!mounted) return;
    final title = m.notification?.title ?? (m.data['title'] as String?) ?? kAppTitle;
    final body = m.notification?.body ?? (m.data['body'] as String?) ?? '';
    final hasUrl = ((m.data['url'] as String?) ?? '').isNotEmpty;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.notifications_active, color: kBrandColor),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (body.isNotEmpty) Text(body),
          ],
        ),
        actions: [
          if (hasUrl)
            TextButton(
              onPressed: () {
                messenger.hideCurrentMaterialBanner();
                _openFromMessage(m);
              },
              child: const Text('فتح'),
            ),
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
    Timer(const Duration(seconds: 8), () {
      if (mounted) messenger.hideCurrentMaterialBanner();
    });
  }

  // ------------------------------ زر الرجوع ------------------------------
  Future<bool> _onWillPop() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اضغط مرة أخرى للخروج'),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }
    SystemNavigator.pop();
    return false;
  }

  // ------------------------------ الواجهة ------------------------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onWillPop();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_firstLoadDone && _progress < 100 && !_hasError)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: _progress / 100.0,
                    color: kBrandColor,
                    minHeight: 3,
                  ),
                ),
              // شاشة تحميل أولى بشعار التطبيق بدل الشاشة البيضاء
              if (!_firstLoadDone)
                Container(
                  color: Colors.white,
                  width: double.infinity,
                  height: double.infinity,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/logo_mark.png', width: 140),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: 120,
                        child: LinearProgressIndicator(
                          value: _progress > 0 ? _progress / 100.0 : null,
                          color: kBrandColor,
                          backgroundColor: kBrandColor.withOpacity(0.12),
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_hasError)
                Container(
                  color: Colors.white,
                  width: double.infinity,
                  height: double.infinity,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('تعذّر تحميل الصفحة',
                          style: TextStyle(fontSize: 18)),
                      const SizedBox(height: 4),
                      const Text('تحقق من اتصالك بالإنترنت'),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() => _hasError = false);
                          _controller.reload();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
