#!/bin/bash
set -ex

RIME_ROOT="$(cd "$(dirname "$0")"; pwd)"
echo "RIME_ROOT: ${RIME_ROOT}"

cd ${RIME_ROOT}/librime
git submodule update --init

# Apply patch (only once)
if [[ ! -f ${RIME_ROOT}/librime.patch.apply ]]; then
    touch ${RIME_ROOT}/librime.patch.apply
    git apply ${RIME_ROOT}/librime.patch >/dev/null 2>&1 || true
fi

# Install lua plugin
rm -rf ${RIME_ROOT}/librime/plugins/lua
${RIME_ROOT}/librime/install-plugins.sh imfuxiao/librime-lua@main
rm -rf ${RIME_ROOT}/librime/src/rime/lua && \
  mkdir ${RIME_ROOT}/librime/src/rime/lua && \
  cp -R ${RIME_ROOT}/librime/plugins/lua/src/* ${RIME_ROOT}/librime/src/rime/lua && \
  rm -rf ${RIME_ROOT}/librime/plugins/lua

# Set up boost
if [[ ! -d ${RIME_ROOT}/.boost ]]; then
    mkdir ${RIME_ROOT}/.boost
    cp -R ${RIME_ROOT}/boost-iosx/dest ${RIME_ROOT}/.boost
fi
export BOOST_ROOT=$RIME_ROOT/.boost/dest

# ── Build directories ──────────────────────────────────────────────────────────
rm -rf ${RIME_ROOT}/lib && mkdir -p ${RIME_ROOT}/lib ${RIME_ROOT}/lib/headers
cp ${RIME_ROOT}/librime/src/*.h ${RIME_ROOT}/lib/headers

# ── 1. Build deps for x86_64 simulator ─────────────────────────────────────────
export PLATFORM=SIMULATOR64
rm -rf ${RIME_ROOT}/librime/build ${RIME_ROOT}/librime/dist
make xcode/ios/deps
cp -f ${RIME_ROOT}/librime/lib/*.a ${RIME_ROOT}/lib/deps_x86/  2>/dev/null || true
mkdir -p ${RIME_ROOT}/lib/deps_x86
cp -f ${RIME_ROOT}/librime/lib/*.a ${RIME_ROOT}/lib/deps_x86/
make xcode/ios/dist
cp -f ${RIME_ROOT}/librime/dist/lib/librime.a ${RIME_ROOT}/lib/librime_simulator_x86_64.a

# ── 2. Build deps for arm64 simulator ──────────────────────────────────────────
export PLATFORM=SIMULATORARM64
rm -rf ${RIME_ROOT}/librime/build ${RIME_ROOT}/librime/dist
make xcode/ios/deps
mkdir -p ${RIME_ROOT}/lib/deps_arm64sim
cp -f ${RIME_ROOT}/librime/lib/*.a ${RIME_ROOT}/lib/deps_arm64sim/
make xcode/ios/dist
cp -f ${RIME_ROOT}/librime/dist/lib/librime.a ${RIME_ROOT}/lib/librime_simulator_arm64.a

# ── 3. Build for arm64 device ───────────────────────────────────────────────────
export PLATFORM=OS64
rm -rf ${RIME_ROOT}/librime/build ${RIME_ROOT}/librime/dist
make xcode/ios/deps
mkdir -p ${RIME_ROOT}/lib/deps_arm64
cp -f ${RIME_ROOT}/librime/lib/*.a ${RIME_ROOT}/lib/deps_arm64/
make xcode/ios/dist
cp -f ${RIME_ROOT}/librime/dist/lib/librime.a ${RIME_ROOT}/lib/librime_arm64.a

# ── 4. Create librime.xcframework (device + fat simulator) ─────────────────────
lipo -create \
  ${RIME_ROOT}/lib/librime_simulator_x86_64.a \
  ${RIME_ROOT}/lib/librime_simulator_arm64.a \
  -output ${RIME_ROOT}/lib/librime_simulator_fat.a

rm -rf ${RIME_ROOT}/Frameworks/librime.xcframework
xcodebuild -create-xcframework \
  -library ${RIME_ROOT}/lib/librime_simulator_fat.a -headers ${RIME_ROOT}/lib/headers \
  -library ${RIME_ROOT}/lib/librime_arm64.a          -headers ${RIME_ROOT}/lib/headers \
  -output ${RIME_ROOT}/Frameworks/librime.xcframework

# ── 5. Create xcframeworks for each dependency ─────────────────────────────────
deps=("libglog" "libleveldb" "libmarisa" "libopencc" "libyaml-cpp")

for dep in "${deps[@]}"; do
    echo "▶ Processing ${dep}..."

    # Extract slices
    lipo ${RIME_ROOT}/lib/deps_x86/${dep}.a     -thin x86_64 \
         -output ${RIME_ROOT}/lib/${dep}_sim_x86.a
    lipo ${RIME_ROOT}/lib/deps_arm64sim/${dep}.a -thin arm64 \
         -output ${RIME_ROOT}/lib/${dep}_sim_arm64.a
    lipo ${RIME_ROOT}/lib/deps_arm64/${dep}.a    -thin arm64 \
         -output ${RIME_ROOT}/lib/${dep}_device_arm64.a

    # Fat simulator
    lipo -create \
      ${RIME_ROOT}/lib/${dep}_sim_x86.a \
      ${RIME_ROOT}/lib/${dep}_sim_arm64.a \
      -output ${RIME_ROOT}/lib/${dep}_sim_fat.a

    rm -rf ${RIME_ROOT}/Frameworks/${dep}.xcframework
    xcodebuild -create-xcframework \
      -library ${RIME_ROOT}/lib/${dep}_sim_fat.a \
      -library ${RIME_ROOT}/lib/${dep}_device_arm64.a \
      -output ${RIME_ROOT}/Frameworks/${dep}.xcframework
done

echo ""
echo "✅ All xcframeworks built with arm64 simulator support!"
ls -la ${RIME_ROOT}/Frameworks/
