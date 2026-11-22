#!/bin/bash
# Claude Code usage lines for fastfetch, from ~/.claude/stats-cache.json (local, no network)
f="$HOME/.claude/stats-cache.json"
[ -r "$f" ] || { echo "no data"; exit 0; }
case "$1" in
  sessions)
    jq -r '"\(.totalSessions) sessions · \(.totalMessages) msgs · since \(.firstSessionDate[:10])"' "$f" ;;
  tokens)
    jq -r '
      def h: if . >= 1e9 then "\(. / 1e8 | floor / 10)B" elif . >= 1e6 then "\(. / 1e5 | floor / 10)M" elif . >= 1e3 then "\(. / 1e2 | floor / 10)K" else tostring end;
      ([.dailyModelTokens[].tokensByModel[]] | add // 0) as $all
      | (.modelUsage | to_entries | map(.value.outputTokens) | add // 0) as $out
      | (.dailyModelTokens | last // {date:"-",tokensByModel:{}}) as $d
      | "\($all | h) total · \($out | h) out · \([$d.tokensByModel[]] | add // 0 | h) on \($d.date[5:])"' "$f" ;;
  model)
    jq -r '.modelUsage | to_entries
      | map({m: .key, t: (.value.inputTokens + .value.outputTokens + .value.cacheReadInputTokens + .value.cacheCreationInputTokens)})
      | (map(.t) | add) as $s | sort_by(-.t)
      | map("\(.m | sub("^claude-"; "")) \(.t * 100 / $s | floor)%") | join(" · ")' "$f" ;;
esac
