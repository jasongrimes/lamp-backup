#!/bin/bash

#
# A basic script for backing up a LAMP server.
#
# See https://github.com/jasongrimes/lamp-backup for details.
#
# Copyright 2014 Jason Grimes <jason@grimesit.com>
#

STARTTIME=$(date +%s)
ERROR=0

THIS_SCRIPT=`basename $0`
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR=${CONFIG_DIR:-$(readlink -f $THIS_DIR/../etc)}
DEFAULT_OUTPUT_BASE_DIR=/var/backup
DEFAULT_DIRS="/var/www /etc/apache2 /etc/php5 /var/log"
DEFAULT_EXCLUDE_PATTERNS="core *~"

usage() {
    echo "Usage: $THIS_SCRIPT [options]"
    echo ""
    echo "$THIS_SCRIPT is a simple tool for backing up files and MySQL databases."
    echo ""
    echo "Options:"
    echo "  -o OUTPUT_DIR, --output-dir=OUTPUT_DIR"
    echo "                         Base directory in which to store backups."
    echo "                         (Default: '$DEFAULT_OUTPUT_BASE_DIR')"
    echo "  -d DIRS, --dirs=DIRS   Directories to back up."
    echo "                         (Default: '$DEFAULT_DIRS')"
    echo "  -e PATTERNS, --exclude=PATTERNS"
    echo "                         Exclude files matching these patterns."
    echo "                         (Default: '$DEFAULT_EXCLUDE_PATTERNS')"
    echo "  -c FILE, --mysql-conf=FILE"
    echo "                         A MySQL config file with connection information."
    echo "                         (Default: '$CONFIG_DIR/mysql-connection.cfg')"
    echo "  -s FILE, -s3-conf=FILE An s3cmd config file with connection info for Amazon S3."
    echo "                         (Default: '/root/.s3cfg')"
    echo "  -p S3_PATH, --s3-path=S3_PATH"
    echo "                         The Amazon S3 path to copy files to (ex. s3://my-bucket/my-folder/)."
    echo "  --do-files             Back up and compress files. (Enabled by default.)"
    echo "  --no-files             Don't back up and compress files."
    echo "  --do-mysql             Back up MySQL databases. (Enabled by default.)"
    echo "  --no-mysql             Don't back up MySQL databases."
    echo "  --do-s3                Copy backups to Amazon S3. Enabled by default if S3 is configured."
    echo "  --no-s3                Don't copy backups to Amazon S3."
    echo "  --do-rotate            Rotate old backups. (Enabled by default.)"
    echo "  --no-rotate            Don't rotate old backups."
    echo "  -q, --quiet            Quiet"
    echo "  -v, --verbose          Verbose"
    echo "  --help                 Print this help screen"
    echo ""
    echo "For more information, see: https://github.com/jasongrimes/lamp-backup"
    echo ""
}

# Send the output of the given command to /dev/null unless VERBOSE >= 2
redirect_output() {
    if [ "$VERBOSE" -ge 2 ]; then
        "$@"
    else
        "$@" > /dev/null
    fi
}

# Source config file, if it exists.
CONFIG_FILE=${CONFIG_FILE:-$CONFIG_DIR/lamp-backup.conf}
if [ -r "$CONFIG_FILE" ]; then
    . $CONFIG_FILE
fi

#
# Parse command line arguments
#

# We need OPTS as the `eval set --' would nuke the return value of getopt.
OPTS=`getopt -o o:d:e:c:s:p:qv --long help,quiet,verbose,output:,dirs:,exclude:,mysql-conf:,s3-conf:,s3-path:,do-files,no-files,do-mysql,no-mysql,do-rotate,no-rotate,do-s3,no-s3 -n $THIS_SCRIPT -- "$@"`
if [ $? != 0 ] ; then usage >&2 ; exit 1 ; fi
eval set -- "$OPTS"
while true; do
    case "$1" in
        -o|--output) OUTPUT_BASE_DIR="$2"; shift 2 ;;
        -d|--dirs) DIRS="$2"; shift 2 ;;
        -e|--exclude) EXCLUDE_PATTERNS="$2"; shift 2 ;;
        -c|--mysql-conf) MYSQL_CONF="$2"; shift 2 ;;
        -s|--s3-conf) S3_CONF="$2"; shift 2 ;;
        -p|--s3-path) S3_PATH="$2"; shift 2 ;;
        --do-files) DO_FILES=1; shift ;;
        --no-files) DO_FILES=0; shift ;;
        --do-mysql) DO_MYSQL=1; shift ;;
        --no-mysql) DO_MYSQL=0; shift ;;
        --do-s3) DO_S3=1; shift ;;
        --no-s3) DO_S3=0; shift ;;
        --do-rotate) DO_ROTATE=1; shift ;;
        --no-rotate) DO_ROTATE=0; shift ;;
        -q|--quiet) VERBOSE=0; shift ;;
        -v|--verbose) VERBOSE=2; shift ;;
        --help) usage >&2; exit 0 ;;
        --) shift ; break ;;
    esac
