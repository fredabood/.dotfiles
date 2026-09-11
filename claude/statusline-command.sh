#!/bin/bash
# Claude Code status line: model display name + extended-thinking state +
# context window token usage + a /compact nudge + current working directory.
# Reads the session JSON payload from stdin (see Claude Code statusLine docs).
# Fast, dependency-free aside from jq/awk (both standard on macOS).

# --- Tunables -----------------------------------------------------------
# Percent of the context window at which to start nudging toward /compact.
COMPACT_WARN_PCT=${COMPACT_WARN_PCT:-33}
COMPACT_URGENT_PCT=${COMPACT_URGENT_PCT:-67}
# ------------------------------------------------------------------------

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
used=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# thinking.enabled is a boolean, so we can't use jq's `//` (it treats
# `false` as falsy and would swallow it). Explicitly distinguish
# true / false / field-absent instead.
thinking_raw=$(echo "$input" | jq -r '
  (.thinking.enabled) as $t
  | if $t == true then "on"
    elif $t == false then "off"
    else "unknown"
    end
')

# ANSI colours, suppressed when NO_COLOR is set.
if [ -n "${NO_COLOR:-}" ]; then
  C_WARN="" C_URGENT="" C_RESET=""
else
  C_WARN=$'\033[33m'      # yellow
  C_URGENT=$'\033[1;31m'  # bold red
  C_RESET=$'\033[0m'
fi

# Format a raw token count as e.g. 42.3k / 1.2M / 512
format_tokens() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000) printf "%.1fM", n/1000000;
    else if (n >= 1000) printf "%.1fk", n/1000;
    else printf "%d", n;
  }'
}

used_fmt=$(format_tokens "$used")
total_fmt=$(format_tokens "$total")

# Fall back to computing the percentage if the server didn't precompute it.
if [ -z "$pct" ] && [ "${total:-0}" -gt 0 ] 2>/dev/null; then
  pct=$(awk -v u="$used" -v t="$total" 'BEGIN { printf "%.0f", (u/t)*100 }')
fi

# Assemble segments (model is always present) and join with " | ",
# skipping any segment we couldn't determine.
segments=("$model")

if [ "$thinking_raw" != "unknown" ]; then
  segments+=("thinking: ${thinking_raw}")
fi

if [ -n "$pct" ] && [ "${total:-0}" -gt 0 ] 2>/dev/null; then
  pct_int=$(awk -v p="$pct" 'BEGIN { printf "%.0f", p }')

  # Colour the usage segment itself, and append an explicit nudge, once
  # usage crosses the thresholds above.
  if [ "$pct_int" -ge "$COMPACT_URGENT_PCT" ]; then
    segments+=("${C_URGENT}${used_fmt}/${total_fmt} tokens (${pct_int}%)${C_RESET}")
    segments+=("${C_URGENT}⚠ run /compact${C_RESET}")
  elif [ "$pct_int" -ge "$COMPACT_WARN_PCT" ]; then
    segments+=("${C_WARN}${used_fmt}/${total_fmt} tokens (${pct_int}%)${C_RESET}")
  else
    segments+=("${used_fmt}/${total_fmt} tokens (${pct_int}%)")
  fi
fi

cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
if [ -n "$cwd" ]; then
  # Abbreviate the home directory prefix as ~
  if [ -n "$HOME" ]; then
    case "$cwd" in
      "$HOME") cwd="~" ;;
      "$HOME"/*) cwd="~${cwd#"$HOME"}" ;;
    esac
  fi
  segments+=("$cwd")
fi

output="${segments[0]}"
for ((i = 1; i < ${#segments[@]}; i++)); do
  output="${output} | ${segments[$i]}"
done

printf "%s\n" "$output"
