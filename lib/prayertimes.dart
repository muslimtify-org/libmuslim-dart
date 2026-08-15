/// Raw FFI bindings for `prayertimes.h`.
///
/// This is the generated C API, unwrapped. An idiomatic Dart layer will be
/// added on top of this library; until then callers work with pointers and
/// decimal-hour doubles directly.
///
/// Memory ownership across the boundary, in three rules:
///
/// 1. [method_params_get] returns a pointer into C static storage. Never free
///    it; it is valid for the process lifetime. The same holds for
///    [method_to_string] and for `MethodParams.name`.
/// 2. [calculate_prayer_times] returns `PrayerTimes` by value. Dart copies it
///    out of the return registers; there is nothing to free.
/// 3. [format_time_hm] and [format_time_hms] write into a buffer the caller
///    allocates and frees.
///
/// Failure modes inherited from C, none of which this layer changes:
///
/// - [method_params_get] returns `nullptr` for an out-of-range method.
///   Reading `.ref` on `nullptr` throws.
/// - [method_from_string] returns `CALC_CUSTOM` for null or unknown input. It
///   never reports failure.
/// - **[calculate_prayer_times] dereferences `params` unconditionally. Passing
///   `nullptr` segfaults the process: no Dart exception and no stack trace.**
///   Guarding this is the job of the Dart API layer built on top of here.
/// - No function reports failure for out-of-range coordinates. A latitude of
///   95.0 yields `NaN`s rather than an error.
library;

export 'src/prayertimes/prayertimes_bindings_generated.dart';
