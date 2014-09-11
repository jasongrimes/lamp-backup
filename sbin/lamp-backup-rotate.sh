#!/bin/bash
#
# Rotate (delete old) backups made by lamp-backup.sh.
#
# See https://github.com/jasongrimes/lamp-backup for details.
#
# Copyright 2014 Jason Grimes <jason@grimesit.com>
#

THIS_SCRIPT=`basename $0`
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR=$(readlink -f $THIS_DIR/../etc)

usage() {
    echo "Usage: $THIS_SCRIPT [options]"
    echo ""
    echo "Rotate (delete old) backups made by lamp-backup.sh."
    echo ""
    echo "Options:"
    echo "  -d BACKUP_DIR, --backup-dir=BACKUP_DIR"
    echo "                         The base directory in which backups are stored."
    echo "  --do-local             Rotate backups locally."
    echo "  --no-local             Don't rotate backups locally."
    echo "  --keep-num-recent=N    Keep the N most recent backups on the local system, where N is an integer."
    echo "                         Set to -1 to keep all."
    echo "  --keep-num-monthlies=N Keep N monthly backups (the backup taken on the first day of the month) on the local system."
    echo "                         Set to -1 to keep all."
    echo "  --keep-one-per-day     If set, keep only one backup for any given day on the local system. (The most recent one.)"
    echo "  --do-s3                Rotate backups on Amazon S3."
    echo "  --no-s3                Don't rotate backups on Amazon S3."
    echo "  --s3-keep-num-recent=N Keep the N most recent backups on S3, where N is an integer."
    echo "                         Set to -1 to keep all."
    echo "  --s3-keep-num-monthlies=N"
    echo "                         Keep N monthly backups (the backup taken on the first day of the month) on S3."
    echo "                         Set to -1 to keep all."
    echo "  --s3-keep-one-per-day  If set, keep only one backup for any given day on S3. (The most recent one.)"
    echo "  -s FILE, -s3-conf=FILE An s3cmd config file with connection info for Amazon S3."
    echo "                         (Default: '/root/.s3cfg')"
    echo "  -p S3_PATH, --s3-path=S3_PATH"
    echo "                         The Amazon S3 path in which backups are stored."
    echo "  -n, --dry-run          Only show what directories would be deleted, but don't actually do it."
    echo "  -f, --force            Don't prompt for confirmation before removing the old backups."
    echo "  -q, --quiet            Quiet"
    echo "  -v, --verbose          Verbose"
    echo "  --help                 Print this help screen"
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

redirect_output() {
    if [ "$VERBOSE" -eq 0 ]; then
        "$@" > /dev/null
    else
        "$@"
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
OPTS=`getopt -o d:s:p:nfqv --long backup-dir:,do-local,no-local,keep-num-recent:,keep-num-monthlies:,keep-one-per-day,do-s3,no-s3,s3-keep-num-recent:,s3-keep-num-monthlies:,s3-keep-one-per-day,s3-conf:,s3-path:,dry-run,force,quiet,verbose,help -n $THIS_SCRIPT -- "$@"`
if [ $? != 0 ] ; then usage >&2 ; exit 1 ; fi
eval set -- "$OPTS"
while true; do
    case "$1" in
        -d|--backup-dir) OUTPUT_BASE_DIR="$2"; shift 2 ;;
        --do-local) DO_ROTATE_LOCAL=1; shift ;;
        --no-local) DO_ROTATE_LOCAL=0; shift ;;
        --keep-num-recent) KEEP_NUM_RECENT="$2"; shift 2 ;;
        --keep-num-monthlies) KEEP_NUM_MONTHLIES="$2"; shift 2 ;;
        --keep-one-per-day) KEEP_ONE_PER_DAY=1; shift ;;
        --do-s3) DO_ROTATE_S3=1; shift ;;
        --no-s3) DO_ROTATE_S3=0; shift ;;
        --s3-keep-num-recent) S3_KEEP_NUM_RECENT="$2"; shift 2 ;;
        --s3-keep-num-monthlies) S3_KEEP_NUM_MONTHLIES="$2"; shift 2 ;;
        --s3-keep-one-per-day) S3_KEEP_ONE_PER_DAY=1; shift ;;
        -s|--s3-conf) S3_CONF="$2"; shift 2 ;;
        -p|--s3-path) S3_PATH="$2"; shift 2 ;;
        -n|--dry-run) DRY_RUN=1; shift ;;
        -f|--force) NO_PROMPT=1; shift ;;
        -q|--quiet) VERBOSE=0; shift ;;
        -v|--verbose) VERBOSE=2; shift ;;
        --help) usage >&2; exit 0 ;;
        --) shift ; break ;;
    esac
