# PhotoChoice

[English](#english) · [Русский](#русский)

---

## English

**PhotoChoice** is a small macOS app for fast photo culling. Pick a folder, browse all shots in a grid, open any of them full screen, and sort each one with a single key or swipe: keep it, send it to one of your folders, or move it to the Trash.

**Current version: 1.3** — see [CHANGELOG.md](CHANGELOG.md).

### Features

- **Grid of all photos** (new in 1.1): thumbnails with file name, size, resolution and camera model. Adjust thumbnail size with the slider, pinch, or `+` / `−` / `0`. Sorting keys work right in the grid.
- **Compare two shots** (new in 1.3, key `C`): reference (A) on the left, candidate (B) on the right, synced zoom and pan, swap sides, promote the candidate to reference, sort the active side with `1`–`9` / `Delete`.
- **Color palette** (new in 1.3): about 10 main colors of the photo in the info panel (k-means in OKLab, works from the embedded preview, so RAW is fast).
- **Themes** (new in 1.3): Studio, Glass, Quiet and Contact; Studio and Glass also come in light versions. The background under photos always stays neutral.
- **RAW + JPEG pairs** (new in 1.3): files with the same name are shown as one card and are moved, trashed and restored together.
- **Rename by metadata** (new in 1.3, off by default): when moved to a destination folder, a photo can be renamed from its capture date and time, e.g. `2026-06-14_174212_DSC_0452`. Undo restores the old name.
- **Settings window** (`⌘,`): theme, light/dark mode, RAW + JPEG pairs, renaming template with a live example.
- **Photo info panel** (new in 1.2, key `I`): shutter speed, aperture, ISO, focal length, camera and lens, exposure settings, resolution, color profile, GPS location, file details, and an RGB histogram with clipped highlights and shadows.
- **Annotations** (new in 1.2, key `D`): draw on a photo with a pen, marker, arrow, rectangle or oval, in 6 colors and 3 sizes, with an eraser and undo. Annotations stay in memory and never change the original. Save an annotated copy (`⌘S`) or copy it to the clipboard (`⌘C` / `⇧⌘C`). Photos with annotations are marked in the grid.
- **Trackpad and mouse** (new in 1.2): two-finger swipe to go to the next or previous photo, pinch and double-tap zoom toward the cursor, `⌘` / `⌥` + scroll to zoom with a mouse, zoom out below fit-to-screen.
- Full-screen viewer with fast loading: nearby photos are decoded in advance.
- Up to 9 destination folders, mapped to keys `1`–`9`. If you don't add any, a `Отобранные` (Selected) folder is created inside the source folder.
- Swipe right or press `1` to move the photo to the first folder. Swipe left or press `Delete` to move it to the Trash.
- Undo the last move with `Z` or `⌘Z`. The file goes back to where it was.
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
| `⌘,` | Settings |
| `⌘R` | Start review |

Grid:

| Key | Action |
|---|---|
| Arrow keys / `Space` | Select photo |
| `Home` / `End` | First / last photo |
| `Return` / double-click | Open photo |
| `+` / `−` / `0` | Bigger / smaller / default thumbnails |
| `Esc` | Exit review |

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

- macOS 26.2 or later
- Xcode 26 or later to build

### Build

1. Clone the repository.
2. Open `PhotoChoice.xcodeproj` in Xcode.
3. Choose your signing team and press `⌘R`.

The app runs in the App Sandbox. It only accesses the folders you pick.

---

## Русский

**PhotoChoice** — небольшое приложение для macOS, чтобы быстро отбирать фотографии. Выберите папку, просмотрите все кадры сеткой, откройте любой на весь экран и одной клавишей или свайпом решайте его судьбу: оставить, отправить в одну из своих папок или убрать в корзину.

**Текущая версия: 1.3** — см. [CHANGELOG.md](CHANGELOG.md).

### Возможности

- **Сетка всех фото** (новое в 1.1): миниатюры с именем файла, размером, разрешением и моделью камеры. Размер миниатюр меняется слайдером, щипком или клавишами `+` / `−` / `0`. Клавиши отбора работают прямо в сетке.
- **Сравнение двух кадров** (новое в 1.3, клавиша `C`): слева эталон (A), справа кандидат (B), синхронные масштаб и перемещение, обмен сторон, кандидат одной клавишей становится эталоном, активную сторону можно отбирать клавишами `1`–`9` / `Delete`.
- **Палитра кадра** (новое в 1.3): около 10 основных цветов снимка в панели сведений (k-means в OKLab, считается по встроенному превью, поэтому быстро и для RAW).
- **Темы оформления** (новое в 1.3): «Студия», «Стекло», «Тишина» и «Контакт»; у «Студии» и «Стекла» есть светлые варианты. Фон под фото всегда нейтральный.
- **Пары RAW + JPEG** (новое в 1.3): файлы с одинаковым именем показываются одной карточкой и переносятся, удаляются и возвращаются вместе.
- **Переименование по метаданным** (новое в 1.3, по умолчанию выключено): при переносе в папку назначения кадр получает имя по дате и времени съёмки, например `2026-06-14_174212_DSC_0452`. Отмена возвращает прежнее имя.
- **Окно «Настройки»** (`⌘,`): тема, светлый и тёмный режим, пары RAW + JPEG, шаблон переименования с примером на реальном кадре.
- **Сведения о снимке** (новое в 1.2, клавиша `I`): выдержка, диафрагма, ISO, фокусное расстояние, камера и объектив, параметры съёмки, разрешение, цветовой профиль, координаты съёмки, данные файла и RGB-гистограмма с долей пересвеченных и провальных пикселей.
- **Пометки** (новое в 1.2, клавиша `D`): рисуйте на фото карандашом, маркером, стрелкой, рамкой или овалом, 6 цветов и 3 толщины, есть ластик и отмена. Пометки хранятся только в памяти и не меняют оригинал. Копию с пометками можно сохранить (`⌘S`) или скопировать в буфер обмена (`⌘C` / `⇧⌘C`). Фото с пометками отмечены в сетке.
- **Трекпад и мышь** (новое в 1.2): свайп двумя пальцами листает фото, щипок и двойной тап увеличивают к курсору, `⌘` / `⌥` + прокрутка меняет масштаб мышью, фото можно уменьшить меньше размера экрана.
- Полноэкранный просмотр с быстрой загрузкой: соседние фото подгружаются заранее.
- До 9 папок назначения, каждой соответствует клавиша `1`–`9`. Если ни одной не добавить, внутри исходной папки создаётся папка «Отобранные».
- Свайп вправо или клавиша `1` переносит фото в первую папку. Свайп влево или `Delete` отправляет его в корзину.
- `Z` или `⌘Z` отменяет последний перенос: файл возвращается на место.
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
| `Z` / `⌘Z` | Отменить перенос |
| `F` | Переключиться между сеткой и одним фото |
| `I` | Показать / скрыть сведения о снимке |
| `C` | Включить / выключить сравнение |
| `⌘,` | Настройки |
| `⌘R` | Начать просмотр |

В сетке:

| Клавиша | Действие |
|---|---|
| Стрелки / `Пробел` | Выбрать фото |
| `Home` / `End` | Первое / последнее фото |
| `Return` / двойной клик | Открыть фото |
| `+` / `−` / `0` | Крупнее / мельче / стандартный размер миниатюр |
| `Esc` | Выйти из просмотра |

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

- macOS 26.2 или новее
- Для сборки нужен Xcode 26 или новее

### Сборка

1. Склонируйте репозиторий.
2. Откройте `PhotoChoice.xcodeproj` в Xcode.
3. Выберите команду для подписи и нажмите `⌘R`.

Приложение работает в песочнице (App Sandbox) и имеет доступ только к тем папкам, которые вы выбрали.
