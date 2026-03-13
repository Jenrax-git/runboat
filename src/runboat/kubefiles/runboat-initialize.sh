#!/bin/bash

#
# Clone repo and install all addons in the test database.
#

set -ex

bash /runboat/runboat-clone-and-install.sh

oca_wait_for_postgres

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
  --stop-after-init || dropdb --if-exists ${PGDATABASE} && exit 0

# Copy source DB to _lastdb if COPY_DB_FROM is set
if [ -n "${COPY_DB_FROM:-}" ]; then
  createdb -T template0 ${PGDATABASE}_lastdb
  if pg_dump -Fc ${COPY_DB_FROM} | pg_restore -d ${PGDATABASE}_lastdb --no-owner --no-acl; then
    # Update repo modules for compatibility with current commit
    unbuffer $(which odoo || which openerp-server) \
      --data-dir=/mnt/data/odoo-data-dir \
      -d ${PGDATABASE}_lastdb \
      -u ${ADDONS:-base} \
      --stop-after-init || { dropdb --if-exists ${PGDATABASE}_lastdb; true; }
  else
    dropdb --if-exists ${PGDATABASE}_lastdb
  fi
fi