done

#
# Set defaults. Any of these could optionally be defined in the external config file (../etc/lamp-backup.conf).
#
OUTPUT_BASE_DIR=${OUTPUT_BASE_DIR:-/var/backup}
S3CMD=${S3CMD:-/usr/bin/s3cmd}
DO_ROTATE_LOCAL=${DO_ROTATE_LOCAL:-1}
KEEP_NUM_RECENT=${KEEP_NUM_RECENT:--1}
KEEP_NUM_MONTHLIES=${KEEP_NUM_MONTHLIES:--1}
KEEP_ONE_PER_DAY=${KEEP_ONE_PER_DAY:-1}
if [ -z "$DO_ROTATE_S3" ]; then
    if [ -n "$S3_PATH" ]; then
        DO_ROTATE_S3=1;
    else
        DO_ROTATE_S3=0;
    fi
fi
S3_KEEP_NUM_RECENT=${S3_KEEP_NUM_RECENT:--1}
S3_KEEP_NUM_MONTHLIES=${S3_KEEP_NUM_MONTHLIES:--1}
S3_KEEP_ONE_PER_DAY=${S3_KEEP_ONE_PER_DAY:-1}
S3_CONF=${S3_CONF:-/root/.s3cfg}
DRY_RUN=${DRY_RUN:-0}
VERBOSE=${VERBOSE:-1}
NO_PROMPT=${NO_PROMPT:-0}

#
# Validate arguments
#
if [ -z "$OUTPUT_BASE_DIR" ]; then
    echo "Error: No backup directory specified. Use the -d argument." >&2
    exit 1
fi
if [ ! -w "$OUTPUT_BASE_DIR" ]; then
    echo "Error: Backup directory '$OUTPUT_BASE_DIR' is not writeable." >&2
    exit 1
fi
if [ "$DO_ROTATE_S3" -eq 1 ]; then
    if [ ! -x "$S3CMD" ]; then
        echo "Error: s3cmd not found at '$S3CMD'." >&2;
        exit 1
    elif [ ! -r "$S3_CONF" ]; then
        echo "Error: S3 config file '$S3_CONF' not found." >&2;
        exit 1
    elif [ -z "$S3_PATH" ]; then
        echo "Error: S3 path not defined." >&2;
        exit 1
    fi
fi

