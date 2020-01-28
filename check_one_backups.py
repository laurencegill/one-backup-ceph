#!/usr/bin/python

# LGill 11/2019
# Check the opennebula pyone api and the bareos python api for 
# persistent VMs that are running but not being backed up and 
# alert us so we can add them to the backup schedule.
# Requires the 'bareos-python' and 'pyone' non standard modules
# Uses python2 rather than 3 as the api for bareos is only
# available for v2.
# Will read the bareos password from a bconsole config, and you
# need to create a config file for the opennebula user account 
# and exclude lists:
#
# > [one backups]
# > user = username
# > password = password
# >
# > [one vms]
# > exclude = blank,or,comma,separated,hosts
#

from sys import exit
import argparse
import ConfigParser
import imp
from pprint import pprint
from os import getcwd


try:
    import bareos.bsock as bc
except:
    print('No bareos module found. Debian install: apt install python-bareos')
    exit(1)

try:
    import pyone
except:
    print('No pyone module found (don\'t install with apt) install: pip install pyone')
    exit(1)

try:
    imp.find_module('sslpsk')
except:
    print('python-bareos requires encryption for auth but it does not install the module, install: pip install sslpsk. You also need the ssl development files: apt install libssl-dev')
    exit(1)


def get_args(argv=None):

    """Parse user arguments and set defaults, return values."""

    cwd = getcwd()
    parser = argparse.ArgumentParser(description='Check if persistent VMs are being backed up by bareos.', epilog='The VM name must be included in the bareos job name.')
    parser.add_argument('-b', '--bconsole', help='bconsole config file, defaults to /etc/bareos/bconsole.conf', default='/etc/bareos/bconsole.conf', type=file)
    parser.add_argument('-c', '--config', help='config for one credentials and VM exclude list, defaults to .one_backups.cnf in current dir', default=cwd+'/.one_backups.cnf')
    parser.add_argument('-d', '--debug', help='debug output', action='store_true')
    parser.add_argument('-H', '--host', help='one frontend host, defaults to localhost', default='127.0.0.1')
    return parser.parse_args(argv)


def get_bareos_pw():

    """Read the bareos config file, return the password."""

    args = get_args()
    bconfig = args.bconsole
    with bconfig as config_file:
        data = config_file.read()
        config_file.close() # File is opened by argparse
    bpass = data.partition('Password')[2].strip(' =').partition('\n')[0].replace('"', '')
    return bpass


def get_jobs():

    """Get statistics about the last jobs, return a bytearray."""

    bpw = bc.Password(get_bareos_pw())
    dir = bc.DirectorConsole(address='localhost', port=9101, password=bpw)
    data = dir.call('list jobtotals')
    return data


def get_vms():

    """List active VMs in the pool, return a list.
    
    The values essentailly mean display all running
    VMs, more information can be found here:
    http://docs.opennebula.org/5.4/integration/system_interfaces/api.html#one-vmpool-info
    """

    args = get_args()
    one_auth = ConfigParser.SafeConfigParser()
    one_auth.read(args.config)
    one_host = args.host
    one_xmlrpc = 'http://' + one_host + ':2633/RPC2'
    one_user = one_auth.get('one backups', 'user')
    one_password = one_auth.get('one backups', 'password')
    one_session = (one_user + ':' + one_password)
    one = pyone.OneServer(one_xmlrpc, session=one_session)
    vmlist = one.vmpool.info(-2, 0, -1, 3).VM
    return vmlist


def get_pvms():

    """Filter out the persistent VMs, return a set."""
    
    vms_to_check = set()
    vms = get_vms()
    for obj in vms:
        if 'PERSISTENT' in (str(obj.get_TEMPLATE())):
            vms_to_check.add(obj.get_NAME())

    return vms_to_check


def get_pvms_and_jobs():
    pvms = get_pvms()
    jobs = get_jobs()
    return (pvms, jobs)


def check_vms_to_jobs():
    nobackup = []
    args = get_args()
    one_exclude = ConfigParser.SafeConfigParser()
    one_exclude.read(args.config)
    exclude = one_exclude.get('one vms', 'exclude').split(',')
    server, backup = get_pvms_and_jobs()
    for val in server:
        if not val in backup:
            if not val in exclude:
                nobackup.append(val)

    if nobackup:
        print ("These VMs are not being backed up, and are not in the exclude list:")
        pprint (nobackup, indent=2)

    if not nobackup:
        print ("Everything is OK, your backup strategy is good")


def print_bacula_jobs():

    """Call the get_jobs() function, print the data."""

    print ('-' * 8, 'DEBUG print bacula jobs:')
    clients = get_jobs()
    print (type(clients))
    print (clients)


def print_all_vms():

    """Call the get_vms() function, print the data and dump index 0."""

    vms = get_vms()
    print ('-' * 8, 'DEBUG print all VMs, and the entire first object:')
    print ('-' * 8, 'There are '  + str(len(vms)) +  ' active vms')
    print ('-' * 8, 'Information about all active VMs:')
    for obj in vms:
        print (obj.get_ID(), obj.get_NAME(), obj.get_STATE())
        #pprint(vars(obj)) # This prints a shitload, use when necessary

    print ('-' * 8, 'Printing index 0 object for debugggings:')
    pprint(vars(vms[0]))


def print_persistent_vms():

    """Call the get_pvms() function, print the data."""

    print ('-' * 8, 'DEBUG print_persistent_vms:')
    pvms = get_pvms()
    print (type(pvms))
    pprint (pvms)


def main():
    args = get_args()
    if args.debug:
        print_bacula_jobs()
        print_all_vms()
        print_persistent_vms()
    check_vms_to_jobs()
    

if __name__ == '__main__':
    main()
