#!/bin/bash
set -e;

main() {
    local exit_code_push=0;
    local exit_code_run=0;
    local gitssh_path;
    local ssh_key_path;

    gitssh_path="$(mktemp)";
    ssh_key_path="$(mktemp -d)/id_rsa";

    # Initialize some values
    init_wercker_environment_variables;
    init_git "$WERCKER_DOKKU_DEPLOY_USER" "$WERCKER_DOKKU_DEPLOY_HOST";
    init_gitssh "$gitssh_path" "$ssh_key_path";

    cd "$WERCKER_DOKKU_DEPLOY_SOURCE_DIR" || fail "could not change directory to source_dir \"$WERCKER_DOKKU_DEPLOY_SOURCE_DIR\""

    use_wercker_ssh_key "$ssh_key_path" "$WERCKER_DOKKU_DEPLOY_KEY_NAME";\

    # Then check if the user wants to use the git repository or use the files in the source directory
    if [ "$WERCKER_DOKKU_DEPLOY_KEEP_REPOSITORY" == "true" ]; then
        use_current_git_directory "$WERCKER_DOKKU_DEPLOY_SOURCE_DIR" "$WERCKER_GIT_BRANCH";
    else
        use_new_git_repository "$WERCKER_DOKKU_DEPLOY_SOURCE_DIR";
    fi

    # Try to push the code
    set +e;
    push_code "$WERCKER_DOKKU_DEPLOY_APP_NAME" "$WERCKER_DOKKU_DEPLOY_USER" "$WERCKER_DOKKU_DEPLOY_HOST";
    exit_code_push=$?
    set -e;

    # Retry pushing the code, if the first push failed and retry was not disabled
    if [ $exit_code_push -ne 0 ]; then
        if [ "$WERCKER_DOKKU_DEPLOY_RETRY" == "false" ]; then
            info "push failed, not going to retry";
        else
            info "push failed, retrying push in 5 seconds";
            sleep 5;

            set +e;
            push_code "$WERCKER_DOKKU_DEPLOY_APP_NAME";
            exit_code_push=$?
            set -e;
        fi
    fi

    if [ "$WERCKER_DOKKU_DEPLOY_INSTALL_TOOLBELT" == "true" -o -n "$WERCKER_DOKKU_DEPLOY_RUN" ]; then
        install_toolbelt;
    fi

    # Run a command, if the push succeeded and the user supplied a run command
    if [ -n "$WERCKER_DOKKU_DEPLOY_RUN" ]; then
        if [ $exit_code_push -eq 0 ]; then
            set +e;
            execute_dokku_command "$WERCKER_DOKKU_DEPLOY_APP_NAME" "$WERCKER_DOKKU_DEPLOY_RUN";
            exit_code_run=$?
            set -e;
        fi
    fi

    # Remove a auto generated key (assuming we generated a public key at ${ssh_key_path}.pub)
    if [ -z "$WERCKER_DOKKU_DEPLOY_KEY_NAME" ]; then
        remove_ssh_key "${ssh_key_path}.pub";
    fi

    if [ $exit_code_run -ne 0 ]; then
        fail 'dokku run failed';
    fi

    if [ $exit_code_push -eq 0 ]; then
        success 'deployment to dokku finished successfully';
    else
        fail 'git push to dokku failed';
    fi
}

init_wercker_environment_variables() {
    if [ -z "$WERCKER_DOKKU_DEPLOY_APP_NAME" ]; then
        export WERCKER_DOKKU_DEPLOY_APP_NAME="$DOKKU_APP_NAME";
    fi

    if [ -z "$WERCKER_DOKKU_DEPLOY_APP_NAME" ]; then
        fail "app-name is required. User app-name parameter or \$DOKKU_APP_NAME environment variable"
    fi

    if [ -z "$WERCKER_DOKKU_DEPLOY_HOST" ]; then
        fail "host is required. User host parameter or \$DOKKU_HOST environment variable"
    fi

    if [ -z "$WERCKER_DOKKU_DEPLOY_KEY_NAME" ]; then
        fail "key_name is required. Use key_name parameter or \$DOKKU_KEY_NAME environment variable"
    fi

    if [ -z "$WERCKER_DOKKU_DEPLOY_USER" ]; then
        if [ ! -z "$DOKKU_USER" ]; then
            export WERCKER_DOKKU_DEPLOY_USER="$DOKKU_USER";
        else
            export WERCKER_DOKKU_DEPLOY_USER="dokku";
        fi
    fi

    if [ -z "$WERCKER_DOKKU_DEPLOY_SOURCE_DIR" ]; then
        export WERCKER_DOKKU_DEPLOY_SOURCE_DIR="$WERCKER_ROOT";
        debug "option source_dir not set. Will deploy directory $WERCKER_DOKKU_DEPLOY_SOURCE_DIR";
    else
        warn "Use of source_dir is deprecated. Please make sure that you fix your Dokku deploy version on a major version."
        debug "option source_dir found. Will deploy directory $WERCKER_DOKKU_DEPLOY_SOURCE_DIR";
    fi
}

