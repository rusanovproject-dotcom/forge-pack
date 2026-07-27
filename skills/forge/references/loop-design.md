# Трек C — Автономный loop (движки + проектировщик)

> Запускается, когда задача итеративная под критерий: «крути, пока не достигнешь». Три движка
> исполнения + один проектировщик НАД ними. Не путать движки между собой.

## Движки исполнения

### Нативный `/goal` (встроен в Claude Code, v2.1.139+)
- Ставишь completion condition → Claude крутит автономно (план→пиши→тесты→рефактор→верифай→повтор),
  пока условие не выполнено или `/goal clear`.
- **Встроенный судья:** после каждого хода маленькая модель (Haiku по умолчанию) сверяет транскрипт
  и пишет короткую причину «выполнено / нет».
- Когда: простой автоном «доведи до зелёного / до условия». Дёшево, без лишней обвязки.
- ⚠️ Перед опорой проверь, что `/goal` и `/loop` реально есть в текущей версии Claude Code
  Нет команды → фолбэк на Трек A или на внешний `/autoresearch` (см. ниже).

### `/autoresearch` (внешний скилл, Karpathy-loop) — В ПАК НЕ ВХОДИТ
- Структурный loop: Modify → Verify → Keep/Discard → Repeat, под измеримую **метрику**.
- Под-домены: `:fix` (чинить до zero errors), `:security` (STRIDE+OWASP аудит), `:ship`, `:debug`,
  `:predict`, `:scenario`. Bounded через `Iterations: N`.
- Когда: задача с явной числовой метрикой, нужен keep/discard по результату каждой итерации.
- ⚠️ **Не вендорится в пак:** у апстрима нет файла лицензии, поэтому класть его копию
  в публичный репозиторий нельзя. Ставится отдельно, если он тебе нужен.
- ⚠️ Его SKILL.md требует `AskUserQuestion` (попапы). Если предпочитаешь живой текст —
  при запуске из forge собирай недостающий контекст **диалогом**, не попапом.

### Workflow-рой — это Трек B, не автономный loop
- Рой = параллель/адверсариал/fan-out за ОДИН веер, а не последовательная итерация «крути до критерия».
  Если задача — «покрутить, пока метрика не улучшится» — это Трек C (движки ниже). Если «разобрать/
  переделать много всего разом» — это Трек B, иди в `references/swarm.md`, а не сюда.
- Гибрид (итеративный цикл, где каждый раунд — параллельный рой): Трек C проектирует критерий
  остановки, а внутри раунда зовёт Workflow. Редкий случай, не путай с обычным роем.

## Проектировщик — `/looper` (design layer НАД движками)

- **Что:** коуч проектирования цикла. «Scaffold, don't run» — сам модель не гоняет, только
  интервьюирует, критикует по рубрикам, пишет файлы.
- **Эмитит:** `loop.yaml` (авторский) → компилит в `loop.resolved.json` + `LOOP.md` +
  `RUN_IN_SESSION.md` (эта сессия исполняет) + `run-loop.py` (внешний раннер).
- **Даёт то, чего нет у движков:** типизированную рубрику «готово», cross-model council
  (ревьюер ≠ судья), termination guards (max_iterations, revision cap, no-progress stop, budget).

### loop.yaml — структура (костяк)
```yaml
goal: { statement, context_sources, definition_of_done }
verification:                         # типизировано: programmatic | judge | human
  - { id, type, check/rubric/prompt, expect }
host:    { cli, model, invoke: [argv], timeout_sec }   # может быть codex/gpt
council: [ { id, role: reviewer|judge, cli, model, scope } ]   # cross-model
gates:
  plan_gate / delivery_gate:
    { when, members, verdict_policy: revise_until_clean, verdict_source, criteria, max_revisions }
loop_control:
  max_iterations, budget: { usd, tokens, wall_clock_min },
  no_progress: { max_stalled_iterations, signals, action }, human_checkpoints, stop_conditions
```
Компиляция: `~/.claude/skills/looper/.venv/bin/python ~/.claude/skills/looper/scripts/looper.py
compile <target>/loop.yaml --out ... --render ... --session-prompt ...`

## Правила выбора (когда что)

1. **Код с тестами → рубрика = тесты.** LOOPER НЕ нужен, бери Трек A или нативный `/goal`.
2. **Мягкая метрика «лучше/хуже» / важный длинный цикл →** `/looper` проектирует рубрику и council,
   потом исполняешь по `RUN_IN_SESSION.md`.
3. **Числовая метрика, keep/discard →** `/autoresearch` (внешний, ставится отдельно).
4. **Простой автоном до условия →** нативный `/goal`.

## Guardrails

- Артефакты цикла → `.forge/` в репо задачи (gitignored по умолчанию).
- **Cross-model судья (Codex/GPT)** — опционально и только для критичного (деньги/auth/архитектура),
  под **consent** + redaction секретов (`.env`, `.env.*`, `secrets/**`, `*.key`).
  Это egress наружу — гейт персональных данных соблюдать железно.
- LOOPER требует ≥1 не-vibe критерий и валидный `verdict_source` на каждом `revise_until_clean`.
