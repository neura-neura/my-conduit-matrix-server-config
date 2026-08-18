#!/bin/sh
set -eu

# Stock Cinny enables voice only if auto-discovery includes rtc_foci.
# It tries HTTPS first and, on failure, falls back to a homeserver URL with no
# voice config. Rewrite that lookup so a private HTTP homeserver still works.

for f in /app/assets/index-*.js; do
  [ -f "$f" ] || continue
  grep -q "const t6=async" "$f" || continue
  if grep -q ":`http://\${e}`" "$f" && grep -q "org.matrix.msc4143.rtc_foci" "$f"; then
    echo "Cinny HTTP voice patch already present in $f"
    continue
  fi

  awk '
    {
      gsub(":`https://${e}`", ":`http://${e}`")
      old = "if(i||a.status===404)return[void 0,{\"m.homeserver\":{base_url:n}}];"
      new = "if(i||a.status===404)return[void 0,{\"m.homeserver\":{base_url:n.startsWith(\"https://\")?(\"http://\"+n.slice(8)):n},\"org.matrix.msc4143.rtc_foci\":[{\"type\":\"livekit\",\"livekit_service_url\":(n.startsWith(\"https://\")?(\"http://\"+n.slice(8)):n)+\"/livekit/jwt\"}]}];"
      p = index($0, old)
      if (p > 0) {
        $0 = substr($0, 1, p-1) new substr($0, p+length(old))
      }
      print
    }
  ' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
  echo "Patched Cinny HTTP voice discovery in $f"
done
