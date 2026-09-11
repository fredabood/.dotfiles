# merge.jq — settings.json := base ⊕ overlay
#
#   jq -n --slurpfile base settings.base.json --slurpfile ovl settings.overlay.json -f merge.jq
#
# Objects merge key by key, recursively. Arrays UNION (base order first, overlay's new items
# appended, duplicates dropped) — jq's own `*` replaces arrays, which would let an overlay's
# `permissions.allow` silently wipe every base entry. Any other clash: the overlay wins.
def umerge($a; $b):
  if ($a|type) == "object" and ($b|type) == "object" then
    reduce (($a|keys_unsorted) + (($b|keys_unsorted) - ($a|keys_unsorted)))[] as $k ({};
      .[$k] = if ($a|has($k)) and ($b|has($k)) then umerge($a[$k]; $b[$k])
              elif ($b|has($k)) then $b[$k]
              else $a[$k] end)
  elif ($a|type) == "array" and ($b|type) == "array" then
    reduce ($a + $b)[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end)
  else $b end;

umerge($base[0] // {}; $ovl[0] // {})
