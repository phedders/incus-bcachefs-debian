#!/bin/sh
set -eu

# Build the Incus web interface from the pinned zabbly fork.
TAG="${INCUS_UI_TAG:-incus-0.22.1}"
URL="${INCUS_UI_URL:-https://github.com/zabbly/incus-ui-canonical.git}"
ROOT="$(pwd)"
SRC="${INCUS_UI_SRC:-${ROOT}/ui-src}"

if [ ! -d "${SRC}/.git" ]; then
    rm -rf "${SRC}"
    git clone --depth 1 --branch "${TAG}" "${URL}" "${SRC}"
else
    git -C "${SRC}" fetch --depth 1 origin "refs/tags/${TAG}"
    git -C "${SRC}" checkout -q -f FETCH_HEAD
fi

# The UI build scripts call yarn themselves, so make sure yarn 1 is on PATH.
if ! command -v yarn >/dev/null 2>&1 || [ "$(yarn --version | cut -d. -f1)" != "1" ]; then
    YARN_DIR="${SRC}/.yarn1"
    npm install --prefix "${YARN_DIR}" --no-save --no-package-lock yarn@1.22.22
    PATH="${YARN_DIR}/node_modules/.bin:${PATH}"
    export PATH
fi

(
    cd "${SRC}"

    # Complete re-branding, as done by the zabbly build.
    find . -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.scss' \) -print0 |
        xargs -0 sed -i -f "${ROOT}/debian/ui-canonical-renames.sed"

    export CI=1
    yarn install --frozen-lockfile --non-interactive --network-timeout 600000
    yarn build
)

rm -rf "${ROOT}/ui"
cp -a "${SRC}/build/ui" "${ROOT}/ui"

test -f "${ROOT}/ui/index.html"
