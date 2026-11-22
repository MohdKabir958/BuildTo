/// Tracks the native image-picker handoff so its Android resume callback
/// does not accidentally tear down the open product editor route.
///
/// This does not change Clerk identity events, sign-out, or explicit access
/// checks. The guard is active only while Android's picker is completing.
abstract final class SupplierPhotoPickerActivity {
  static int _active = 0;

  static bool get isActive => _active > 0;

  static void begin() => _active++;

  static void end() {
    if (_active > 0) _active--;
  }
}
