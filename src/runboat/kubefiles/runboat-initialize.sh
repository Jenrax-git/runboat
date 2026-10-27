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
  # Prefer _lastdb of the source build (has preserved user data) over its fresh install.
  if psql postgres -lqt 2>/dev/null | cut -d'|' -f1 | grep -qw "${COPY_DB_FROM}_lastdb"; then
    echo "Found ${COPY_DB_FROM}_lastdb, using it as copy source to preserve user data."
    COPY_DB_FROM="${COPY_DB_FROM}_lastdb"
  fi
  echo "Copying database from ${COPY_DB_FROM} to ${PGDATABASE}_lastdb..."
  # createdb -T requires no active connections on the source DB.
  # Terminate them and retry up to 3 times to handle Odoo reconnects.
  _copy_ok=0
  for _attempt in 1 2 3; do
    psql postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${COPY_DB_FROM}' AND pid <> pg_backend_pid();" 2>/dev/null || true
    if createdb -T ${COPY_DB_FROM} ${PGDATABASE}_lastdb 2>/dev/null; then
      _copy_ok=1
      break
    fi
    echo "Attempt ${_attempt} failed (active connections?), retrying in 3s..."
    sleep 3
  done
  if [ ${_copy_ok} -eq 1 ]; then
    echo "Copy succeeded. Clearing asset bundle cache so Odoo regenerates them for the new filestore..."
    # Asset bundle files live in the source build's PVC filestore, which is inaccessible
    # from this pod. Deleting these ir.attachment records forces Odoo to regenerate
    # the assets during the module update below. Business record attachments (res_model
    # != 'ir.ui.view') are not touched.
    psql ${PGDATABASE}_lastdb -c "
      DELETE FROM ir_attachment
      WHERE store_fname IS NOT NULL
        AND (res_model IS NULL OR res_model = 'ir.ui.view');
    " 2>/dev/null || true
    echo "Updating modules for compatibility with current commit..."
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
    echo "ERROR: Copy from ${COPY_DB_FROM} failed after 3 attempts. Dropping ${PGDATABASE}_lastdb."
    dropdb --if-exists ${PGDATABASE}_lastdb
  fi
fi

# Clean up pre-reinit snapshot if one was made
if [ -n "${_COPY_DB_SNAPSHOT}" ]; then
  dropdb --if-exists ${_COPY_DB_SNAPSHOT}
fi
