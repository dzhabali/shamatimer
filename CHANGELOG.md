# Changelog

Все заметные изменения шаматаймера.

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
