#!/bin/bash

#
# Back up all databases from a MySQL server with mysqldump, one database per file.
#
# See https://github.com/jasongrimes/lamp-backup for details.
#
# Copyright 2014 Jason Grimes <jason@grimesit.com>
#

THIS_SCRIPT=`basename $0`
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR=${CONFIG_DIR:-$(readlink -f $THIS_DIR/../etc/)}
DEFAULT_MYSQL_CONF=$CONFIG_DIR/mysql-connection.cnf
DEFAULT_SKIP_DBS="information_schema performance_schema"

usage() {
    echo "Usage: $THIS_SCRIPT [options]"
    echo ""
    echo "Back up MySQL databases with mysqldump, one database per file."
    echo ""
    echo "Options:"
    echo "  -o DIR, --output=DIR   Directory in which to save dumpfiles. (Default: '.')"
    echo "  -c FILE, --defaults-extra-file=FILE"
    echo "                         A MySQL config file with connection information."
    echo "                         (Default: '$DEFAULT_MYSQL_CONF')"
    echo "  -u USER, --user=USER   The MySQL username."
    echo "  -p [PASSWORD], --password[=PASSWORD]"
    echo "                         The MySQL password. A prompt is shown if PASSWORD is omitted."
    echo "                         Warning: specifying the password on the command line is insecure (visible with 'ps', etc.)."
    echo "                         It's recommended to specify it in the MySQL config file instead."
    echo "  -h HOST, --host=HOST   The MySQL hostname."
    echo "  -P PORT, --port=PORT   The MySQL port."
    echo "  -s DBS, --skip-dbs=DBS A list of databases *not* to dump. (Default: '$DEFAULT_SKIP_DBS')"
    echo "  -q, --quiet            Quiet."
    echo "  -v, --verbose          Verbose."
    echo "  -vv, --verbose=2       Very verbose."
    echo "  --help                 Print this help screen."
    echo ""
    echo "For more information, see: https://github.com/jasongrimes/lamp-backup"
    echo ""
}

# Test whether the given value is in the given array.
# Call it like this: if [ `in_array $needle "${haystack[@]}"` ]; then ...
function in_array() {
  NEEDLE="$1"; shift; ARRAY=("$@")
  for VALUE in ${ARRAY[@]}; do [ "$VALUE" == "$NEEDLE" ] && echo 1 && return; done
}

# Source the config file, if any.
CONFIG_FILE=${CONFIG_FILE:-$(readlink -f $THIS_DIR/../etc/mysql-backup.conf)}
if [ -r "$CONFIG_FILE" ]; then
    . $CONFIG_FILE
fi

#
# Parse command line arguments
#

# We need OPTS as the `eval set --' would nuke the return value of getopt.
OPTS=`getopt -o qu:h:P:p::v::o:c: --long help,quiet,user:,host:,port:,password::,verbose::,output:,defaults-extra-file: -n $THIS_SCRIPT -- "$@"`
if [ $? != 0 ] ; then usage >&2 ; exit 1 ; fi
eval set -- "$OPTS"
while true; do
    case "$1" in
        -q|--quiet) VERBOSE=0; shift ;;
        -v|--verbose)
            if [ "$2" = "2" -o "$2" = "v" ]; then
                VERBOSE=2
            else
                VERBOSE=1
            fi
            shift 2
            ;;
        -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
        -c|--defaults-extra-file) MYSQL_CONF="$2"; shift 2 ;;
        -u|--user) MYSQL_USER="$2"; shift 2 ;;
        -h|--host) MYSQL_HOST=$2; shift 2 ;;
        -P|--port) MYSQL_PORT=$2; shift 2 ;;
        -p|--password)
            # p has an optional argument. As we are in quoted mode,
            # an empty parameter will be generated if its optional
            # argument is not found.
            MYSQL_PASS=$2;
            if [ -z $MYSQL_PASS ]; then
                NEED_MYSQL_PASS="y"
            fi
            shift 2
            ;;
        -s|--skip-dbs) SKIP_DBS="$2"; shift 2 ;;
        --help) usage >&2; exit 0 ;;
        --) shift ; break ;;
    esac
done

# Get mysql pass, if necessary
if [ "$NEED_MYSQL_PASS" = "y" ]; then
    read -s -p 'Enter mysql password: ' MYSQL_PASS
    echo "" >&2
fi

