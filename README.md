# PhotoChoice

[English](#english) · [Русский](#русский)

---

## English

**PhotoChoice** is a small macOS app for fast photo culling. Pick a folder, browse all shots in a grid, open any of them full screen, and sort each one with a single key or swipe: keep it, send it to one of your folders, or move it to the Trash.

**Current version: 1.1** — see [CHANGELOG.md](CHANGELOG.md).

### Features

- **Grid of all photos** (new in 1.1): thumbnails with file name, size, resolution and camera model. Adjust thumbnail size with the slider, pinch, or `+` / `−` / `0`. Sorting keys work right in the grid.
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

**Текущая версия: 1.1** — см. [CHANGELOG.md](CHANGELOG.md).

### Возможности

- **Сетка всех фото** (новое в 1.1): миниатюры с именем файла, размером, разрешением и моделью камеры. Размер миниатюр меняется слайдером, щипком или клавишами `+` / `−` / `0`. Клавиши отбора работают прямо в сетке.
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

### Требования

- macOS 26.2 или новее
- Для сборки нужен Xcode 26 или новее

### Сборка

1. Склонируйте репозиторий.
2. Откройте `PhotoChoice.xcodeproj` в Xcode.
3. Выберите команду для подписи и нажмите `⌘R`.

Приложение работает в песочнице (App Sandbox) и имеет доступ только к тем папкам, которые вы выбрали.
