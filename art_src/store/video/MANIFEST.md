# Store videos (local only)

The rendered videos are **not in git** (`.gitignore`: `art_src/store/video/*.mp4`, `upload/`, `frames/`).
They live on the release Mac in this folder. Keep a backup outside the repo, or rebuild them with `tool/store/make_store_video.sh`; the frames take ~2 GB per target, and 4K `header` needs ~10 GB.

| File | Size | Resolution | Length | Made | SHA-256 (first 16) | Goes to |
|---|---|---|---|---|---|---|
| `preview_iphone.mp4` | 32.2 MB | 1920x886 | 28.8 s | 2026-10-13 | `283ebeb296a1e306` | App Store iPhone + iPhone Duo App Preview (master) |
| `preview_ipad.mp4` | 31.7 MB | 1600x1200 | 28.8 s | 2026-10-13 | `20f6930cf30b3fc4` | App Store iPad 13" App Preview (master) |
| `youtube_1080.mp4` | 72.8 MB | 1920x1080 | 74.3 s | 2026-10-13 | `f9f367bbc416d2ca` | YouTube https://youtu.be/Qzr7kQMdvJg → Play promo video |
| `upload/preview_iphone.mp4` | 8.6 MB | 1920x886 | 28.8 s | 2026-10-13 | `1844360a41550293` | uploaded to ASC iPhone (< 10 MB copy) |
| `upload/preview_ipad.mp4` | 8.6 MB | 1600x1200 | 28.8 s | 2026-10-13 | `322f6961c8fee12a` | uploaded to ASC iPad (< 10 MB copy) |

Pending: `header_3840x1646.mp4` and `search_2880x1920.mp4` (App Store product page header and search results, iOS 27), from `tool/store/make_store_video.sh header`. Add them to this table once rendered.

Poster frame: `poster.png` (tracked).
