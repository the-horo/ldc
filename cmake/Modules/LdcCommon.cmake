# Common functionality shared by the compiler and the runtime build system.

function(append value)
    foreach(variable ${ARGN})
	if(${variable} STREQUAL "")
	    set(${variable} "${value}" PARENT_SCOPE)
	else()
	    set(${variable} "${${variable}} ${value}" PARENT_SCOPE)
	endif()
    endforeach(variable)
endfunction()

function(defineIfUnset variable)
    if(ARGC EQUAL 1)
	set(args)
    else()
	list(SUBLIST ARGV 1 -1 args)
    endif()

    if(NOT DEFINED ${variable})
	set(${variable} ${args} PARENT_SCOPE)
    endif()
endfunction()

function(formatArray out_var)
    if(ARGC EQUAL 1)
	set(${out_var} "[]" PARENT_SCOPE)
	return()
    endif()

    list(SUBLIST ARGV 1 -1 values)
    set(result "[")
    foreach(value ${values})
	set(result "${result}\n        \"${value}\",")
    endforeach()
    set(result "${result}\n    ]")

    set(${out_var} "${result}" PARENT_SCOPE)
endfunction()

function(formatArraySetting out_var name)
    if(ARGC EQUAL 2)
	# Ignore `value ~= []`
	set(${out_var} "" PARENT_SCOPE)
	return()
    endif()

    list(SUBLIST ARGV 2 -1 values)
    list(GET values 0 maybe_override)
    if(maybe_override STREQUAL "OVERRIDE")
	set(operator "=")
	list(POP_FRONT values)
    else()
	set(operator "~=")
    endif()
    formatArray(array ${values})
    set(${out_var} "\n    ${name} ${operator} ${array};" PARENT_SCOPE)
endfunction()

function(formatScalarSetting out_var name value)
    if(value STREQUAL "")
	set(${out_var} "" PARENT_SCOPE)
    else()
	set(${out_var} "\n    ${name} = \"${value}\";" PARENT_SCOPE)
    endif()
endfunction()


