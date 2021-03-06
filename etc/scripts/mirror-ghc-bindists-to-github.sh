#!/usr/bin/env bash
#
# This script will download official GHC bindists from download.haskell.org and upload
# them to the Github Release that Stack uses.
#
# Prerequisites:
#  - Create a Github release with tag `ghc-X.Y.Z-release`
#  - Set GITHUB_AUTH_TOKEN to a token that has permission to upload assets to a Release
#
# To use:
#  - Update GHCVER at the top of the script for the version you are mirring.
#  - Update the `mirror` commands at the bottom with any required filename adjustments
#    and other changes.
#  - Run the script.
#
# The script will output a `stack-setup.yaml` file containing info for each
# platform that you can paste into
# https://github.com/fpco/stackage-content/blob/master/stack/stack-setup-2.yaml.
# Be sure to double check the SHA1 sums against those in
# https://downloads.haskell.org/~ghc/X.Y.Z/.
#
GHCVER=8.4.3
if [[ -z "$GITHUB_AUTH_TOKEN" ]]; then
  echo "$0: GITHUB_AUTH_TOKEN environment variable is required" >&2
  exit 1
fi
set -xe
UPLOAD_URL="$(curl --fail -sSLH "Authorization: token $GITHUB_AUTH_TOKEN" https://api.github.com/repos/commercialhaskell/ghc/releases/tags/ghc-$GHCVER-release |grep upload_url |head -1 |sed 's/.*"\(https.*assets\){.*/\1/')"
if [[ -z "$UPLOAD_URL" ]]; then
  set +x
  echo
  echo "$0: Could not get upload URL from Github" >&2
  exit 1
fi
echo 'ghc:' >stack-setup.yaml

mirror () {
  suffix="$1"; shift
  srcext="$1"; shift
  destext="$1"; shift
  local srcfn=ghc-$GHCVER-${suffix}.tar.${srcext}
  if [[ ! -s "$srcfn.downloaded" ]]; then
    rm -f "$srcfn"
    curl -LO --fail "http://downloads.haskell.org/~ghc/$GHCVER/$srcfn"
    date >"$srcfn.downloaded"
  fi
  local destfn=ghc-$GHCVER-${suffix}.tar.${destext}
  if [[ ! -s "$destfn.uploaded" ]]; then
    if [[ "${srcext}" == "xz" && "${destext}" == "bz2" ]]; then
      xzcat "$srcfn" | bzip2 -c > "$destfn"
    elif [[ "${srcext}" != "${destext}" ]]; then
      set +x
      echo
      echo "$0: Unsupported conversion: ${srcext} to ${destext}" >&2
      exit 1
    fi
    curl -X POST --data-binary "@$destfn" -H "Content-type: application/octet-stream" -H "Authorization: token $GITHUB_AUTH_TOKEN" "$UPLOAD_URL?name=$destfn"
    date >"$destfn.uploaded"
  fi
  while [[ $# -gt 0 ]]; do
    alias="$1"
    echo "    $alias:" >>stack-setup.yaml
    echo "        $GHCVER:" >>stack-setup.yaml
    echo "            url: \"https://github.com/commercialhaskell/ghc/releases/download/ghc-$GHCVER-release/$destfn\"" >>stack-setup.yaml
    echo "            content-length: $(stat --printf="%s" "$destfn" 2>/dev/null || stat -f%z "$destfn")" >>stack-setup.yaml
    echo "            sha1: $(shasum -a 1 $destfn |cut -d' ' -f1)" >>stack-setup.yaml
    echo "            sha256: $(shasum -a 256 $destfn |cut -d' ' -f1)" >>stack-setup.yaml
    echo "" >>stack-setup.yaml
    shift
  done
}


# NOTE: keep the 'mirror' commands in the same order as entries in
# https://github.com/fpco/stackage-content/blob/master/stack/stack-setup-2.yaml

mirror i386-deb8-linux xz xz linux32 linux32-nopie
mirror x86_64-deb8-linux xz xz linux64 linux64-nopie
#mirror x86_64-centos67-linux xz xz linux64-gmp4 linux64-gmp4-nopie
mirror x86_64-fedora27-linux xz xz linux64-tinfo6 linux64-tinfo6-nopie linux64-ncurses6 linux64-ncurses6-nopie
mirror x86_64-apple-darwin xz bz2 macosx
mirror i386-unknown-mingw32 xz xz windows32
mirror x86_64-unknown-mingw32 xz xz windows64
#mirror x86_64-portbld-freebsd xz xz freebsd64-11
#mirror aarch64-deb8-linux xz xz linux-aarch64

set +x
echo
echo "DONE!  See 'stack-setup.yaml' for 'stack setup' to add to"
echo "  https://github.com/fpco/stackage-content/blob/master/stack/stack-setup-2.yaml"
