# Changelog / История изменений

## 1.4 — 2026-10-21

### English
- Star filter picks exact counts: only ★★, or any set of counts (and "no stars"), instead of "at least N". The filter is now a panel that stays open while you tick several stars and colors.
- Stars and colors set right before quitting are no longer lost.
- `Z` / `⌘Z` also undoes stars and colors, in the same order as moves.
- Clipping overlay like in Lightroom: click the triangles in the histogram corners (info panel) to show crushed shadows in blue and clipped highlights in red on the photo, in the viewer and in compare mode.
- People: merging similar groups is done with one matrix multiply instead of rescanning all pairs after every merge — on large folders it took minutes of CPU after the analysis had finished.
- Rejects open fitted to the screen; zooming to 100 % on the problem spot is now off by default (Settings → "Open rejects at the problem spot").
- "All photos / Rejects / Bursts" sections in the grid (`⌘1`–`⌘3`), background analysis with an on-disk cache (nothing next to your photos).
- Rejects: blur and missed focus checked at 100 % around the eyes or the subject, "softer than burst neighbors", closed eyes, highlights, dark faces, tilted horizon, accidental shots; strictness Soft / Normal / Strict; reason mark in "All photos" and in the viewer; rejects open at 100 % on the problem spot (can be turned off).
- Bursts: grouping by time, image similarity and faces; headers, best shot per burst (sharpness, everyone's eyes open, face quality, exposure), `↑` / `↓` between bursts, open a single burst.
- Reject calibration panel (`⌥⌘K`): per-metric scatter with thresholds, labeling, training a model on your labels, CSV export.
- Viewer loads the full-resolution image when zoomed in past the preview resolution.
- Rejects grid: a reason line under each shot.
- People section (`⌘4`): faces grouped into people without a recognition model; face descriptors stay in the analysis cache on this Mac.
- The "Selected" folder is created only on the first move, and the default folder can be turned off in Settings.
- Blur rule rewritten: 100 % sharpness at the eyes (or the subject) compared to the folder median, instead of the fine-detail share of the 1280 px copy that flagged sharp portraits.
- People: optional AuraFace-v1 face recognition model (faces aligned by eyes, nose and mouth); grouping starts only from good faces, refines group centers, merges close groups and leaves doubtful faces ungrouped. Fixed missing person tiles when two people share a cover photo; face tiles are centered.
- Highlights: a reject only when faces or the main subject are blown out (bright windows and lamps behind people are no longer rejects). Blur: with MobileCLIP, a shot stays in Rejects only if the model also sees it as blurry.
- Optional MobileCLIP-S2 model (Core ML, not in the repository by default): image vectors of the frame, the 100 % crop and up to three faces are cached; prompt scores for focus, closed eyes, camera shake and accidental shots are shown in the calibration panel and in the CSV. Prompts are computed once in the app with the text encoder.
- Stars and color labels (off by default): `⌥1`–`⌥5`, `⌃1`–`⌃8` or a click under the thumbnail, in the viewer and in compare mode; a grid filter, "Write to XMP" into sidecars next to photos. An `.xmp` sidecar now moves, goes to the Trash and comes back together with its photo.
- Memory: preview and thumbnail caches are bounded and cleared when another folder is opened; analysis models are unloaded when analysis finishes; analysis runs on up to 3 threads. Analysis results reach the grid once per second instead of per shot. Cache writes are queued, so a slow older write can no longer overwrite a newer one and force re-analysis.

### Русский
- Фильтр по звёздам выбирает точное число: только ★★ или любой набор (в том числе «без звёзд»), а не «не меньше N». Фильтр теперь — панель, которая не закрывается, пока отмечаешь несколько звёзд и цветов.
- Звёзды и цвета, поставленные прямо перед закрытием приложения, больше не теряются.
- `Z` / `⌘Z` отменяет и звёзды с цветом — в общем порядке с переносами.
- Подсветка пересветов и провалов, как в Lightroom: клик по треугольникам в углах гистограммы (сведения, I) показывает на кадре провалы синим и выбитые света красным — в просмотре и в сравнении.
- «Люди»: слияние похожих групп — одним умножением матриц, а не перебором всех пар после каждого слияния: на больших папках это минутами грузило процессор уже после анализа.
- Брак открывается вписанным в экран; приближение к проблемному месту в 100 % теперь по умолчанию выключено (Настройки → «Открывать брак сразу на проблемном месте»).
- Разделы «Все фото / Брак / Серии» в сетке (`⌘1`–`⌘3`), анализ в фоне с кэшем на диске (рядом с фото ничего не пишется).
- Брак: размытость и промах фокуса проверяются в 100 % на глазах или объекте, «мягче соседей по серии», закрытые глаза, пересвет, лица в тени, завал горизонта, случайные кадры; строгость «Мягко / Обычно / Строго»; значок с причиной в «Все фото» и строка причины в просмотре; брак открывается сразу в 100 % на проблемном месте (можно выключить).
- Серии: по времени, похожести кадров и лицам; заголовки, лучший кадр серии (резкость, у всех открыты глаза, качество лиц, экспозиция), `↑` / `↓` между сериями, открытие одной серии.
- Панель «Калибровка брака» (`⌥⌘K`): график каждой метрики с порогом, разметка, обучение модели по разметке, экспорт CSV.
- Просмотр подгружает кадр в полном разрешении, когда при зуме пикселей превью уже не хватает.
- В сетке «Брак» под каждым кадром — строка с причиной.
- Раздел «Люди» (`⌘4`): лица собираются в людей без модели распознавания; описания лиц хранятся только в кэше анализа на этом Mac.
- Папка «Отобранные» создаётся только при первом переносе, а папку по умолчанию можно выключить в настройках.
- Правило «Размыто» переписано: резкость в 100 % у глаз (или объекта) сравнивается с медианой папки вместо доли мелких деталей на копии 1280 px, из-за которой в брак попадали резкие портреты.
- «Люди»: модель распознавания лиц AuraFace-v1 по желанию (лицо выравнивается по глазам, носу и рту); группы начинаются только с хороших лиц, центры уточняются, близкие группы сливаются, сомнительные лица остаются без группы. Исправлены пропавшие плитки, когда у двух людей обложка из одного кадра; лицо на плитке по центру.
- Пересвет: брак, только если выбиты лица или главный объект (светлые окна и лампы за спиной больше не брак). Размыто: с MobileCLIP кадр остаётся в браке, только если и модель считает его размытым.
- Модель MobileCLIP-S2 по желанию (Core ML, в репозиторий по умолчанию не входит): векторы кадра, фрагмента в 100 % и до трёх лиц сохраняются в кэше; оценки «не в фокусе», «закрыты глаза», «шевелёнка», «случайный кадр» видны в калибровке и в CSV. Подсказки считаются один раз в приложении текстовой частью модели.
- Звёзды и цветовые метки (по умолчанию выкл.): `⌥1`–`⌥5`, `⌃1`–`⌃8` или кликом под миниатюрой, в просмотре и в сравнении; фильтр сетки, «Записать в XMP» — в файл рядом с фото. XMP рядом с кадром теперь переносится, уходит в корзину и возвращается вместе с ним.
- Память: кэши превью и миниатюр ограничены и очищаются при открытии другой папки; нейросети выгружаются после анализа; анализ идёт не больше чем в 3 потока. Результаты анализа попадают в сетку раз в секунду, а не после каждого кадра. Записи кэша идут по очереди: медленная старая запись больше не затирает новую, и кадры не анализируются повторно.

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
