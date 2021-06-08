#!/bin/bash
#
# Copyright (C) 2018 Google Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
# Enable bash debug if DEBUG_DOCKER_ENTERYPOINT exists
if [[ ! -z "${DEBUG_DOCKER_ENTERYPOINT}" ]]; then
	echo "!!! WARNING: DEBUG_DOCKER_ENTERYPOINT is enabled!"
	echo "!!! WARNING: Use only for debugging. Do not use in production!"
	set -x
fi

set -eo pipefail
shopt -s nullglob

# if command starts with an option, prepend mysqld
if [ "${1:0:1}" = '-' ]; then
	set -- mysqld "$@"
fi

# skip setup if they want an option that stops mysqld
wantHelp=
for arg; do
	case "$arg" in
		-'?'|--help|--print-defaults|-V|--version)
			wantHelp=1
			break
			;;
	esac
done
# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		mysql_error "Both $var and $fileVar are set (but are exclusive)"
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}
# Fetch value from server config
# We use mysqld --verbose --help instead of my_print_defaults because the
# latter only show values present in config files, and not server defaults
mysql_get_config() {
	local conf="$1"; shift
	"$@" "${_verboseHelpArgs[@]}" 2>/dev/null \
		| awk -v conf="$conf" '$1 == conf && /^[^ \t]/ { sub(/^[^ \t]+[ \t]+/, ""); print; exit }'
	# match "datadir      /some/path with/spaces in/it here" but not "--xyz=abc\n     datadir (xyz)"
}

# Do a temporary startup of the MariaDB server, for init purposes
docker_temp_server_start() {
	"$@" --skip-networking --socket="${SOCKET}" --wsrep_on=OFF &
	mysql_note "Waiting for server startup"
	# only use the root password if the database has already been initializaed
	# so that it won't try to fill in a password file when it hasn't been set yet
	extraArgs=()
	if [ -z "$DATABASE_ALREADY_EXISTS" ]; then
		extraArgs+=( '--dont-use-mysql-root-password' )
	fi
	local i
	for i in {30..0}; do
		if docker_process_sql "${extraArgs[@]}" --database=mysql <<<'SELECT 1' &> /dev/null; then
			break
		fi
		sleep 1
	done
	if [ "$i" = 0 ]; then
		mysql_error "Unable to start server."
	fi
}

# Stop the server. When using a local socket file mysqladmin will block until
# the shutdown is complete.
docker_temp_server_stop() {
	if ! MYSQL_PWD=$MARIADB_ROOT_PASSWORD mysqladmin shutdown -uroot --socket="${SOCKET}"; then
		mysql_error "Unable to shut down server."
	fi
}

# Verify that the minimally required password settings are set for new databases.
docker_verify_minimum_env() {
	if [ -z "$MARIADB_ROOT_PASSWORD" -a -z "$MARIADB_ALLOW_EMPTY_ROOT_PASSWORD" -a -z "$MARIADB_RANDOM_ROOT_PASSWORD" ]; then
		mysql_error $'Database is uninitialized and password option is not specified\n\tYou need to specify one of MARIADB_ROOT_PASSWORD, MARIADB_ALLOW_EMPTY_ROOT_PASSWORD and MARIADB_RANDOM_ROOT_PASSWORD'
	fi
}

# creates folders for the database
	mkdir -p "$DATADIR"

	if [ "$user" = "0" ]; then
		# this will cause less disk access than `chown -R`
		find "$DATADIR" \! -user mysql -exec chown mysql '{}' +
		# See https://github.com/MariaDB/mariadb-docker/issues/363
		find "${SOCKET%/*}" -maxdepth 0 \! -user mysql -exec chown mysql '{}' \;
	fi
}

# initializes the database directory
docker_init_database_dir() {
	mysql_note "Initializing database files"
	installArgs=( --datadir="$DATADIR" --rpm --auth-root-authentication-method=normal )
	if { mysql_install_db --help || :; } | grep -q -- '--skip-test-db'; then
		# 10.3+
		installArgs+=( --skip-test-db )
	fi
	# "Other options are passed to mysqld." (so we pass all "mysqld" arguments directly here)
	mysql_install_db "${installArgs[@]}" "${@:2}"
	mysql_note "Database files initialized"
}

