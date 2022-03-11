#!/bin/bash
#########################################################################
# Title:         Saltbox Mod: SBMOD Script                              #
# Author(s):     hackmonker                                             #
# URL:           https://github.com/media-byte/sb_mod                   #
# --                                                                    #
#########################################################################
#                   GNU General Public License v3.0                     #
#########################################################################

################################
# Privilege Escalation
################################

# Restart script in SUDO
# https://unix.stackexchange.com/a/28793

if [ $EUID != 0 ]; then
    sudo "$0" "$@"
    exit $?
fi

################################
# Scripts
################################

source /srv/git/sb/yaml.sh
create_variables /srv/git/saltbox/accounts.yml

################################
# Variables
################################

#Ansible
ANSIBLE_PLAYBOOK_BINARY_PATH="/usr/local/bin/ansible-playbook"

# Saltbox Mod
SALTBOX_REPO_PATH="/opt/saltbox_mod"
SALTBOX_PLAYBOOK_PATH="$SALTBOX_REPO_PATH/saltbox_mod.yml"
SALTBOX_LOGFILE_PATH="$SALTBOX_REPO_PATH/saltbox_mod.log"

# SB
SB_REPO_PATH="/srv/git/sb_mod"

################################
# Functions
################################

git_fetch_and_reset () {

    git fetch --quiet >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard "@{u}" >/dev/null
    git checkout --quiet master >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard "@{u}" >/dev/null
    git submodule update --init --recursive
    chmod 664 "${SALTBOX_REPO_PATH}/ansible.cfg"
    # shellcheck disable=SC2154
    chown -R "${user_name}":"${user_name}" "${SALTBOX_REPO_PATH}"
}

git_fetch_and_reset_sb () {

    git fetch --quiet >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard "@{u}" >/dev/null
    git checkout --quiet master >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard "@{u}" >/dev/null
    git submodule update --init --recursive
    chmod 775 "${SB_REPO_PATH}/sb.sh"
}

run_playbook_sb () {

    local arguments=$*

    echo "" > "${SALTBOX_LOGFILE_PATH}"

    cd "${SALTBOX_REPO_PATH}" || exit

    # shellcheck disable=SC2086
    "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
        "${SALTBOX_PLAYBOOK_PATH}" \
        --become \
        ${arguments}

    cd - >/dev/null || exit

}

install () {

    local arg=("$@")
    echo "${arg[*]}"

    # Remove space after comma
    # shellcheck disable=SC2128,SC2001
    arg_clean=$(sed -e 's/, /,/g' <<< "$arg")

    # Split tags from extra arguments
    # https://stackoverflow.com/a/10520842
    re="^(\S+)\s+(-.*)?$"
    if [[ "$arg_clean" =~ $re ]]; then
        tags_arg="${BASH_REMATCH[1]}"
        extra_arg="${BASH_REMATCH[2]}"
    else
        tags_arg="$arg_clean"
    fi

    # Save tags into 'tags' array
    # shellcheck disable=SC2206
    tags_tmp=(${tags_arg//,/ })

    # Remove duplicate entries from array
    # https://stackoverflow.com/a/31736999
    readarray -t tags < <(printf '%s\n' "${tags_tmp[@]}" | awk '!x[$0]++')

    # Build SB/CM tag arrays
    local tags_sb

    for i in "${!tags[@]}"
    do
        if [[ ${tags[i]} == sandbox-* ]]; then
            tags_sandbox="${tags_sandbox}${tags_sandbox:+,}${tags[i]##sandbox-}"

        else
            tags_sb="${tags_sb}${tags_sb:+,}${tags[i]}"

        fi
    done

    # Saltbox Ansible Playbook
    if [[ -n "$tags_sb" ]]; then

        # Build arguments
        local arguments_sb="--tags $tags_sb"

        if [[ -n "$extra_arg" ]]; then
            arguments_sb="${arguments_sb} ${extra_arg}"
        fi

        # Run playbook
        echo ""
        echo "Running Saltbox Tags: ${tags_sb//,/,  }"
        echo ""
        run_playbook_sb "$arguments_sb"
        echo ""

    fi

}

update () {

    if [[ -d "${SALTBOX_REPO_PATH}" ]]
    then
        echo -e "Updating Saltbox Mod...\n"

        cd "${SALTBOX_REPO_PATH}" || exit

        git_fetch_and_reset

        run_playbook_sb "--tags settings" && echo -e '\n'

        echo -e "Update Completed."
    else
        echo -e "Saltbox Mod folder not present."
    fi

}

sb-update () {

    echo -e "Updating sb mod...\n"

    cd "${SB_REPO_PATH}" || exit

    git_fetch_and_reset_sb

    echo -e "Update Completed."

}

sb-list ()  {

    if [[ -d "${SALTBOX_REPO_PATH}" ]]
    then
        echo -e "Saltbox Mod tags:\n"

        cd "${SALTBOX_REPO_PATH}" || exit

        "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
            "${SALTBOX_PLAYBOOK_PATH}" \
            --become \
            --list-tags --skip-tags "always" 2>&1 | grep "TASK TAGS" | cut -d":" -f2 | awk '{sub(/\[/, "")sub(/\]/, "")}1' | cut -c2-

        echo -e "\n"

        cd - >/dev/null || exit
    else
        echo -e "Saltbox folder not present.\n"
    fi

}

list () {
    sb-list
}

usage () {
    echo "Usage:"
    echo "    sbmod update              Update Saltbox Mod."
    echo "    sbmod list                List Saltbox Mod packages."
    echo "    sbmod install <package>   Install <package>."
}

################################
# Update check
################################

cd "${SB_REPO_PATH}" || exit

git fetch
HEADHASH=$(git rev-parse HEAD)
UPSTREAMHASH=$(git rev-parse "master@{upstream}")

if [ "$HEADHASH" != "$UPSTREAMHASH" ]
then
 echo -e Not up to date with origin. Updating.
 sb-update
 echo -e Relaunching with previous arguments.
 sudo "$0" "$@"
 exit 0
fi

################################
# Argument Parser
################################

# https://sookocheff.com/post/bash/parsing-bash-script-arguments-with-shopts/

roles=""  # Default to empty role
#target=""  # Default to empty target

# Parse options
while getopts ":h" opt; do
  case ${opt} in
    h)
        usage
        exit 0
        ;;
   \?)
        echo "Invalid Option: -$OPTARG" 1>&2
        echo ""
        usage
        exit 1
     ;;
  esac
done
shift $((OPTIND -1))

# Parse commands
subcommand=$1; shift  # Remove 'sb' from the argument list
case "$subcommand" in

  # Parse options to the various sub commands
    list)
        list
        ;;
    update)
        update
        ;;
    install)
        roles=${*}
        install "${roles}"
        ;;
    "") echo "A command is required."
        echo ""
        usage
        exit 1
        ;;
    *)
        echo "Invalid Command: $subcommand"
        echo ""
        usage
        exit 1
        ;;
esac
