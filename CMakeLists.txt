cmake_minimum_required(VERSION 3.20)
project(PlayableAirplay VERSION 0.1.0 LANGUAGES C CXX)

# Everything the sender needs is built here, so a consumer links one library
# and includes one header. mbedTLS, ed25519 and the sender itself stay behind
# that line: nothing about them reaches the interface, and swapping any of them
# changes nothing a caller has to know.

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(PLAYABLE_AIRPLAY_BUILD_TESTS   "build the test binary" ON)

set(SENDER_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/airplay2-sender-cpp)
if(NOT EXISTS ${SENDER_DIR}/CMakeLists.txt)
    message(FATAL_ERROR
        "third_party/airplay2-sender-cpp is missing. Run:\n"
        "  git submodule update --init --recursive")
endif()

# The upstream example and tests are not ours to build, and its Qt host is off
# by default. What is wanted is its two libraries.
set(AIRPLAY_BUILD_EXAMPLE OFF CACHE BOOL "" FORCE)
set(AIRPLAY_BUILD_TESTS   OFF CACHE BOOL "" FORCE)
set(AIRPLAY_BUILD_QT_HOST OFF CACHE BOOL "" FORCE)
add_subdirectory(${SENDER_DIR} ${CMAKE_CURRENT_BINARY_DIR}/airplay2-sender EXCLUDE_FROM_ALL)

add_library(PlayableAirplay STATIC
    src/session.cpp
    src/discovery.c
    src/receiver_name.c)

target_include_directories(PlayableAirplay
    PUBLIC  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
            $<INSTALL_INTERFACE:include>
    PRIVATE ${SENDER_DIR}/src
            ${CMAKE_CURRENT_SOURCE_DIR}/src)

target_link_libraries(PlayableAirplay PRIVATE raop_sender airplay_crypto)

# A static library does not carry what it was linked against, so the archive is
# rebuilt to hold those members too. Without it, linking libPlayableAirplay.a
# alone leaves every RaopSender symbol undefined and a consumer has to learn the
# names and the order of five more archives.
set(PA_BUNDLED_TARGETS raop_sender airplay_crypto)
foreach(candidate IN ITEMS ed25519 mbedcrypto everest p256m)
    if(TARGET ${candidate})
        list(APPEND PA_BUNDLED_TARGETS ${candidate})
    endif()
endforeach()

set(PA_BUNDLED_ARCHIVES "")
foreach(bundled IN LISTS PA_BUNDLED_TARGETS)
    string(APPEND PA_BUNDLED_ARCHIVES "$<TARGET_FILE:${bundled}>\n")
endforeach()

# The archive paths go through a file rather than through the command line,
# because a list on a -D argument is split by the generator before the script
# ever sees it, and the script would silently bundle only the first one.
set(PA_BUNDLE_LIST ${CMAKE_CURRENT_BINARY_DIR}/bundled-archives.txt)
file(GENERATE OUTPUT ${PA_BUNDLE_LIST} CONTENT "${PA_BUNDLED_ARCHIVES}")

add_custom_command(TARGET PlayableAirplay POST_BUILD
    COMMAND ${CMAKE_COMMAND}
            -DBUNDLE_OUTPUT=$<TARGET_FILE:PlayableAirplay>
            -DBUNDLE_LIST=${PA_BUNDLE_LIST}
            -DCMAKE_AR=${CMAKE_AR}
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/bundle_static.cmake
    VERBATIM
    COMMENT "Bundling the sender and its crypto into libPlayableAirplay.a")

if(APPLE)
    # dns_sd is in the system library here. On Linux the same header comes from
    # Avahi's compatibility package, which is why the discovery is one file.
    target_link_libraries(PlayableAirplay PRIVATE "-framework CoreFoundation")
else()
    find_library(DNSSD_LIBRARY NAMES dns_sd)
    if(NOT DNSSD_LIBRARY)
        message(FATAL_ERROR "libdns_sd not found. On Debian: apt install libavahi-compat-libdnssd-dev")
    endif()
    target_link_libraries(PlayableAirplay PRIVATE ${DNSSD_LIBRARY} pthread)
endif()

# The example is Swift and is built with swiftc rather than here, because this
# file's job is the library. README.md carries the one command it takes.

if(PLAYABLE_AIRPLAY_BUILD_TESTS)
    enable_testing()
    add_executable(pa_tests test/pa_tests.c)
    # The tests reach into src/ for the name parsing, which is internal on
    # purpose: it is the one piece that can be checked without a receiver.
    target_include_directories(pa_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_link_libraries(pa_tests PRIVATE PlayableAirplay)
    add_test(NAME PlayableAirplay COMMAND pa_tests)
endif()

include(GNUInstallDirs)
install(TARGETS PlayableAirplay ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})
install(FILES include/PlayableAirplay.h include/module.modulemap
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
