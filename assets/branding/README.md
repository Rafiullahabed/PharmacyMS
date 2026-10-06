# Pharmacy Companion icon

The mobile launcher icon depicts a white mortar with a medical-cross cutout and a mint pestle on teal. It contains no text and stays recognizable at small sizes.

`pharmacy.svg` is the vector export; `pharmacy.png` is the opaque 1024px master. Shared geometry and export settings are maintained in `tool/generate_app_icons.py`. Update that generator before regenerating so platform assets stay consistent. Pillow is a development tool only; no Flutter runtime dependency was added.

From the project root, run `python tool/generate_app_icons.py`.

The command writes all 15 iOS catalog PNGs, five Android legacy density PNGs, Android adaptive vectors for API 26+, and a monochrome layer for themed icons on API 33+. iOS PNGs are RGB with no alpha or baked-in corner mask. Android adaptive icons let the launcher apply its mask; legacy icons have rounded corners.

The review sheet is `build/icon-review/platform-icons.png`. This directory holds source artwork, not Flutter runtime assets. Native Android/iOS resources are used by installed launchers. Desktop/web icons are outside the requested mobile change.