# Determine local backups to rotate
if [ "$DO_ROTATE_LOCAL" -gt 0 ]; then
    # Get the list of backups.
    backups=$(ls -d -r -1 $OUTPUT_BASE_DIR/backup_20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*)

    # Determine what to keep and what to remove.
    kept_dates=""
    dirs_to_remove=""
    dirs_to_keep=""
    num_kept_recents=0
    num_kept_monthlies=0
    for fullpath in $backups; do
        dir=$(basename $fullpath)
        datepart=${dir:7:10}

        if [ "$VERBOSE" -ge 2 ]; then
            echo "Checking $dir"
        fi

        # If the directory is empty, remove it and continue.
       if [ -z "$(ls -A $fullpath)" ]; then
            if [ "$VERBOSE" -ge 2 ]; then echo "  Marking $dir for removal because it is empty."; fi
            dirs_to_remove="$dirs_to_remove $fullpath"
            continue
       fi

        # If we've already seen this date and we're only keeping one per day, remove it and continue.
        if [ "$KEEP_ONE_PER_DAY" -eq 1 ]; then
            if [ "`in_array $datepart "${kept_dates[@]}"`" ]; then
                if [ "$VERBOSE" -ge 2 ]; then echo "  Marking $dir for removal because there's a more recent backup from $datepart."; fi
                dirs_to_remove="$dirs_to_remove $fullpath"
                continue
            fi
        fi

        # Test if it's a "monthly" backup, i.e. the date is the first day of the month.
        if [ "${datepart:8:2}" = "01" ]; then
            is_monthly=1
        else
            is_monthly=0
        fi

        # If it's not a monthly backup, and we've maxed out the number of recents to keep, remove it and continue.
        if [ "$KEEP_NUM_RECENT" -ne "-1" ]; then
            if [ "$is_monthly" -eq "0" -a "$num_kept_recents" -ge "$KEEP_NUM_RECENT" ]; then
                if [ "$VERBOSE" -ge 2 ]; then echo "  Marking $dir for removal because it exceeds the number of recent backups to keep ($KEEP_NUM_RECENT)."; fi
                dirs_to_remove="$dirs_to_remove $fullpath"
                continue
            fi
        fi

        # If it's a monthly backup, and we've maxed out the number of recents and monthlies to keep, remove it and continue.
        if [ "$KEEP_NUM_MONTHLIES" -ne "-1" ]; then
            if [ "$is_monthly" -eq "1" -a "$num_kept_monthlies" -ge "$KEEP_NUM_MONTHLIES" ]; then
                if [ "$VERBOSE" -ge 2 ]; then echo "  Marking $dir for removal because it exceeds the number of monthly backups to keep ($KEEP_NUM_MONTHLIES)."; fi
                dirs_to_remove="$dirs_to_remove $fullpath"
                continue
            fi
        fi

        # Add it to the list of kept backups.
        kept_dates="$kept_dates $datepart"
        dirs_to_keep="$dirs_to_keep $fullpath"

        # Increment the numbers of backups kept.
        if [ "$is_monthly" -eq 1 ]; then
            num_kept_monthlies=$(($num_kept_monthlies + 1))
        else
            num_kept_recents=$(($num_kept_recents + 1))
        fi
    done
fi

# Determine S3 backups to rotate
if [ "$DO_ROTATE_S3" -gt 0 ]; then
    # Get the list of backups.
    backups=$($S3CMD -c $S3_CONF ls $S3_PATH | awk '{ print $2 }')

    # Determine what to keep and what to remove.
    s3_kept_dates=""
    s3_dirs_to_remove=""
    s3_dirs_to_keep=""
    s3_num_kept_recents=0
    s3_num_kept_monthlies=0
    for fullpath in $backups; do
        # if [ "$fullpath" = "DIR" ]; then continue; fi

        dir=$(basename "$fullpath")
        if [ -z "$(echo $dir | egrep -o 'backup_20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*')" ]; then
            if [ "$VERBOSE" -ge 2 ]; then
                echo "Skipping $fullpath because it does not have the format of a backup directory name."
                continue;
            fi
        fi

        datepart=${dir:7:10}

        if [ "$VERBOSE" -ge 2 ]; then
            echo "Checking $fullpath"
        fi

        # If the directory is empty, remove it and continue.
        files=$($S3CMD -c $S3_CONF ls $fullpath | awk '{ print $4 }')
        if [ "${#files[@]}" -eq 1 -a "$files" = "$fullpath" ]; then
            if [ "$VERBOSE" -ge 2 ]; then echo "  Marking $dir for removal because it is empty."; fi
            s3_dirs_to_remove="$s3_dirs_to_remove $fullpath"
            continue
        fi

        # If we've already seen this date and we're only keeping one per day, remove it and continue.
        if [ "$S3_KEEP_ONE_PER_DAY" -eq 1 ]; then
            if [ "`in_array $datepart "${s3_kept_dates[@]}"`" ]; then
                if [ "$VERBOSE" -ge 2 ]; then echo "  Marking $dir for removal because there's a more recent backup from $datepart."; fi
                s3_dirs_to_remove="$s3_dirs_to_remove $fullpath"
                continue
            fi
        fi

        # Test if it's a "monthly" backup, i.e. the date is the first day of the month.
        if [ "${datepart:8:2}" = "01" ]; then
            is_monthly=1
        else
            is_monthly=0
        fi

        # If it's not a monthly backup, and we've maxed out the number of recents to keep, remove it and continue.
        if [ "$S3_KEEP_NUM_RECENT" -ne "-1" ]; then
            if [ "$is_monthly" -eq "0" -a "$s3_num_kept_recents" -ge "$S3_KEEP_NUM_RECENT" ]; then
                if [ "$VERBOSE" -ge 2 ]; then echo "  Marking $dir for removal because it exceeds the number of recent backups to keep ($S3_KEEP_NUM_RECENT)."; fi
                s3_dirs_to_remove="$s3_dirs_to_remove $fullpath"
                continue
            fi
        fi

        # If it's a monthly backup, and we've maxed out the number of recents and monthlies to keep, remove it and continue.
        if [ "$S3_KEEP_NUM_MONTHLIES" -ne "-1" ]; then
            if [ "$is_monthly" -eq "1" -a "$s3_num_kept_monthlies" -ge "$S3_KEEP_NUM_MONTHLIES" ]; then
                if [ "$VERBOSE" -ge 2 ]; then echo "  Marking $dir for removal because it exceeds the number of monthly backups to keep ($S3_KEEP_NUM_MONTHLIES)."; fi
                s3_dirs_to_remove="$s3_dirs_to_remove $fullpath"
                continue
            fi
        fi

        # Add it to the list of kept backups.
        s3_kept_dates="$s3_kept_dates $datepart"
        s3_dirs_to_keep="$s3_dirs_to_keep $fullpath"

        # Increment the numbers of backups kept.
        if [ "$is_monthly" -eq 1 ]; then
            s3_num_kept_monthlies=$(($s3_num_kept_monthlies + 1))
        else
            s3_num_kept_recents=$(($s3_num_kept_recents + 1))
        fi
    done
