#!/usr/bin/env bash
# install.sh — ставит Forge и все его зависимости из этого репозитория.
#
# Ничего не качает из интернета: скиллы и плагины лежат внутри пака.
# Что делает:
#   1. кладёт скилл forge   → ~/.claude/skills/forge   (зовётся /forge)
#   2. кладёт скилл looper  → ~/.claude/skills/looper  (зовётся /looper, движок Трека C)
#   3. подключает этот репозиторий как маркетплейс Claude Code
#   4. ставит из него плагины superpowers и compound-engineering
#
# Уже стоит настоящий superpowers или compound-engineering из апстрима? Тогда
# вендоренную копию НЕ ставим — два плагина с одним пространством имён конфликтуют,
# а апстрим свежее. Скрипт это проверяет сам.
#
# Повторный запуск безопасен: старое уносится в бэкап с отметкой времени.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SKILLS_DIR="$CLAUDE_DIR/skills"
STAMP="$(date +%Y%m%d-%H%M%S)"

bold()  { printf '\033[1m%s\033[0m\n' "$1"; }
say()   { printf '\033[1;36m▸\033[0m %s\n' "$1"; }
ok()    { printf '\033[1;32m✓\033[0m %s\n' "$1"; }
warn()  { printf '\033[1;33m!\033[0m %s\n' "$1"; }
die()   { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

bold "Forge — установка"
echo

# ── 0. Предпосылки ───────────────────────────────────────────
command -v claude >/dev/null 2>&1 || die "не найден CLI claude. Поставь Claude Code и повтори."
[ -d "$ROOT/skills/forge" ] || die "нет $ROOT/skills/forge — репозиторий скачан не полностью."

HAS_JQ=0
command -v jq >/dev/null 2>&1 && HAS_JQ=1

mkdir -p "$SKILLS_DIR"

# ── 1-2. Личные скиллы ───────────────────────────────────────
install_skill() {
  local name="$1" src="$ROOT/skills/$1" dst="$SKILLS_DIR/$1"
  [ -d "$src" ] || { warn "в паке нет скилла $name — пропускаю"; return; }
  if [ -e "$dst" ]; then
    mv "$dst" "$dst.backup-$STAMP"
    warn "прежний $name сохранён: $dst.backup-$STAMP"
  fi
  cp -R "$src" "$dst"
  ok "скилл $name → $dst"
}

say "Ставлю скиллы"
install_skill forge
install_skill looper
echo

# ── 3. Маркетплейс ───────────────────────────────────────────
say "Подключаю маркетплейс пака"
if claude plugin marketplace list 2>/dev/null | grep -q 'forge-pack'; then
  claude plugin marketplace update forge-pack >/dev/null 2>&1 || true
  ok "маркетплейс forge-pack уже подключён — обновлён"
else
  claude plugin marketplace add "$ROOT" >/dev/null || die "не удалось подключить маркетплейс"
  ok "маркетплейс forge-pack подключён из $ROOT"
fi
echo

# ── 4. Плагины-зависимости ───────────────────────────────────
# Пространство имён определяется ИМЕНЕМ плагина, а не маркетплейсом:
# superpowers@forge-pack и superpowers@superpowers-marketplace дают один и тот же
# префикс superpowers:*. Держать оба разом — значит спорить самим с собой.
plugin_installed_elsewhere() {
  local name="$1" out
  if [ "$HAS_JQ" = "1" ]; then
    out="$(claude plugin list --json 2>/dev/null \
      | jq -r --arg n "$name" '.[] | select(.enabled) | .id | select(startswith($n + "@"))' 2>/dev/null || true)"
  else
    out="$(claude plugin list 2>/dev/null | grep -o "${name}@[a-zA-Z0-9._-]*" || true)"
  fi
  printf '%s' "$out" | grep -v "^${name}@forge-pack$" | head -1 || true
}

install_dep() {
  local name="$1" existing
  existing="$(plugin_installed_elsewhere "$name")"
  if [ -n "$existing" ]; then
    warn "$name уже стоит как $existing — вендоренную копию не ставлю (апстрим свежее)"
    return
  fi
  if claude plugin install "${name}@forge-pack" >/dev/null 2>&1; then
    ok "плагин $name установлен из пака"
  else
    warn "не удалось поставить $name автоматически. Вручную: claude plugin install ${name}@forge-pack"
  fi
}

say "Ставлю зависимости"
install_dep superpowers
install_dep compound-engineering
echo

# ── 5. Итог ──────────────────────────────────────────────────
bold "Готово"
cat <<'TXT'

Перезапусти Claude Code, чтобы плагины подхватились, и проверь:

    /forge собери мне маленькую фичу

Что теперь есть:
  /forge   — единый вход в цикл разработки (классификатор → трек → ревью → верификация)
  /looper  — проектировщик автономного цикла (Трек C)
  superpowers:*          — TDD, systematic-debugging, executing-plans, verification
  compound-engineering:* — ce-plan, ce-brainstorm, document-review + агенты-ревьюеры

Чтобы Claude сам заходил в /forge на задачах по коду, добавь в свой CLAUDE.md
блок роутинга — он лежит в README.md, раздел «Роутинг: чтобы Claude заходил сам».

Что дальше читать:
  README.md           — как устроен цикл и почему именно так
  docs/METHODOLOGY.md — логика методологии целиком
  docs/MAP.md         — карта: какой скилл где и зачем
TXT
