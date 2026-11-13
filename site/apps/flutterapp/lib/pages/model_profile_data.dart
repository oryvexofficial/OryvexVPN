/// Normalizes the Core API's model profile into the same sections as the site.
Map<String, dynamic> modelProfileMap(dynamic value) {
  if (value is! Map) return <String, dynamic>{};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

Map<String, dynamic> unwrapModelProfile(dynamic value) {
  var current = modelProfileMap(value);
  // Some Core deployments wrap the profile in data/result before model/profile.
  // Merge wrapper fields instead of discarding them, keeping the deepest values.
  final merged = <String, dynamic>{};
  for (var depth = 0; depth < 4; depth++) {
    merged.addAll(current);
    final nested = current['model'] ?? current['profile'] ?? current['data'] ?? current['result'];
    if (nested is! Map) break;
    current = modelProfileMap(nested);
  }
  return merged;
}

String modelDetailValue(dynamic value) {
  if (value == null) return '';
  if (value is Map) {
    final map = modelProfileMap(value);
    for (final key in ['name', 'label', 'value', 'text']) {
      final text = modelDetailValue(map[key]);
      if (text.isNotEmpty) return text;
    }
    return '';
  }
  if (value is Iterable) {
    return value.map(modelDetailValue).where((text) => text.isNotEmpty).join(', ');
  }
  return value.toString().trim();
}

List<String> modelProfilePhotos(Map<String, dynamic> model) {
  final result = <String>[];
  void add(dynamic value) {
    final map = modelProfileMap(value);
    final raw = value is Map
        ? (map['url'] ?? map['image_url'] ?? map['src'] ?? '')
        : value;
    final url = (raw ?? '').toString().trim();
    if ((url.startsWith('https://') || url.startsWith('http://') || url.startsWith('//')) && !result.contains(url)) {
      result.add(url);
    }
  }

  // The website uses the full images list in its original order.
  for (final key in ['images', 'gallery', 'photos']) {
    final items = model[key];
    if (items is Iterable && items is! String) {
      for (final item in items) {
        add(item);
      }
    }
  }
  for (final key in ['image_url', 'image', 'thumbnail_url', 'thumbnail', 'photo', 'avatar', 'picture']) {
    add(model[key]);
  }
  return result;
}

Map<String, String> modelProfileDetails(Map<String, dynamic> model, String section) {
  final nested = modelProfileMap(model[section]);
  final keys = section == 'personal_details'
      ? const ['age', 'gender', 'career', 'country', 'birth_date']
      : const ['height', 'hair_color', 'eye_color', 'ethnicity', 'measurements', 'breast_type', 'piercings'];
  final result = <String, String>{};
  for (final key in keys) {
    final source = nested[key] ?? model[key] ??
        (key == 'country' ? model['country_name'] : null);
    final value = modelDetailValue(source);
    if (value.isNotEmpty) result[key] = value;
  }
  // Do not discard extra public fields returned by newer Core versions.
  for (final entry in nested.entries) {
    final value = modelDetailValue(entry.value);
    if (value.isNotEmpty && !result.containsKey(entry.key)) result[entry.key] = value;
  }
  return result;
}
