#!/bin/bash

# This script can build a release branch, or update an existing release branch.
# It doesn't care which branch you're currently standing on.
#
# Building a new set of release branches: "new" | "-n"
# It takes a parameter "new", which should only be used when preparing a new major release (x.x), not a point release.
#
# The "new" parameter will request a version number. It should be the version format "x.x" (example 4.9)
# It will then create a new (unbuilt) branch with the specific naming convention of "release-branch-x.x", and push it to the repo.
# It will also create another (built) branch with the specific naming convention of "release-branch-x.x-built",
#   push it to the repo, and build a production version to it.
#
# Updating an existing built branch: "update" | "-u"
# The "update" parameter will request an existing branch name to build to.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

# Exit the build in scary red text if error
function exit_build {
    echo -e "${RED}Something went wrong and the build has stopped.  See error above for more details."
    exit 1
}
trap 'exit_build' ERR

# Instructions
function usage {
    echo "usage: $0 [-n --new] [-u --update <branchname>]"
    echo "  -n      Create new release branches"
    echo "  -u      Update existing release built branch"
    echo "          Can take an extra param that refers to an existing branch."
    echo "          Example: $0 -u master"
    echo "  -h      help"
    exit 1
}

function takeyourtime() {
    local message=${1:-Building will resume}
    local seconds=${2}
    while [ "${seconds}" -gt 0 ]; do
        echo -ne "$message in $seconds seconds. Press Ctrl+C to abort\033[0K\r"
        sleep 1
        : $((seconds--))
    done
    echo
}

function purgesvn() {
#    DIR=$(dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" )
    # @todo get the right path always? Or be opinionated about where the script should be running from?
    DIR=$(pwd)
    echo -e "${GREEN}Purging paths included in .svnignore${RESET}"
    # check .svnignore
    for file in $( cat "$DIR/.svnignore" 2>/dev/null ); do
        rm -rf $file
        echo $file >> $DIR/.gitignore
        echo -e "    ${YELLOW}$file was removed and added to this branch's .gitignore${RESET}"
    done

    git commit -am "Cleared .svnignore files and added to this branch .gitignore"
    echo $(git status)
}

# This function will create a new release branch.
# The branch format will be release-branch-x.x
# These branches will be created off of master
function create_new_release_branch {

    # Prompt for version number.
    read -p "$(echo -e $YELLOW"What version are you releasing? Please write in x.x syntax: "$RESET)" version
    NEW_RELEASE_BRANCH="release-branch-$version"

    # Bail if branch already exists
    if [[ -n $( git branch -r | grep "$NEW_RELEASE_BRANCH" ) ]]; then
        echo -e "${RED}$NEW_RELEASE_BRANCH already exists.${RESET} Exiting..."
        exit 1
    fi

    # Prompt for source branch
    read -p "$(echo -e $YELLOW"Which branch would you like to base the release branch on? (or hit enter for master)"$RESET)" branch

    # Declare the new branch names.
    BRANCH=${branch:-master}

    echo -e "${GREEN}Fetching latest...${RESET}"
    echo `git fetch origin`

    # Create new branch, push to repo
    git checkout origin/$BRANCH
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne "0" ]; then
        echo -e "${RED}Whoops!${RESET}"
        exit 1
    fi

    echo ""
    echo -e "${GREEN}Creating new branch $NEW_RELEASE_BRANCH${RESET}"
    echo ""

    echo `git checkout -b $NEW_RELEASE_BRANCH`
    echo -e "Now standing on new release branch $NEW_RELEASE_BRANCH. $YELLOW'git status' shows:$RESET"
    echo $(git status)
    echo ""

    purgesvn

    read -p "$(echo -e "The above output is the 'git status' of the local release branch. "$GREEN"Push to repo? [y/N]"$RESET)" -n 1 -r
    if [[ $REPLY != "y" && $REPLY != "Y" ]]; then
        exit 1
    fi

    echo "Pushing to repo..."
    echo ""
    if git push -u origin $NEW_RELEASE_BRANCH | grep "error:"; then
        echo "whoops!"
        echo ""
        exit 1
    fi

    echo ""
    echo -e "${GREEN}New branch $NEW_RELEASE_BRANCH successfully created!${RESET}"
    echo ""

    read -p "Would you like to create a new tag for the beta release? [y/N]" -n 1 -r
    if [[ $REPLY != "y" && $REPLY != "Y" ]]; then
        echo -e "${GREEN}All done!${RESET}"
        exit 1
    else
        echo ""
        echo "It's not written yet :("
    fi

    exit 1
}

