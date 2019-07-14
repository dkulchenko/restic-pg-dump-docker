#!/bin/bash

set -e

setup.sh

export HOSTNAME_VAR="HOSTNAME"
export PGHOST_VAR="PGHOST"
export PGPASSWORD_VAR="PGPASSWORD"
export PGPORT_VAR="PGPORT"
export PGUSER_VAR="PGUSER"
export PGDATABASE_VAR="PGDATABASE"

export HOSTNAME="${!HOSTNAME_VAR:-$PGHOST_$i}"
export PGHOST="${!PGHOST_VAR}"
export PGPASSWORD="${!PGPASSWORD_VAR}"
export PGPORT="${!PGPORT_VAR:-5432}"
export PGUSER="${!PGUSER_VAR}"
export PGDATABASE="${!PGDATABASE_VAR:-postgres}"

# No more databases.
for var in PGHOST PGUSER; do
	[[ -z "${!var}" ]] && {
		echo "Forgetting old snapshots"
		while ! restic forget \
				--compact \
				--keep-hourly="${RESTIC_KEEP_HOURLY:-24}" \
				--keep-daily="${RESTIC_KEEP_DAILY:-7}" \
				--keep-weekly="${RESTIC_KEEP_WEEKLY:-4}" \
				--keep-monthly="${RESTIC_KEEP_MONTHLY:-12}"; do
			echo "Sleeping for 10 seconds before retry..."
			sleep 10
		done

		restic check --no-lock

		echo 'Finished backup successfully'

		exit 0
	}
done

echo "Dumping database cluster $i: $PGUSER@$PGHOST:$PGPORT/$PGDATABASE"

# Wait for PostgreSQL to become available.
COUNT=0
until psql -l -d "$PGDATABASE"; do
	if [[ "$COUNT" == 0 ]]; then
		echo "Waiting for PostgreSQL to become available..."
	fi
	(( COUNT += 1 ))
	sleep 1
done
if (( COUNT > 0 )); then
	echo "Waited $COUNT seconds."
fi

mkdir -p "/pg_dump"

echo "Dumping database '$PGDATABASE'"
pg_dump --file="/pg_dump/$PGDATABASE.sql" --no-owner --no-privileges --dbname="$PGDATABASE"

echo "Sending database dumps to S3"
while ! restic backup --host "$HOSTNAME" "/pg_dump"; do
	echo "Sleeping for 10 seconds before retry..."
	sleep 10
done

echo 'Finished sending database dumps to S3'

rm -rf "/pg_dump"
