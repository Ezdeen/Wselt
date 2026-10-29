<?php
/**
 * إرسال إشعار FCM (HTTP v1) من سيرفر موقعك.
 * 1) Firebase Console > Project settings > Service accounts > Generate new private key
 * 2) ضع الملف بجانب هذا السكربت باسم service-account.json (خارج المجلد العام ما أمكن!)
 *
 * أمثلة:
 *   sendFcm($sa, ['token' => $userToken], 'عنوان', 'نص الإشعار', 'https://app.futureroots.site/wa/page');
 *   sendFcm($sa, ['topic' => 'all'],      'عنوان', 'نص الإشعار');
 */
$sa = json_decode(file_get_contents(__DIR__ . '/service-account.json'), true);

function b64url($d) { return rtrim(strtr(base64_encode($d), '+/', '-_'), '='); }

function fcmAccessToken(array $sa): string {
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
        CURLOPT_POSTFIELDS => http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $jwt,
        ]),
    ]);
    $res = json_decode(curl_exec($ch), true);
    curl_close($ch);
    return $res['access_token'] ?? '';
}

function sendFcm(array $sa, array $target, string $title, string $body, string $url = ''): string {
    $msg = ['notification' => ['title' => $title, 'body' => $body]] + $target;
    $msg['android'] = ['priority' => 'HIGH'];
    $msg['apns'] = ['payload' => ['aps' => ['sound' => 'default']]]; // iOS
    if ($url !== '') $msg['data'] = ['url' => $url];

    $ch = curl_init("https://fcm.googleapis.com/v1/projects/{$sa['project_id']}/messages:send");
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . fcmAccessToken($sa),
            'Content-Type: application/json',
        ],
        CURLOPT_POSTFIELDS => json_encode(['message' => $msg], JSON_UNESCAPED_UNICODE),
    ]);
    $res = curl_exec($ch);
    curl_close($ch);
    return $res;
}

// تجربة سريعة (احذفها عند الاستخدام الفعلي):
// echo sendFcm($sa, ['topic' => 'all'], 'مرحباً', 'هذا إشعار تجريبي', 'https://app.futureroots.site/wa/');
