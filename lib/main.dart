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
const String kAppTitle = 'Future Roots';
const String kTopic = 'all'; // اشتراك تلقائي لإرسال إشعار لكل المستخدمين
const AndroidNotificationChannel kHighImportanceChannel = AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: 'This channel is used for important notifications.',
  importance: Importance.max,
);
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
// ===================================================================

/// معالج الإشعارات عندما يكون التطبيق في الخلفية أو مغلقاً.
/// إشعارات (notification) يعرضها النظام تلقائياً، وهذه الدالة للتعامل مع رسائل data فقط.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> _initLocalNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      final payload = response.payload;
      if (payload == null || payload.isEmpty) return;
      final uri = Uri.tryParse(payload);
      if (uri != null && uri.hasScheme) {
        launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    },
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(kHighImportanceChannel);
}

Future<void> _showForegroundNotification(RemoteMessage message) async {
  final title = message.notification?.title ?? kAppTitle;
  final body = message.notification?.body ?? 'لديك إشعار جديد';
  final payload = message.data['url'] ?? '';

  await flutterLocalNotificationsPlugin.show(
    message.messageId.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        kHighImportanceChannel.id,
        kHighImportanceChannel.name,
        channelDescription: kHighImportanceChannel.description,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        ticker: 'ticker',
      ),
    ),
    payload: payload,
  );
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
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
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
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _initFirebase();
  }

  bool _isInternalHost(String host) {
    final normalizedHost = host.toLowerCase();
    return kAllowedDomains.contains(normalizedHost) ||
        kAllowedDomains.any(
          (domain) =>
              normalizedHost == domain || normalizedHost.endsWith('.$domain'),
        );
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
          onPageFinished: (_) => _sendTokenToPage(),
          onWebResourceError: (e) {
            if ((e.isForMainFrame ?? true) && mounted) {
              setState(() => _hasError = true);
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

      // التطبيق مفتوح (Foreground)
      FirebaseMessaging.onMessage.listen((message) {
        _showForegroundNotification(message);
        _onForegroundMessage(message);
      });

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
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme && _isInternalHost(uri.host)) {
      _controller.loadRequest(uri);
    }
  }

  void _onForegroundMessage(RemoteMessage m) {
    if (!mounted) return;
    final title = m.notification?.title ?? kAppTitle;
    final body = m.notification?.body ?? '';
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.notifications_active),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (body.isNotEmpty) Text(body),
          ],
        ),
        actions: [
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
              if (_progress < 100 && !_hasError)
                LinearProgressIndicator(value: _progress / 100.0),
              if (_hasError)
                Container(
                  color: Colors.white,
                  width: double.infinity,
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
