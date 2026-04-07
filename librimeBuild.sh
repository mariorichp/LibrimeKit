#!/bin/bash
set -ex

RIME_ROOT="$(cd "$(dirname "$0")"; pwd)"

echo ${RIME_ROOT}

cd ${RIME_ROOT}/librime
git submodule update --init


if [[ ! -f ${RIME_ROOT}/librime.patch.apply ]]
then
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
    PYTHON3_BIN="${python3_bin}" perl -0pi -e 's|-DCMAKE_INSTALL_PREFIX:PATH="\$\(rime_root\)" \\\n\t|-DCMAKE_INSTALL_PREFIX:PATH="\$\(rime_root\)" \\\n\t-DPYTHON_EXECUTABLE:FILEPATH=$ENV{PYTHON3_BIN} \\\n\t|g' "${deps_mk}"
    perl -0pi -e 's/-DLEVELDB_BUILD_TESTS:BOOL=OFF \\\n\t/-DLEVELDB_BUILD_TESTS:BOOL=OFF \\\n\t-DHAVE_CRC32C=0 \\\n\t-DHAVE_SNAPPY=0 \\\n\t-DHAVE_TCMALLOC=0 \\\n\t/g' "${deps_mk}"

    if ! rg -q 'DPYTHON_EXECUTABLE:FILEPATH=' "${deps_mk}"; then
      echo "Failed to inject PYTHON_EXECUTABLE into ${deps_mk}" >&2
      exit 1
    fi
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
  local opencc_src_cmake="${RIME_ROOT}/librime/deps/opencc/src/CMakeLists.txt"
  local opencc_tools_cmake="${RIME_ROOT}/librime/deps/opencc/src/tools/CMakeLists.txt"
  local opencc_data_cmake="${RIME_ROOT}/librime/deps/opencc/data/CMakeLists.txt"

  if [[ -f "${opencc_src_cmake}" ]]; then
    perl -0pi -e 's/\nif\(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS"\)\n  add_subdirectory\(tools\)\nendif\(\)\n/\nadd_subdirectory(tools)\n/m' "${opencc_src_cmake}"
    perl -0pi -e 's/\nadd_subdirectory\(tools\)\n/\nif(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")\n  add_subdirectory(tools)\nendif()\n/m' "${opencc_src_cmake}"
  fi

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

