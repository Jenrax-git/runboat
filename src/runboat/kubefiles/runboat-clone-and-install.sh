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

# Download to a temporary directory first
TEMP_DIR=$(mktemp -d)
curl -sSL https://${GITHUB_TOKEN}@github.com/${RUNBOAT_GIT_REPO}/tarball/${RUNBOAT_GIT_REF} | tar zxf - --strip-components=1 -C $TEMP_DIR

# Check if it's a single module or a collection of modules
if [[ -f "$TEMP_DIR/__manifest__.py" || -f "$TEMP_DIR/__openerp__.py" ]]; then
    # It's a single module - extract repo name and create module directory
    REPO_NAME=$(basename ${RUNBOAT_GIT_REPO})
    MODULE_DIR="$ADDONS_DIR/$REPO_NAME"
    mkdir -p "$MODULE_DIR"
    cp -r "$TEMP_DIR"/* "$MODULE_DIR"/
    
    # Copy requirements files to addons root if they exist
    if [[ -f "$TEMP_DIR/requirements.txt" ]]; then
        cp "$TEMP_DIR/requirements.txt" "$ADDONS_DIR/"
    fi
    if [[ -f "$TEMP_DIR/test-requirements.txt" ]]; then
        cp "$TEMP_DIR/test-requirements.txt" "$ADDONS_DIR/"
    fi
else
    # It's a collection of modules - copy everything to addons dir
    cp -r "$TEMP_DIR"/* "$ADDONS_DIR"/
fi

# Clean up temporary directory
rm -rf "$TEMP_DIR"

cd $ADDONS_DIR

# Install.
INSTALL_METHOD=${INSTALL_METHOD:-oca_install_addons}
if [[ "${INSTALL_METHOD}" == "oca_install_addons" ]] ; then
    oca_install_addons
elif [[ "${INSTALL_METHOD}" == "editable_pip_install" ]] ; then
    pip install -e .
else
    echo "Unsupported INSTALL_METHOD: '${INSTALL_METHOD}'"
    exit 1
fi

# Keep a copy of the venv that we can re-use for shorter startup time.
cp -ar /opt/odoo-venv/ /mnt/data/odoo-venv

touch /mnt/data/initialized