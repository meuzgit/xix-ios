# xix.golf

The static no-app landing page for join links (`xix.golf/r/{code}`) and the universal-link association file.

Deploy the folder to any static host that can rewrite `/r/*` to `index.html` (`_redirects` covers Netlify and Cloudflare Pages; on other hosts add the equivalent rule). `.well-known/apple-app-site-association` must be served as `application/json` at the root with no redirect, or iOS never opens the app from the link.

The page shows the invite as Pass 6 §2 draws it: "Ray asked you to play", the course and date, the players' names, and two buttons, "Open in XIX" (the `xix://r/{code}` scheme, which the app also handles) and "Get XIX". It reads the round through `xix.round_preview(code)` (migration 0020), the one anonymous RPC, which returns course, region, date, holes, status, the owner's name and the players' display names and nothing else. `config.js` (from `scripts/gen-xcconfig.sh`, not committed) carries the project URL and anon key; without it the page still shows the code and the buttons.
