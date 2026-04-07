#!/bin/bash
set -ex

RIME_ROOT="$(cd "$(dirname "$0")"; pwd)"
echo "RIME_ROOT: ${RIME_ROOT}"

cd ${RIME_ROOT}/librime
git submodule update --init

# Apply patch (only once)
if [[ ! -f ${RIME_ROOT}/librime.patch.apply ]]; then
    git apply --check ${RIME_ROOT}/librime.patch
    git apply ${RIME_ROOT}/librime.patch
    touch ${RIME_ROOT}/librime.patch.apply
fi

fix_glog_for_cmake4() {
    local cmake_policy_file="${RIME_ROOT}/librime/deps/glog/cmake/GetCacheVariables.cmake"

    if [[ -f "${cmake_policy_file}" ]]; then
        perl -0pi -e 's/cmake_policy \(VERSION 3\.3\)/cmake_policy (VERSION 3.5)/' "${cmake_policy_file}"
    fi
}

fix_deps_for_cmake4() {
    local deps_mk="${RIME_ROOT}/librime/deps.mk"
    local python3_bin

    python3_bin="$(xcrun --find python3 2>/dev/null || command -v python3)"

    if [[ -f "${deps_mk}" ]]; then
        perl -0pi -e 's/\n\t-DCMAKE_POLICY_VERSION_MINIMUM=3\.5 \\\n/\n/g' "${deps_mk}"
        perl -0pi -e 's/\n\t-DPYTHON_EXECUTABLE:FILEPATH=[^\n]+ \\\n/\n/g' "${deps_mk}"
        perl -0pi -e 's/\n\t-DHAVE_CRC32C=0 \\\n/\n/g' "${deps_mk}"
        perl -0pi -e 's/\n\t-DHAVE_SNAPPY=0 \\\n/\n/g' "${deps_mk}"
        perl -0pi -e 's/\n\t-DHAVE_TCMALLOC=0 \\\n/\n/g' "${deps_mk}"
        perl -0pi -e 's/-DCMAKE_BUILD_TYPE:STRING="Release" \\\n\t/-DCMAKE_BUILD_TYPE:STRING="Release" \\\n\t-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \\\n\t/g' "${deps_mk}"
        perl -0pi -e "s|-DCMAKE_INSTALL_PREFIX:PATH=\"\\$\\(rime_root\\)\" \\\\\\n\\t|-DCMAKE_INSTALL_PREFIX:PATH=\"\\$\\(rime_root\\)\" \\\\\\n\\t-DPYTHON_EXECUTABLE:FILEPATH=${python3_bin} \\\\\\n\\t|g" "${deps_mk}"
        perl -0pi -e 's/-DLEVELDB_BUILD_TESTS:BOOL=OFF \\\n\t/-DLEVELDB_BUILD_TESTS:BOOL=OFF \\\n\t-DHAVE_CRC32C=0 \\\n\t-DHAVE_SNAPPY=0 \\\n\t-DHAVE_TCMALLOC=0 \\\n\t/g' "${deps_mk}"
    fi
}

fix_xcode_deployment_target() {
    local xcode_mk="${RIME_ROOT}/librime/xcode.mk"

    if [[ -f "${xcode_mk}" ]]; then
        perl -0pi -e 's/\n\t-DDEPLOYMENT_TARGET=\$\(MINVERSION\) \\\n/\n/g' "${xcode_mk}"
        perl -0pi -e 's/-DPLATFORM=\$\(PLATFORM\) \\\n\t/-DPLATFORM=\$\(PLATFORM\) \\\n\t-DDEPLOYMENT_TARGET=\$\(MINVERSION\) \\\n\t/g' "${xcode_mk}"
        perl -0pi -e "s/RIME_CMAKE_FLAGS='\\$\\(IOS_CROSS_COMPILE_CMAKE_FLAGS\\)'/RIME_CMAKE_FLAGS='\\$\\(XCODE_IOS_CROSS_COMPILE_CMAKE_FLAGS\\)'/g" "${xcode_mk}"
    fi
}

