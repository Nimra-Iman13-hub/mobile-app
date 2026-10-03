# helloworld — Flutter iOS app, built without a Mac

## Goal

Get a minimal Flutter "hello world" app running on a physical **iPhone 11**, built and
installed entirely from a **Windows 10** machine. No Mac is available and none can be
bought or rented.

This is a pipeline proof, not a product. The point is to prove the build-and-install
chain works end to end. Once it does, real apps follow the same path.

## Hard constraints

- Dev machine: Windows 10 Home (`E:\aznuT\Aznu Tech\mobapps\helloworld`)
- Target device: iPhone 11, physical, connects via **Lightning** cable
- No Mac, no macOS, no purchases
- Budget: $0 (no Apple Developer Program at $99/yr)

## Why this approach

Apple's build tools are macOS-only. Flutter does not change that — `flutter build ios`
shells out to Xcode. Flutter is cross-platform for *source code*, not for *toolchains*.

So the work is split across two machines:

| Step | Where | Why |
|---|---|---|
| Write the app | Windows (here) | Flutter SDK runs on Windows fine |
| Build the iOS binary | Cloud macOS runner | Only macOS can compile for iOS |
| Sign + install to iPhone | Windows | The phone is plugged in *here*, over USB |

That last row is the part people get wrong. A rented cloud Mac **cannot** install to your
iPhone, because it cannot see a USB device plugged into your Windows PC. The signing and
install must happen locally.

## The pipeline

1. Write the Flutter app on Windows.
2. Push to GitHub.
3. **Codemagic** (free tier, 500 macOS build minutes/month) runs
   `flutter build ios --release --no-codesign` and packages the result as an unsigned
   `.ipa`.
4. Download the `.ipa` to Windows.
5. **Sideloadly** signs it with a free Apple ID and installs it to the iPhone 11 over USB.

Total cost: $0.

### Why unsigned, then signed locally

Signing on the CI would need an Apple Developer Program membership (paid) to generate
provisioning profiles. Building unsigned and letting Sideloadly re-sign with a **free**
Apple ID sidesteps that entirely.

## Prerequisites to install on Windows

Nothing is installed yet. Verified absent as of 2026-09-20: `flutter`, `dart`, `java`,
`adb`, Android SDK. Present: `git`, `node`.

| Tool | Purpose | Notes |
|---|---|---|
| Flutter SDK | Build + project scaffolding | Needed locally even though the iOS build is remote |
| Android Studio | Supplies the Android SDK + a local emulator | Flutter expects it; also lets you test on an emulator without any Apple involvement |
| Apple iTunes + iCloud | Lets Sideloadly see the iPhone | **Must** be the installers from apple.com, *not* the Microsoft Store versions — the Store builds are sandboxed and Sideloadly cannot talk to them |
| Sideloadly | Signs and installs the IPA | Free |

Roughly 15 GB and a couple of hours for the first run through.

## Known gotchas

- **7-day expiry.** A free Apple ID signs apps for 7 days only. After that the app stops
  launching and must be re-installed with Sideloadly. **AltStore** can auto-refresh it
  over WiFi if AltServer is left running on the PC.
- **3-app cap.** A free Apple ID allows 3 sideloaded apps at a time, and 10 new app IDs
  per week. Fine for this; painful for real daily-use apps.
- **Microsoft Store iTunes will silently fail.** If Sideloadly cannot find the device,
  this is almost always why.
- **`--no-codesign` output is a `.app`, not a `.ipa`.** The Codemagic build script has to
  wrap it: create a `Payload/` directory, move the `.app` inside, and zip it to `.ipa`.
- **Developer Mode.** iOS 16+ requires Settings → Privacy & Security → Developer Mode to
  be switched on before a sideloaded app will launch. The toggle only appears after the
  first sideload attempt.
- **Trust the certificate.** After install: Settings → General → VPN & Device Management
  → trust the developer profile.

## Escape hatch

If the sideload chain stalls, `flutter build web` produces a site that runs in Safari on
the iPhone and can be added to the Home Screen with an icon. Zero Apple friction, ~10
minutes. It is not a native app, but it proves the code runs on the device.

## Status

Nothing built yet. Next step: install the Flutter SDK and Android Studio on this machine,
then `flutter create` the project here.

## Background

This folder follows earlier work in `../Remindly` — a full native Swift/SwiftUI reminder
app. That app is complete but has never been compiled, because it needs Xcode. It is
parked, not abandoned. The purpose of `helloworld` is to establish a working Windows →
iPhone pipeline first; whether Remindly is later ported to Flutter or built on borrowed
Mac time is an open question.