# install lua plugin
# TODO: 这里是临时解决方案. 非librime官方方法.
# 可能是个人能力问题, 使用官方的方法始终无法加载lua模块. 临时使用此方法. 希望以后可以解决这个问题.
# 注意: 改写代码后发现 gear 模块也无法加载. 所以代码中同时将gear模块添加进去.
rm -rf ${RIME_ROOT}/librime/plugins/lua
${RIME_ROOT}/librime/install-plugins.sh imfuxiao/librime-lua@master
rm -rf ${RIME_ROOT}/librime/src/rime/lua && \
  mkdir ${RIME_ROOT}/librime/src/rime/lua && \
  cp -R ${RIME_ROOT}/librime/plugins/lua/src/* ${RIME_ROOT}/librime/src/rime/lua && \
  rm -rf ${RIME_ROOT}/librime/plugins/lua

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

clean_dep_builds() {
  make -f deps.mk clean-src
}

fix_glog_for_cmake4
fix_deps_for_cmake4
fix_xcode_deployment_target
fix_opencc_for_ios
fix_boost_compat
  
# TODO: begin 改写文件内容
cat << "MODULE" | tee ${RIME_ROOT}/librime/src/rime/core_module.cc

//
// Copyright RIME Developers
// Distributed under the BSD License
//
// 2013-10-17 GONG Chen <chen.sst@gmail.com>
//

#include <rime_api.h>
#include <rime/common.h>
#include <rime/registry.h>

// built-in components
#include <rime/config.h>
#include <rime/config/plugins.h>
#include <rime/schema.h>

#include <cstdio>
#include "lua/lib/lua_templates.h"
#include "lua/lua_gears.h"

#include <rime/gear/abc_segmentor.h>
#include <rime/gear/affix_segmentor.h>
#include <rime/gear/ascii_composer.h>
#include <rime/gear/ascii_segmentor.h>
#include <rime/gear/charset_filter.h>
#include <rime/gear/chord_composer.h>
#include <rime/gear/echo_translator.h>
#include <rime/gear/editor.h>
#include <rime/gear/fallback_segmentor.h>
#include <rime/gear/history_translator.h>
#include <rime/gear/key_binder.h>
#include <rime/gear/matcher.h>
#include <rime/gear/navigator.h>
#include <rime/gear/punctuator.h>
#include <rime/gear/recognizer.h>
#include <rime/gear/reverse_lookup_filter.h>
#include <rime/gear/reverse_lookup_translator.h>
#include <rime/gear/schema_list_translator.h>
#include <rime/gear/script_translator.h>
#include <rime/gear/selector.h>
#include <rime/gear/shape.h>
#include <rime/gear/simplifier.h>
#include <rime/gear/single_char_filter.h>
#include <rime/gear/speller.h>
#include <rime/gear/switch_translator.h>
#include <rime/gear/table_translator.h>
#include <rime/gear/uniquifier.h>

void types_init(lua_State *L);

static bool file_exists(const char *fname) noexcept {
  FILE * const fp = fopen(fname, "r");
  if (fp) {
    fclose(fp);
    return true;
  }
  return false;
}


static void lua_init(lua_State *L) {
  const auto user_dir = std::string(RimeGetUserDataDir());
  const auto shared_dir = std::string(RimeGetSharedDataDir());

  types_init(L);
  lua_getglobal(L, "package");
  lua_pushfstring(L, "%s%slua%s?.lua;"
                     "%s%slua%s?%sinit.lua;"
                     "%s%slua%s?.lua;"
                     "%s%slua%s?%sinit.lua;",
                  user_dir.c_str(), LUA_DIRSEP, LUA_DIRSEP,
                  user_dir.c_str(), LUA_DIRSEP, LUA_DIRSEP, LUA_DIRSEP,
                  shared_dir.c_str(), LUA_DIRSEP, LUA_DIRSEP,
                  shared_dir.c_str(), LUA_DIRSEP, LUA_DIRSEP, LUA_DIRSEP);
  lua_getfield(L, -2, "path");
  lua_concat(L, 2);
  lua_setfield(L, -2, "path");
  lua_pop(L, 1);

  const auto user_file = user_dir + LUA_DIRSEP "rime.lua";
  const auto shared_file = shared_dir + LUA_DIRSEP "rime.lua";

  // use the user_file first
  // use the shared_file if the user_file doesn't exist
  if (file_exists(user_file.c_str())) {
    if (luaL_dofile(L, user_file.c_str())) {
      const char *e = lua_tostring(L, -1);
      LOG(ERROR) << "rime.lua error: " << e;
      lua_pop(L, 1);
    }
  } else if (file_exists(shared_file.c_str())) {
    if (luaL_dofile(L, shared_file.c_str())) {
      const char *e = lua_tostring(L, -1);
      LOG(ERROR) << "rime.lua error: " << e;
      lua_pop(L, 1);
    }
  } else {
    LOG(INFO) << "rime.lua info: rime.lua should be either in the "
                 "rime user data directory or in the rime shared "
                 "data directory";
  }
}

using namespace rime;
static void rime_core_initialize() {
  LOG(INFO) << "registering core components.";
  Registry& r = Registry::instance();

  auto config_builder = new ConfigComponent<ConfigBuilder>(
      [&](ConfigBuilder* builder) {
        builder->InstallPlugin(new AutoPatchConfigPlugin);
        builder->InstallPlugin(new DefaultConfigPlugin);
        builder->InstallPlugin(new LegacyPresetConfigPlugin);
        builder->InstallPlugin(new LegacyDictionaryConfigPlugin);
        builder->InstallPlugin(new BuildInfoPlugin);
        builder->InstallPlugin(new SaveOutputPlugin);
      });
  r.Register("config_builder", config_builder);

  auto config_loader =
      new ConfigComponent<ConfigLoader, DeployedConfigResourceProvider>;
  r.Register("config", config_loader);
  r.Register("schema", new SchemaComponent(config_loader));

  auto user_config =
      new ConfigComponent<ConfigLoader, UserConfigResourceProvider>(
          [](ConfigLoader* loader) {
            loader->set_auto_save(true);
          });
  r.Register("user_config", user_config);

  LOG(INFO) << "registering components from module 'gears'.";

  // processors
  r.Register("ascii_composer", new Component<AsciiComposer>);
  r.Register("chord_composer", new Component<ChordComposer>);
  r.Register("express_editor", new Component<ExpressEditor>);
  r.Register("fluid_editor", new Component<FluidEditor>);
  r.Register("fluency_editor", new Component<FluidEditor>);  // alias
  r.Register("key_binder", new Component<KeyBinder>);
  r.Register("navigator", new Component<Navigator>);
  r.Register("punctuator", new Component<Punctuator>);
  r.Register("recognizer", new Component<Recognizer>);
  r.Register("selector", new Component<Selector>);
  r.Register("speller", new Component<Speller>);
  r.Register("shape_processor", new Component<ShapeProcessor>);

  // segmentors
  r.Register("abc_segmentor", new Component<AbcSegmentor>);
  r.Register("affix_segmentor", new Component<AffixSegmentor>);
  r.Register("ascii_segmentor", new Component<AsciiSegmentor>);
  r.Register("matcher", new Component<Matcher>);
  r.Register("punct_segmentor", new Component<PunctSegmentor>);
  r.Register("fallback_segmentor", new Component<FallbackSegmentor>);

  // translators
  r.Register("echo_translator", new Component<EchoTranslator>);
  r.Register("punct_translator", new Component<PunctTranslator>);
  r.Register("table_translator", new Component<TableTranslator>);
  r.Register("script_translator", new Component<ScriptTranslator>);
  r.Register("r10n_translator", new Component<ScriptTranslator>);  // alias
  r.Register("reverse_lookup_translator",
             new Component<ReverseLookupTranslator>);
  r.Register("schema_list_translator", new Component<SchemaListTranslator>);
  r.Register("switch_translator", new Component<SwitchTranslator>);
  r.Register("history_translator", new Component<HistoryTranslator>);

  // filters
  r.Register("simplifier", new Component<Simplifier>);
  r.Register("uniquifier", new Component<Uniquifier>);
  if (!r.Find("charset_filter")) {  // allow improved implementation
    r.Register("charset_filter", new Component<CharsetFilter>);
  }
  r.Register("cjk_minifier", new Component<CharsetFilter>);  // alias
  r.Register("reverse_lookup_filter", new Component<ReverseLookupFilter>);
  r.Register("single_char_filter", new Component<SingleCharFilter>);

  // formatters
  r.Register("shape_formatter", new Component<ShapeFormatter>);

  LOG(INFO) << "registering components from module 'lua'.";

  an<Lua> lua(new Lua);
  lua->to_state(lua_init);

  r.Register("lua_translator", new LuaComponent<LuaTranslator>(lua));
  r.Register("lua_filter", new LuaComponent<LuaFilter>(lua));
  r.Register("lua_segmentor", new LuaComponent<LuaSegmentor>(lua));
  r.Register("lua_processor", new LuaComponent<LuaProcessor>(lua));
}

static void rime_core_finalize() {
  // registered components have been automatically destroyed prior to this call
}

RIME_REGISTER_MODULE(core)


MODULE


cat << "MODULE" | tee ${RIME_ROOT}/librime/src/CMakeLists.txt
set(LIBRARY_OUTPUT_PATH ${PROJECT_BINARY_DIR}/lib)

aux_source_directory(. rime_api_src)
aux_source_directory(rime rime_base_src)
aux_source_directory(rime/algo rime_algo_src)
aux_source_directory(rime/config rime_config_src)
aux_source_directory(rime/dict rime_dict_src)
aux_source_directory(rime/gear rime_gears_src)
aux_source_directory(rime/lever rime_levers_src)
aux_source_directory(rime/lua rime_lua_src)
aux_source_directory(rime/lua/lib rime_lua_lib_src)
aux_source_directory(rime/lua/lib/lua rime_lua_lib_lua_src)
if(rime_plugins_library)
  aux_source_directory(../plugins rime_plugins_src)
endif()

set(rime_core_module_src
  ${rime_api_src}
  ${rime_base_src}
  ${rime_config_src}
  ${rime_lua_src}
  ${rime_lua_lib_src}
  ${rime_lua_lib_lua_src}
)
set(rime_dict_module_src
  ${rime_algo_src}
  ${rime_dict_src})

if(BUILD_SHARED_LIBS AND BUILD_SEPARATE_LIBS)
  set(rime_src ${rime_core_module_src})
else()
  set(rime_src
      ${rime_core_module_src}
      ${rime_dict_module_src}
      ${rime_gears_src}
      ${rime_levers_src}
      ${rime_plugins_src}
      ${rime_plugins_objs})
endif()

set(rime_optional_deps "")
if(Gflags_FOUND)
  set(rime_optional_deps ${rime_optional_deps} ${Gflags_LIBRARY})
endif()
if(ENABLE_EXTERNAL_PLUGINS)
  set(rime_optional_deps ${rime_optional_deps} dl)
endif()

set(rime_core_deps
    ${Boost_LIBRARIES}
    ${Glog_LIBRARY}
    ${YamlCpp_LIBRARY}
    ${CMAKE_THREAD_LIBS_INIT}
    ${rime_optional_deps})
set(rime_dict_deps
    ${LevelDb_LIBRARY}
    ${Marisa_LIBRARY})
set(rime_gears_deps
    ${ICONV_LIBRARIES}
    ${ICU_LIBRARIES}
    ${Opencc_LIBRARY})
set(rime_levers_deps "")

if(MINGW)
  set(rime_core_deps ${rime_core_deps} wsock32 ws2_32)
endif()

if(BUILD_SEPARATE_LIBS)
  set(rime_deps ${rime_core_deps})
else()
  set(rime_deps
    ${rime_core_deps}
    ${rime_dict_deps}
    ${rime_gears_deps}
    ${rime_levers_deps}
    ${rime_plugins_deps})
endif()


if(BUILD_SHARED_LIBS)
  add_library(rime ${rime_src})
  target_link_libraries(rime ${rime_deps})
  set_target_properties(rime PROPERTIES
    DEFINE_SYMBOL "RIME_EXPORTS"
    VERSION ${rime_version}
    SOVERSION ${rime_soversion})

  if(XCODE_VERSION)
    set_target_properties(rime PROPERTIES INSTALL_NAME_DIR "@rpath")
  endif()

  if(${CMAKE_SYSTEM_NAME} MATCHES "iOS")
    set(RIME_BUNDLE_IDENTIFIER "")
    set(RIME_BUNDLE_IDENTIFIER ${RIME_BUNDLE_IDENTIFIER})

    if (DEFINED RIME_BUNDLE_IDENTIFIER)
      message (STATUS "Using RIME_BUNDLE_IDENTIFIER: ${RIME_BUNDLE_IDENTIFIER}")
      set_xcode_property (rime PRODUCT_BUNDLE_IDENTIFIER ${RIME_BUNDLE_IDENTIFIER} All)
    else()
      message (STATUS "No RIME_BUNDLE_IDENTIFIER - with -DRIME_BUNDLE_IDENTIFIER=<rime bundle identifier>")
    endif()

    if (NOT DEFINED DEVELOPMENT_TEAM)
      message (STATUS "No DEVELOPMENT_TEAM specified - if code signing for running on an iOS devicde is required, pass a valid development team id with -DDEVELOPMENT_TEAM=<YOUR_APPLE_DEVELOPER_TEAM_ID>")
      set(CODESIGN_EMBEDDED_FRAMEWORKS 0)
    else()
      message (STATUS "Using DEVELOPMENT_TEAM: ${DEVELOPMENT_TEAM}")
      set(CODESIGN_EMBEDDED_FRAMEWORKS 1)
      set_xcode_property (rime DEVELOPMENT_TEAM ${DEVELOPMENT_TEAM} All)
    endif()
  endif()


  install(TARGETS rime DESTINATION ${CMAKE_INSTALL_FULL_LIBDIR})

  if(BUILD_SEPARATE_LIBS)
    add_library(rime-dict ${rime_dict_module_src})
    target_link_libraries(rime-dict
      ${rime_dict_deps}
      ${rime_library})
    set_target_properties(rime-dict PROPERTIES
      VERSION ${rime_version}
      SOVERSION ${rime_soversion})
    if(XCODE_VERSION)
      set_target_properties(rime-dict PROPERTIES INSTALL_NAME_DIR "@rpath")
    endif()
    install(TARGETS rime-dict DESTINATION ${CMAKE_INSTALL_FULL_LIBDIR})

    add_library(rime-gears ${rime_gears_src})
    target_link_libraries(rime-gears
      ${rime_gears_deps}
      ${rime_library}
      ${rime_dict_library})
    set_target_properties(rime-gears PROPERTIES
      VERSION ${rime_version}
      SOVERSION ${rime_soversion})
    if(XCODE_VERSION)
      set_target_properties(rime-gears PROPERTIES INSTALL_NAME_DIR "@rpath")
    endif()
    install(TARGETS rime-gears DESTINATION ${CMAKE_INSTALL_FULL_LIBDIR})

    add_library(rime-levers ${rime_levers_src})
    target_link_libraries(rime-levers
      ${rime_levers_deps}
      ${rime_library}
      ${rime_dict_library})
    set_target_properties(rime-levers PROPERTIES
      VERSION ${rime_version}
      SOVERSION ${rime_soversion})
    if(XCODE_VERSION)
      set_target_properties(rime-levers PROPERTIES INSTALL_NAME_DIR "@rpath")
    endif()
    install(TARGETS rime-levers DESTINATION ${CMAKE_INSTALL_FULL_LIBDIR})

    if(rime_plugins_library)
      add_library(rime-plugins
        ${rime_plugins_src}
        ${rime_plugins_objs})
      target_link_libraries(rime-plugins
        ${rime_plugins_deps}
        ${rime_library}
        ${rime_dict_library}
        ${rime_gears_library})
      set_target_properties(rime-plugins PROPERTIES
        VERSION ${rime_version}
        SOVERSION ${rime_soversion})
      if(XCODE_VERSION)
        set_target_properties(rime-plugins PROPERTIES INSTALL_NAME_DIR "@rpath")
      endif()
      install(TARGETS rime-plugins DESTINATION ${CMAKE_INSTALL_FULL_LIBDIR})
    endif()
  endif()
else()
  add_library(rime-static STATIC ${rime_src})
  target_link_libraries(rime-static ${rime_deps})
  set_target_properties(rime-static PROPERTIES OUTPUT_NAME "rime" PREFIX "lib")
  install(TARGETS rime-static DESTINATION ${CMAKE_INSTALL_FULL_LIBDIR})
endif()

MODULE

# TODO: end 改写文件内容



# librime dependences build
export PLATFORM=OS64COMBINED
prepare_boost_root ios-arm64_x86_64-simulator
clean_dep_builds
make xcode/ios/deps

# PLATFORM value means
# OS64: to build for iOS (arm64 only)
# OS64COMBINED: to build for iOS & iOS Simulator (FAT lib) (arm64, x86_64)
# SIMULATOR64: to build for iOS simulator 64 bit (x86_64)
# SIMULATORARM64: to build for iOS simulator 64 bit (arm64)
# MAC: to build for macOS (x86_64)
export PLATFORM=SIMULATOR64

# temp save *.a
rm -rf ${RIME_ROOT}/lib && mkdir -p ${RIME_ROOT}/lib ${RIME_ROOT}/lib/headers
cp ${RIME_ROOT}/librime/src/*.h ${RIME_ROOT}/lib/headers

# librime build: iOS simulator 64 bit (x86_64)
rm -rf ${RIME_ROOT}/librime/build ${RIME_ROOT}/librime/dist
make xcode/ios/dist
cp -f ${RIME_ROOT}/librime/dist/lib/librime.a ${RIME_ROOT}/lib/librime_simulator_x86_64.a
# cp -f ${RIME_ROOT}/librime/build/plugins/lua/rime.build/Release/rime-lua-objs.build/librime-lua-objs.a ${RIME_ROOT}/lib/librime_lua_x86_64.a

# librime build: arm64
export PLATFORM=OS64
prepare_boost_root ios-arm64
rm -rf ${RIME_ROOT}/librime/build ${RIME_ROOT}/librime/dist
make xcode/ios/dist
cp -f ${RIME_ROOT}/librime/dist/lib/librime.a ${RIME_ROOT}/lib/librime_arm64.a
# cp -f ${RIME_ROOT}/librime/build/plugins/lua/rime.build/Release/rime-lua-objs.build/librime-lua-objs.a ${RIME_ROOT}/lib/librime_lua_arm64.a

# transform *.a to xcframework
rm -rf ${RIME_ROOT}/Frameworks/librime.xcframework
xcodebuild -create-xcframework \
 -library ${RIME_ROOT}/lib/librime_simulator_x86_64.a -headers ${RIME_ROOT}/lib/headers \
 -library ${RIME_ROOT}/lib/librime_arm64.a -headers ${RIME_ROOT}/lib/headers \
 -output ${RIME_ROOT}/Frameworks/librime.xcframework

# rm -rf ${RIME_ROOT}/Frameworks/librime-lua.xcframework
# xcodebuild -create-xcframework \
#  -library ${RIME_ROOT}/lib/librime_lua_x86_64.a \
#  -library ${RIME_ROOT}/lib/librime_lua_arm64.a \
#  -output ${RIME_ROOT}/Frameworks/librime-lua.xcframework

# clean
rm -rf ${RIME_ROOT}/lib/librime*.a

# copy librime dependence lib
cp -f ${RIME_ROOT}/librime/lib/*.a ${RIME_ROOT}/lib

files=("libglog" "libleveldb" "libmarisa" "libopencc" "libyaml-cpp")
for file in ${files[@]}
do
    echo "file = ${file}"

    # 拆分模拟器编译文件
    rm -rf $RIME_ROOT/lib/${file}_x86.a
    copy_or_thin_archive $RIME_ROOT/lib/${file}.a \
         x86_64 \
         $RIME_ROOT/lib/${file}_x86.a

    rm -rf $RIME_ROOT/lib/${file}_arm64.a
    copy_or_thin_archive $RIME_ROOT/lib/${file}.a \
         arm64 \
         $RIME_ROOT/lib/${file}_arm64.a

    rm -rf ${RIME_ROOT}/Frameworks/${file}.xcframework
    xcodebuild -create-xcframework \
    -library ${RIME_ROOT}/lib/${file}_x86.a \
    -library ${RIME_ROOT}/lib/${file}_arm64.a \
    -output ${RIME_ROOT}/Frameworks/${file}.xcframework
done
