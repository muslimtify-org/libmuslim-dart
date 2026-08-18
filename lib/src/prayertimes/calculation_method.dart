import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'prayertimes_bindings_generated.dart' as c;

// `_asrSchool` and `_ihtiyat` are private fields set from public named
// parameters of the same base name. `prefer_initializing_formals`'s fix
// (`this._asrSchool`) would make the named parameter private, which Dart
// does not allow, so the lint is a false positive here.
// ignore_for_file: prefer_initializing_formals

/// Which shadow length marks the start of Asr.
enum AsrSchool {
  /// Asr begins when an object's shadow equals its own length. Every method in
  /// the C table uses this unless a caller overrides it.
  standard(1),

  /// Asr begins when an object's shadow is twice its own length.
  hanafi(2);

  const AsrSchool(this._shadowFactor);

  final int _shadowFactor;
}

/// A published prayer-time calculation method.
///
/// The C library's `CALC_CUSTOM` and `CALC_COUNT` have no member here.
/// `COUNT` is a sentinel rather than a method, and a custom method is
/// expressed by [CalculationParameters.custom] rather than by an enum value.
enum CalculationMethod {
  mwl(c.CalcMethod.CALC_MWL),
  makkah(c.CalcMethod.CALC_MAKKAH),
  isna(c.CalcMethod.CALC_ISNA),
  egypt(c.CalcMethod.CALC_EGYPT),
  karachi(c.CalcMethod.CALC_KARACHI),
  turkey(c.CalcMethod.CALC_TURKEY),
  singapore(c.CalcMethod.CALC_SINGAPORE),
  jakim(c.CalcMethod.CALC_JAKIM),
  kemenag(c.CalcMethod.CALC_KEMENAG),
  france(c.CalcMethod.CALC_FRANCE),
  russia(c.CalcMethod.CALC_RUSSIA),
  dubai(c.CalcMethod.CALC_DUBAI),
  qatar(c.CalcMethod.CALC_QATAR),
  kuwait(c.CalcMethod.CALC_KUWAIT),
  jordan(c.CalcMethod.CALC_JORDAN),
  gulf(c.CalcMethod.CALC_GULF),
  tunisia(c.CalcMethod.CALC_TUNISIA),
  algeria(c.CalcMethod.CALC_ALGERIA),
  morocco(c.CalcMethod.CALC_MOROCCO),
  portugal(c.CalcMethod.CALC_PORTUGAL),
  moonsighting(c.CalcMethod.CALC_MOONSIGHTING);

  const CalculationMethod(this._native);

  final c.CalcMethod _native;

  /// The method's full name, for example `KEMENAG, Indonesia`.
  ///
  /// Read from the C table on each access rather than duplicated here, so
  /// there is exactly one source of truth for these strings.
  String get displayName =>
      _table(this).ref.name.cast<Utf8>().toDartString();

  /// The method's short key, for example `kemenag`.
  String get key =>
      c.method_to_string(_native).cast<Utf8>().toDartString();
}

/// The parameter set a calculation runs with.
final class CalculationParameters {
  /// A published [method], optionally with the two adjustments practitioners
  /// actually vary.
  ///
  /// Leaving both overrides null passes the C library's own parameter table
  /// through untouched, with no allocation.
  const CalculationParameters.of(
    CalculationMethod method, {
    AsrSchool? asrSchool,
    int? ihtiyat,
  }) : _method = method,
       _asrSchool = asrSchool,
       _ihtiyat = ihtiyat,
       _fajrAngle = null,
       _ishaAngle = null,
       _ishaInterval = null,
       _maghribInterval = 0;

