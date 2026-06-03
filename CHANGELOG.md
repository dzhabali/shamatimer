# Changelog

Все заметные изменения шаматаймера.

## 2026-06-03

### Заметки к сессиям

- В History каждая карточка сессии стала **кликабельной** → модал `Session` с шапкой (дата, время начала–конца, длительность, activity) и полем `Note`.
- Новое поле `note` в модели сессии (опциональное, обратно совместимо). Сохраняется локально и в Firestore (`_updateSession` через `updateDoc`).
- Маркер `✎` у дат сессий с непустой заметкой.
- Крестик удаления больше не открывает карточку (`event.stopPropagation()`).
- Заметка **не** всплывает при добавлении сессии — только по клику на существующую.

### Импорт истории из Insight Timer

- Кнопка `⤓` в шапке History → модал импорта **JSON**-бэкапа сессий. Чекбоксы `Include yoga & healing` (off) и `Skip sessions under 1 min` (on), превью `N new / M existing / K in file`.
- **Дедуп** по `id` против local + cloud → идемпотентно (повторный импорт ничего не плодит).
- Запись локально (upsert) + в Firestore пачками (`writeBatch`, детерминированный doc-id `it_<id>` — ре-импорт перезаписывает).
- `tools/insight_to_shama.py` — конвертер стандартного экспорта Insight Timer (`InsightTimerLogs.csv` + `InsightTimerJournal.txt`) в этот JSON: джойнит заметки журнала к сессиям по `(старт до минуты, длительность)`, чистит потерянные при экспорте символы. Импортированы ~1.5k сессий за 2016–2026 с историческими заметками.

## 2026-05-20

### Calendar tab, ручное добавление и удаление сессий ([fca24bc](https://github.com/dzhabali/shamatimer/commit/fca24bc))

- **Calendar** — новая вкладка между Timer и History. Месячная сетка с минутами медитации в каждой ячейке. Стрелки ‹ › переключают месяцы. Сверху — карточка `avg per active day` (среднее по дням с практикой).
- **Heatmap** 6 уровней (оттенки зелёного `--accent`): `0` · `1–20` · `21–40` · `41–59` · `60–90` · `91+` минут. Сегодняшний день — тонкая зелёная рамка.
- **Добавление вручную** — кнопка `+` в шапке History. Модал с полями `Date` (нативный picker) и `Minutes`. Сохраняется как `mode: 'manual'`, `complete: true`, время старта = полдень.
- **Удаление** — `×` в правом верхнем углу каждой карточки в History. `confirm()` → удаление локально и в Firestore (если есть `firebaseDocId`).
- Firebase: `addDoc` теперь возвращает doc-id, `_loadSessions` подмешивает `firebaseDocId` к каждой записи, новый `_deleteSession(fid)` удаляет по id.

### DPE-секундомер ([274c921](https://github.com/dzhabali/shamatimer/commit/274c921))

- Верхний orb стал режимом **DPE** (Direct Perception of Emptiness) — секундомер count-up.
  - Idle: большой ▶ + подпись `DPE`.
  - Running: время в формате `M:SS` (`1:37`, без zero-pad минут).
  - При finish сессия пишется с `mode: 'stopwatch'`, `complete: true`.
- Нижняя кнопка ▶ осталась режимом обратного отсчёта (`mode: 'countdown'`).
- Пресеты сокращены до **15 / 30 / 45 / 60** мин, дефолт `30`.
- Mutual exclusion: пока работает один режим — второй заблокирован.
- Каждая сессия в логе получила поле `mode`. Старые записи трактуются как countdown.
- Persistence (`saveActiveState`/`restoreActiveState`) и `visibilitychange` стали mode-aware.
- Фикс: SVG-кольцо больше не перехватывает клики по orb (`pointer-events: none`).

## 2026-05-05

### Fix timer drift when app is backgrounded ([a96063f](https://github.com/dzhabali/shamatimer/commit/a96063f))

- Время сессии перестало уплывать, когда приложение в фоне.

## 2026-04-29

### Initial upload ([34c116a](https://github.com/dzhabali/shamatimer/commit/34c116a), [775cce9](https://github.com/dzhabali/shamatimer/commit/775cce9))

- Базовая версия: orb с обратным отсчётом, пресеты, history (local + Firestore), guest-режим.