done

#
# Set defaults. Any of these could optionally be defined in the external config file (../etc/lamp-backup.conf).
#
TAR=${TAR:-/bin/tar}
MYSQL_BACKUP=${MYSQL_BACKUP:-$THIS_DIR/mysql-backup.sh}
ROTATE_CMD=${ROTATE_CMD:-$THIS_DIR/lamp-backup-rotate.sh}
S3CMD=${S3CMD:-/usr/bin/s3cmd}
VERBOSE=${VERBOSE:-1}
OUTPUT_BASE_DIR=${OUTPUT_BASE_DIR:-$DEFAULT_OUTPUT_BASE_DIR}
DIRS=${DIRS:-$DEFAULT_DIRS}
EXCLUDE_PATTERNS=${EXCLUDE_PATTERNS:-$DEFAULT_EXCLUDE_PATTERNS}
DO_FILES=${DO_FILES:-1}
DO_MYSQL=${DO_MYSQL:-1}
DO_ROTATE=${DO_ROTATE:-1}
S3_CONF=${S3_CONF:-/root/.s3cfg}
if [ -z "$DO_S3" ]; then
    if [ -n "$S3_PATH" ]; then
        DO_S3=1;
    else
        DO_S3=0;
    fi
fi

# Create output directory
date=`date +%Y-%m-%d-%s`
outdir=backup_$date
fullpath=$OUTPUT_BASE_DIR/$outdir
if [ "$VERBOSE" -ge 1 ]; then echo "Creating $fullpath"; fi
mkdir -p $fullpath
chmod 700 $fullpath
if [ ! -w $fullpath ]; then
    echo "Error creating output directory '$fullpath'" >&2
    echo "Aborting." >&2
    exit 1
fi

# Do MySQL backup
if [ "$DO_MYSQL" -gt 0 ]; then
    blockstarttime=$(date +%s)

    if [ "$VERBOSE" -ge 1 ]; then
        echo "--------------------------";
        echo "Backing up MySQL databases";
        echo "--------------------------";
    fi

    dumpdir=$fullpath/mysqldump
    if [ "$VERBOSE" -ge 2 ]; then echo "Creating $dumpdir"; fi
    mkdir -p $dumpdir

    mysql_args="-o $dumpdir"
    if [ -n "$MYSQL_CONF" ]; then mysql_args="$mysql_args -c $MYSQL_CONF"; fi
    if [ "$VERBOSE" -eq 0 ]; then mysql_args="$mysql_args -q";
    elif [ "$VERBOSE" -eq 2 ]; then mysql_args="$mysql_args -vv"; fi

    cmd="$MYSQL_BACKUP $mysql_args"
    if [ "$VERBOSE" -ge 2 ]; then echo "  Executing command: $cmd"; fi
    CONFIG_DIR=$CONFIG_DIR $cmd

    if [ $? -eq 0 ]; then
        if [ "$VERBOSE" -ge 1 ]; then echo "Compressing $dumpdir"; fi
        $TAR czf $dumpdir.tgz -C $fullpath mysqldump && rm -rf $dumpdir
        chmod 0600 $dumpdir.tgz
    else
        ERROR=1
    fi

    if [ "$VERBOSE" -ge 1 ]; then
        now=$(date +%s)
        echo "Elapsed time: $((now - $blockstarttime)) seconds."
    fi
fi

