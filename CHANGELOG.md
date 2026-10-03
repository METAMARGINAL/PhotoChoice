# Changelog / История изменений

## 1.3 — 2026-10-03

### English

**New**
- Compare mode (`C`): two shots side by side, reference (A) and candidate (B). Synced zoom and pan (`L`), swap sides (`X`), promote to reference (`↑`), sort the active side with `1`–`9` / `Delete`, info panel for the active shot.
- Color palette: the info panel shows about 10 main colors of the photo (k-means in OKLab). Palettes are cached and survive move + undo.
- Themes: Studio, Glass, Quiet and Contact, with light versions of Studio and Glass. Light mode applies to the start window and the grid; the viewer, drawing and compare stay dark.
- New design system: shared keycaps, hint bar grouped by meaning, buttons with hover, pressed and disabled states, checkbox and action confirmations, all following the current theme.
- RAW + JPEG pairs: files with the same name are shown as one card and are moved, trashed and restored together (can be turned off in Settings).
- Rename by metadata on move (off by default): three templates based on capture date and time, falling back to the file date. RAW + JPEG pairs get the same name; Trash keeps the original name; undo restores it.
- Settings window (`⌘,`) with theme previews, appearance mode, pairing and renaming options.
- Redesigned start window.
- Spec for the upcoming "Reject" and "Bursts" sections: `docs/SmartCulling.md`.

### Русский

**Новое**
- Сравнение (`C`): два кадра рядом, эталон (A) и кандидат (B). Синхронные масштаб и перемещение (`L`), обмен сторон (`X`), «сделать эталоном» (`↑`), отбор активной стороны клавишами `1`–`9` / `Delete`, панель сведений для активного кадра.
- Палитра кадра: в панели сведений показываются около 10 основных цветов снимка (k-means в OKLab). Палитры кэшируются и находятся снова после переноса и отмены.
- Темы оформления: «Студия», «Стекло», «Тишина» и «Контакт», у «Студии» и «Стекла» есть светлые варианты. Светлый режим действует на стартовое окно и сетку; просмотр, рисование и сравнение всегда тёмные.
- Новая дизайн-система: общие клавиши-подсказки, строка подсказок со смысловыми группами, кнопки с состояниями наведения, нажатия и выключения, чекбокс и подтверждения действий — всё по текущей теме.
- Пары RAW + JPEG: файлы с одинаковым именем показываются одной карточкой и переносятся, удаляются и возвращаются вместе (можно выключить в настройках).
- Переименование по метаданным при переносе (по умолчанию выключено): три шаблона на основе даты и времени съёмки, если их нет — даты файла. Пара RAW + JPEG получает общее имя, в корзину файлы уходят со старым именем, Z возвращает прежнее.
- Окно «Настройки» (`⌘,`): превью тем, режим оформления, пары и переименование.
- Новое оформление стартового окна.
- Спецификация будущих разделов «Брак» и «Серии»: `docs/SmartCulling.md`.

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
