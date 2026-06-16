# TiktokLayer fixed precheck

This is a conservative precheck fix based on the currently visible repository files:

- Restores required newlines in `Makefile` and `control`.
- Uses `AwemeX_AlphaPro.plist` so the filter plist matches `TWEAK_NAME`.
- Adds iPad/Aweme bundle IDs to the filter.
- Fixes the alpha setter bug where the original alpha could be restored after the adjusted alpha had already been applied.
- Avoids reading preferences on every single `setAlpha:` call.
- Limits the global UIView hook to Douyin/Aweme-like layer classes to reduce UI side effects.

Build example:

```sh
make clean package
# for rootless jailbreaks:
make clean package THEOS_PACKAGE_SCHEME=rootless
```
