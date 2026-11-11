# Splyzo branding

`branding/brand.json` is the single source of truth for the public name, role labels, primary/accent colors, tagline and shared logo path. The exact supplied Splyzo logo is stored at `branding/assets/splyzo-logo.png` and used by the Flutter apps, Android launcher/splash screens, public website and Admin Portal.

Android status-bar notification art is a separate monochrome Splyzo mark because Android tints notification icons.

After changing the brand configuration, run `python3 scripts/configure_brand.py` and `python3 scripts/configure_brand.py --check`. Each Flutter app's `flutter_launcher_icons` configuration points to the canonical Splyzo square logo.

Existing Android application IDs and native integration identifiers are intentionally preserved so existing installs and provider registrations do not break. The previous BuildTo support email is disabled; in-app Help and requests remains available until a new Splyzo support address is provided.
