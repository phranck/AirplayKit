#
#  bundle_static.cmake
#  Merges several static archives into one.
#
#  A static library does not carry the libraries it was linked against, so
#  without this a consumer would have to know about the sender, the crypto and
#  Mbed TLS and link all of them in the right order. That is exactly the
#  knowledge this package exists to keep to itself.
#
#  Expects BUNDLE_OUTPUT, and BUNDLE_LIST naming a file with one archive path
#  per line. The output is one of those paths, and it is rebuilt in place.
#

if(NOT BUNDLE_OUTPUT OR NOT BUNDLE_LIST)
    message(FATAL_ERROR "bundle_static needs BUNDLE_OUTPUT and BUNDLE_LIST")
endif()

file(STRINGS "${BUNDLE_LIST}" BUNDLE_INPUTS)
list(INSERT BUNDLE_INPUTS 0 "${BUNDLE_OUTPUT}")

set(scratch "${BUNDLE_OUTPUT}.bundling")

if(APPLE)
    # libtool merges archives in one call and keeps the table of contents right.
    execute_process(
        COMMAND libtool -static -no_warning_for_no_symbols -o "${scratch}" ${BUNDLE_INPUTS}
        RESULT_VARIABLE status
        ERROR_VARIABLE problem)
else()
    # GNU ar takes a script on its input, which is the portable way to say
    # "take every member of that archive" without unpacking anything.
    set(script "create ${scratch}\n")
    foreach(input IN LISTS BUNDLE_INPUTS)
        string(APPEND script "addlib ${input}\n")
    endforeach()
    string(APPEND script "save\nend\n")

    set(scriptFile "${BUNDLE_OUTPUT}.mri")
    file(WRITE "${scriptFile}" "${script}")

    execute_process(
        COMMAND ${CMAKE_AR} -M
        INPUT_FILE "${scriptFile}"
        RESULT_VARIABLE status
        ERROR_VARIABLE problem)

    file(REMOVE "${scriptFile}")
endif()

if(NOT status EQUAL 0)
    message(FATAL_ERROR "could not bundle the static archives: ${problem}")
endif()

file(RENAME "${scratch}" "${BUNDLE_OUTPUT}")