fix_opencc_for_ios() {
    local opencc_tools_cmake="${RIME_ROOT}/librime/deps/opencc/src/tools/CMakeLists.txt"
    local opencc_data_cmake="${RIME_ROOT}/librime/deps/opencc/data/CMakeLists.txt"

    if [[ -f "${opencc_tools_cmake}" ]]; then
        perl -0pi -e 's/^if\(CMAKE_SYSTEM_NAME STREQUAL "iOS"\)\n  return\(\)\nendif\(\)\n\n//m' "${opencc_tools_cmake}"
        perl -0pi -e 's/^# Executables\n/# Executables\n\nif(CMAKE_SYSTEM_NAME STREQUAL "iOS")\n  return()\nendif()\n\n/m' "${opencc_tools_cmake}"
    fi

    if [[ -f "${opencc_data_cmake}" ]]; then
        if rg -q '^set\(OPENCC_DICT_BIN opencc_dict\)$' "${opencc_data_cmake}"; then
            perl -0pi -e 's/^set\(OPENCC_DICT_BIN opencc_dict\)$/if(TARGET opencc_dict)\n  set(OPENCC_DICT_BIN \$<TARGET_FILE:opencc_dict>)\nelseif(CMAKE_SYSTEM_NAME STREQUAL "iOS")\n  set(OPENCC_DICT_BIN "\${CMAKE_INSTALL_PREFIX}\/bin\/opencc_dict")\nelse()\n  set(OPENCC_DICT_BIN opencc_dict)\nendif()/m' "${opencc_data_cmake}"
        fi

        if rg -q '\$<TARGET_FILE_DIR:\$\{OPENCC_DICT_BIN\}>' "${opencc_data_cmake}"; then
            perl -0pi -e 's/\nadd_custom_target\(\n  copy_libopencc_to_dir_of_opencc_dict\n  COMMENT\n    "Copying libopencc to directory of opencc_dict"\n  COMMAND\n    \$\{CMAKE_COMMAND\} -E copy "\$<TARGET_FILE:libopencc>" "\$<TARGET_FILE_DIR:\$\{OPENCC_DICT_BIN\}>"\n\)\nif \(WIN32\)\n  set\(DICT_WIN32_DEPENDS copy_libopencc_to_dir_of_opencc_dict\)/\nif (WIN32 AND TARGET opencc_dict)\n  add_custom_target(\n    copy_libopencc_to_dir_of_opencc_dict\n    COMMENT\n      "Copying libopencc to directory of opencc_dict"\n    COMMAND\n      \${CMAKE_COMMAND} -E copy "\$<TARGET_FILE:libopencc>" "\$<TARGET_FILE_DIR:opencc_dict>"\n  )\n  set(DICT_WIN32_DEPENDS copy_libopencc_to_dir_of_opencc_dict)/s' "${opencc_data_cmake}"
        fi
    fi
}

clean_dep_builds() {
    make -f deps.mk clean-src
}

fix_boost_compat() {
    local customizer="${RIME_ROOT}/librime/src/rime/lever/customizer.cc"
    local deployment_tasks="${RIME_ROOT}/librime/src/rime/lever/deployment_tasks.cc"

    if [[ -f "${customizer}" ]]; then
        perl -0pi -e 's/fs::copy_option::overwrite_if_exists/fs::copy_options::overwrite_existing/g' "${customizer}"
    fi

    if [[ -f "${deployment_tasks}" ]]; then
        perl -0pi -e 's/fs::copy_option::overwrite_if_exists/fs::copy_options::overwrite_existing/g' "${deployment_tasks}"
    fi
}

prepare_boost_root() {
    local slice="$1"
    local boost_root="${RIME_ROOT}/.boost/${slice}"
    local libs=("boost_atomic" "boost_filesystem" "boost_regex" "boost_system")

    rm -rf "${boost_root}"
    mkdir -p "${boost_root}/include" "${boost_root}/lib"
    cp -R "${RIME_ROOT}/boost-iosx/boost/boost" "${boost_root}/include/"

    for lib in "${libs[@]}"; do
        local src="${RIME_ROOT}/boost-iosx/frameworks/${lib}.xcframework/${slice}/lib${lib}.a"
        if [[ ! -f "${src}" ]]; then
            echo "Missing Boost slice: ${src}" >&2
            exit 1
        fi
        cp -f "${src}" "${boost_root}/lib/"
    done

    export BOOST_ROOT="${boost_root}"
}

