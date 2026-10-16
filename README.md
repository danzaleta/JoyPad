# JoyPad — Universal Multi-Mode Pad (iOS & macOS)

> **Convierte tu iPhone en un Magic Trackpad, Teclado con Dictado por Voz, Macropad y Gamepad Híbrido (estilo Steam Deck) de ultra-baja latencia para macOS.**

---

## Modos de Operación

1. **Modo Magic Trackpad (`0x02` / `0x03`)**
   - Movimiento de cursor sub-píxel con curva de aceleración balística nativa.
   - Simulación de clic físico *Force Touch* mediante `CoreHaptics`.
   - Scroll suave de 2 dedos y gestos de 3 dedos (Mission Control, App Exposé, cambio de Spaces).
2. **Modo Teclado, Dictado & Multimedia (`0x04` / `0x05` / `0x06`)**
   - Soporte directo del teclado nativo y **Dictado por Voz de iOS** (inyección Unicode `UTF-8/UTF-16` independiente del layout).
   - Barra táctica con `Esc`, `Tab`, `Cmd`, `Opt`, `Ctrl`, `Shift` y atajos rápidos (`Cmd+C`, `Cmd+V`, Spotlight, Captura).
   - Controles nativos de sistema (`NX_KEYTYPE`): Volumen, Brillo de pantalla y Play/Pause.
3. **Modo Gamepad Nativo (`0x01`)**
   - Joysticks analógicos duales, D-Pad, botonera ABXY y gatillos L2/R2.
4. **Modo Híbrido "Steam Deck" (`0x01` + `0x02` + `0x07`)**
   - Stick izquierdo mapeado a `WASD` + mitad derecha como Trackpad de cámara de alta precisión + apuntado por giroscopio (`CoreMotion`), ideal para *Minecraft* y shooters en Mac.

---

## Estructura del Repositorio

```text
JoyPad/
├── Package.swift
├── Info.plist
├── build.sh
├── Sources/
│   ├── JoyPadProtocol/       # Protocolo binario multiplexado (4-byte header + payloads) y config AWDL P2P
│   ├── JoyPadServer/         # App Companion de Barra de Menú para macOS + Motores CGEvent / NXEvent
│   └── JoyPadClientCore/     # Core del Cliente iOS (NWBrowser P2P, CoreHaptics Force Touch, UI Multi-Modo)
└── Tests/
    └── JoyPadProtocolTests/  # Pruebas unitarias de serialización binaria y tamaños de paquete
```

---

## Compilación y Pruebas

```bash
# Ejecutar pruebas unitarias del protocolo binario
swift test

# Compilar y empaquetar JoyPadServer.app para macOS
chmod +x build.sh
./build.sh
```
