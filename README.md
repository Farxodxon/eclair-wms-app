# WMS App (Flutter)

Eclair zavodi WMS uchun Flutter frontend. Backend bilan HTTPS orqali ishlaydi,
JWT token asosida autentifikatsiya qilinadi.

## Ishga tushirish

1. Bog'liqliklarni o'rnating:

```
flutter pub get
```

2. Ilovani ishga tushiring:

```
flutter run -d macos
```

Ilova default holatda bulut backend'ga ulanadi:
`https://eclair-wms-app.onrender.com`. Render bepul tarifda uxlab qolsa,
birinchi so'rov 30-60 soniya kutishi mumkin.

Boshqa bulut muhiti kerak bo'lsa:

```
flutter run -d macos --dart-define=API_BASE_URL=https://<bulut-backend>
```

## Testlar

Birlik va widget testlari tarmoqsiz ishlaydi:

```
flutter test
```

Live skaner testi alohida test backend'da konteyner yaratadi va OUT qiladi.
Muhit o'zgaruvchilari berilmasa o'tkazib yuboriladi:

```
WMS_LIVE_TEST=1 \
WMS_TEST_BASE_URL=https://<test-backend> \
WMS_TEST_EMAIL=<test-email> \
WMS_TEST_PASSWORD=<test-password> \
flutter test test/features/scanner/scan_result_test.dart
```

Production backend bloklangan. Real parollarni repo'ga yozmang.

## Ekranlar

- Login: `lib/features/auth/login_screen.dart`
- Omborlar ro'yxati: `lib/features/warehouses/warehouse_list_screen.dart`

## Manzillar

- `lib/core/config.dart` - API bazaviy manzil (default Render)
- `lib/core/api_client.dart` - HTTP klient (Dio)
- `lib/features/auth/auth_provider.dart` - auth holati (Riverpod)
