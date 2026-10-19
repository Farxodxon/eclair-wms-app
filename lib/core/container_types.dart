const containerTypes = [
  'Qop',
  'Plastik bochka',
  'Kanistr',
  'Karton quti',
  'Bobina (rulon)',
  'Metall bochka',
  "Qog'oz bochka",
  'IBC konteyner',
  'Plastik chelak',
  'Plastik idish',
  'Shisha idish',
  'Vakuum qadoq',
  'Big Bag',
  'Pallet',
  'Boshqa',
];

/// Eski matn qiymatlari ro'yxatda bo'lmasa ham yo'qolmasligi uchun
List<String> containerTypeOptions(String? current) {
  final c = (current ?? '').trim();
  if (c.isEmpty) return containerTypes;
  if (containerTypes.contains(c)) return containerTypes;
  return [...containerTypes, c];
}
