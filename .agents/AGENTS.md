# Project Rules - Termode

Follow all rules in `GEMINI.md` at the project root for strict operational guidelines.

## Device Verification & Screenshot Testing
- When a physical phone or emulator is connected, install the built APK using `adb install` or `flutter install`.
- Verify the app's UI and functionality directly by injecting commands, taking screenshots (using `adb shell screencap`), and visually confirming the results to ensure everything is correct.
- For network servers and runtimes, verify real OS socket binding (`netstat`/`ss`) and test live connectivity (Chrome/curl). NEVER mock or fake runtime execution.
