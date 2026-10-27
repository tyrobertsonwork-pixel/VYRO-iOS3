# VYRO iOS starter

A mobile-first VYRO cinema interface prototype with a GitHub Actions workflow that builds an **unsigned IPA** on a hosted macOS runner.

## Build from Windows

1. Commit these files to the root of your GitHub repository, preserving the `.github/workflows/ios-unsigned-ipa.yml` and `www/index.html` paths. GitHub Desktop is the easiest way: clone this repo, copy these files into the cloned folder, commit, then push.
2. Open **Actions → VYRO iOS unsigned IPA → Run workflow**. You can also push to `main` to trigger a build.
3. When it finishes successfully, open the run and download the `VYRO-unsigned-IPA` artifact.
4. Try signing the IPA with your signing app/service (such as ESign or Feather), then install it on your iPhone. Compatibility of a separately signed unsigned IPA is not guaranteed.

## Important limitations

- This build is deliberately unsigned and does not include your certificate or private keys. Never commit `.p12` files, private keys, passwords, provisioning profiles, or signing-service tokens.
- The app is a UI prototype with sample titles. Real streaming playback, catalog metadata, add-ons, accounts and live TV have not been integrated.
- Bundle identifier: `app.vyro.cinema` in `capacitor.config.ts`. Change before the first build if needed; changing it after signing can affect updates/install behavior.

## Stack

- Capacitor 7 / iOS WKWebView
- GitHub Actions macOS runner