# Do file backup
if [ "$DO_FILES" -gt 0 ]; then
    blockstarttime=$(date +%s)

    if [ "$VERBOSE" -ge 1 ]; then
        echo "------------------";
        echo "Backing up files";
        echo "------------------";
    fi

    exclude_ops=""
    for exclude in $EXCLUDE_PATTERNS; do
        exclude_ops="$exclude_ops --exclude='$exclude'"
    done

    for dir in $DIRS; do
        tarfile=$fullpath/$(echo $dir | tr '/' '_' | sed -r 's/^_//').tgz
        if [ "$VERBOSE" -ge 1 ]; then echo "Backing up $dir to $tarfile"; fi

        cmd="$TAR czfp $tarfile $exclude_ops -C / .${dir}"
        if [ "$VERBOSE" -ge 2 ]; then echo "  Executing command: $cmd"; fi
        $cmd
        if [ "$?" -ge 1 ]; then
            ERROR=1
        fi

        chmod 0600 $tarfile
    done

    if [ "$VERBOSE" -ge 1 ]; then
        echo "File backup complete."
        now=$(date +%s)
        echo "Elapsed time: $((now - $blockstarttime)) seconds."
    fi
fi

# Copy to S3
if [ "$DO_S3" -gt 0 ]; then
    blockstarttime=$(date +%s)

    if [ "$VERBOSE" -ge 1 ]; then
        echo "--------------------";
        echo "Copying to Amazon S3";
        echo "--------------------";
    fi
    if [ ! -x "$S3CMD" ]; then
        echo "Error: s3cmd not found at '$S3CMD'. Skipping copy to S3." >&2;
        ERROR=1
    elif [ ! -r "$S3_CONF" ]; then
        echo "Error: S3 config file '$S3_CONF' not found. Skipping copy to S3." >&2;
        ERROR=1
    elif [ -z "$S3_PATH" ]; then
        echo "Error: S3 path not defined." >&2;
        echo "Specify with the -p parameter, or set the S3_PATH option in the config file." >&2
        echo "Run '$THIS_SCRIPT --help' for details." >&2
        echo "Skipping copy to S3." >&2
        ERROR=1
    else
        if [ "$VERBOSE" -ge 1 ]; then echo "Copying $fullpath to $S3_PATH"; fi
        cmd="$S3CMD -c $S3_CONF put --recursive $fullpath $S3_PATH"
        if [ "$VERBOSE" -ge 2 ]; then echo "  Executing command: $cmd"; fi
        redirect_output $cmd

        if [ "$?" -ge 1 ]; then
            ERROR=1
        fi

        if [ "$VERBOSE" -ge 1 ]; then
            echo "Copy to S3 complete."
            now=$(date +%s)
            echo "Elapsed time: $((now - $blockstarttime)) seconds."
        fi
    fi
fi

# Rotate old backups
if [ "$DO_ROTATE" -eq 1 ]; then
    if [ "$ERROR" -ge 1 ]; then
        echo "Skipping backup rotation because an error occurred." >&2
    else
        if [ "$VERBOSE" -ge 1 ]; then
            echo "---------------------";
            echo "Rotating old backups";
            echo "---------------------";
        fi

        rotate_args="--force"
        if [ "$DO_S3" -gt 0 ]; then rotate_args="$rotate_args --do-s3"
        else rotate_args="$rotate_args --no-s3"
        fi
        if [ "$DO_FILES" -gt 0 ]; then rotate_args="$rotate_args --do-local"
        else rotate_args="$rotate_args --no-local"
        fi
        if [ -n "$S3_CONF" ]; then rotate_args="$rotate_args --s3-conf=$S3_CONF"; fi
        if [ -n "$S3_PATH" ]; then rotate_args="$rotate_args --s3-path=$S3_PATH"; fi

        if [ "$VERBOSE" -eq 0 ]; then rotate_args="$rotate_args -q";
        elif [ "$VERBOSE" -eq 2 ]; then rotate_args="$rotate_args -v";
        fi

        cmd="$ROTATE_CMD $rotate_args"
        if [ "$VERBOSE" -ge 2 ]; then echo "  Executing command: $cmd"; fi
        CONFIG_DIR=$CONFIG_DIR $cmd
    fi
fi

# Summary
if [ "$VERBOSE" -ge 0 ]; then
    echo "---------------"
    echo "Backup complete"
    echo "---------------"
    now=$(date +%s)
    echo "Elapsed time: $((now - $STARTTIME)) seconds."
    echo "Disk space used:"
    du -sh $fullpath
    echo "Disk space available on backup partition:"
    df -h $OUTPUT_BASE_DIR
fi

if [ "$ERROR" -ge 1 ]; then
    echo "---------------------" >&2
    echo "ERROR RUNNING BACKUP" >&2
    echo "---------------------" >&2
    echo "The backup may have partially completed, but there was at least one error." >&2
    echo "Check above for any error messages." >&2
    echo "Try running with the --verbose option if you need help troubleshooting." >&2
    exit 1
fi
