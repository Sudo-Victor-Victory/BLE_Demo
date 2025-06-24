# ble_test

Both a showcase and documentation of utilizing [flutter blue plus](https://pub.dev/packages/flutter_blue_plus) and [permission handler](https://pub.dev/packages/permission_handler) to create a mobile app that acts as BLE client. I found that the documentation in utilizing both libraries was limited so this is my attempt to fill that gap.

## Getting Started

Due to having imported all of my files - you can simply download the git repository, run, then scan & connect to nearby BLE devices at your leisure. Its also a great learning resource. 
However, here are some **GOTCHAS** that this and many other BLE apps will encounter
- You **Cannot** run this project with an emulator. Most Android and iOS emulators:
  - Do not support Bluetooth hardware passthrough.
  - Cannot scan for or connect to BLE devices.
  - Lack the necessary Bluetooth stack/hardware simulation.
- Verify and modify permissions on your tech stack (Android versions 12+ will run out of the box)
  - Android frequently changes required permissions for technology like BLE. This code is acceptable for android ver 12+.
  - For other versions, you will have to google and change various things such as
    - Required permissions in AndroidManifest.xml (/android/app/src/main/AndroidManifest.xml)
    - Library versions of Flutter_Blue_Plus and Permission_Handler
    - Various small changes in build.gradle.kts for compatability
- No IOS compatability as of right now
  - I don't have an iphone and therefore can't test the functionality.
  - Similarly, Android and IOS' permissions are handled differently, but the logic behind the two remains similar.

Here is a video showing off what this code can do. The ESP32 code is not included only the client is (Flutter / mobile app)
https://github.com/user-attachments/assets/1ae3cd78-b3a0-4ed9-ad5b-b1d2520386f5