# init_git checks that git exists and is configured
init_git() {
    local username="$1";
    local host="$2";

    if ! type git &> /dev/null; then
        if ! type apt-get &> /dev/null; then
            fail "git is not available. Install it, and make sure it is available in \$PATH"
        else
            debug "git not found; installing it."

            sudo apt-get update;
            sudo apt-get install git-core -y;
        fi
    fi

    git config --global user.name "$username";
    git config --global user.email "$username@$host";
}

init_gitssh() {
    local gitssh_path="$1";
    local ssh_key_path="$2";

    echo "ssh -e none -i \"$ssh_key_path\" \$@" > "$gitssh_path";
    chmod 0700 "$gitssh_path";
    export GIT_SSH="$gitssh_path";
}

install_toolbelt() {
    if ! type dokku &> /dev/null; then
        info 'dokku toolbelt not found, starting installing it';

        # extract from $steproot/dokku-client.tgz into /usr/local/dokku
        sudo rm -rf /usr/local/dokku
        sudo cp -r "$WERCKER_STEP_ROOT/vendor/dokku" /usr/local/dokku
        export PATH="/usr/local/dokku/bin:$PATH"

        info 'finished dokku toolbelt installation';
    else
        info 'dokku toolbelt is available, and will not be installed by this step';
    fi

    debug "type dokku: $(type dokku)";
    debug "dokku version: $(dokku --version)";
}

use_wercker_ssh_key() {
    local ssh_key_path="$1";
    local wercker_ssh_key_name="$2";

    debug "will use specified key in key-name option: ${wercker_ssh_key_name}_PRIVATE";

    local private_key;
    private_key=$(eval echo "\$${wercker_ssh_key_name}_PRIVATE");

    if [ ! -n "$private_key" ]; then
        fail 'Missing key error. The key-name is specified, but no key with this name could be found. Make sure you generated an key, and exported it as an environment variable.';
    fi

    debug "writing key file to $ssh_key_path";
    echo -e "$private_key" > "$ssh_key_path";
    chmod 0600 "$ssh_key_path";
}

push_code() {
    local app_name="$1";
    local username="$2"
    local host="$3"

    debug "starting dokku deployment with git push";
    git remote add dokku "$username@$host:$app_name.git"
    git push -f dokku master;
    local exit_code_push=$?;

    debug "git pushed exited with $exit_code_push";
    return $exit_code_push;
}

execute_dokku_command() {
    local app_name="$1";
    local command="$2";

    debug "starting dokku run $command";
    dokku run "$command" --app "$app_name";
    local exit_code_run=$?;

    debug "dokku run exited with $exit_code_run";
    return $exit_code_run;
}

use_current_git_directory() {
    local working_directory="$1";
    local branch="$2";

    debug "keeping git repository"
    if [ -d "$working_directory/.git" ]; then
        debug "found git repository in $working_directory";
    else
        fail "no git repository found to push";
    fi

    git checkout "$branch"
}

use_new_git_repository() {
    local working_directory="$1"

    # If there is a git repository, remove it because
    # we want to create a new git repository to push
    # to dokku.
    if [ -d "$working_directory/.git" ]; then
        debug "found git repository in $working_directory"
        warn "Removing git repository from $working_directory"
        rm -rf "$working_directory/.git"

        #submodules found are flattened
        if [ -f "$working_directory/.gitmodules" ]; then
            debug "found possible git submodule(s) usage"
            while IFS= read -r -d '' file
            do
                rm -f "$file" && warn "Removed submodule $file"
            done < <(find "$working_directory" -type f -name ".git" -print0)
        fi
    fi

    # Create git repository and add all files.
    # This repository will get pushed to dokku.
    git init
    git add .
    git commit -m 'wercker deploy'
}

check_curl() {
    if ! type curl &> /dev/null; then
        if ! type apt-get &> /dev/null; then
            fail "curl is not available. Install it, and make sure it is available in \$PATH"
        else
            debug "curl not found; installing it."

            sudo apt-get update;
            sudo apt-get install curl -y;
        fi
    fi
}

main;
