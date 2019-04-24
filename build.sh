#!/bin/bash

SHELL_DIR=$(dirname $0)

CMD=${1:-${CIRCLE_JOB}}

USERNAME=${CIRCLE_PROJECT_USERNAME}
REPONAME=${CIRCLE_PROJECT_REPONAME}

REPOPATH="kubernetes/kubernetes"

BUCKET="repo.opspresso.com"

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

_prepare() {
    # target
    mkdir -p ${SHELL_DIR}/target/dist

    # 755
    find ./** | grep [.]sh | xargs chmod 755
}

_get_version() {
    NOW=$(cat ${SHELL_DIR}/Dockerfile | grep 'ENV VERSION' | awk '{print $3}' | xargs)
    NEW=$(curl -s https://api.github.com/repos/${REPOPATH}/releases/latest | grep tag_name | cut -d'"' -f4 | xargs)

    printf '# %-10s %-10s %-10s\n' "${REPONAME}" "${NOW}" "${NEW}"
}

_replace() {
    printf "${NEW}" > ${SHELL_DIR}/target/dist/${REPONAME}

    sed -i -e "s/ENV VERSION .*/ENV VERSION ${NEW}/g" ${SHELL_DIR}/Dockerfile
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

    # git tag ${NEW}
    # git push -q https://${GITHUB_TOKEN}@github.com/${USERNAME}/${REPONAME}.git ${NEW}
}

_flat_version() {
    echo "$@" | awk -F. '{ printf("%05d%05d%05d\n", $1,$2,$3); }'
}

_s3_sync() {
    _command "aws s3 sync ${1} s3://${2}/ --acl public-read"
    aws s3 sync ${1} s3://${2}/ --acl public-read
}

_cf_reset() {
    CFID=$(aws cloudfront list-distributions --query "DistributionList.Items[].{Id:Id, DomainName: DomainName, OriginDomainName: Origins.Items[0].DomainName}[?contains(OriginDomainName, '${1}')] | [0].Id" | cut -d'"' -f2)
    if [ "${CFID}" != "" ]; then
        _command "aws cloudfront create-invalidation --distribution-id ${CFID}"
        aws cloudfront create-invalidation --distribution-id ${CFID} --paths "/*"
    fi
}

_slack() {
    if [ -z ${SLACK_TOKEN} ]; then
        return
    fi

    curl -sL opspresso.com/tools/slack | bash -s -- \
        --token="${SLACK_TOKEN}" --username="${USERNAME}" \
        --footer="<https://github.com/${REPOPATH}/releases/tag/${NEW}|${REPOPATH}>" \
        --footer_icon="https://repo.opspresso.com/favicon/github.png" \
        --color="good" --title="${REPONAME} updated" "\`${NEW}\`"
}

_package() {
    _prepare

    _get_version

    if [ "${NEW}" != "" ] && [ "${NEW}" != "${NOW}" ]; then
        _replace

        _git_push

        if [ "$(_flat_version "$NEW")" -gt "$(_flat_version "$NOW")" ]; then
            _s3_sync "${SHELL_DIR}/target/dist/" "${BUCKET}/latest"
            _cf_reset "${BUCKET}"
        fi

        _slack
    fi
}

_release() {
    if [ -z ${GITHUB_TOKEN} ]; then
        return
    fi
    if [ ! -f ${SHELL_DIR}/target/dist/${REPONAME} ]; then
        return
    fi

    VERSION=$(cat ${SHELL_DIR}/target/dist/${REPONAME} | xargs)

    _result "VERSION=${VERSION}"

    _command "go get github.com/tcnksm/ghr"
    go get github.com/tcnksm/ghr

    _command "ghr ${VERSION} ${SHELL_DIR}/target/dist/"
    ghr -t ${GITHUB_TOKEN:-EMPTY} \
        -u ${USERNAME} \
        -r ${REPONAME} \
        -c ${CIRCLE_SHA1} \
        -delete \
        ${VERSION} ${SHELL_DIR}/target/dist/
}

_prepare

case ${CMD} in
    package)
        _package
        ;;
    release)
        _release
        ;;
esac