copy_or_thin_archive() {
    local input="$1"
    local arch="$2"
    local output="$3"
    local info

    info="$(lipo -info "${input}" 2>/dev/null || true)"

    if [[ "${info}" == Non-fat\ file:*" architecture: ${arch}" ]]; then
        cp -f "${input}" "${output}"
        return
    fi

    if [[ "${info}" == *"are:"* && "${info}" == *"${arch}"* ]]; then
        lipo "${input}" -thin "${arch}" -output "${output}"
        return
    fi

    echo "Archive ${input} does not contain architecture ${arch}: ${info}" >&2
    exit 1
}

fix_glog_for_cmake4
fix_deps_for_cmake4
fix_xcode_deployment_target
fix_opencc_for_ios
fix_boost_compat

# Install lua plugin
rm -rf ${RIME_ROOT}/librime/plugins/lua
${RIME_ROOT}/librime/install-plugins.sh imfuxiao/librime-lua@master
rm -rf ${RIME_ROOT}/librime/src/rime/lua && \
  mkdir ${RIME_ROOT}/librime/src/rime/lua && \
  cp -R ${RIME_ROOT}/librime/plugins/lua/src/* ${RIME_ROOT}/librime/src/rime/lua && \
  rm -rf ${RIME_ROOT}/librime/plugins/lua

# ── Build directories ──────────────────────────────────────────────────────────
rm -rf ${RIME_ROOT}/lib && mkdir -p ${RIME_ROOT}/lib ${RIME_ROOT}/lib/headers
cp ${RIME_ROOT}/librime/src/*.h ${RIME_ROOT}/lib/headers

# ── 1. Build deps for x86_64 simulator ─────────────────────────────────────────
export PLATFORM=SIMULATOR64
prepare_boost_root ios-arm64_x86_64-simulator
rm -rf ${RIME_ROOT}/librime/build ${RIME_ROOT}/librime/dist
clean_dep_builds
make xcode/ios/deps
cp -f ${RIME_ROOT}/librime/lib/*.a ${RIME_ROOT}/lib/deps_x86/  2>/dev/null || true
mkdir -p ${RIME_ROOT}/lib/deps_x86
cp -f ${RIME_ROOT}/librime/lib/*.a ${RIME_ROOT}/lib/deps_x86/
make xcode/ios/dist
cp -f ${RIME_ROOT}/librime/dist/lib/librime.a ${RIME_ROOT}/lib/librime_simulator_x86_64.a

# ── 2. Build deps for arm64 simulator ──────────────────────────────────────────
export PLATFORM=SIMULATORARM64
prepare_boost_root ios-arm64_x86_64-simulator
rm -rf ${RIME_ROOT}/librime/build ${RIME_ROOT}/librime/dist
clean_dep_builds
make xcode/ios/deps
mkdir -p ${RIME_ROOT}/lib/deps_arm64sim
cp -f ${RIME_ROOT}/librime/lib/*.a ${RIME_ROOT}/lib/deps_arm64sim/
make xcode/ios/dist
cp -f ${RIME_ROOT}/librime/dist/lib/librime.a ${RIME_ROOT}/lib/librime_simulator_arm64.a

# ── 3. Build for arm64 device ───────────────────────────────────────────────────
export PLATFORM=OS64
prepare_boost_root ios-arm64
rm -rf ${RIME_ROOT}/librime/build ${RIME_ROOT}/librime/dist
clean_dep_builds
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
    copy_or_thin_archive ${RIME_ROOT}/lib/deps_x86/${dep}.a x86_64 \
         ${RIME_ROOT}/lib/${dep}_sim_x86.a
    copy_or_thin_archive ${RIME_ROOT}/lib/deps_arm64sim/${dep}.a arm64 \
         ${RIME_ROOT}/lib/${dep}_sim_arm64.a
    copy_or_thin_archive ${RIME_ROOT}/lib/deps_arm64/${dep}.a arm64 \
         ${RIME_ROOT}/lib/${dep}_device_arm64.a

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
