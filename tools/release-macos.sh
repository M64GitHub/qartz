#!/bin/zsh
# Build the macOS release: one universal (Apple Silicon + Intel) qartz for
# macOS 13+, libusb compiled in, ad-hoc signed, packed with README + LICENSE.
#
#   tools/release-macos.sh  ->  zig-out/release/qartz-macos-universal.tar.gz (+ .sha256)
#
# The asset name carries no version, so .../releases/latest/download/<name>
# keeps working; the folder inside it does.
set -euo pipefail
cd "${0:A:h}/.."

version=$(sed -n 's/^ *\.version = "\(.*\)",.*/\1/p' build.zig.zon)
out=zig-out/release
pkg=qartz-$version-macos-universal
mkdir -p $out/$pkg

# The macOS 26 SDK's library stubs are arm64e-only and Zig 0.15 can't link
# plain arm64 against them; a 15.x SDK (still shipped with the Command Line
# Tools) has both. Override with QARTZ_SDK=<path>.
sdk=${QARTZ_SDK:-$(xcrun --sdk macosx15.4 --show-sdk-path 2>/dev/null || ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX15*.sdk | tail -1)}
echo "SDK: $sdk"

for arch in aarch64 x86_64; do
    echo "building $arch..."
    zig build -Doptimize=ReleaseFast -Dtarget=$arch-macos.13.0 -Dmacos-sdk=$sdk --prefix $out/$arch
done

lipo -create -output $out/$pkg/qartz $out/aarch64/bin/qartz $out/x86_64/bin/qartz
codesign --force --sign - $out/$pkg/qartz
cp README.md LICENSE $out/$pkg/

asset=qartz-macos-universal.tar.gz
tar -C $out -czf $out/$asset $pkg
(cd $out && shasum -a 256 $asset > $asset.sha256)

echo
lipo -info $out/$pkg/qartz
cat $out/$asset.sha256
