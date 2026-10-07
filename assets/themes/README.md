# World theme art

Drop files into `assets/themes/<world>/` (`tutorial`, `alien`, `mine`, `ice`, `lava`).
Every file is optional — anything missing falls back to the flat palette look.
Hot restart (not hot reload) after adding files.

| File | Size | Notes |
|---|---|---|
| `rock.png` | 1024×1024 | Seamless tileable on both axes. Fills all solid rock; one tile = `ThemeSpec.rockTextureMeters` (8 m). |
| `far.png` | 1920×1080 | Opaque distant background, seamless left/right edges. |
| `mid.png` | 1920×1080 | Transparent silhouettes, seamless left/right. |
| `near.png` | 1920×1080 | Transparent close silhouettes, seamless left/right. |
| `decor.png` | 1024×256 | 4 props in a row (256×256 cells), transparent, each growing **up from the bottom-center** of its cell. Auto-flipped for ceilings (stalactites). |

Any parallax layer present → that world drops the shared tinted `far/mid/near.png`
and the solid backdrop becomes a 35% haze so the art shows through the caves.
Without `decor.png`, procedural spikes are drawn (tip colour = `ThemeSpec.decorTip`).
