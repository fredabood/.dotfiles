# subtract.jq — overlay := live ⊖ base
#
#   jq -n --slurpfile live settings.json --slurpfile base settings.base.json -f subtract.jq
#
# Keeps only what `live` has that `base` does not: keys base lacks, array items base lacks,
# scalars that differ. The inverse of merge.jq for every change an overlay can express.
# It cannot express REMOVING something base has — callers must check the round trip
# merge(base, subtract(live, base)) == live and refuse when it fails.
def usub($l; $b):
  if ($l|type) == "object" and ($b|type) == "object" then
    reduce ($l|keys_unsorted)[] as $k ({};
      if ($b|has($k)|not) then .[$k] = $l[$k]
      else usub($l[$k]; $b[$k]) as $d
        | if $d == null or $d == {} or $d == [] then . else .[$k] = $d end
      end)
  elif ($l|type) == "array" and ($b|type) == "array" then
    [ $l[] | select(. as $x | any($b[]; . == $x) | not) ]
  elif $l == $b then null
  else $l end;

usub($live[0] // {}; $base[0] // {})
