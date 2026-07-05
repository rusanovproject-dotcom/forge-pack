#!/usr/bin/env bash
# Forge — установка скилла цикла разработки в Claude Code.
# Копирует скилл в ~/.claude/skills/forge и проверяет два плагина-зависимости.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${1:-$HOME/.claude}"
SKILLS_DIR="$CLAUDE_DIR/skills"
DST="$SKILLS_DIR/forge"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

say ""
say "═══ Forge — установка ═══"
say ""

# 1. Копируем скилл ------------------------------------------------------------
if [ ! -d "$SCRIPT_DIR/skills/forge" ]; then
  say "ОШИБКА: не нашёл skills/forge рядом со скриптом. Запускай из корня пака."
  exit 1
fi
mkdir -p "$SKILLS_DIR"
if [ -d "$DST" ]; then
  warn "forge уже установлен в $DST — перезаписываю (бэкап в forge.bak)"
  rm -rf "$DST.bak"; cp -r "$DST" "$DST.bak"
fi
rm -rf "$DST"
cp -r "$SCRIPT_DIR/skills/forge" "$DST"
ok "скилл скопирован → $DST"

# 2. Проверяем плагины-зависимости --------------------------------------------
say ""
say "Проверяю зависимости (два плагина):"
PLUGINS_JSON="$CLAUDE_DIR/plugins/installed_plugins.json"
need_compound=1; need_superpowers=1
if [ -f "$PLUGINS_JSON" ]; then
  grep -q "compound-engineering@" "$PLUGINS_JSON" && need_compound=0 || true
  grep -q "superpowers@"          "$PLUGINS_JSON" && need_superpowers=0 || true
fi
[ "$need_compound" -eq 0 ]    && ok "compound-engineering — установлен" || warn "compound-engineering — НЕ найден"
[ "$need_superpowers" -eq 0 ] && ok "superpowers — установлен"          || warn "superpowers — НЕ найден"

# 3. Итог + ручные шаги -------------------------------------------------------
say ""
say "═══ Готово. Осталось 2 ручных шага в Claude Code ═══"
say ""

if [ "$need_compound" -ne 0 ] || [ "$need_superpowers" -ne 0 ]; then
  say "① Поставь недостающие плагины (внутри Claude Code, не в терминале):"
  [ "$need_superpowers" -ne 0 ] && say "     /plugin marketplace add obra/superpowers-marketplace"
  [ "$need_superpowers" -ne 0 ] && say "     /plugin install superpowers@superpowers-marketplace"
  [ "$need_compound" -ne 0 ]    && say "     /plugin marketplace add EveryInc/compound-engineering-plugin"
  [ "$need_compound" -ne 0 ]    && say "     /plugin install compound-engineering@compound-engineering-plugin"
  say "   (Forge без них будет ссылаться в пустоту — это его главная зависимость.)"
else
  say "① Плагины на месте — ничего ставить не надо."
fi
say ""
say "② Пропиши роутинг в свой CLAUDE.md (чтобы Claude сам заходил через forge)."
say "   Готовый блок — в README.md, раздел «Как подвязать»."
say ""
say "После этого перезапусти Claude Code и скажи: /forge собери фичу …"
say "или просто «напиши код …» — forge подхватит сам."
say ""
