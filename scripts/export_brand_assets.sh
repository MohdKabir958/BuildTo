#!/usr/bin/env bash
# Export the canonical Splyzo artwork to Flutter, Android and web targets.
# Requires ImageMagick 7. The committed assets are also used directly by normal builds.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v magick >/dev/null || { echo 'Install ImageMagick 7 to export brand assets.' >&2; exit 1; }
source_logo=branding/assets/splyzo-logo.png
source_icon=branding/assets/splyzo-icon.png
test -s "$source_logo"
test -s "$source_icon"

mkdir -p packages/kraveo_ui/assets/brand
cp "$source_logo" packages/kraveo_ui/assets/brand/splyzo-logo.png

for site in web/landing/public web/super_admin/public; do
  mkdir -p "$site/brand"
  cp "$source_logo" "$site/brand/splyzo-logo.png"
  magick "$source_icon" -resize 64x64 "$site/favicon.png"
done

for role in customer vendor driver; do
  res="apps/${role}_app/android/app/src/main/res"
  mkdir -p "$res/drawable-nodpi" "$res/mipmap-anydpi-v26"
  cp "$source_icon" "$res/drawable-nodpi/splyzo_launcher.png"
  cp "$source_logo" "$res/drawable-nodpi/brand_logo.png"
  cp "$source_logo" "$res/drawable-nodpi/brand_splash_icon.png"
  cp "$source_logo" "$res/drawable-nodpi/brand_launcher_foreground.png"
  for item in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
    density="${item%:*}"; size="${item#*:}"
    mkdir -p "$res/mipmap-$density"
    magick "$source_icon" -resize "${size}x${size}" "$res/mipmap-$density/ic_launcher.png"
  done
  cat > "$res/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/white"/>
    <foreground android:drawable="@drawable/brand_launcher_foreground"/>
</adaptive-icon>
XML
done

example=packages/kraveo_ui/example/web
magick "$source_icon" -resize 64x64 "$example/favicon.png"
for size in 192 512; do
  for prefix in Icon Icon-maskable; do
    magick "$source_icon" -resize "${size}x${size}" "$example/icons/$prefix-$size.png"
  done
done

echo 'Splyzo mobile, Android and web assets exported.'
