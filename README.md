lamp-backup
===========

Bash shell scripts for basic backup management on a LAMP server.

## Overview

These tools are designed to backup a basic Linux/Apache/MySQL/PHP server with a relatively small amount of data.
They're intended for cases in which fancy enterprise backup solutions are overkill.
The goal is simplicity and ease of use, while providing an acceptable level of fault tolerance and security.

By default, `lamp-backup.sh` backs up important Apache, MySQL, and PHP files from their default locations,
and dumps all MySQL databases with mysqldump.
Backups are compressed with tar/gzip and stored in a directory named after the date under `/var/backup`.
Old backups are automatically rotated.
A copy of the backed up files can optionally be stored on Amazon S3.

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
                             (Default: '/home/ubuntu/lamp-backup/etc/mysql-connection.cfg')
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


## Installing lamp-backup

The following commands will copy the lamp-backup `sbin` and `etc` directories into `/usr/local`.
It's safe to upgrade an existing installation this way too,
since your existing config files won't get overwritten.

    INSTALL_DIR=/usr/local;
    wget https://github.com/jasongrimes/lamp-backup/archive/master.zip \
        && unzip master.zip \
        && sudo cp -r lamp-backup-master/sbin $INSTALL_DIR/ \
        && sudo cp -r lamp-backup-master/etc $INSTALL_DIR/ \
        && rm -rf lamp-backup-master master.zip

## Configuring the MySQL connection

You can supply MySQL login information on the command line,
but to run the backup script automatically via cron you'll need to store connection information securely in a config file.

Create the `mysql-connection.cnf` file from the template,
and add the connection information for the MySQL user that will perform the backup.
Make sure this file is readable only by root to prevent exposing your secret login information.

    cd /usr/local/etc
    sudo cp mysql-connection.cnf.dist mysql-connection.cnf
    sudo chown root:root mysql-connection.cnf
    sudo chmod 0600 mysql-connection.cnf
    sudo vim mysql-connection.cnf

Example mysql-connection.cnf file:

    [client]
    host = localhost
    user = root
    password = MySuPeRsEcReTrOoTpAsSwOrD

## Customizing backup configuration

All command-line options can be specified in a configuration file.

The lamp-backup configuration file is optional.
The defaults are intended to be suitable for basic LAMP servers.
To customize the configuration, create the `lamp-backup.conf` file from the template and edit as needed.

    cd /usr/local/etc
    sudo cp lamp-backup.conf.dist lamp-backup.conf
    sudo vim lamp-backup.conf

See the comments in the config file for details about the options available.


## Configuring Amazon S3

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

## Setting up a cron job to run nightly backups

Run backups nightly by setting up a cron job like the following.

    sudo vim /etc/cron.d/lamp-backup

Sample cron file to run backups nightly at 10 minutes after midnight,
and send an email report to you@example.com:

    # Run backups nightly
    MAILTO=you@example.com
    5 * * * * root /usr/local/sbin/lamp-backup.sh

