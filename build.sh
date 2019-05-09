#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

SHELL_DIR=$(dirname $0)

CMD=${1:-${CIRCLE_JOB}}

USERNAME=${CIRCLE_PROJECT_USERNAME}
REPONAME=${CIRCLE_PROJECT_REPONAME}

REPOPATH="kubernetes/kubernetes"

GIT_USERNAME="bot"
GIT_USEREMAIL="bot@nalbam.com"

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

_flat_version() {
    echo "$@" | awk -F. '{ printf("%05d%05d%05d\n", $1,$2,$3); }'
}

_prepare() {
    # target
    mkdir -p ${SHELL_DIR}/target/dist

    # 755
    find ./** | grep [.]sh | xargs chmod 755
}

_package() {
    NOW=$(cat ${SHELL_DIR}/Dockerfile | grep 'ENV VERSION' | awk '{print $3}' | xargs)
    NEW=$(curl -s https://api.github.com/repos/${REPOPATH}/releases/latest | grep tag_name | cut -d'"' -f4 | xargs)

    printf '# %-10s %-10s %-10s\n' "${REPONAME}" "${NOW}" "${NEW}"

    if [ "${NEW}" != "" ] && [ "${NEW}" != "${NOW}" ]; then
        printf "${NEW}" > ${SHELL_DIR}/VERSION
        printf "${NEW}" > ${SHELL_DIR}/target/VERSION

        printf "${NEW}" > ${SHELL_DIR}/target/dist/${REPONAME}

        _replace "s/ENV VERSION .*/ENV VERSION ${NEW}/g" ${SHELL_DIR}/Dockerfile
        _replace "s/ENV VERSION .*/ENV VERSION ${NEW}/g" ${SHELL_DIR}/README.md

        _git_push
    else
        echo "stop" > ${SHELL_DIR}/target/circleci-stop
    fi
}

_git_push() {
    if [ -z ${GITHUB_TOKEN} ]; then
        return
    fi

    git config --global user.name "${GIT_USERNAME}"
    git config --global user.email "${GIT_USEREMAIL}"

    git add --all
    git commit -m "${NEW}"

    _command "git push github.com/${USERNAME}/${REPONAME} ${NEW}"
    git push -q https://${GITHUB_TOKEN}@github.com/${USERNAME}/${REPONAME}.git master
}

################################################################################

_prepare

_package
