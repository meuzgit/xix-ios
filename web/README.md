# xix.golf

The static no-app landing page for join links (`xix.golf/r/{code}`) and the universal-link association file.

Deploy the folder to any static host that can rewrite `/r/*` to `index.html` (`_redirects` covers Netlify and Cloudflare Pages; on other hosts add the equivalent rule). `.well-known/apple-app-site-association` must be served as `application/json` at the root with no redirect, or iOS never opens the app from the link.

The page shows the invite and two buttons: "Open in XIX" (the `xix://r/{code}` scheme, which the app also handles) and "Get XIX". The round's course and players are shown by the app after sign-in; the join screen RPC needs an identity, so the page does not read them.
