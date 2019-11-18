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

_pickup() {
    THISVERSIONS=/tmp/this-versions
    curl -s https://api.github.com/repos/${REPOSITORY}/releases | grep tag_name | cut -d'"' -f4 > ${THISVERSIONS}

    _command "this-versions"
    cat ${THISVERSIONS}

    REPOVERSIONS=/tmp/repo-versions
    curl -s https://api.github.com/repos/${REPOPATH}/releases | grep tag_name | cut -d'"' -f4 > ${REPOVERSIONS}

    _command "repo-versions"
    cat ${REPOVERSIONS}

    while read VERSION; do
        COUNT=$(cat ${THISVERSIONS} | grep "${VERSION}" | wc -l | xargs)

        if [ "x${COUNT}" == "x0" ]; then
            NEW="${VERSION}"
            break
        fi
    done < ${REPOVERSIONS}
}

_package() {
    NOW=$(cat ${SHELL_DIR}/Dockerfile | grep 'ENV VERSION' | awk '{print $3}' | xargs)

    # NEW=$(curl -s https://api.github.com/repos/${REPOPATH}/releases | grep tag_name | cut -d'"' -f4 | xargs)
    # NEW=$(curl -s https://api.github.com/repos/${REPOPATH}/releases/latest | grep tag_name | cut -d'"' -f4 | cut -c 2- | xargs)

    _pickup

    echo
    printf '# %-10s %-10s %-10s\n' "${REPONAME}" "${NOW}" "${NEW}"

    _updated
    _latest
}

_latest() {
    BIGGER=$(echo -e "${NOW}\n${NEW}" | sort -V -r | head -1)

    if [ "${BIGGER}" == "${NOW}" ]; then
        _success "_latest ${NOW} >= ${NEW}"
    fi

    VERSION="${NEW}"

    _result "_latest ${VERSION}"

    printf "${VERSION}" > ${SHELL_DIR}/LATEST
    printf "${VERSION}" > ${SHELL_DIR}/target/publish/${REPONAME}
}

_updated() {
    if [ "${NEW}" == "" ] || [ "${NEW}" == "${NOW}" ]; then
        _error "_updated ${NOW} == ${NEW}"
    fi

    VERSION="${NEW}"

    _result "_updated ${VERSION}"

    printf "${VERSION}" > ${SHELL_DIR}/VERSION
    printf "${VERSION}" > ${SHELL_DIR}/target/commit_message

    _replace "s/ENV VERSION .*/ENV VERSION ${VERSION}/g" ${SHELL_DIR}/Dockerfile
    _replace "s/ENV VERSION .*/ENV VERSION ${VERSION}/g" ${SHELL_DIR}/README.md

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
