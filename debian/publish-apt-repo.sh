#!/bin/sh
set -eu

# Build a static, signed apt repository from built .deb files.
# Usage: publish-apt-repo.sh <deb-dir> <suite> [<deb-dir> <suite> ...]

OUT="${OUT_DIR:-site}"
GPG_KEY_ID="${APT_GPG_KEY_ID:?APT_GPG_KEY_ID is not set}"
ORIGIN="${APT_ORIGIN:-phedders}"
LABEL="${APT_LABEL:-Incus bcachefs}"
ARCH="${APT_ARCH:-amd64}"
DESCRIPTION="${APT_DESCRIPTION:-Incus with the native bcachefs storage driver}"
PAGES_URL="${PAGES_URL:-https://phedders.github.io/incus-bcachefs-debian}"

if [ "$#" -eq 0 ] || [ $(( $# % 2 )) -ne 0 ]; then
    echo "usage: $0 <deb-dir> <suite> [...]" >&2
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

while [ "$#" -gt 0 ]; do
    src="$1"
    suite="$2"
    shift 2

    pool="$OUT/pool/$suite/main/i/incus"
    mkdir -p "$pool"

    count=0
    for deb in "$src"/*.deb; do
        [ -f "$deb" ] || continue
        case "$deb" in
            *-dbgsym_*) continue ;;
        esac
        cp "$deb" "$pool/"
        count=$((count + 1))
    done

    if [ "$count" -eq 0 ]; then
        echo "no packages found for $suite in $src" >&2
        exit 1
    fi

    pkgdir="$OUT/dists/$suite/main/binary-$ARCH"
    mkdir -p "$pkgdir"
    ( cd "$OUT" && dpkg-scanpackages --multiversion "pool/$suite" ) > "$pkgdir/Packages" 2>/dev/null
    gzip -9c "$pkgdir/Packages" > "$pkgdir/Packages.gz"

    ( cd "$OUT" && apt-ftparchive \
        -o "APT::FTPArchive::Release::Origin=$ORIGIN" \
        -o "APT::FTPArchive::Release::Label=$LABEL" \
        -o "APT::FTPArchive::Release::Suite=$suite" \
        -o "APT::FTPArchive::Release::Codename=$suite" \
        -o "APT::FTPArchive::Release::Architectures=$ARCH" \
        -o "APT::FTPArchive::Release::Components=main" \
        -o "APT::FTPArchive::Release::Description=$DESCRIPTION" \
        release "dists/$suite" ) > "$OUT/.Release-$suite"
    mv "$OUT/.Release-$suite" "$OUT/dists/$suite/Release"

    gpg --batch --yes --local-user "$GPG_KEY_ID" --clearsign \
        -o "$OUT/dists/$suite/InRelease" "$OUT/dists/$suite/Release"
    gpg --batch --yes --local-user "$GPG_KEY_ID" --armor --detach-sign \
        -o "$OUT/dists/$suite/Release.gpg" "$OUT/dists/$suite/Release"
done

gpg --batch --armor --export "$GPG_KEY_ID" > "$OUT/key.asc"
FPR=$(gpg --batch --with-colons --list-keys "$GPG_KEY_ID" | awk -F: '/^fpr:/ {print $10; exit}')

cat > "$OUT/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Incus bcachefs apt repository</title>
  <style>
    body { font-family: sans-serif; max-width: 55em; margin: 2em auto; padding: 0 1em; }
    pre { background: #f4f4f4; padding: 1em; overflow-x: auto; }
  </style>
</head>
<body>
  <h1>Incus bcachefs apt repository</h1>
  <p>
    Incus packages with the native bcachefs storage driver, built for Debian
    testing and unstable. Only the most recent build of each suite is kept.
  </p>
  <p>Signing key fingerprint: <code>$FPR</code></p>
  <h2>Install</h2>
  <pre>
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL $PAGES_URL/key.asc -o /etc/apt/keyrings/incus-bcachefs.asc
echo "deb [signed-by=/etc/apt/keyrings/incus-bcachefs.asc] $PAGES_URL/ testing main" | sudo tee /etc/apt/sources.list.d/incus-bcachefs.list
sudo apt update
sudo apt install incus incus-ui-canonical
  </pre>
  <p>Replace <code>testing</code> with <code>sid</code> on unstable.</p>
  <h2>Suites</h2>
  <ul>
    <li><a href="dists/testing/InRelease">testing</a></li>
    <li><a href="dists/sid/InRelease">sid</a></li>
  </ul>
</body>
</html>
EOF