# Create a ldc2.conf section
#
# Example:
#
# makeConfSectionImpl(
#     FILEPATH "${CMAKE_BINARY_DIR}/ldc2.conf"
#     # The output filename
#
#     SECTION "^wasm(32|64)-"
#     # A regex to match a target triple or "default"
#
#     SWITCHES -d-version=foo -L--linker-flag
#     # The `switches` list
#
#     POST_SWITCHES OVERRIDE -I/path/to/druntime/src
#     # The `post-switches` list
#
#     LIB_DIRS "${CMAKE_BINARY_DIR}/lib64"
#     # The `lib-dirs` list
#
#     RPATH "/path/to/dir"
#     # The `rpath` value
# )
#
# Would generate:
#
# $ cat "${CMAKE_BINARY_DIR}/ldc2.conf"
# "^wasm(32|64)-":
# {
#     switches ~= [
#         "-d-version=foo",
#         "-L--linker-flag",
#     ];
#     post-switches = [
#         "-I/path/to/druntime/src"
#     ];
#     lib-dirs ~= [
#         "${CMAKE_BINARY_DIR}/lib64"
#     ];
#     rpath = "/path/to/dir"
# }
#
# You don't need to pass all setting keys, only the ones that have values.
#
# Array settings (SWITCHES, POST_SWITCHES, LIB_DIRS) may start with an
# OVERRIDE signifying that they should overwrite the (possibly)
# previously stored values. The default is to append to them.
function(makeConfSectionImpl)
    set(oneValueArgs FILEPATH SECTION RPATH)
    set(multiValueArgs SWITCHES POST_SWITCHES LIB_DIRS)
    cmake_parse_arguments(args "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    foreach(var FILEPATH SECTION)
	if(NOT DEFINED args_${var})
	    message(SEND_ERROR "Expected ${var} argument")
	endif()
    endforeach()
    if(DEFINED args_UNPARSED_ARGUMENTS)
	message(SEND_ERROR "Unexpected arguments: ${args_UNPARSED_ARGUMENTS}")
    endif()

    formatArraySetting(switches "switches" ${args_SWITCHES})
    formatArraySetting(post_switches "post-switches" ${args_POST_SWITCHES})
    formatArraySetting(lib_dirs "lib-dirs" ${args_LIB_DIRS})
    formatScalarSetting(rpath "rpath" "${args_RPATH}")

    file(WRITE "${args_FILEPATH}"
	"\"${args_SECTION}\":\n"
	"{"
	"${switches}"
	"${post_switches}"
	"${lib_dirs}"
	"${rpath}"
	"\n};\n\n"
    )
endfunction()

# Create a ldc2.conf section
#
# Example:
#
# makeConfSection(
#     NAME 40-runtime
#     # a unique name for the file that will store this section
#
#     SECTION "x86_64-.*-linux-gnu"
#     # A regex for a target triple or the string "default"
#
#     BUILD
#     # Settings for ldc2.conf when part of this cmake project
#     SWITCHES -a -b
#     POST_SWITCHES -I${CMAKE_SOURCE_DIR}/runtime/import -c
#
#     INSTALL
#     # Settings for ldc2.conf when installed on a user system
#     SWITCHES OVERRIDE -bar
#     LIB_DIRS "${CMAKE_INSTALL_PREFIX}/lib"
#     RPATH "${CMAKE_INSTALL_PREFIX}/lib"
# )
#
# The possible settings are described by makeConfSectionImpl.
#
# As a shortcut the BUILD and INSTALL arguments may be omitted, making the
# settings be applied to both build and install ldc2.conf. Example:
#
# makeConfSection(NAME 10-example SECTION default
#     SWITCHES -my-important-switch
# )
#
# Is equivalent to:
#
# makeConfSection(NAME 10-example SECTION default
#     BUILD
#     SWITCHES -my-important-switch
#     INSTALL
#     SWITCHES -my-important-switch
# )
#
# It is also possible to generate a configuration file for either only the build
# or only the install. Simply pass only BUILD or INSTALL to this function.
function(makeConfSection)
    set(oneValueArgs NAME SECTION)
    set(multiValueArgs BUILD INSTALL)
    cmake_parse_arguments(PARSE_ARGV 0 args "" "${oneValueArgs}" "${multiValueArgs}")

    foreach(var ${oneValueArgs})
	if(NOT DEFINED args_${var})
	    message(SEND_ERROR "Expected defined ${var} argument")
	endif()
    endforeach()
    if(DEFINED args_UNPARSED_ARGUMENTS)
	if(NOT DEFINED args_BUILD AND NOT DEFINED args_INSTALL)
	    set(args_BUILD "${args_UNPARSED_ARGUMENTS}")
	    set(args_INSTALL "${args_UNPARSED_ARGUMENTS}")
	else()
	    message(SEND_ERROR "Unexpected arguments: ${args_UNPARSED_ARGUMENTS}")
	endif()
    endif()

    if(args_BUILD)
	set(build_conf "${LDC2_BUILD_CONF}/${args_NAME}.conf")
	makeConfSectionImpl(FILEPATH "${build_conf}" SECTION "${args_SECTION}" ${args_BUILD})
    endif()
    if(args_INSTALL)
	set(install_conf "${LDC2_INSTALL_CONF}/${args_NAME}.conf")
	makeConfSectionImpl(FILEPATH "${install_conf}" SECTION "${args_SECTION}" ${args_INSTALL})
	if(CONF_PREFER_DIR)
	    if(NOT DONT_INSTALL_CONF)
		install(FILES "${install_conf}" DESTINATION "${CONF_INST_DIR}/ldc2.conf")
	    endif()
	else()
	    get_filename_component(install_path "${install_path}" ABSOLUTE)
	    list(APPEND _ALL_CONF_INSTALL_FILES "${install_conf}")
	    set(_ALL_CONF_INSTALL_FILES "${_ALL_CONF_INSTALL_FILES}" PARENT_SCOPE)
	endif()
    endif()
endfunction()

function(installConf)
    if(CONF_PREFER_DIR OR DONT_INSTALL_CONF)
	return()
    endif()

    list(SORT _ALL_CONF_INSTALL_FILES COMPARE FILE_BASENAME)

    set(out_dir "${CMAKE_BINARY_DIR}/etc")
    make_directory("${out_dir}")
    set(output_conf_file "${out_dir}/ldc2_install.conf")

    # The first argument is the output file name, for the below scripts
    set(cmd_args "${output_conf_file}" "${_ALL_CONF_INSTALL_FILES}")
    if(WIN32)
	file(WRITE "${CMAKE_BINARY_DIR}/cat_into.bat"
	    # Yes, we are relying on `> %1` to clear the file content
	    # before the file is "cat"ed because SHIFT does not shift
	    # %*.
	    "@ECHO OFF\ntype %* > %1\n")
	set(cmd "${CMAKE_BINARY_DIR}/cat_into.bat")
	# Convert the cmake /-style paths to \
	list(TRANSFORM cmd_args REPLACE "/" "\\\\")
    else()
	set(cmd sh -c "cat \"\$@\" > \"\$1\"" script)
    endif()
    add_custom_command(OUTPUT "${output_conf_file}"
	# cat all files into OUTPUT
	COMMAND ${cmd} ${cmd_args}
	VERBATIM
	DEPENDS ${_ALL_CONF_INSTALL_FILES}
    )
    add_custom_target(gen_conf_file ALL DEPENDS "${output_conf_file}")
    install(FILES "${output_conf_file}" DESTINATION "${CONF_INST_DIR}" RENAME ldc2.conf)
endfunction()

# Generally, we want to install everything into CMAKE_INSTALL_PREFIX, but when
# it is /usr, put the config files into /etc to meet common practice.
if(NOT DEFINED SYSCONF_INSTALL_DIR)
    if(CMAKE_INSTALL_PREFIX STREQUAL "/usr")
        set(SYSCONF_INSTALL_DIR "/etc")
    else()
        set(SYSCONF_INSTALL_DIR "${CMAKE_INSTALL_PREFIX}/etc")
    endif()
endif()

set(CONF_INST_DIR ${SYSCONF_INSTALL_DIR} CACHE PATH "Directory in which to install ldc2.conf")
if(CONF_INST_DIR STREQUAL "")
    set(DONT_INSTALL_CONF TRUE)
else()
    set(DONT_INSTALL_CONF FALSE)
endif()

option(CONF_PREFER_DIR "Prefer installing ldc2.conf as a directory")
# Avoid making the D code check for all cmake truthy values
if(CONF_PREFER_DIR)
    set(CONF_PREFER_DIR_D_BOOLEAN true)
else()
    set(CONF_PREFER_DIR_D_BOOLEAN false)
endif()

set(INCLUDE_INSTALL_DIR ${CMAKE_INSTALL_PREFIX}/include/d CACHE PATH "Path to install D modules to")

defineIfUnset(LDC2_BUILD_CONF "${CMAKE_BINARY_DIR}/etc/ldc2.conf")
defineIfUnset(LDC2_INSTALL_CONF "${CMAKE_BINARY_DIR}/etc/ldc2_install.conf.d")
