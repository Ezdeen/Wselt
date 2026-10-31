<?php
/**
 * إرسال إشعار FCM (HTTP v1) من سيرفر موقعك — تطبيق وصلت.
 * 1) Firebase Console > Project settings > Service accounts > Generate new private key
 * 2) ضع الملف بجانب هذا السكربت باسم service-account.json (خارج المجلد العام ما أمكن!)
 *
 * أمثلة:
 *   sendFcm($sa, ['token' => $userToken], 'عنوان', 'نص الإشعار', 'https://app.futureroots.site/wa/page');
 *   sendFcm($sa, ['topic' => 'all'],      'عنوان', 'نص الإشعار');
 *   // إشعار عادي (بدون ظهور منبثق فوق التطبيقات الأخرى):
 *   sendFcm($sa, ['topic' => 'all'], 'عنوان', 'نص', '', ['urgent' => false]);
 */

// يجب أن يطابق kUrgentChannelId في lib/main.dart و AndroidManifest.xml
const FCM_URGENT_CHANNEL = 'wasalt_urgent_v2';
const FCM_NORMAL_CHANNEL = 'wasalt_normal_v1'; // يطابق kNormalChannelId في lib/main.dart

$sa = json_decode(file_get_contents(__DIR__ . '/service-account.json'), true);

function b64url($d) { return rtrim(strtr(base64_encode($d), '+/', '-_'), '='); }

/** يجلب Access Token ويخزّنه مؤقتاً (صالح ساعة) لتجنب طلب جديد مع كل إشعار. */
function fcmAccessToken(array $sa): string {
    $cacheFile = sys_get_temp_dir() . '/fcm_token_' . md5($sa['client_email']) . '.json';
    if (is_readable($cacheFile)) {
        $c = json_decode(file_get_contents($cacheFile), true);
        if (!empty($c['token']) && ($c['exp'] ?? 0) > time() + 120) return $c['token'];
    }

    $now = time();
    $h = b64url(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
    $c = b64url(json_encode([
        'iss' => $sa['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud' => 'https://oauth2.googleapis.com/token',
        'iat' => $now, 'exp' => $now + 3600,
    ]));
    openssl_sign("$h.$c", $sig, $sa['private_key'], 'SHA256');
    $jwt = "$h.$c." . b64url($sig);

    $ch = curl_init('https://oauth2.googleapis.com/token');
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 15,
        CURLOPT_POSTFIELDS => http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $jwt,
        ]),
    ]);
    $res = json_decode((string)curl_exec($ch), true);
    curl_close($ch);

    $token = $res['access_token'] ?? '';
    if ($token !== '') {
        @file_put_contents($cacheFile, json_encode(['token' => $token, 'exp' => $now + (int)($res['expires_in'] ?? 3600)]), LOCK_EX);
        @chmod($cacheFile, 0600);
    }
    return $token;
}

/**
 * @param array  $target ['token' => '...'] أو ['topic' => 'all']
 * @param string $url    رابط داخل الموقع يُفتح داخل التطبيق عند الضغط (يقبل مسار نسبي مثل /wa/orders/5)
 * @param array  $opts   urgent (افتراضي true) | tag (لاستبدال إشعار سابق بنفس الوسم) | ttl بالثواني
 */
function sendFcm(array $sa, array $target, string $title, string $body, string $url = '', array $opts = []): string {
    $urgent = $opts['urgent'] ?? true;
    $ttl    = (int)($opts['ttl'] ?? 86400);

    $androidNotification = [
        // أهم سطر: بدونه يستخدم أندرويد قناة FCM الافتراضية (أهمية عادية) فلا يظهر الإشعار منبثقاً
        'channel_id' => $urgent ? FCM_URGENT_CHANNEL : FCM_NORMAL_CHANNEL,
        'notification_priority' => $urgent ? 'PRIORITY_MAX' : 'PRIORITY_DEFAULT',
        'visibility' => 'PUBLIC',
        'default_sound' => true,
        'default_vibrate_timings' => true,
        'icon' => 'ic_stat_wasalt',
        'color' => '#6A2C91',
    ];
    if (!empty($opts['tag'])) $androidNotification['tag'] = (string)$opts['tag'];

    $msg = $target + [
        'notification' => ['title' => $title, 'body' => $body],
        'android' => [
            'priority' => $urgent ? 'HIGH' : 'NORMAL',
            'ttl' => $ttl . 's',
            'notification' => $androidNotification,
        ],
        // iOS
        'apns' => [
            'headers' => ['apns-priority' => $urgent ? '10' : '5'],
            'payload' => ['aps' => [
                'sound' => 'default',
                'interruption-level' => $urgent ? 'time-sensitive' : 'active',
            ]],
        ],
    ];
    if ($url !== '') $msg['data'] = ['url' => $url];

    $ch = curl_init("https://fcm.googleapis.com/v1/projects/{$sa['project_id']}/messages:send");
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 15,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . fcmAccessToken($sa),
            'Content-Type: application/json',
        ],
        CURLOPT_POSTFIELDS => json_encode(['message' => $msg], JSON_UNESCAPED_UNICODE),
    ]);
    $res = (string)curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    // التوكن لم يعد صالحاً (المستخدم حذف التطبيق): احذفه من قاعدة بياناتك
    if ($code === 404 && strpos($res, 'UNREGISTERED') !== false) {
        error_log('FCM: token UNREGISTERED -> delete it from DB');
    }
    return $res;
}

// تجربة سريعة (احذفها عند الاستخدام الفعلي):
// echo sendFcm($sa, ['topic' => 'all'], 'مرحباً', 'هذا إشعار تجريبي', 'https://app.futureroots.site/wa/');
