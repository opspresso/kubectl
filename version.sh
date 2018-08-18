#!/bin/bash

USERNAME=${1}
REPONAME=${2}
GITHUB_TOKEN=${3}

NOW=$(cat ./VERSION)
NEW=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt | xargs)

printf '# %-10s: %-10s %-10s\n' "${REPONAME}" "${NOW}" "${NEW}"

if [ "${NOW}" != "${NEW}" ]; then
    printf "${NEW}" > VERSION
    sed -i -e "s/ENV VERSION .*/ENV VERSION ${NEW}/g" Dockerfile

    git config --global user.name "bot"
    git config --global user.email "ops@nalbam.com"

    git add --all
    git commit -m "${NEW}"
    git push -q https://${GITHUB_TOKEN}@github.com/${USERNAME}/${REPONAME}.git master

    echo "# git push github.com/${USERNAME}/${REPONAME} ${NEW}"

    git tag ${NEW}
    git push -q https://${GITHUB_TOKEN}@github.com/${USERNAME}/${REPONAME}.git ${NEW}
fi
