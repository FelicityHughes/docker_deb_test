#!/usr/bin/env bash

################################################################################
# This script tests the validity of a .deb file by performing the following
# steps:
# 1. Copy any .deb files nominated in the LOCAL_DEB_FILES and REMOTE_DEB_FILES
#    environment variables to the local build directory.
# 2. Run Docker Compose to:
#      a) Create a basic Linux Docker image and install the .deb files.
#      b) Launch a daemonised Docker container based on the created image.
#
# Once the container is up and running, the user can log in to it and check the
# .deb has been unpacked as expected with the following command:
#
# docker exec -it deb-test /bin/bash
#
# The container can be shut down by running:
#
# docker-compose down
#
# ...in the root directory (where docker-compose.yml lives).  Add the -v flag to
# tear down all volumes owned by the container.
#
# Command line options:
# -b When set, instructs Docker to tear down any volumes attached to the
#    container from a previous run and rebuild the image from scratch.
# -l <local_deb_files> Whitespace-separated list of local .deb files to unpack.
# -r <remote_deb_files> Whitespace-separated list of remote .deb files to
#                       unpack.
#
# Note: there must be at least one argument for the -l or -r flag.
################################################################################


# Include error handling functionality.
. ./ErrorHandling.sh

# File and command info.
readonly USAGE="${0} [-l <local_deb_files>] [-r <remote_deb_files>] [-b(uild)]"

# Exit states.
readonly BAD_ARGUMENT_ERROR=90
readonly MISSING_DEB_ERROR=91
readonly MISSING_DIR_ERROR=92
readonly CURL_ERROR=93

# Command line switch environment variables.
LOCAL_DEB_FILES=()
REMOTE_DEB_FILES=()
REBUILD="${FALSE}"


################################################################################
# Checks command line arguments are valid and have valid arguments.
#
# @param $@ All arguments passed on the command line.
################################################################################
check_args() {
  local deb_specified="${FALSE}"

  while [[ ${#} -gt 0 ]]; do
    case "${1}" in
      -b)
        if ! [[ "${2}" =~ ^-[lr]$ ]] && [[ ${#} -gt 1 ]]; then
          exit_with_error "${BAD_ARGUMENT_ERROR}" \
                          "Option ${1} does not require an argument.  Usage:  $USAGE"
        else
          REBUILD="${TRUE}"
        fi
        ;;
      -l)
        while ! [[ "${2}" =~ ^-[blr]$ ]] && [[ ${#} -gt 1 ]]; do
          LOCAL_DEB_FILES+=("${2}")
          shift
        done

        if [[ ${#LOCAL_DEB_FILES[@]} -eq 0 ]]; then
          exit_with_error "${BAD_ARGUMENT_ERROR}" \
                          "Option ${1} requires an argument.  Usage:  $USAGE"
        else
          deb_specified="${TRUE}"
        fi
        ;;
      -r)
        while ! [[ "${2}" =~ ^-[blr]$ ]] && [[ ${#} -gt 1 ]]; do
          REMOTE_DEB_FILES+=("${2}")
          shift
        done

        if [[ ${#REMOTE_DEB_FILES[@]} -eq 0 ]]; then
          exit_with_error "${BAD_ARGUMENT_ERROR}" \
                          "Option ${1} requires an argument.  Usage:  $USAGE"
        else
          deb_specified="${TRUE}"
        fi
        ;;
      *)
        exit_with_error "${BAD_ARGUMENT_ERROR}" \
                        "Invalid option: ${1}.  Usage:  $USAGE"
        ;;
    esac
    shift
  done

  if ((deb_specified == FALSE)); then
    exit_with_error "${MISSING_DEB_ERROR}" \
                    "No local or remote .deb files specified!"
  fi
}


################################################################################
# Executes clean up tasks required before exiting - basically writing the 
# interrupt signal to stderr.
#
# Note:  This function is assigned to signal trapping for the script so any
#        unexpected interrupts are handled gracefully.
################################################################################
cleanup() {
  # Exit and indicate what caused the interrupt
  if [[ "${1}" != "EXIT" ]]; then
    write_log "Script interrupted by '${1}' signal"

    if [[ "${1}" != "INT" ]] && [[ "${1}" != "QUIT" ]]; then
      exit ${SCRIPT_INTERRUPTED}
    else
      kill -"${1}" "$$"
    fi
  fi
}


#################################################################################
# Retrieves the deb files required for the build and copies them to the build
# directory.
#################################################################################
get_deb_files() {
  local return_val="${SUCCESS}"

  # Make sure we only have .deb files relevant for this script run.
  rm -rf ./*.deb

  for deb_file in "${LOCAL_DEB_FILES[@]}"; do
    if [[ ! -f "${deb_file}" ]]; then
      exit_with_error "${MISSING_DEB_ERROR}" \
                      "Deb file *${deb_file}* not found."
    fi

    cp "${deb_file}" "${BUILD_DIR}"
  done

  cd "${BUILD_DIR}" || \
     exit_with_error ${MISSING_DIR_ERROR} \
                     "Could not change to ${BUILD_DIR} dir."

  for remote_deb_file in "${REMOTE_DEB_FILES[@]}"; do
    curl -f -O "${remote_deb_file}"
    return_val="${?}"

    if ((return_val != SUCCESS)); then
      exit_with_error ${CURL_ERROR} \
                      "Could not retrieve base deb file from *${remote_deb_file}*!"
    fi
  done

  cd "${WORKING_DIR}" || \
     exit_with_error ${MISSING_DIR_ERROR} \
                     "Could not change to ${WORKING_DIR} dir."
}


#################################################################################
# Entry point to the program.  Valid command line options are described at the
# top of the script.
#
# @param ARGS Command line flags, including -d <deb_file> and the optional
#             -b <base_deb_file> and -r(ebuild).
################################################################################
main() {
  ARGS=("${@}")
  check_args "${ARGS[@]}"
  get_deb_files

  if ((REBUILD == TRUE)); then
    remove_docker_containers "${TRUE}"
    docker-compose up --build -d
  else
    remove_docker_containers "${FALSE}"
    docker-compose up -d
  fi
}


################################################################################
# Set up for bomb-proof exit, then run the script
################################################################################
trap_with_signal cleanup HUP INT QUIT ABRT TERM EXIT

main "${@}"
exit ${SUCCESS}