# ZC2 VR Arena

Native Meta Quest/OpenXR prototype for the ZC2 universe.

## Current playable slice

- Quest-native OpenXR tracked head + Touch controllers
- Left-stick smooth locomotion
- Right-stick 30 degree snap turn
- Right-hand ZC2 rifle
- Support-hand fore-end grip for lower recoil / higher damage
- Physical magazine removal
- Fresh magazine retrieval from the left hip
- Physical magazine insertion
- Charging-handle pull required after a new magazine
- Haptic feedback for firing, reload interactions and damage
- Standalone magnified scope renderer
- Scope eye-box / eye-relief blackout when the headset is not correctly aligned
- 2x / 4x / 6x magnification cycle
- ZC2-styled zombie arena waves
- Dr Mantis Stage 1 boss wave every fifth wave
- Health, ammo, magazines, score and wave HUD

The handling benchmark is the physicality of modern standalone VR shooters. This project uses original ZC2 presentation and code; it does not copy third-party maps, models, audio or assets.

## Quest controls

- **Left stick:** move
- **Right stick:** snap turn
- **Right trigger:** fire
- **Left grip near rifle fore-end:** two-hand stabilise
- **Left grip on magazine + pull away:** remove current magazine
- **Left grip at left hip:** draw a fresh magazine
- **Release fresh magazine at magwell:** insert
- **Left grip at charging handle + pull toward yourself:** chamber
- **A:** cycle scope magnification
- **B after death:** restart

## APK build

GitHub Actions builds the Quest APK automatically on every push to `main`.

1. Open **Actions** → **Build Quest APK**.
2. Open the latest successful run.
3. Download **ZC2-VR-Quest-APK**.

The workflow also creates a GitHub pre-release with `ZC2-VR.apk` attached, making headset download easier.

The APK is debug-signed for developer-mode sideload testing. A persistent release keystore should be added before Meta Horizon release-channel distribution.

## Engine

- Godot 4.7.2
- Android ARM64
- OpenXR
- Godot OpenXR Vendors 5.1.0
- Meta Quest 2 / 3 / 3S / Pro target
