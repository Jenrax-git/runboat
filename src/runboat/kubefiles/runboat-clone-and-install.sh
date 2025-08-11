#!/bin/bash

set -exo pipefail

# Remove previous initialization sentinel and data
rm -fr /mnt/data/*

# Remove addons directory in case of reinitialization after a failed installation
rm -fr $ADDONS_DIR

# Download repository at git reference into $ADDONS_DIR
mkdir -p $ADDONS_DIR
cd $ADDONS_DIR

# Function to determine which GitHub token to use with multiple fallbacks
determine_github_token() {
    if [ -n "$RUNBOAT_GITHUB_TOKEN" ]; then
        echo "$RUNBOAT_GITHUB_TOKEN"
        return 0
    elif [ -n "$GITHUB_TOKEN" ]; then
        echo "$GITHUB_TOKEN"
        return 0
    elif [ -n "$TOKEN" ]; then
        echo "$TOKEN"
        return 0
    elif [ -n "$GH_TOKEN" ]; then
        echo "$GH_TOKEN"
        return 0
    else
        return 1
    fi
}

# Select authentication token if available
if GITHUB_AUTH_TOKEN=$(determine_github_token); then
    echo "Using GitHub authentication token"
else
    GITHUB_AUTH_TOKEN=""
    echo "No GitHub authentication token found, using public access"
fi

# Function to download using authentication
download_with_auth() {
    local method="$1"
    local url="$2"
    shift 2
    local curl_headers=("$@")
    
    local temp_output=$(mktemp)
    
    if [ ${#curl_headers[@]} -gt 0 ]; then
        curl -s -w "%{http_code}" -L "${curl_headers[@]}" -o tarball.tar.gz "$url" > "$temp_output"
    else
        curl -s -w "%{http_code}" -L -o tarball.tar.gz "$url" > "$temp_output"
    fi
    
    HTTP_CODE=$(cat "$temp_output")
    rm -f "$temp_output"
    
    if [ "$HTTP_CODE" = "200" ] && tar -tzf tarball.tar.gz >/dev/null 2>&1; then
        tar zxf tarball.tar.gz --strip-components=1
        rm tarball.tar.gz
        return 0
    else
        rm -f tarball.tar.gz
        return 1
    fi
}

# Function to download public repository
download_public() {
    local url="https://github.com/${RUNBOAT_GIT_REPO}/tarball/${RUNBOAT_GIT_REF}"
    
    local temp_output=$(mktemp)
    curl -s -w "%{http_code}" -L -o tarball.tar.gz "$url" > "$temp_output"
    HTTP_CODE=$(cat "$temp_output")
    rm -f "$temp_output"
    
    if [ "$HTTP_CODE" = "200" ] && tar -tzf tarball.tar.gz >/dev/null 2>&1; then
        tar zxf tarball.tar.gz --strip-components=1
        rm tarball.tar.gz
        return 0
    else
        rm -f tarball.tar.gz
        return 1
    fi
}

# Download process
if [ -n "$GITHUB_AUTH_TOKEN" ]; then
    if ! download_with_auth "token_in_url" \
        "https://${GITHUB_AUTH_TOKEN}@github.com/${RUNBOAT_GIT_REPO}/tarball/${RUNBOAT_GIT_REF}"; then
        if ! download_with_auth "authorization_bearer" \
            "https://github.com/${RUNBOAT_GIT_REPO}/tarball/${RUNBOAT_GIT_REF}" \
            "-H" "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
            "-H" "Accept: application/vnd.github.v3.raw"; then
            if ! download_with_auth "authorization_token" \
                "https://github.com/${RUNBOAT_GIT_REPO}/tarball/${RUNBOAT_GIT_REF}" \
                "-H" "Authorization: token ${GITHUB_AUTH_TOKEN}" \
                "-H" "Accept: application/vnd.github.v3.raw"; then
                if ! download_with_auth "github_api" \
                    "https://api.github.com/repos/${RUNBOAT_GIT_REPO}/tarball/${RUNBOAT_GIT_REF}" \
                    "-H" "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
                    "-H" "Accept: application/vnd.github+json"; then
                    if ! download_public; then
                        exit 1
                    fi
                fi
            fi
        fi
    fi
else
    if ! download_public; then
        exit 1
    fi
fi

# Detect if the repository is an Odoo module in root
detect_root_module() {
    if [ -f "__manifest__.py" ] || [ -f "__openerp__.py" ]; then
        return 0
    fi
    return 1
}

# Reorganize module to be inside a folder if it is in the root
reorganize_root_module() {
    local repo_name=$(basename "${RUNBOAT_GIT_REPO}")
    mkdir -p temp_module
    find . -maxdepth 1 -mindepth 1 -not -name temp_module -not -name "." -not -name ".." -exec mv {} temp_module/ \;
    mkdir -p "$repo_name"
    if [ -d "temp_module" ] && [ "$(ls -A temp_module 2>/dev/null)" ]; then
        mv temp_module/* "$repo_name/" 2>/dev/null || true
        mv temp_module/.* "$repo_name/" 2>/dev/null || true
    fi
    rmdir temp_module 2>/dev/null || true
}

if detect_root_module; then
    reorganize_root_module
fi

INSTALL_METHOD=${INSTALL_METHOD:-oca_install_addons}

if [[ "${INSTALL_METHOD}" == "oca_install_addons" ]] ; then
    oca_install_addons
elif [[ "${INSTALL_METHOD}" == "editable_pip_install" ]] ; then
    pip install -e .
else
    exit 1
fi

# Save venv copy for faster future startups
cp -ar /opt/odoo-venv/ /mnt/data/odoo-venv

touch /mnt/data/initialized
