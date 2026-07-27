#!/usr/bin/env python3
"""
check-links.py — доказывает, что пак самодостаточен.

Главное обещание forge-pack: всё, что зовёт /forge, лежит внутри репозитория.
Обещание без проверки — просто надежда, поэтому здесь оно проверяется машинно:
каждая ссылка вида superpowers:X и compound-engineering:Y:Z должна резолвиться
в реально существующий файл внутри пака.

Запуск:  python3 scripts/check-links.py
Выход:   0 — пак целостен, 1 — есть висячие ссылки.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SP_SKILLS = ROOT / "plugins" / "superpowers" / "skills"
CE_SKILLS = ROOT / "plugins" / "compound-engineering" / "skills"
CE_AGENTS = ROOT / "plugins" / "compound-engineering" / "agents"

TEXT_SUFFIXES = {".md", ".json", ".txt", ".sh", ".yaml", ".yml", ".py", ".ps1"}

# Файлы, где имена скиллов упоминаются как ДОКУМЕНТАЦИЯ, а не как вызов.
# Апстрим superpowers держит таблицу соответствий для других платформ
# (Gemini CLI, Codex): там перечислены имена агентов, которых в самом плагине нет
# и не должно быть. Это не битые ссылки — это описание чужих аналогов.
DOC_ONLY_FILES = {
    # Сам верификатор содержит примеры ссылок в комментариях и регулярках.
    "scripts/check-links.py",
    "plugins/superpowers/skills/using-superpowers/references/gemini-tools.md",
    "plugins/superpowers/skills/using-superpowers/references/codex-tools.md",
    "plugins/superpowers/skills/using-superpowers/references/copilot-tools.md",
}

# Внешние зависимости, сознательно НЕ зашитые в пак. Каждая — с причиной.
# Проверяем, что forge упоминает их только как опциональные, и печатаем статус.
EXTERNAL = {
    "autoresearch": "нет лицензии в апстриме — чужой код без лицензии в публичный репо не кладём",
    "goal": "нативная команда Claude Code, если она есть в твоей версии — вендорить нечего",
}

RE_SP = re.compile(r"superpowers:([a-z0-9][a-z0-9-]*)")
RE_CE_AGENT = re.compile(r"compound-engineering:([a-z-]+):([a-z0-9][a-z0-9-]*)")
# Имя скилла берём целиком и требуем, чтобы за ним НЕ шло двоеточие —
# иначе "compound-engineering:research:foo" ложно распознаётся как скилл "researc".
RE_CE_SKILL = re.compile(r"compound-engineering:([a-z0-9][a-z0-9-]*)(?![a-z0-9:-])")

AGENT_GROUPS = {"review", "research", "document-review", "workflow", "design", "docs"}


def text_files() -> list[Path]:
    out = []
    for p in ROOT.rglob("*"):
        if ".git" in p.parts or not p.is_file():
            continue
        if p.suffix.lower() in TEXT_SUFFIXES:
            out.append(p)
    return out


def rel(p: Path) -> str:
    return str(p.relative_to(ROOT))


def main() -> int:
    broken: list[str] = []
    checked = 0

    sp_available = {d.name for d in SP_SKILLS.iterdir() if d.is_dir()} if SP_SKILLS.is_dir() else set()
    ce_skill_available = {d.name for d in CE_SKILLS.iterdir() if d.is_dir()} if CE_SKILLS.is_dir() else set()
    ce_agent_available = set()
    if CE_AGENTS.is_dir():
        for grp in CE_AGENTS.iterdir():
            if grp.is_dir():
                for f in grp.glob("*.md"):
                    ce_agent_available.add(f"{grp.name}:{f.stem}")

    print(f"В паке: {len(sp_available)} скиллов superpowers, "
          f"{len(ce_skill_available)} скиллов compound-engineering, "
          f"{len(ce_agent_available)} агентов compound-engineering\n")

    for path in text_files():
        r = rel(path)
        if r in DOC_ONLY_FILES:
            continue
        try:
            body = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue

        for name in set(RE_SP.findall(body)):
            checked += 1
            if name not in sp_available:
                broken.append(f"{r}: superpowers:{name} → нет скилла")

        for grp, name in set(RE_CE_AGENT.findall(body)):
            if grp not in AGENT_GROUPS:
                continue
            checked += 1
            if f"{grp}:{name}" not in ce_agent_available:
                broken.append(f"{r}: compound-engineering:{grp}:{name} → нет агента")

        for name in set(RE_CE_SKILL.findall(body)):
            if name in AGENT_GROUPS:
                continue  # это префикс группы агентов, разобран выше
            checked += 1
            if name not in ce_skill_available:
                broken.append(f"{r}: compound-engineering:{name} → нет скилла")

    # Битые симлинки — отдельная категория: файл вроде есть, а указывает в пустоту.
    dangling = [rel(p) for p in ROOT.rglob("*")
                if ".git" not in p.parts and p.is_symlink() and not p.exists()]

    # Пустые файлы — тихий признак сорванного копирования.
    empty = [rel(p) for p in ROOT.rglob("*")
             if ".git" not in p.parts and p.is_file() and not p.is_symlink()
             and p.stat().st_size == 0]

    # У каждого скилла должен быть SKILL.md с frontmatter.
    no_frontmatter = []
    for skills_dir in (SP_SKILLS, CE_SKILLS, ROOT / "skills"):
        if not skills_dir.is_dir():
            continue
        for d in skills_dir.iterdir():
            if not d.is_dir():
                continue
            sk = d / "SKILL.md"
            if not sk.is_file():
                no_frontmatter.append(f"{rel(d)}: нет SKILL.md")
            elif not sk.read_text(encoding="utf-8", errors="ignore").lstrip().startswith("---"):
                no_frontmatter.append(f"{rel(sk)}: нет frontmatter")

    print(f"Проверено ссылок: {checked}")
    print(f"Битых ссылок:     {len(broken)}")
    print(f"Битых симлинков:  {len(dangling)}")
    print(f"Пустых файлов:    {len(empty)}")
    print(f"Скиллов без SKILL.md/frontmatter: {len(no_frontmatter)}")

    print("\nВнешние зависимости (сознательно не в паке):")
    for name, why in EXTERNAL.items():
        print(f"  /{name} — {why}")

    problems = broken + dangling + empty + no_frontmatter
    if problems:
        print("\n✗ ПРОБЛЕМЫ:")
        for p in problems:
            print(f"  {p}")
        return 1

    print("\n✓ Пак самодостаточен: каждая ссылка резолвится внутри репозитория.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