#
# Set defaults.
# Any of these could optionally be defined in an external config file as well (default: ../etc/mysql-backup.conf)
#
MYSQL=${MYSQL:-/usr/bin/mysql}
MYSQLADMIN=${MYSQLADMIN:-/usr/bin/mysqladmin}
MYSQLDUMP=${MYSQLDUMP:-/usr/bin/mysqldump}
VERBOSE=${VERBOSE:-1}
SKIP_DBS=${SKIP_DBS:-$DEFAULT_SKIP_DBS}
OUTPUT_DIR=${OUTPUT_DIR:-.}
MYSQL_CONF=${MYSQL_CONF:-$DEFAULT_MYSQL_CONF}

# MYSQL_HOST=${MYSQL_HOST:-localhost}
# MYSQL_USER=${MYSQL_USER:-root}

#
# Validate arguments
#
if [ -z "$OUTPUT_DIR" ]; then
    echo "Error: OUTPUT_DIR not specified." >&2
    echo "Pass the -o option or set OUTPUT_DIR in $CONFIG_FILE." >&2
    echo "Pass --help for details." >&2
    exit 1;
fi

OUTPUT_DIR=$(readlink -f $OUTPUT_DIR) # Convert into an absolute path, if necessary
if [ ! -d $OUTPUT_DIR ]; then echo "Output directory '$OUTPUT_DIR' does not exist."; exit 1; fi
if [ ! -w $OUTPUT_DIR ]; then echo "Output directory '$OUTPUT_DIR' is not writeable."; exit 1; fi

# Create MySQL connection arguments
MYSQL_CONN_ARGS=''
if [ -n "$MYSQL_CONF" -a -r "$MYSQL_CONF" ]; then MYSQL_CONN_ARGS="$MYSQL_CONN_ARGS --defaults-extra-file=$MYSQL_CONF"; fi
if [ -n "$MYSQL_USER" ]; then MYSQL_CONN_ARGS="$MYSQL_CONN_ARGS -u$MYSQL_USER"; fi
#if [ -n "$MYSQL_PASS" ]; then MYSQL_CONN_ARGS="$MYSQL_CONN_ARGS -p$MYSQL_PASS"; fi # Pass it in an environment variable instead, so it's not visible in the process list.
if [ -n "$MYSQL_HOST" ]; then MYSQL_CONN_ARGS="$MYSQL_CONN_ARGS -h$MYSQL_HOST"; fi
if [ -n "$MYSQL_PORT" ]; then MYSQL_CONN_ARGS="$MYSQL_CONN_ARGS -P$MYSQL_PORT"; fi

# Test connecting to MySQL server
if [ "$VERBOSE" -ge 2 ]; then echo "Testing connection to MySQL server"; fi
MYSQL_PWD=$MYSQL_PASS $MYSQLADMIN $MYSQL_CONN_ARGS status >/dev/null
if [ $? != 0 ] ; then echo "Aborting."; exit 1 ; fi

# if [ "$VERBOSE" -ge 1 ]; then echo "Writing dump files to $OUTPUT_DIR..."; fi

# Get list of dbs
if [ "$VERBOSE" -ge 2 ]; then echo "Getting database list"; fi
dbs=$(MYSQL_PWD=$MYSQL_PASS $MYSQL $MYSQL_CONN_ARGS --batch --skip-column-names -e 'SHOW DATABASES')
for db in $dbs; do
    if [ `in_array $db "${SKIP_DBS[@]}"` ]; then continue; fi
    if [ "$VERBOSE" -ge 1 ]; then echo "Dumping database '$db' to $OUTPUT_DIR/$db.sql"; fi

    #tables=$($MYSQL --batch --skip-column-names $MYSQL_CONN_ARGS -e "SHOW TABLES FROM $db")

    # Determine if this database has any non-InnoDB tables.
    # If so, we need to get a read lock.
    non_innodb_tables=$(MYSQL_PWD=$MYSQL_PASS $MYSQL $MYSQL_CONN_ARGS --batch --skip-column-names -e "SELECT TABLE_NAME FROM information_schema.tables WHERE TABLE_SCHEMA='$db' AND ENGINE != 'InnoDB'");
    if [ ! -z "$non_innodb_tables" ]; then
        if [ "$VERBOSE" -ge 2 ]; then echo "  Database contains non-InnoDB tables. Acquiring read lock."; fi
        LOCK_ARGS="--lock-tables"
    else
        LOCK_ARGS="--single-transaction --skip-lock-tables"
    fi

    mysql_cmd="$MYSQLDUMP $MYSQL_CONN_ARGS --ignore-table=mysql.event --opt $LOCK_ARGS $db"
    if [ "$VERBOSE" -ge 2 ]; then echo "  Executing command: $mysql_cmd >$OUTPUT_DIR/$db.sql"; fi
    MYSQL_PWD=$MYSQL_PASS $mysql_cmd >$OUTPUT_DIR/$db.sql
done

if [ "$VERBOSE" -ge 1 ]; then echo "Database backup complete."; fi