  /// A method built from scratch.
  ///
  /// Exactly one of [ishaAngle] and [ishaInterval] must be given. In C an
  /// `isha_angle` of zero silently means "use the interval instead", so a
  /// caller who passed a literal zero angle would switch modes without
  /// noticing; requiring exactly one makes the choice explicit.
  CalculationParameters.custom({
    required double fajrAngle,
    double? ishaAngle,
    int? ishaInterval,
    int maghribInterval = 0,
    AsrSchool asrSchool = AsrSchool.standard,
    int ihtiyat = 0,
  }) : _method = null,
       _fajrAngle = fajrAngle,
       _ishaAngle = ishaAngle,
       _ishaInterval = ishaInterval,
       _maghribInterval = maghribInterval,
       _asrSchool = asrSchool,
       _ihtiyat = ihtiyat {
    if ((ishaAngle == null) == (ishaInterval == null)) {
      throw ArgumentError(
        'give exactly one of ishaAngle and ishaInterval, not '
        '${ishaAngle == null ? 'neither' : 'both'}',
      );
    }
    checkAngle(fajrAngle, 'fajrAngle');
    if (ishaAngle != null) checkAngle(ishaAngle, 'ishaAngle');
    if (ishaInterval != null) {
      checkNonNegative(ishaInterval, 'ishaInterval');
    }
    checkNonNegative(maghribInterval, 'maghribInterval');
    checkNonNegative(ihtiyat, 'ihtiyat');
  }

  final CalculationMethod? _method;
  final AsrSchool? _asrSchool;
  final int? _ihtiyat;
  final double? _fajrAngle;
  final double? _ishaAngle;
  final int? _ishaInterval;
  final int _maghribInterval;
}

/// Throws [ArgumentError] unless [value] is a finite angle in 0..90 degrees.
void checkAngle(double value, String name) {
  if (!value.isFinite || value < 0 || value > 90) {
    throw ArgumentError.value(
      value,
      name,
      'must be a finite angle between 0 and 90 degrees',
    );
  }
}

/// Throws [ArgumentError] unless [value] is zero or more.
void checkNonNegative(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
}

ffi.Pointer<c.MethodParams> _table(CalculationMethod method) {
  final params = c.method_params_get(method._native);
  if (params == ffi.nullptr) {
    throw StateError(
      'the C method table has no entry for ${method.name}; the generated '
      'bindings and the compiled library are out of step',
    );
  }
  return params;
}

/// Calls [body] with a `MethodParams` matching [parameters].
///
/// When [CalculationParameters.of] carries no overrides this hands over the
/// pointer C already owns and allocates nothing. Every other case copies into
/// a fresh allocation and frees it before returning, because the pointer
/// `method_params_get` returns is static storage shared by the whole process:
/// writing to it would corrupt the method table for every later caller.
T withNativeParams<T>(
  CalculationParameters parameters,
  T Function(ffi.Pointer<c.MethodParams>) body,
) {
  final method = parameters._method;
  final asrSchool = parameters._asrSchool;
  final ihtiyat = parameters._ihtiyat;

  if (method != null) {
    final table = _table(method);
    if (asrSchool == null && ihtiyat == null) return body(table);
    if (ihtiyat != null) checkNonNegative(ihtiyat, 'ihtiyat');

    final copy = calloc<c.MethodParams>();
    try {
      copy.ref
        ..name = table.ref.name
        ..fajr_angle = table.ref.fajr_angle
        ..isha_angle = table.ref.isha_angle
        ..isha_interval = table.ref.isha_interval
        ..maghrib_interval = table.ref.maghrib_interval
        ..asr_shadow = asrSchool?._shadowFactor ?? table.ref.asr_shadow
        ..midnight_modeAsInt = table.ref.midnight_modeAsInt
        ..ihtiyat = ihtiyat ?? table.ref.ihtiyat;
      return body(copy);
    } finally {
      calloc.free(copy);
    }
  }

  final custom = c.method_params_get(c.CalcMethod.CALC_CUSTOM);
  final copy = calloc<c.MethodParams>();
  try {
    copy.ref
      ..name = custom.ref.name
      ..fajr_angle = parameters._fajrAngle!
      ..isha_angle = parameters._ishaAngle ?? 0.0
      ..isha_interval = parameters._ishaInterval ?? 0
      ..maghrib_interval = parameters._maghribInterval
      ..asr_shadow = asrSchool!._shadowFactor
      ..midnight_modeAsInt = c.MidnightMode.MIDNIGHT_STANDARD.value
      ..ihtiyat = ihtiyat!;
    return body(copy);
  } finally {
    calloc.free(copy);
  }
}
