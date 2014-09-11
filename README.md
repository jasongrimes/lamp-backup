lamp-backup
===========

Bash shell scripts for basic backup management on a LAMP server.

## Overview

These tools are designed to backup a basic Linux/Apache/MySQL/PHP server with a relatively small amount of data.
They're intended for cases in which fancy enterprise backup solutions are overkill.
The goal is simplicity and ease of use, while providing an acceptable level of fault tolerance and security.
Only full backups are performed (not incremental backups), to make it easier to restore data when needed.

## Quick start

This section shows how to set up **lamp-backup** with the default configuration.

By default, your important Apache, PHP, and MySQL files and databases will be backed up nightly into `/var/backup`,
with a second copy stored offsite at Amazon S3.
Old backups will be automatically removed.
The most recent two weeks of nightly backups will be kept by default,
along with twelve months of monthly backups (the backup taken on the first day of the month).

(1) Install the **lamp-backup** tools by downloading the project files and copying the sbin and etc directories to `/usr/local`.
The following commands will do this and set some important file permissions.
(It also avoids overwriting any existing config files, in case you're upgrading.)

    INSTALL_DIR=/usr/local; \
    echo 'Downloading lamp-backup from github...'; \
    wget -q https://github.com/jasongrimes/lamp-backup/archive/master.zip \
        && unzip -q master.zip \
        && cd lamp-backup-master \
        && sudo mkdir -p $INSTALL_DIR/etc \
        && echo "Copying scripts to $INSTALL_DIR/sbin/" \
        && sudo cp -r sbin $INSTALL_DIR/ \
        && for file in $(ls etc); do if [ ! -f "$INSTALL_DIR/etc/$file" ]; then echo "Copying $file to $INSTALL_DIR/etc/"; sudo cp etc/$file $INSTALL_DIR/etc/; fi; done \
        && echo "Setting permissions on $INSTALL_DIR/etc/mysql-connection.cnf" \
        && sudo chown root:root $INSTALL_DIR/etc/mysql-connection.cnf \
        && sudo chmod 0600 $INSTALL_DIR/etc/mysql-connection.cnf \
        && sudo chmod a+x $INSTALL_DIR/sbin/lamp-backup*.sh $INSTALL_DIR/sbin/mysql-backup.sh \
        && cd - >/dev/null \
        && rm -rf lamp-backup-master master.zip \
        && echo "Done. See https://github.com/jasongrimes/lamp-backup for details."

(2) Edit `/usr/local/etc/mysql-connection.cfg` and set the password for your MySQL root user.
Make sure this file is readable only by root.

(3) To enable offsite backups to [Amazon S3](http://aws.amazon.com/s3), run the following and enter your AWS access key and secret:

    sudo apt-get install s3cmd python-magic
    sudo s3cmd --configure -c /root/.s3cfg

Then edit `/usr/local/etc/lamp-backup.conf` and set the `S3_PATH` to the S3 URL where you want your backups to be saved.

(4) Set up a cron job for running nightly backups by creating a `/etc/cron.d/lamp-backup` file with the following contents:

    # Run backups nightly
    MAILTO=you@example.com
    5 0 * * * root /usr/local/sbin/lamp-backup.sh

For more details about customizing your backups, see the information below.

## Usage

    Usage: lamp-backup.sh [options]

    lamp-backup.sh is a simple tool for backing up files and MySQL databases.

    Options:
      -o OUTPUT_DIR, --output-dir=OUTPUT_DIR
                             Base directory in which to store backups.
                             (Default: '/var/backup')
      -d DIRS, --dirs=DIRS   Directories to back up.
                             (Default: '/var/www /etc/apache2 /etc/php5 /var/log')
      -e PATTERNS, --exclude=PATTERNS
                             Exclude files matching these patterns.
                             (Default: 'core *~')
      -c FILE, --mysql-conf=FILE
                             A MySQL config file with connection information.
                             (Default: '/usr/local/etc/mysql-connection.cfg')
      -s FILE, -s3-conf=FILE An s3cmd config file with connection info for Amazon S3.
                             (Default: '/root/.s3cfg')
      -p S3_PATH, --s3-path=S3_PATH
                             The Amazon S3 path to copy files to (ex. s3://my-bucket/my-folder/).
      --do-files             Back up and compress files. (Enabled by default.)
      --no-files             Don't back up and compress files.
      --do-mysql             Back up MySQL databases. (Enabled by default.)
      --no-mysql             Don't back up MySQL databases.
      --do-s3                Copy backups to Amazon S3. Enabled by default if S3 is configured.
      --no-s3                Don't copy backups to Amazon S3.
      --do-rotate            Rotate old backups. (Enabled by default.)
      --no-rotate            Don't rotate old backups.
      -q, --quiet            Quiet
      -v, --verbose          Verbose
      --help                 Print this help screen

Typically, you'll want to run the lamp-backup script as root so it has access to all the files.
Do so with sudo:

    sudo lamp-backup.sh

## Configuration

### Customizing backup configuration

To customize the backup configuration, edit `/usr/local/etc/lamp-backup.conf`.
This file is optional, and if it doesn't exist, sensible defaults will be used.

All command-line options can be specified in a configuration file.
See the comments in the config file for details about the options available.

### Configuring the MySQL connection

You can supply MySQL login information on the command line,
but to run the backup script automatically via cron you'll need to store connection information securely in a config file.

Add the connection information for the MySQL user that will perform the backup in `/usr/local/etc/mysq-connection.cnf`.
Make sure this file is readable only by root to prevent exposing your secret login information.

    cd /usr/local/etc
    sudo chown root:root mysql-connection.cnf
    sudo chmod 0600 mysql-connection.cnf
    sudo vim mysql-connection.cnf

Example mysql-connection.cnf file:

    [client]
    host = localhost
    user = root
    password = MySuPeRsEcReTrOoTpAsSwOrD


### Configuring Amazon S3

It's possible to configure lamp-backup to store a copy of the backups on [Amazon S3](http://aws.amazon.com/s3/).

First, install the `s3cmd` package and its dependencies. On Ubuntu or Debian, do it like this:

    sudo apt-get install s3cmd python-magic

Configure s3cmd, providing it with your access keys.
Make sure to run this with sudo,
to ensure that the generated config file is protected with suitable permissions
(it should be readable only by root).

    sudo s3cmd --configure -c /root/.s3cfg

Enter your AWS key and secret when prompted. Accept defaults for the other values.

Then specify the S3 path to store your backups in.
Edit the following value in `/usr/local/etc/lamp-backup.conf`:

    S3_PATH=s3://my-bucket/my-folder/

Make sure the path ends with a slash (/).


### Setting up a cron job to run nightly backups

Run backups nightly by setting up a cron job like the following.

    sudo vim /etc/cron.d/lamp-backup

Sample cron file to run backups nightly at 5 minutes after midnight,
and send an email report to you@example.com:

    # Run backups nightly
    MAILTO=you@example.com
    5 0 * * * root /usr/local/sbin/lamp-backup.sh

## Backup rotation

**lamp-backup** automatically deletes old backups, to prevent filling up disk space.

### Default rotation

By default, the most recent two weeks of daily backups are kept.

Twelve monthly backups (the backup taken on the first day of the month) are kept locally,
and monthly backups are kept forever on Amazon S3.

Only one backup is kept for each day (the most recent one).

### Configuring backup rotation

These defaults can be changed by editing `/usr/local/etc/lamp-backup.conf`.

There are separate config options for locally stored backups and backups stored on Amazon S3.

Set `KEEP_NUM_RECENT` to the number of recent backups to keep on the local system.
Typically this will be the number of days of recent backups to keep,
unless you set `KEEP_ONE_PER_DAY` to 0.
Set `KEEP_NUM_RECENT=-1` to keep all (i.e. never delete old backups).

Set `KEEP_NUM_MONTHLIES` to the number of monthly backups to keep on the local system.
A monthly backup is just a backup taken on the first day of the month.
This allows you to keep historical snapshots over a long period of time,
without using a ton of disk space.
Set `KEEP_NUM_MONTHLIES=-1` to keep all monthly backups.

Backup rotation on Amazon S3 is configured the same way,
but the option names start with `S3_`,
ex. `S3_KEEP_NUM_RECENT` and `S3_KEEP_NUM_MONTHLIES`.

### Disk space considerations

Backup rotation should be configured in such a way that you have enough backups around to recover anything you might need,
but that you never keep so many backups you risk running out of disk space.

To estimate the amount of disk space that will be needed,
first determine the size of a single backup.
The following command shows the size of each backup in the `/var/backup` directory:

    du -sh /var/backup/*

If all future backups are the same size as your latest backup,
calculating the amount of disk space required by your rotation strategy is as simple as this:

    (BACKUP_SIZE * KEEP_NUM_RECENT) + (BACKUP_SIZE * KEEP_NUM_MONTHLY)

If the required disk space won't leave you with a comfortable amount of free space,
adjust your configuration accordingly.
Keep in mind that the size of your backups is likely to grow over time.

A summary of disk usage is shown at the end of the report each time a backup is run.
Check this periodically to make sure that disk space won't become an issue.

### Rotating backups independently

While backup rotation is typically done automatically when `lamp-backup.sh` is run,
you can also do a backup rotation independently by running
`/usr/local/sbin/lamp-backup-rotate.sh`.

When run independently, `lamp-backup-rotate.sh`
prompts you for confirmation before deleting anything,
showing you a list of what would be deleted and what would be kept.
You can disable this prompt with the `--force` argument.
Run `lamp-backup-rotate.sh --help` for a complete list of arguments.

## Restoring from backups

Backups are stored as tar/gzip archives, with one for each backed up directory, and one for the MySQL dumps.
File permissions are set so that backups are only readable by the user who ran the backup script (presumably root).

To see the contents of an archive:

    sudo tar tzvf $BACKUPDIR/etc_php5.tgz

To extract the archive:

    sudo tar xzvf $BACKUPDIR/etc_php5.tgz

To extract a single file from an archive (ex. php.ini):

    sudo tar xzvf $BACKUPDIR/etc_php5.tgz ./etc/php5/apache2/php.ini

The MySQL databases are stored in SQL files created by mysqldump, with one file per database.
All of these files are zipped up into a single `mysqldump.tgz` archive.

To restore a database named "mydb":

    sudo tar xzvf $BACKUPDIR/mysqldump.tgz
    cd mysqldump
    mysqladmin -uroot -p create mydb
    mysql -uroot -p mydb < mydb.sql

You could also restore the tables from the "mydb" database into a temporary database (ex. "mydbtemp"),
for review or manipulation before overwriting any existing data.

    mysqladmin -uroot -p create mydbtemp
    mysql -uroot -p mydbtemp < mydb.sql

