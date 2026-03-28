#!/bin/bash

#
# Clone repo and install all addons in the test database.
#

set -ex

bash /runboat/runboat-clone-and-install.sh

oca_wait_for_postgres

# If COPY_DB_FROM points to the current database (redeploy case), snapshot it
# before wiping so _lastdb ends up with the pre-reinit data, not the fresh install.
_COPY_DB_SNAPSHOT=""
if [ -n "${COPY_DB_FROM:-}" ] && [ "${COPY_DB_FROM}" = "${PGDATABASE}" ]; then
  echo "COPY_DB_FROM is self; snapshotting ${PGDATABASE} before reinit..."
  if createdb -T ${PGDATABASE} ${PGDATABASE}_snapshot 2>/dev/null; then
    _COPY_DB_SNAPSHOT=${PGDATABASE}_snapshot
    COPY_DB_FROM=${PGDATABASE}_snapshot
  else
    echo "No existing DB to snapshot (first init?), skipping _lastdb copy."
    COPY_DB_FROM=""
  fi
fi

# Drop database, in case we are reinitializing.
dropdb --if-exists ${PGDATABASE}
dropdb --if-exists ${PGDATABASE}-baseonly
dropdb --if-exists ${PGDATABASE}_lastdb

ADDONS=$(manifestoo --select-addons-dir ${ADDONS_DIR} --select-include "${INCLUDE}" --select-exclude "${EXCLUDE}" list --separator=,)

# In Odoo 19+, demo data is not loaded by default. We enable it via $ODOO_RC,
# because --with-demo does not exists in previous version and would error out,
# while unknown options in the configuration file are ignored.
echo "with_demo = True" >> $ODOO_RC

# Create the baseonly database if installation failed.
unbuffer $(which odoo || which openerp-server) \
  --data-dir=/mnt/data/odoo-data-dir \
  --db-template=template1 \
  -d ${PGDATABASE}-baseonly \
  -i base \
  --stop-after-init

# Try to install all addons, but do not fail in case of error, to let the build start
# so users can work with the 'baseonly' database.
unbuffer $(which odoo || which openerp-server) \
  --data-dir=/mnt/data/odoo-data-dir \
  --db-template=template1 \
  -d ${PGDATABASE} \
  -i ${ADDONS:-base} \
  --stop-after-init || { dropdb --if-exists ${PGDATABASE} && exit 0; }

# Copy source DB to _lastdb if COPY_DB_FROM is set
if [ -n "${COPY_DB_FROM:-}" ]; then
  echo "Copying database from ${COPY_DB_FROM} to ${PGDATABASE}_lastdb..."
  if createdb -T ${COPY_DB_FROM} ${PGDATABASE}_lastdb; then
    echo "Copy succeeded. Updating modules for compatibility with current commit..."
    if unbuffer $(which odoo || which openerp-server) \
      --data-dir=/mnt/data/odoo-data-dir \
      -d ${PGDATABASE}_lastdb \
      -u ${ADDONS:-base} \
      --stop-after-init; then
      echo "Module update succeeded for ${PGDATABASE}_lastdb."
    else
      echo "WARNING: Module update failed for ${PGDATABASE}_lastdb. Keeping database as-is (may need manual update)."
    fi
  else
    echo "ERROR: Copy from ${COPY_DB_FROM} failed. Dropping ${PGDATABASE}_lastdb."
    dropdb --if-exists ${PGDATABASE}_lastdb
  fi
fi

# Clean up pre-reinit snapshot if one was made
if [ -n "${_COPY_DB_SNAPSHOT}" ]; then
  dropdb --if-exists ${_COPY_DB_SNAPSHOT}
fi
