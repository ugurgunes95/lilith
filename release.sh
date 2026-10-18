#!/bin/sh
# Usage: ./release.sh 1.1.0
# Sets the version, builds and signs the universal app, publishes it as a GitHub release
# and points the Homebrew cask in the tap clone ($TAP_DIR, default ../homebrew-tap) at it.
set -e
cd "$(dirname "$0")"
V="$1"
TAP="${TAP_DIR:-../homebrew-tap}"
ID=dev.ugurgunes.lilith
REPO=ugurgunes95/lilith

[ -n "$V" ] || { echo "usage: ./release.sh <version>"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "commit or stash your changes first"; exit 1; }
[ -d "$TAP/.git" ] || { echo "no homebrew-tap clone at $TAP (set TAP_DIR)"; exit 1; }
# Same certificate every release: Gatekeeper approval and Accessibility permission are tied to it.
security find-identity -p codesigning | grep -q '"Lilith Code Signing"' || { echo "missing signing identity, run ./make-signing-cert.sh"; exit 1; }

sed -i '' -E "s#(<key>CFBundle(ShortVersionString|Version)</key><string>)[^<]*#\1$V#" Resources/Info.plist
./build.sh
ZIP="build/Lilith-$V.zip"
ditto -c -k --keepParent build/Lilith.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

git commit -qm "Release $V" Resources/Info.plist || true  # nothing to commit when re-releasing the same version
git tag "v$V"
git push origin main "v$V"
gh release create "v$V" "$ZIP" --repo "$REPO" --title "Lilith $V" --generate-notes

mkdir -p "$TAP/Casks"
cat > "$TAP/Casks/lilith.rb" <<CASK
cask "lilith" do
  version "$V"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/Lilith-#{version}.zip"
  name "Lilith"
  desc "Keyboard launcher for apps, files, math, conversions and clipboard history"
  homepage "https://github.com/$REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Lilith.app"

  uninstall quit: "$ID"

  zap trash: [
    "~/Library/Caches/$ID",
    "~/Library/HTTPStorages/$ID",
    "~/Library/Preferences/$ID.plist",
  ]
end
CASK
git -C "$TAP" add Casks/lilith.rb
git -C "$TAP" commit -qm "lilith $V"
git -C "$TAP" push
echo "Released $V: brew update && brew upgrade --cask lilith"