fi

# Prompt for confirmation
if [ "$NO_PROMPT" -ne "1" ]; then
    if [ "${#dirs_to_remove[@]}" -gt "0" -o "${#s3_dirs_to_remove[@]}" -gt "0" ]; then
        echo "---------------"
        echo "Please confirm"
        echo "---------------"
        echo "The following local directories will be KEPT:"
        for dir in $dirs_to_keep; do echo $dir; done
        echo ""
        echo "The following S3 directories will be KEPT:"
        for dir in $s3_dirs_to_keep; do echo $dir; done
        echo ""
        echo "The following local directories will be REMOVED:"
        for dir in $dirs_to_remove; do echo $dir; done
        echo ""
        echo "The following S3 directories will be REMOVED:"
        for dir in $s3_dirs_to_remove; do echo $dir; done
        echo ""

        if [ "$DRY_RUN" -gt 0 ]; then
            echo "(Note: This is a dry run. No changes will actually be made.)"
            echo ""
        fi

        read -r -p "Are you sure? [y/N] " response
        response=${response,,}    # tolower
        if [[ $response =~ ^(yes|y)$ ]]; then
            confirmed=1
        else
            echo "Canceled."
            exit 1
        fi
    fi
fi

# Remove local directories
if [ "${#dirs_to_remove[@]}" -gt 0 ]; then
    for dir in $dirs_to_remove; do
        cmd="rm -rf $dir"
        if [ "$DRY_RUN" = "1" ]; then
            echo "Would remove: $dir"
        else
            if [ "$VERBOSE" -ge 1 ]; then echo "Removing $dir"; fi
            $cmd
        fi
        if [ "$VERBOSE" -ge 2 ]; then echo "  $cmd"; fi
    done
fi

# Remove S3 directories
if [ "${#s3_dirs_to_remove[@]}" -gt 0 ]; then
    for dir in $s3_dirs_to_remove; do
        cmd="$S3CMD -c $S3_CONF del --recursive $dir"
        if [ "$DRY_RUN" = "1" ]; then
            echo "Would remove: $dir"
        else
            if [ "$VERBOSE" -ge 1 ]; then echo "Removing $dir"; fi
            $cmd
        fi
        if [ "$VERBOSE" -ge 2 ]; then echo "  $cmd"; fi
    done
fi
