#!/bin/bash

set -exo pipefail

# Remove initialization sentinel and data, in case we are reinitializing.
rm -fr /mnt/data/*

# Remove addons dir, in case we are reinitializing after a previously
# failed installation.
rm -fr $ADDONS_DIR

# Download the repository at git reference into $ADDONS_DIR.
# We use curl instead of git clone because the git clone method used more than 1GB RAM,
# which exceeded the default pod memory limit.
mkdir -p $ADDONS_DIR
cd $ADDONS_DIR

echo "Downloading repository: ${RUNBOAT_GIT_REPO}@${RUNBOAT_GIT_REF}"

# Determine GitHub token with fallbacks
GITHUB_AUTH_TOKEN="${RUNBOAT_GITHUB_TOKEN:-${GITHUB_TOKEN:-${TOKEN:-${GH_TOKEN:-}}}}"

if [ -n "$GITHUB_AUTH_TOKEN" ]; then
    echo "Using GitHub token for authentication"
else
    echo "No authentication token available, attempting public access"
fi

# Download repository with authentication or fallback to public
download_repository() {
    local repo="$1"
    local ref="$2"
    local is_private="$3"
    
    local url=""
    local http_code=""
    
    if [ "$is_private" = "true" ] && [ -n "$GITHUB_AUTH_TOKEN" ]; then
        # Try authenticated download first
        url="https://${GITHUB_AUTH_TOKEN}@github.com/${repo}/tarball/${ref}"
        http_code=$(curl -s -w "%{http_code}" -L -o tarball.tar.gz "$url")
        
        if [ "$http_code" = "200" ] && tar -tzf tarball.tar.gz >/dev/null 2>&1; then
            tar zxf tarball.tar.gz --strip-components=1
            rm tarball.tar.gz
            return 0
        fi
        
        echo "Authenticated download failed, trying public access..."
        rm -f tarball.tar.gz
    fi
    
    # Public download
    url="https://github.com/${repo}/tarball/${ref}"
    http_code=$(curl -s -w "%{http_code}" -L -o tarball.tar.gz "$url")
    
    if [ "$http_code" = "200" ] && tar -tzf tarball.tar.gz >/dev/null 2>&1; then
        tar zxf tarball.tar.gz --strip-components=1
        rm tarball.tar.gz
        return 0
    else
        echo "ERROR: Failed to download repository ${repo}"
        rm -f tarball.tar.gz
        return 1
    fi
}

# Process addons-requirements.txt file
process_addons_requirements() {
    local requirements_file="$1"
    
    if [ ! -f "$requirements_file" ]; then
        return 0
    fi
    
    echo "Processing ${requirements_file}..."
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Parse line: format: repo@ref#private or repo@ref#public
        local repo_spec="$line"
        local repo_url=""
        local branch="main"
        local is_private="false"
        
        # Extract authentication requirement
        if [[ "$repo_spec" == *"#private" ]]; then
            is_private="true"
            repo_spec="${repo_spec%#private}"
        elif [[ "$repo_spec" == *"#public" ]]; then
            is_private="false"
            repo_spec="${repo_spec%#public}"
        fi
        
        # Extract branch
        if [[ "$repo_spec" == *"@"* ]]; then
            repo_url="${repo_spec%@*}"
            branch="${repo_spec#*@}"
        else
            repo_url="$repo_spec"
        fi
        
        # Create temporary directory for this repository
        local temp_dir=$(mktemp -d)
        cd "$temp_dir"
        
        # Download the repository
        if download_repository "$repo_url" "$branch" "$is_private"; then
            # Detect if it's a root module and reorganize if needed
            if detect_root_module; then
                reorganize_root_module "$repo_url"
            fi
            
            # Move content to addons directory
            find . -maxdepth 1 -mindepth 1 -not -name "." -not -name ".." -exec mv {} "${ADDONS_DIR}/" \;
        else
            cd "$ADDONS_DIR"
            rm -rf "$temp_dir"
            return 1
        fi
        
        # Return to addons directory
        cd "$ADDONS_DIR"
        rm -rf "$temp_dir"
    done < "$requirements_file"
    
    return 0
}

# Detect if repository is an Odoo module at root
detect_root_module() {
    if [ -f "__manifest__.py" ] || [ -f "__openerp__.py" ]; then
        return 0
    fi
    return 1
}

# Reorganize root modules
reorganize_root_module() {
    local repo_name="$1"
    if [ -z "$repo_name" ]; then
        repo_name=$(basename "${RUNBOAT_GIT_REPO}")
    else
        repo_name=$(basename "$repo_name")
    fi
    
    echo "Reorganizing root module: creating folder '$repo_name'"
    
    # Create temporary directory to move files
    mkdir -p temp_module
    
    # Move all files and directories to temporary directory
    find . -maxdepth 1 -mindepth 1 -not -name temp_module -not -name "." -not -name ".." -exec mv {} temp_module/ \;
    
    # Create module folder
    mkdir -p "$repo_name"
    
    # Move everything back to module folder
    if [ -d "temp_module" ] && [ "$(ls -A temp_module 2>/dev/null)" ]; then
        mv temp_module/* "$repo_name/" 2>/dev/null || true
        mv temp_module/.* "$repo_name/" 2>/dev/null || true
    fi
    
    # Clean temporary directory
    rmdir temp_module 2>/dev/null || true
}

# Install Python requirements from all subdirectories
install_all_python_requirements() {
    local base_path="$1"
    
    echo "Installing Python requirements from all modules..."
    
    # Find all requirements.txt files in subdirectories
    while IFS= read -r -d '' file; do
        echo "Installing Python requirements from: $file"
        pip install -r "$file"
    done < <(find "$base_path" -name "requirements.txt" -type f -print0 2>/dev/null)
}

# Download main repository
if [ -n "$GITHUB_AUTH_TOKEN" ]; then
    if ! download_repository "${RUNBOAT_GIT_REPO}" "${RUNBOAT_GIT_REF}" "true"; then
        echo "ERROR: Failed to download main repository"
        exit 1
    fi
else
    if ! download_repository "${RUNBOAT_GIT_REPO}" "${RUNBOAT_GIT_REF}" "false"; then
        echo "ERROR: Failed to download main repository"
        exit 1
    fi
fi

# Check if it's a root module and reorganize if needed
if detect_root_module; then
    reorganize_root_module
fi

# Install Python requirements for main repository
install_all_python_requirements "."

# Process addons-requirements.txt if exists
REQUIREMENTS_FOUND=false

# Check in current directory
if [ -f "addons-requirements.txt" ]; then
    if ! process_addons_requirements "addons-requirements.txt"; then
        echo "ERROR: Failed to process addons-requirements.txt"
        exit 1
    fi
    REQUIREMENTS_FOUND=true
fi

# Check in subdirectories if not found in root
if [ "$REQUIREMENTS_FOUND" = "false" ]; then
    while IFS= read -r -d '' file; do
        if ! process_addons_requirements "$file"; then
            echo "ERROR: Failed to process addons-requirements.txt"
            exit 1
        fi
        REQUIREMENTS_FOUND=true
        break
    done < <(find . -name "addons-requirements.txt" -type f -print0 2>/dev/null)
fi

# Install Python requirements for all modules after all downloads are complete
install_all_python_requirements "${ADDONS_DIR}"

# Set default INSTALL_METHOD if not provided
INSTALL_METHOD=${INSTALL_METHOD:-oca_install_addons}
echo "Starting installation with method: ${INSTALL_METHOD}"

if [[ "${INSTALL_METHOD}" == "oca_install_addons" ]] ; then
    oca_install_addons
elif [[ "${INSTALL_METHOD}" == "editable_pip_install" ]] ; then
    pip install -e .
else
    echo "ERROR: Unsupported INSTALL_METHOD: '${INSTALL_METHOD}'"
    exit 1
fi

# Keep a copy of the venv that we can re-use for shorter startup time.
cp -ar /opt/odoo-venv/ /mnt/data/odoo-venv

echo "Initialization completed"
touch /mnt/data/initialized