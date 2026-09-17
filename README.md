# WMS App (Flutter)

Eclair zavodi WMS uchun Flutter frontend. Backend bilan HTTP orqali ishlaydi,
JWT token asosida autentifikatsiya qilinadi.

## Ishga tushirish

1. Bog'liqliklarni o'rnating:

```
flutter pub get
```

2. Backend ishlab turganini tekshiring (`cd ../wms_backend && dart run bin/server.dart`).

3. Ilovani ishga tushiring (API manzili `--dart-define` orqali uzatiladi):

```
flutter run -d macos --dart-define=API_BASE_URL=http://localhost:8080
```

Agar backend boshqa manzilda bo'lsa, `API_BASE_URL`ni o'zgartiring.

## Ekranlar

- Login: `lib/features/auth/login_screen.dart`
- Omborlar ro'yxati: `lib/features/warehouses/warehouse_list_screen.dart`

## Manzillar

- `lib/core/config.dart` - API bazaviy manzil
- `lib/core/api_client.dart` - HTTP klient (Dio)
- `lib/features/auth/auth_provider.dart` - auth holati (Riverpod)