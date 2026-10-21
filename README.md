# PhotoChoice

[English](#english) · [Русский](#русский)

---

## English

**PhotoChoice** is a small macOS app for fast photo culling. Pick a folder, browse all shots in a grid, open any of them full screen, and sort each one with a single key or swipe: keep it, send it to one of your folders, or move it to the Trash.

**Current version: 1.4.1** — see [CHANGELOG.md](CHANGELOG.md).

### Download

**[Download PhotoChoice.dmg](https://github.com/METAMARGINAL/photochoice/releases/latest/download/PhotoChoice.dmg)** — the latest version, macOS 15 Sequoia or later (Apple Silicon and Intel). Open the DMG and drag PhotoChoice to Applications.

The app is not notarized by Apple, so the first launch is blocked: open System Settings → Privacy & Security, click "Open Anyway" next to PhotoChoice and confirm. After that it opens normally.

### Features

- **Smart culling** (in development): photos are analyzed in the background on this Mac (nothing is uploaded, files are never changed) and the grid gets three more sections. **Rejects** (`⌘2`) — blurry or out-of-focus shots (checked at 100 % around the eyes or the main subject), softer than their burst neighbors, closed eyes, blown highlights, too dark, tilted horizon, accidental shots; a small mark in "All photos" shows the reason. **Bursts** (`⌘3`) — shots taken in a row that look alike (and have the same faces), each with a header and the best shot marked: sharpest, with everyone's eyes open. **People** (`⌘4`) — faces that appear in several shots, grouped into people with the AuraFace recognition model (face vectors stay in the analysis cache on this Mac). Strictness, burst interval and "open rejects at the problem spot at 100 %" are in Settings. The **Reject calibration** panel (`⌥⌘K`) shows every photo on each metric's scale, lets you move thresholds, label shots as reject / good and train a small model on your labels. Apple's MobileCLIP model double-checks "Blurry": a shot stays in Rejects only if the model also sees it as out of focus; its other scores are shown in the calibration panel. Both models are in the repository (see below).
- **Stars and color labels** (off by default, Settings → "Stars and colors"): `⌥1`–`⌥5` set stars, `⌃1`–`⌃8` set a color label, `⌥0` / `⌃0` clear them; in the grid they apply to the selection. You can also click the stars and the color dot under a thumbnail (on hover), in the viewer and in compare mode. Filter the grid by stars and colors with the button above it: pick one or several star counts and colors, e.g. only ★★ or ★★★–★★★★★. Marks are stored in the app and follow a photo when it is moved. "Write to XMP" saves them to a sidecar next to the photo (`DSCF0001.xmp`: `xmp:Rating`, `xmp:Label`) without touching the photo; an existing sidecar keeps everything else and moves together with its photo.
- **Grid of all photos** (new in 1.1): thumbnails with file name, size, resolution and camera model. Adjust thumbnail size with the slider, pinch, or `+` / `−` / `0`. Sorting keys work right in the grid.
- **Compare two shots** (new in 1.3, key `C`): reference (A) on the left, candidate (B) on the right, synced zoom and pan, swap sides, promote the candidate to reference, sort the active side with `1`–`9` / `Delete`.
- **Color palette** (new in 1.3): about 10 main colors of the photo in the info panel (k-means in OKLab, works from the embedded preview, so RAW is fast).
- **Themes** (new in 1.3): Studio, Glass, Quiet and Contact; Studio and Glass also come in light versions. The background under photos always stays neutral.
- **RAW + JPEG pairs** (new in 1.3): files with the same name are shown as one card and are moved, trashed and restored together.
- **Rename by metadata** (new in 1.3, off by default): when moved to a destination folder, a photo can be renamed from its capture date and time, e.g. `2026-06-14_174212_DSC_0452`. Undo restores the old name.
- **Settings window** (`⌘,`): theme, light/dark mode, RAW + JPEG pairs, renaming template with a live example.
- **Photo info panel** (new in 1.2, key `I`): shutter speed, aperture, ISO, focal length, camera and lens, exposure settings, resolution, color profile, GPS location, file details, and an RGB histogram with clipped highlights and shadows. Click a triangle in the histogram corner (or the number under it) to show crushed shadows in blue or clipped highlights in red right on the photo, in the viewer and in compare mode — like in Lightroom.
- **Annotations** (new in 1.2, key `D`): draw on a photo with a pen, marker, arrow, rectangle or oval, in 6 colors and 3 sizes, with an eraser and undo. Annotations stay in memory and never change the original. Save an annotated copy (`⌘S`) or copy it to the clipboard (`⌘C` / `⇧⌘C`). Photos with annotations are marked in the grid.
- **Trackpad and mouse** (new in 1.2): two-finger swipe to go to the next or previous photo, pinch and double-tap zoom toward the cursor, `⌘` / `⌥` + scroll to zoom with a mouse, zoom out below fit-to-screen.
- Full-screen viewer with fast loading: nearby photos are decoded in advance.
- Up to 9 destination folders, mapped to keys `1`–`9`. If you don't add any, a `Отобранные` (Selected) folder is created inside the source folder.
- Swipe right or press `1` to move the photo to the first folder. Swipe left or press `Delete` to move it to the Trash.
- Undo the last move, star or color with `Z` or `⌘Z`. A moved file goes back to where it was.
- Zoom with pinch, double-click, or `+` / `−` / `0`. Pan the image by dragging.
- Supports JPEG, PNG, HEIC/HEIF, TIFF, WebP, GIF, BMP and RAW (DNG, RAF, CR2, CR3, NEF, ARW, ORF, RW2).
- Optionally includes subfolders. Destination folders are skipped when it does.
- Never overwrites files: if a file with the same name already exists, `_2`, `_3`, … is added to the name.

### Keyboard shortcuts

Everywhere:

| Key | Action |
|---|---|
| `1`–`9` | Move to destination folder |
| `Delete` | Move to Trash |
| `Z` / `⌘Z` | Undo |
| `F` | Switch between grid and single photo |
| `I` | Show / hide photo info |
| `C` | Compare mode on / off |
| `⌥1`–`⌥5` / `⌥0` | Stars / clear stars (when enabled in Settings) |
| `⌃1`–`⌃8` / `⌃0` | Color label / clear label (when enabled in Settings) |
| `⌘,` | Settings |
| `⌘R` | Start review |

Grid:

| Key | Action |
|---|---|
| Arrow keys / `Space` | Select photo |
| `Home` / `End` | First / last photo |
| `Return` / double-click | Open photo |
| `+` / `−` / `0` | Bigger / smaller / default thumbnails |
| `⌘1` / `⌘2` / `⌘3` / `⌘4` | All photos / Rejects / Bursts / People |
| `↑` / `↓` in Bursts | Previous / next burst |
| `⌥⌘K` | Reject calibration panel |
| `Esc` | Clear selection / close the opened burst or person / exit review |

Single photo:

| Key | Action |
|---|---|
| `→` / `Space` | Next photo |
| `←` | Previous photo |
| `+` / `−` / `0` | Zoom in / out / reset |
| `Esc` | Reset zoom / back to grid |
| `⌘` / `⌥` + scroll | Zoom toward cursor |
| `D` | Drawing mode on / off |
| `P` `M` `A` `R` `O` `E` | Pen, marker, arrow, rectangle, oval, eraser |
| `Z` (while drawing) | Undo last stroke |
| `⌘S` | Save annotated copy |
| `⌘C` / `⇧⌘C` | Copy annotated photo |

Compare:

| Key | Action |
|---|---|
| Click / `Tab` | Choose active side |
| `←` / `→` | Change the candidate |
| `↑` | Make the active shot the reference |
| `X` | Swap sides |
| `L` | Sync zoom and pan on / off |
| `1`–`9` / `Delete` | Sort the active shot |
| `C` / `Esc` | Exit compare |

### Requirements

- macOS 15 or later (the Glass theme uses Liquid Glass on macOS 26 and a frosted background on older systems)
- Xcode 26 or later to build

### Build

To build and install over `/Applications/PhotoChoice.app` in one step: `./scripts/install.sh` (stars, colors, analysis cache and settings are kept — they live in the app container, not in the app). To build the DMG for a release: `./scripts/make-dmg.sh` (see the comments inside for Developer ID signing and notarization), then upload `build/PhotoChoice.dmg` to a GitHub release under exactly this name — the download link always points to the latest one.

1. Install Git LFS before cloning: `brew install git-lfs && git lfs install`. The Core ML models (≈330 MB) are stored in LFS; without it you get small pointer files instead of models and the app runs without them.
2. Clone the repository.
3. Open `PhotoChoice.xcodeproj` in Xcode.
4. Choose your signing team and press `⌘R`.

The app runs in the App Sandbox. It only accesses the folders you pick.

### MobileCLIP model

Smart culling uses Apple's MobileCLIP-S2 (Core ML): the image encoder (≈70 MB) in every build, the text encoder (≈130 MB) only in Debug. Both are already in `PhotoChoice/Models/` (Git LFS); the app also works without them. To download them again:

1. Install the Hugging Face CLI: `brew install hf`.
2. Download the S2 packages: `hf download apple/coreml-mobileclip --include "mobileclip_s2_*" --local-dir ~/Downloads/mobileclip`.
3. Move both packages into `PhotoChoice/Models/` and build. The text encoder (`mobileclip_s2_text.mlpackage`, ≈130 MB) goes only into Debug builds: Release excludes it (`EXCLUDED_SOURCE_FILE_NAMES`).
4. Prompts are computed automatically when a folder is opened (Debug). To ship them with Release, save `prompts.json` from Reject calibration (`⌥⌘K`) → "MobileCLIP" into `PhotoChoice/Models/`.
5. Models go to Git through Git LFS (`.gitattributes`): run `brew install git-lfs && git lfs install` before `git add`.

The Core ML weights were published under the Apple Sample Code License (text in `PhotoChoice/Models/LICENSE-MobileCLIP.txt`). Newer releases (MobileCLIP2) use a research-only license, so don't swap them in.

### Face recognition model

The People section groups faces with AuraFace-v1 (fal, Apache-2.0, ArcFace-style ResNet-100, Core ML fp16, ≈124 MB). It is already in `PhotoChoice/Models/` (Git LFS); without it, faces are compared with a generic Vision image descriptor, which mixes people up more often. To download it again:

1. Download: `hf download TechnoThinker/visuals-models-open --local-dir ~/Downloads/auraface`.
2. Move `auraface_v1.mlpackage` into `PhotoChoice/Models/` and copy `LICENSE.md` there as `LICENSE-AuraFace.md`. Build.
3. Folders are analyzed again on the next open, then People uses the new face vectors.

---

## Русский

**PhotoChoice** — небольшое приложение для macOS, чтобы быстро отбирать фотографии. Выберите папку, просмотрите все кадры сеткой, откройте любой на весь экран и одной клавишей или свайпом решайте его судьбу: оставить, отправить в одну из своих папок или убрать в корзину.

**Текущая версия: 1.4.1** — см. [CHANGELOG.md](CHANGELOG.md).

### Скачать

**[Скачать PhotoChoice.dmg](https://github.com/METAMARGINAL/photochoice/releases/latest/download/PhotoChoice.dmg)** — последняя версия, macOS 15 Sequoia или новее (Apple Silicon и Intel). Откройте DMG и перетащите PhotoChoice в «Программы».

Приложение не нотаризовано Apple, поэтому первый запуск macOS заблокирует: откройте Системные настройки → Конфиденциальность и безопасность, нажмите «Всё равно открыть» рядом с PhotoChoice и подтвердите. Дальше оно открывается как обычно.

### Возможности

- **Умный отбор** (в разработке): фото анализируются в фоне на этом Mac (ничего не отправляется, файлы не меняются), и в сетке появляются ещё три раздела. **Брак** (`⌘2`) — размытые кадры и промахи фокуса (проверяется в 100 % на глазах или главном объекте), кадры мягче соседей по серии, закрытые глаза, пересвет, темнота, завал горизонта, случайные кадры; в «Все фото» на таких кадрах маленький значок с причиной. **Серии** (`⌘3`) — кадры, снятые подряд и похожие друг на друга (в том числе по лицам), с заголовками и отметкой лучшего кадра: самый резкий, у всех открыты глаза. **Люди** (`⌘4`) — лица, которые встречаются на нескольких кадрах, собранные в людей моделью распознавания AuraFace (векторы лиц хранятся только в кэше анализа на этом Mac). Строгость, интервал серии и «открывать брак сразу в 100 % на проблемном месте» — в настройках. Панель **«Калибровка брака»** (`⌥⌘K`) показывает все кадры на шкале каждой метрики, позволяет двигать пороги, размечать кадры как «брак» и «норма» и обучить по этой разметке небольшую модель. Модель MobileCLIP от Apple перепроверяет «Размыто»: кадр остаётся в браке, только если и она видит, что он не в фокусе; остальные её оценки показываются в калибровке. Обе модели лежат в репозитории (см. ниже).
- **Звёзды и цветовые метки** (по умолчанию выключены, Настройки → «Звёзды и цвета»): `⌥1`–`⌥5` ставят звёзды, `⌃1`–`⌃8` — цвет, `⌥0` / `⌃0` снимают; в сетке — выделенным кадрам. Звёзды и кружок цвета можно и кликнуть: под миниатюрой при наведении, в просмотре и в сравнении. Фильтр по звёздам и цвету — кнопка над сеткой: можно выбрать одно или несколько значений, например только ★★ или ★★★–★★★★★. Оценки хранятся в приложении и переезжают вместе с кадром. «Записать в XMP» сохраняет их в файл рядом с фото (`DSCF0001.xmp`: `xmp:Rating`, `xmp:Label`), сам снимок не меняется; в существующем XMP остальное остаётся, и он переносится вместе с кадром.
- **Сетка всех фото** (новое в 1.1): миниатюры с именем файла, размером, разрешением и моделью камеры. Размер миниатюр меняется слайдером, щипком или клавишами `+` / `−` / `0`. Клавиши отбора работают прямо в сетке.
- **Сравнение двух кадров** (новое в 1.3, клавиша `C`): слева эталон (A), справа кандидат (B), синхронные масштаб и перемещение, обмен сторон, кандидат одной клавишей становится эталоном, активную сторону можно отбирать клавишами `1`–`9` / `Delete`.
- **Палитра кадра** (новое в 1.3): около 10 основных цветов снимка в панели сведений (k-means в OKLab, считается по встроенному превью, поэтому быстро и для RAW).
- **Темы оформления** (новое в 1.3): «Студия», «Стекло», «Тишина» и «Контакт»; у «Студии» и «Стекла» есть светлые варианты. Фон под фото всегда нейтральный.
- **Пары RAW + JPEG** (новое в 1.3): файлы с одинаковым именем показываются одной карточкой и переносятся, удаляются и возвращаются вместе.
- **Переименование по метаданным** (новое в 1.3, по умолчанию выключено): при переносе в папку назначения кадр получает имя по дате и времени съёмки, например `2026-06-14_174212_DSC_0452`. Отмена возвращает прежнее имя.
- **Окно «Настройки»** (`⌘,`): тема, светлый и тёмный режим, пары RAW + JPEG, шаблон переименования с примером на реальном кадре.
- **Сведения о снимке** (новое в 1.2, клавиша `I`): выдержка, диафрагма, ISO, фокусное расстояние, камера и объектив, параметры съёмки, разрешение, цветовой профиль, координаты съёмки, данные файла и RGB-гистограмма с долей пересвеченных и провальных пикселей. Клик по треугольнику в углу гистограммы (или по цифре под ней) показывает прямо на кадре провалы синим или пересветы красным — в просмотре и в сравнении, как в Lightroom.
- **Пометки** (новое в 1.2, клавиша `D`): рисуйте на фото карандашом, маркером, стрелкой, рамкой или овалом, 6 цветов и 3 толщины, есть ластик и отмена. Пометки хранятся только в памяти и не меняют оригинал. Копию с пометками можно сохранить (`⌘S`) или скопировать в буфер обмена (`⌘C` / `⇧⌘C`). Фото с пометками отмечены в сетке.
- **Трекпад и мышь** (новое в 1.2): свайп двумя пальцами листает фото, щипок и двойной тап увеличивают к курсору, `⌘` / `⌥` + прокрутка меняет масштаб мышью, фото можно уменьшить меньше размера экрана.
- Полноэкранный просмотр с быстрой загрузкой: соседние фото подгружаются заранее.
- До 9 папок назначения, каждой соответствует клавиша `1`–`9`. Если ни одной не добавить, внутри исходной папки создаётся папка «Отобранные».
- Свайп вправо или клавиша `1` переносит фото в первую папку. Свайп влево или `Delete` отправляет его в корзину.
- `Z` или `⌘Z` отменяет последний перенос, звёзды или цвет: перенесённый файл возвращается на место.
- Масштаб меняется щипком, двойным кликом или клавишами `+` / `−` / `0`. Увеличенное фото можно двигать перетаскиванием.
- Поддерживаются JPEG, PNG, HEIC/HEIF, TIFF, WebP, GIF, BMP и RAW (DNG, RAF, CR2, CR3, NEF, ARW, ORF, RW2).
- Можно включить просмотр вложенных папок. Папки назначения при этом пропускаются.
- Файлы никогда не перезаписываются: если имя уже занято, к нему добавляется `_2`, `_3` и так далее.

### Горячие клавиши

Везде:

| Клавиша | Действие |
|---|---|
| `1`–`9` | Перенести в папку назначения |
| `Delete` | В корзину |
| `Z` / `⌘Z` | Отменить перенос, звёзды или цвет |
| `F` | Переключиться между сеткой и одним фото |
| `I` | Показать / скрыть сведения о снимке |
| `C` | Включить / выключить сравнение |
| `⌥1`–`⌥5` / `⌥0` | Звёзды / снять звёзды (если включено в настройках) |
| `⌃1`–`⌃8` / `⌃0` | Цветовая метка / снять метку (если включено в настройках) |
| `⌘,` | Настройки |
| `⌘R` | Начать просмотр |

В сетке:

| Клавиша | Действие |
|---|---|
| Стрелки / `Пробел` | Выбрать фото |
| `Home` / `End` | Первое / последнее фото |
| `Return` / двойной клик | Открыть фото |
| `+` / `−` / `0` | Крупнее / мельче / стандартный размер миниатюр |
| `⌘1` / `⌘2` / `⌘3` / `⌘4` | Все фото / Брак / Серии / Люди |
| `↑` / `↓` в «Сериях» | Предыдущая / следующая серия |
| `⌥⌘K` | Панель «Калибровка брака» |
| `Esc` | Снять выделение / закрыть открытую серию или человека / выйти из просмотра |

В просмотре одного фото:

| Клавиша | Действие |
|---|---|
| `→` / `Пробел` | Следующее фото |
| `←` | Предыдущее фото |
| `+` / `−` / `0` | Увеличить / уменьшить / сбросить масштаб |
| `Esc` | Сбросить масштаб / вернуться к сетке |
| `⌘` / `⌥` + прокрутка | Масштаб к курсору |
| `D` | Включить / выключить рисование |
| `P` `M` `A` `R` `O` `E` | Карандаш, маркер, стрелка, рамка, овал, ластик |
| `Z` (при рисовании) | Отменить последний штрих |
| `⌘S` | Сохранить копию с пометками |
| `⌘C` / `⇧⌘C` | Скопировать фото с пометками |

Сравнение:

| Клавиша | Действие |
|---|---|
| Клик / `Tab` | Выбрать активную сторону |
| `←` / `→` | Листать кандидата |
| `↑` | Сделать активный кадр эталоном |
| `X` | Поменять стороны местами |
| `L` | Синхронный масштаб и перемещение |
| `1`–`9` / `Delete` | Отобрать активный кадр |
| `C` / `Esc` | Выйти из сравнения |

### Требования

- macOS 15 или новее (тема «Стекло» на macOS 26 использует Liquid Glass, на старых системах — матовую подложку)
- Для сборки нужен Xcode 26 или новее

### Сборка

Собрать и поставить поверх `/Applications/PhotoChoice.app` одной командой: `./scripts/install.sh` (звёзды, цвета, кэш анализа и настройки остаются — они лежат в контейнере приложения, а не в нём самом). DMG для релиза собирает `./scripts/make-dmg.sh` (подпись Developer ID и нотаризация — в комментарии внутри). Затем загрузите `build/PhotoChoice.dmg` в релиз на GitHub ровно под этим именем — ссылка «Скачать» всегда ведёт на последний.

1. До клонирования поставьте Git LFS: `brew install git-lfs && git lfs install`. Модели Core ML (≈330 МБ) хранятся в LFS; без него вместо моделей скачаются маленькие файлы-ссылки, и приложение будет работать без моделей.
2. Склонируйте репозиторий.
3. Откройте `PhotoChoice.xcodeproj` в Xcode.
4. Выберите команду для подписи и нажмите `⌘R`.

Приложение работает в песочнице (App Sandbox) и имеет доступ только к тем папкам, которые вы выбрали.

### Модель MobileCLIP

Умный отбор использует MobileCLIP-S2 от Apple (Core ML): кодировщик картинок (≈70 МБ) — в любой сборке, текстовую часть (≈130 МБ) — только в Debug. Обе уже лежат в `PhotoChoice/Models/` (Git LFS); без них приложение тоже работает. Скачать заново:

1. Установите Hugging Face CLI: `brew install hf`.
2. Скачайте пакеты S2: `hf download apple/coreml-mobileclip --include "mobileclip_s2_*" --local-dir ~/Downloads/mobileclip`.
3. Перенесите оба пакета в `PhotoChoice/Models/` и соберите проект. Текстовая часть (`mobileclip_s2_text.mlpackage`, ≈130 МБ) попадает только в сборку Debug: из Release её исключает `EXCLUDED_SOURCE_FILE_NAMES`.
4. Подсказки считаются сами при открытии папки (в Debug). Чтобы они были в Release, сохраните `prompts.json` из «Калибровка брака» (`⌥⌘K`) → «Модель MobileCLIP» в `PhotoChoice/Models/`.
5. Модели идут в гит через Git LFS (`.gitattributes`): до `git add` выполните `brew install git-lfs && git lfs install`.

Веса Core ML опубликованы под Apple Sample Code License (текст — `PhotoChoice/Models/LICENSE-MobileCLIP.txt`). Новые версии (MobileCLIP2) выходят под лицензией только для исследований — их не подставляйте.

### Модель распознавания лиц

Раздел «Люди» собирает лица моделью AuraFace-v1 (fal, Apache-2.0, ResNet-100 по схеме ArcFace, Core ML fp16, ≈124 МБ). Она уже лежит в `PhotoChoice/Models/` (Git LFS); без неё лица сравниваются по общему описанию картинки от Vision, и люди путаются чаще. Скачать заново:

1. Скачайте: `hf download TechnoThinker/visuals-models-open --local-dir ~/Downloads/auraface`.
2. Перенесите `auraface_v1.mlpackage` в `PhotoChoice/Models/`, туда же скопируйте `LICENSE.md` под именем `LICENSE-AuraFace.md`. Соберите проект.
3. При следующем открытии папки кадры проанализируются заново, и «Люди» перейдут на новые векторы лиц.
