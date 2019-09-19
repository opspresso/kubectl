#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

SHELL_DIR=$(dirname $0)

CMD=${1:-${CIRCLE_JOB}}

USERNAME=${CIRCLE_PROJECT_USERNAME}
REPONAME=${CIRCLE_PROJECT_REPONAME}

REPOPATH="kubernetes/kubernetes"

# ${BUCKET}/latest/${REPONAME}
PUBLISH_PATH="repo.opspresso.com/latest"

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
    echo "$@" | awk -F. '{ printf("%05s%05s%05s\n", $1,$2,$3); }'
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
    FLAT_NOW="$(_flat_version ${NOW})"
    FLAT_NEW="$(_flat_version ${NEW})"

    if [[ "${FLAT_NOW}" -ge "${FLAT_NEW}" ]]; then
        return
    fi

    _result "_s3_sync ${REPONAME} ${NEW}"

    printf "${NEW}" > ${SHELL_DIR}/LATEST
    printf "${NEW}" > ${SHELL_DIR}/target/publish/${REPONAME}

    BUCKET="$(echo "${PUBLISH_PATH}" | cut -d'/' -f1)"

    # aws s3 sync
    _command "aws s3 sync ${SHELL_DIR}/target/publish/ s3://${PUBLISH_PATH}/ --acl public-read"
    aws s3 sync ${SHELL_DIR}/target/publish/ s3://${PUBLISH_PATH}/ --acl public-read

    # aws cf reset
    CFID=$(aws cloudfront list-distributions --query "DistributionList.Items[].{Id:Id,Origin:Origins.Items[0].DomainName}[?contains(Origin,'${BUCKET}')] | [0]" | grep 'Id' | cut -d'"' -f4)
    if [ "${CFID}" != "" ]; then
        aws cloudfront create-invalidation --distribution-id ${CFID} --paths "/*"
    fi
}

_git_push() {
    if [ -z ${GITHUB_TOKEN} ]; then
        return
    fi

    if [ "${NEW}" == "" ] || [ "${NEW}" == "${NOW}" ]; then
        return
    fi

    _result "_git_push ${REPONAME} ${NEW}"

    printf "${NEW}" > ${SHELL_DIR}/VERSION

    _replace "s/ENV VERSION .*/ENV VERSION ${NEW}/g" ${SHELL_DIR}/Dockerfile
    _replace "s/ENV VERSION .*/ENV VERSION ${NEW}/g" ${SHELL_DIR}/README.md

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
