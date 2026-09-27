# Changelog / История изменений

## 1.2 — 2026-09-27

### English

**New**
- Photo info panel (`I`), in the grid and in the single-photo view: exposure (shutter, aperture, ISO, focal length, exposure compensation), camera, lens, mode, metering, flash, white balance, resolution and megapixels, orientation, color profile and bit depth, GPS location, file details.
- RGB histogram in the info panel, with the share of clipped highlights and shadows. Built from the embedded preview, so it is fast even for RAW.
- Annotations (`D`): pen, marker, arrow, rectangle, oval and eraser; 6 colors, 3 sizes; undo a stroke with `Z`, clear all. Annotations move and zoom with the photo.
- Annotations never touch the original file. Save an annotated copy at full resolution as JPEG or PNG (`⌘S`), or copy it to the clipboard (`⌘C` / `⇧⌘C`).
- Grid thumbnails show a marker when a photo has annotations. Annotations follow the photo when it is moved, and come back on undo.
- Two-finger horizontal swipe on the trackpad goes to the next or previous photo.
- Zoom toward the cursor: pinch, double-click / double-tap, and `⌘` or `⌥` + scroll for a mouse.

**Changed**
- Photos can be zoomed out below fit-to-screen, like in Preview.
- When a photo is zoomed, two-finger scrolling pans it.
- Scroll events that the viewer doesn't use now reach the grid and the info panel.

### Русский

**Новое**
- Панель сведений о снимке (`I`) в сетке и при просмотре одного фото: параметры съёмки (выдержка, диафрагма, ISO, фокусное расстояние, экспокоррекция), камера, объектив, режим, замер, вспышка, баланс белого, разрешение и мегапиксели, ориентация, цветовой профиль и глубина цвета, координаты съёмки, данные файла.
- RGB-гистограмма в панели сведений с долей пересвеченных и провальных пикселей. Строится по встроенному превью, поэтому быстро работает даже с RAW.
- Пометки (`D`): карандаш, маркер, стрелка, рамка, овал и ластик; 6 цветов, 3 толщины; отмена штриха клавишей `Z`, очистка всех пометок. Пометки двигаются и масштабируются вместе с фото.
- Оригинальный файл пометки не меняют. Копию с пометками можно сохранить в полном разрешении в JPEG или PNG (`⌘S`) или скопировать в буфер обмена (`⌘C` / `⇧⌘C`).
- На миниатюрах в сетке отмечены фото с пометками. Пометки переезжают вместе с фото при переносе и возвращаются при отмене.
- Горизонтальный свайп двумя пальцами по трекпаду листает фото.
- Масштаб к курсору: щипок, двойной клик или двойной тап, а с мышью — `⌘` или `⌥` + прокрутка.

**Изменено**
- Фото можно уменьшить меньше размера экрана, как в «Просмотре».
- Увеличенное фото двигается прокруткой двумя пальцами.
- Прокрутка, которую не использует просмотр, теперь доходит до сетки и панели сведений.

## 1.1 — 2026-09-27

### English

**New**
- Grid of all photos. Review now opens in a grid instead of the first photo.
- Each thumbnail shows the file name, size, resolution and camera model.
- Thumbnail size can be changed with a slider, pinch, or `+` / `−` / `0`.
- Keyboard navigation in the grid: arrow keys, `Space`, `Home` / `End`. Rows are skipped exactly with `↑` / `↓`.
- Sorting works in the grid: `1`–`9`, `Delete` and `Z` behave as in the single-photo view.
- `F` toggles between the grid and a single photo. `Return` or a double-click opens the selected photo.

**Changed**
- In the single-photo view, `Esc` now returns to the grid instead of ending the review.
- Thumbnails are loaded in the background with a limit on parallel decodes, so large RAW folders don't freeze the Mac.

### Русский

**Новое**
- Сетка всех фото. Просмотр теперь открывается с сетки, а не с первого снимка.
- На каждой миниатюре видны имя файла, размер, разрешение и модель камеры.
- Размер миниатюр меняется слайдером, щипком или клавишами `+` / `−` / `0`.
- В сетке можно перемещаться с клавиатуры: стрелки, `Пробел`, `Home` / `End`. Стрелки `↑` / `↓` переходят ровно на строку.
- Отбирать можно прямо в сетке: `1`–`9`, `Delete` и `Z` работают так же, как при просмотре одного фото.
- `F` переключает между сеткой и одним фото. `Return` или двойной клик открывает выбранный снимок.

**Изменено**
- При просмотре одного фото `Esc` теперь возвращает к сетке, а не завершает просмотр.
- Миниатюры загружаются в фоне, и одновременно декодируется ограниченное число файлов, поэтому большие папки с RAW не подвешивают Mac.

## 1.0

First release: full-screen culling with swipes and keys, up to 9 destination folders, Trash, undo, zoom, RAW support.

Первая версия: полноэкранный отбор свайпами и клавишами, до 9 папок назначения, корзина, отмена, масштаб, поддержка RAW.