function update_release_branch {
    # Current directory and current branch vars
    DIR=$(dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" )
    CURRENT_BRANCH=$( git branch | grep -e "^*" | cut -d' ' -f 2 )

    TMP_REMOTE_BUILT_VERSION="/tmp/release-plugin"
    TMP_LOCAL_BUILT_VERSION="/tmp/release-plugin-2"

    # Make sure we don't have uncommitted changes.
    if [[ -n $( git status -s --porcelain ) ]]; then
        echo "Uncommitted changes found."
        echo "Please deal with them and try again clean."
        exit 1
    fi

    # Cast the branch name that we'll be building to a single var.
    if [[ -n $NEW_RELEASE_BRANCH ]]; then
        BUILD_TARGET=$NEW_RELEASE_BRANCH
    elif [[ -n $UPDATE_RELEASE_BRANCH ]]; then
        BUILD_TARGET=$UPDATE_RELEASE_BRANCH
    else
        echo ""
        echo "No target branch specified.  How did you make it this far?"
        exit 1
    fi

    ### This bit is the engine that will build a branch and push to another one ####

    # Make sure we're trying to deploy something that exists.
    if [[ -z $( git branch -r | grep "$BUILD_TARGET" ) ]]; then
        echo "Branch $BUILD_TARGET not found in git repository."
        echo ""
        exit 1
    fi

    read -p "You are about to update the $BUILD_TARGET branch from the $CURRENT_BRANCH branch. Are you sure? [y/N]" -n 1 -r
    if [[ $REPLY != "y" && $REPLY != "Y" ]]; then
        exit 1
    fi
    echo ""

    # Prep a home to drop our new files in. Just make it in /tmp so we can start fresh each time.
    rm -rf $TMP_REMOTE_BUILT_VERSION
    rm -rf $TMP_LOCAL_BUILT_VERSION

    echo "Rsync'ing everything over from Git except for .git and npm stuffs."
    rsync -r --exclude='*.git*' --exclude=node_modules $DIR/* $TMP_LOCAL_BUILT_VERSION
    echo "Done!"

    echo "Pulling latest from $BUILD_TARGET branch"
    CLONE_URL="$(git config --get remote.origin.url)"
    git clone --depth 1 -b $BUILD_TARGET --single-branch $CLONE_URL $TMP_REMOTE_BUILT_VERSION
    echo "Done!"

    echo "Rsync'ing everything over remote version"
    rsync -r --delete $TMP_LOCAL_BUILT_VERSION/* $TMP_REMOTE_BUILT_VERSION
    echo "Done!"

    cd $TMP_REMOTE_BUILT_VERSION

    echo "Finally, Committing and Pushing"
    git add .
    git commit -am 'New build'
    git push origin $BUILD_TARGET
    echo "Done! Branch $BUILD_TARGET has been updated."

    echo "Cleaning up the mess"
    cd $DIR
    rm -rf $TMP_REMOTE_BUILT_VERSION
    rm -rf $TMP_LOCAL_BUILT_VERSION
    echo "All clean!"
}



# Script parameter, what do you want to do?
# Expected to be "-n", "new", "-u", or "update"
COMMAND=$1

# Check the command
if [[ '--new' == $COMMAND || '-n' == $COMMAND ]]; then
    create_new_release_branch
elif [[ '--update' = $COMMAND || '-u' = $COMMAND ]]; then
    # It's possible they passed the branch name directly to the script
    if [[ -z $2 ]]; then
        read -p "What release branch are you updating? (enter just version number i.e. X.X): " version
        UPDATE_RELEASE_BRANCH="release-branch-$version"
    else
        UPDATE_RELEASE_BRANCH=$2
    fi

    update_release_branch
else
    usage
fi