# Loads various settings that are used elsewhere in the script
# This should be called after mysql_check_config, but before any other functions
docker_setup_env() {
	# Get config
	declare -g DATADIR SOCKET
	DATADIR="$(mysql_get_config 'datadir' "$@")"
	SOCKET="$(mysql_get_config 'socket' "$@")"


	# Initialize values that might be stored in a file
	_mariadb_file_env 'MYSQL_ROOT_HOST' '%'
	_mariadb_file_env 'MYSQL_DATABASE'
	_mariadb_file_env 'MYSQL_USER'
	_mariadb_file_env 'MYSQL_PASSWORD'
	_mariadb_file_env 'MYSQL_ROOT_PASSWORD'

	# set MARIADB_ from MYSQL_ when it is unset and then make them the same value
	: "${MARIADB_ALLOW_EMPTY_ROOT_PASSWORD:=${MYSQL_ALLOW_EMPTY_PASSWORD:-}}"
	export MYSQL_ALLOW_EMPTY_PASSWORD="$MARIADB_ALLOW_EMPTY_ROOT_PASSWORD" MARIADB_ALLOW_EMPTY_ROOT_PASSWORD
	: "${MARIADB_RANDOM_ROOT_PASSWORD:=${MYSQL_RANDOM_ROOT_PASSWORD:-}}"
	export MYSQL_RANDOM_ROOT_PASSWORD="$MARIADB_RANDOM_ROOT_PASSWORD" MARIADB_RANDOM_ROOT_PASSWORD
	: "${MARIADB_INITDB_SKIP_TZINFO:=${MYSQL_INITDB_SKIP_TZINFO:-}}"
	export MYSQL_INITDB_SKIP_TZINFO="$MARIADB_INITDB_SKIP_TZINFO" MARIADB_INITDB_SKIP_TZINFO

	declare -g DATABASE_ALREADY_EXISTS
	if [ -d "$DATADIR/mysql" ]; then
		DATABASE_ALREADY_EXISTS='true'
	fi
}
	# Generate random root password
	if [ -n "$MARIADB_RANDOM_ROOT_PASSWORD" ]; then
		MARIADB_ROOT_PASSWORD="$(pwgen --numerals --capitalize --symbols --remove-chars="'\\" -1 32)"
		export MARIADB_ROOT_PASSWORD MYSQL_ROOT_PASSWORD=$MARIADB_ROOT_PASSWORD
		mysql_note "GENERATED ROOT PASSWORD: $MARIADB_ROOT_PASSWORD"
	fi
	# Sets root password and creates root users for non-localhost hosts
	local rootCreate=
	local rootPasswordEscaped
	rootPasswordEscaped=$( docker_sql_escape_string_literal "${MARIADB_ROOT_PASSWORD}" )

	# default root to listen for connections from anywhere
	if [ -n "$MARIADB_ROOT_HOST" ] && [ "$MARIADB_ROOT_HOST" != 'localhost' ]; then
		# no, we don't care if read finds a terminating character in this heredoc
		# https://unix.stackexchange.com/questions/265149/why-is-set-o-errexit-breaking-this-read-heredoc-expression/265151#265151
		read -r -d '' rootCreate <<-EOSQL || true
			CREATE USER 'root'@'${MARIADB_ROOT_HOST}' IDENTIFIED BY '${rootPasswordEscaped}' ;
			GRANT ALL ON *.* TO 'root'@'${MARIADB_ROOT_HOST}' WITH GRANT OPTION ;
		EOSQL
	fi
	# Creates a custom database and user if specified
	if [ -n "$MARIADB_DATABASE" ]; then
		mysql_note "Creating database ${MARIADB_DATABASE}"
		docker_process_sql --database=mysql <<<"CREATE DATABASE IF NOT EXISTS \`$MARIADB_DATABASE\` ;"
	fi

	if [ -n "$MARIADB_USER" ] && [ -n "$MARIADB_PASSWORD" ]; then
		mysql_note "Creating user ${MARIADB_USER}"
		# SQL escape the user password, \ followed by '
		local userPasswordEscaped
		userPasswordEscaped=$( docker_sql_escape_string_literal "${MARIADB_PASSWORD}" )
		docker_process_sql --database=mysql --binary-mode <<-EOSQL_USER
			SET @@SESSION.SQL_MODE=REPLACE(@@SESSION.SQL_MODE, 'NO_BACKSLASH_ESCAPES', '');
			CREATE USER '$MARIADB_USER'@'%' IDENTIFIED BY '$userPasswordEscaped';
		EOSQL_USER

		if [ -n "$MARIADB_DATABASE" ]; then
			mysql_note "Giving user ${MARIADB_USER} access to schema ${MARIADB_DATABASE}"
			docker_process_sql --database=mysql <<<"GRANT ALL ON \`${MARIADB_DATABASE//_/\\_}\`.* TO '$MARIADB_USER'@'%' ;"
		fi
	fi
}

# check arguments for an option that would cause mysqld to stop
# return true if there is one
_mysql_want_help() {
	local arg
	for arg; do
		case "$arg" in
			-'?'|--help|--print-defaults|-V|--version)
				return 0
				;;
		esac
	done
	return 1
}

_main() {
	# if command starts with an option, prepend mysqld
	if [ "${1:0:1}" = '-' ]; then
		set -- mysqld "$@"
	fi

	# skip setup if they aren't running mysqld or want an option that stops mysqld
	if [ "$1" = 'mariadbd' ] || [ "$1" = 'mysqld' ] && ! _mysql_want_help "$@"; then
		mysql_note "Entrypoint script for MariaDB Server ${MARIADB_VERSION} started."

		mysql_check_config "$@"
		# Load various environment variables
		docker_setup_env "$@"
		docker_create_db_directories

		# If container is started as root user, restart as dedicated mysql user
		if [ "$(id -u)" = "0" ]; then
			mysql_note "Switching to dedicated user 'mysql'"
			exec gosu mysql "$BASH_SOURCE" "$@"
		fi

		# there's no database, so it needs to be initialized
		if [ -z "$DATABASE_ALREADY_EXISTS" ]; then
			docker_verify_minimum_env

			# check dir permissions to reduce likelihood of half-initialized database
			ls /docker-entrypoint-initdb.d/ > /dev/null

			docker_init_database_dir "$@"

			mysql_note "Starting temporary server"
			docker_temp_server_start "$@"
			mysql_note "Temporary server started."

			docker_setup_db
			docker_process_init_files /docker-entrypoint-initdb.d/*

			mysql_note "Stopping temporary server"
			docker_temp_server_stop
			mysql_note "Temporary server stopped"

			echo
			mysql_note "MariaDB init process done. Ready for start up."
			echo
		fi
	fi
	exec "$@"
}
