#!/usr/bin/env python3
"""
depersonalize.py — снимает со скилла forge всё личное и локальное.

Личная версия /forge живёт внутри конкретного AI-офиса и ссылается на его правила,
на владельца по имени и на скиллы, которых у постороннего человека нет.
В публичный пак это ехать не должно.

Замены заданы ТОЧНЫМИ строками, а не регулярками. Если апстрим-версия скилла
изменилась и строка не нашлась — скрипт падает с ошибкой, а не «молча пропускает».
Так правка в личной версии не потеряется при следующей пересборке пака.

Запуск: python3 scripts/depersonalize.py   (вызывается из build-vendor.sh)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FORGE = ROOT / "skills" / "forge"

# (файл, что было, чем заменить) — каждая пара обязана найтись ровно один раз.
REPLACEMENTS: list[tuple[str, str, str]] = [
    (
        "SKILL.md",
        "**Verify падает 2 раза подряд → СТОП, `/rewind` к точке + иной подход** (правило офиса), не долбить корректировками.",
        "**Verify падает 2 раза подряд → СТОП, `/rewind` к точке + иной подход**, не долбить корректировками.",
    ),
    (
        "SKILL.md",
        "**Фаза 6 — Land (приземление, офис PR-only).** Готовый код не висит дифом: на main → сперва ветка;\n"
        "коммит по правилам офиса; **Draft PR**; pre-push PD-gate отрабатывает. В `main` не пушить, не мержить\n"
        "без отмашки Никиты. Это шаг «ship», ради которого цикл и затевался.",
        "**Фаза 6 — Land (приземление, PR-only).** Готовый код не висит дифом: на main → сперва ветка;\n"
        "коммит по конвенции проекта; **Draft PR**. В `main` не пушить и не мержить без явной отмашки\n"
        "владельца репозитория. Это шаг «ship», ради которого цикл и затевался.",
    ),
    (
        "references/swarm.md",
        "1. **Глубина** — «быстро» или «люто» (большой пул, 3-5 скептиков, синтез)? Слово-усилитель\n"
        "   `ultracode` от Никиты (не отдельный режим/скилл) = всегда люто.",
        "1. **Глубина** — «быстро» или «люто» (большой пул, 3-5 скептиков, синтез)? Заведи себе\n"
        "   слово-усилитель (например `ultracode`) — оно не отдельный режим и не скилл, просто\n"
        "   договорённость: сказал его — значит всегда «люто».",
    ),
    (
        "references/loop-design.md",
        "  (факт из research-само-исправления, в среде не подтверждён). Нет → фолбэк на `/autoresearch`.",
        "  Нет команды → фолбэк на Трек A или на внешний `/autoresearch` (см. ниже).",
    ),
    (
        "references/loop-design.md",
        "### `/autoresearch` (скилл, Karpathy-loop)",
        "### `/autoresearch` (внешний скилл, Karpathy-loop) — В ПАК НЕ ВХОДИТ",
    ),
    (
        "references/loop-design.md",
        "- ⚠️ Его SKILL.md требует `AskUserQuestion` (попапы) — конфликт со стилем офиса (живой текст).\n"
        "  При запуске из forge: собери недостающий контекст **диалогом**, не попапом.",
        "- ⚠️ **Не вендорится в пак:** у апстрима нет файла лицензии, поэтому класть его копию\n"
        "  в публичный репозиторий нельзя. Ставится отдельно, если он тебе нужен.\n"
        "- ⚠️ Его SKILL.md требует `AskUserQuestion` (попапы). Если предпочитаешь живой текст —\n"
        "  при запуске из forge собирай недостающий контекст **диалогом**, не попапом.",
    ),
    (
        "references/code-cycle.md",
        "ревьюеров. Code cycle — для кода Tier 1-3 и значимых артефактов. Это совпадает с разделом\n"
        "«Цикл разработки» в проектном `CLAUDE.md` — forge его исполняет, не дублирует.",
        "ревьюеров. Code cycle — для кода, который живёт дольше одного дня, и значимых артефактов.\n"
        "Если в проектном `CLAUDE.md` уже описан цикл разработки — forge его исполняет, не дублирует.",
    ),
    (
        "references/loop-design.md",
        "3. **Числовая метрика, keep/discard →** `/autoresearch`.",
        "3. **Числовая метрика, keep/discard →** `/autoresearch` (внешний, ставится отдельно).",
    ),
    (
        "references/loop-design.md",
        "  под **consent** + ПД-redaction (`.env`, `.env.*`, `secrets/**`, `*.key`). Это egress наружу —\n"
        "  ПД-гейт офиса железно.",
        "  под **consent** + redaction секретов (`.env`, `.env.*`, `secrets/**`, `*.key`).\n"
        "  Это egress наружу — гейт персональных данных соблюдать железно.",
    ),
]

# Маркеры, которых после обезличивания в паке быть не должно вообще.
# Осознанно НЕ запрещены: адрес самого публичного репозитория (rusanovproject-dotcom)
# и почты авторов вендоренных плагинов — это атрибуция, она обязана остаться.
# Строка "/Users/name/..." в апстриме compound-engineering — плейсхолдер в инструкции
# «не используйте абсолютные пути», поэтому ловим только реальный домашний каталог.
FORBIDDEN = [
    r"Никит",
    r"[Nn]ikita",
    r"irusanov",
    r"/Users/macbookpro",
    r"правил[аоы] офиса",
    r"офис PR-only",
    r"Tier \d",  # внутренняя система приоритетов офиса — постороннему непонятна
    r"[A-Za-z0-9._%+-]+@(?:gmail|yandex|mail|ya)\.[a-z]{2,}",
]


def main() -> int:
    if not FORGE.is_dir():
        print(f"✗ нет {FORGE} — сначала build-vendor.sh", file=sys.stderr)
        return 1

    for relpath, old, new in REPLACEMENTS:
        path = FORGE / relpath
        if not path.is_file():
            print(f"✗ нет файла {relpath}", file=sys.stderr)
            return 1
        body = path.read_text(encoding="utf-8")
        count = body.count(old)
        if count != 1:
            print(
                f"✗ {relpath}: искомая строка найдена {count} раз (ожидалось 1).\n"
                f"  Похоже, личная версия скилла изменилась — обнови таблицу замен "
                f"в scripts/depersonalize.py.\n  Искали:\n    {old[:120]}...",
                file=sys.stderr,
            )
            return 1
        path.write_text(body.replace(old, new), encoding="utf-8")

    print(f"▸ обезличено замен: {len(REPLACEMENTS)}")

    # Контрольный скан: вдруг личное просочилось где-то ещё.
    leaks: list[str] = []
    for p in ROOT.rglob("*"):
        if ".git" in p.parts or not p.is_file():
            continue
        if p.suffix.lower() not in {".md", ".json", ".txt", ".sh", ".yaml", ".yml", ".py"}:
            continue
        if p.name in {"depersonalize.py", "build-vendor.sh"}:
            continue  # сами скрипты содержат искомые строки по долгу службы
        try:
            body = p.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for pat in FORBIDDEN:
            for m in re.finditer(pat, body):
                line = body[: m.start()].count("\n") + 1
                leaks.append(f"{p.relative_to(ROOT)}:{line}: {m.group(0)}")

    if leaks:
        print("\n✗ В паке осталось личное/локальное:", file=sys.stderr)
        for x in leaks[:40]:
            print(f"  {x}", file=sys.stderr)
        return 1

    print("✓ личного и локальных путей в паке не осталось")
    return 0


if __name__ == "__main__":
    sys.exit(main())
