#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

SHELL_DIR=$(dirname $0)

REPOSITORY=${GITHUB_REPOSITORY}

USERNAME=${GITHUB_ACTOR}
REPONAME=$(echo "${REPOSITORY}" | cut -d'/' -f2)

REPOPATH="kubernetes/kubernetes"

NOW=
NEW=

################################################################################

# command -v tput > /dev/null && TPUT=true
TPUT=

_echo() {
    if [ "${TPUT}" != "" ] && [ "$2" != "" ]; then
        echo -e "$(tput setaf $2)$1$(tput sgr0)"
    else
        echo -e "$1"
    fi
}

_result() {
    echo
    _echo "# $@" 4
}

_command() {
    echo
    _echo "$ $@" 3
}

_success() {
    echo
    _echo "+ $@" 2
    exit 0
}

_error() {
    echo
    _echo "- $@" 1
    exit 1
}

_replace() {
    if [ "${OS_NAME}" == "darwin" ]; then
        sed -i "" -e "$1" $2
    else
        sed -i -e "$1" $2
    fi
}

################################################################################

_prepare() {
    # target
    mkdir -p ${SHELL_DIR}/target/publish

    # 755
    find ./** | grep [.]sh | xargs chmod 755
}

_package() {
    NOW=$(cat ${SHELL_DIR}/Dockerfile | grep 'ENV VERSION' | awk '{print $3}' | xargs)
    NEW=$(curl -s https://api.github.com/repos/${REPOPATH}/releases/latest | grep tag_name | cut -d'"' -f4 | xargs)
    # NEW=$(curl -s https://api.github.com/repos/${REPOPATH}/releases/latest | grep tag_name | cut -d'"' -f4 | cut -c 2- | xargs)

    printf '# %-10s %-10s %-10s\n' "${REPONAME}" "${NOW}" "${NEW}"

    _s3_sync

    _git_push
}

_s3_sync() {
    BIGGER=$(echo -e "${NOW}\n${NEW}" | sort -V -r | head -1)

    if [ "${BIGGER}" == "${NOW}" ]; then
        _result "_s3_sync ${NOW} >= ${NEW}"
        return
    fi

    _result "_s3_sync ${NEW}"

    printf "${NEW}" > ${SHELL_DIR}/LATEST
    printf "${NEW}" > ${SHELL_DIR}/target/publish/${REPONAME}
}

_git_push() {
    if [ "${NEW}" == "" ] || [ "${NEW}" == "${NOW}" ]; then
        _result "_git_push ${NOW} == ${NEW}"
        return
    fi

    _result "_git_push ${NEW}"

    printf "${NEW}" > ${SHELL_DIR}/VERSION
    printf "${NEW}" > ${SHELL_DIR}/target/commit_message

    _replace "s/ENV VERSION .*/ENV VERSION ${NEW}/g" ${SHELL_DIR}/Dockerfile
    _replace "s/ENV VERSION .*/ENV VERSION ${NEW}/g" ${SHELL_DIR}/README.md

    cat <<EOF > ${SHELL_DIR}/target/slack_message.json
{
    "username": "${USERNAME}",
    "attachments": [{
        "color": "good",
        "footer": "<https://github.com/${REPOSITORY}/releases/tag/${VERSION}|${REPOSITORY}>",
        "footer_icon": "https://repo.opspresso.com/favicon/github.png",
        "title": "${REPONAME}",
        "text": "\`${VERSION}\`"
    }]
}
EOF
}

################################################################################

_prepare

_package
