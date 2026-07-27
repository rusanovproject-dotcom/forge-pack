#!/usr/bin/env bash
# build-vendor.sh — пересобирает вендоренные зависимости пака из локальных апстримов.
#
# Зачем: пак самодостаточен — все скиллы, которые зовёт /forge, лежат внутри репо.
# Чтобы это не протухло, вендоринг собирается скриптом, а не руками.
#
# Запускать на машине, где апстримы установлены (плагины Claude Code + ~/.claude/skills).
# После запуска — обязательно scripts/check-links.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SP_SRC="${SP_SRC:-$HOME/.claude/plugins/cache/superpowers-marketplace/superpowers/5.1.0}"
CE_SRC="${CE_SRC:-$HOME/.claude/plugins/marketplaces/compound-engineering-plugin/plugins/compound-engineering}"
LOOPER_SRC="${LOOPER_SRC:-$HOME/.claude/skills/looper}"
FORGE_SRC="${FORGE_SRC:-$HOME/.claude/skills/forge}"

say() { printf '\033[1;36m▸\033[0m %s\n' "$1"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

for d in "$SP_SRC" "$CE_SRC" "$LOOPER_SRC" "$FORGE_SRC"; do
  [ -d "$d" ] || die "нет источника: $d"
done

# ─────────────────────────────────────────────────────────────
# 1. forge — сам скилл (ставится как личный скилл, зовётся /forge)
# ─────────────────────────────────────────────────────────────
say "forge → skills/forge"
rm -rf "$ROOT/skills/forge"
mkdir -p "$ROOT/skills/forge"
cp -R "$FORGE_SRC/." "$ROOT/skills/forge/"

# ─────────────────────────────────────────────────────────────
# 2. superpowers — плагин целиком (14 скиллов, MIT, obra)
#    Берём целиком, а не замыкание: скиллы ссылаются друг на друга,
#    целый плагин = гарантия, что ни одна ссылка не повиснет.
# ─────────────────────────────────────────────────────────────
say "superpowers → plugins/superpowers"
rm -rf "$ROOT/plugins/superpowers"
mkdir -p "$ROOT/plugins/superpowers"
# LICENSE + README.md обязательны — это атрибуция автора.
# AGENTS.md / CLAUDE.md апстрима не берём: это доки для контрибьюторов самого
# superpowers, плагином они не загружаются и валидатор на них ругается.
for item in .claude-plugin skills hooks scripts LICENSE README.md package.json; do
  [ -e "$SP_SRC/$item" ] && cp -R "$SP_SRC/$item" "$ROOT/plugins/superpowers/"
done
# tests/ docs/ assets/ .git — в пак не нужны
# Апстрим держит внутри .claude-plugin/ ещё и свой dev-маркетплейс "superpowers-dev".
# Внутри нашего маркетплейса он лишний и путает резолвер — убираем.
rm -f "$ROOT/plugins/superpowers/.claude-plugin/marketplace.json"

# ─────────────────────────────────────────────────────────────
# 3. compound-engineering — подмножество (3 скилла + 33 агента, MIT, Every)
#    Полный плагин = 41 скилл / 49 агентов, из них /forge зовёт малую часть.
#    Берём точное транзитивное замыкание: всё, на что ссылается forge,
#    плюс всё, на что ссылаются они сами. Проверяется check-links.sh.
# ─────────────────────────────────────────────────────────────
say "compound-engineering → plugins/compound-engineering (подмножество)"
CE_DST="$ROOT/plugins/compound-engineering"
rm -rf "$CE_DST"
mkdir -p "$CE_DST/skills" "$CE_DST/agents"
cp -R "$CE_SRC/.claude-plugin" "$CE_DST/"
cp "$CE_SRC/LICENSE" "$CE_DST/"

CE_SKILLS=(ce-plan ce-brainstorm document-review)
for s in "${CE_SKILLS[@]}"; do
  [ -d "$CE_SRC/skills/$s" ] || die "нет скилла CE: $s"
  cp -R "$CE_SRC/skills/$s" "$CE_DST/skills/"
done

CE_AGENTS=(
  document-review/adversarial-document-reviewer
  document-review/coherence-reviewer
  document-review/design-lens-reviewer
  document-review/feasibility-reviewer
  document-review/product-lens-reviewer
  document-review/scope-guardian-reviewer
  document-review/security-lens-reviewer
  research/best-practices-researcher
  research/framework-docs-researcher
  research/git-history-analyzer
  research/learnings-researcher
  research/repo-research-analyst
  research/slack-researcher
  review/adversarial-reviewer
  review/api-contract-reviewer
  review/architecture-strategist
  review/correctness-reviewer
  review/data-integrity-guardian
  review/data-migration-expert
  review/data-migrations-reviewer
  review/deployment-verification-agent
  review/dhh-rails-reviewer
  review/kieran-python-reviewer
  review/kieran-typescript-reviewer
  review/maintainability-reviewer
  review/pattern-recognition-specialist
  review/performance-oracle
  review/performance-reviewer
  review/reliability-reviewer
  review/security-reviewer
  review/security-sentinel
  review/testing-reviewer
  workflow/spec-flow-analyzer
)
for a in "${CE_AGENTS[@]}"; do
  [ -f "$CE_SRC/agents/$a.md" ] || die "нет агента CE: $a"
  mkdir -p "$CE_DST/agents/$(dirname "$a")"
  cp "$CE_SRC/agents/$a.md" "$CE_DST/agents/$a.md"
done

# ─────────────────────────────────────────────────────────────
# 4. looper — движок Трека C (MIT, Kevin Simback)
#    Личный скилл, зовётся /looper. Без .venv/.git/tests.
# ─────────────────────────────────────────────────────────────
say "looper → skills/looper"
rm -rf "$ROOT/skills/looper"
mkdir -p "$ROOT/skills/looper"
( cd "$LOOPER_SRC" && tar cf - \
    --exclude='.venv' --exclude='.git' --exclude='tests' --exclude='__pycache__' \
    --exclude='.pytest_cache' --exclude='*.pyc' . ) | ( cd "$ROOT/skills/looper" && tar xf - )

# ─────────────────────────────────────────────────────────────
# 5. Обезличивание + верификация — не отдельный ритуал, а часть сборки.
# ─────────────────────────────────────────────────────────────
say "обезличивание"
python3 "$ROOT/scripts/depersonalize.py"

say "проверка целостности ссылок"
python3 "$ROOT/scripts/check-links.py"

say "готово"
