# one-backup-ceph
Backup rbd backed images to bareos or bacula.

Also there is a complementary python script that checks the bacula and opennebula python apis to check that all of your persistent VMs are being backed up.

Script to snapshot and export opennebula persistent VMs (image and optionally files from within the image using libguestfs) from a ceph datastore.

The backup server must have access to the opennebula controller and the ceph cluster.

It is assumed that

1. image names are the same as the vm name
2. backup user exists in opennebula
3. ceph client authentication is working
4. opennebula-tools is installed
5. libguestfs is installed if file extraction is enabled

Inspired by http://opennebula.org/rentalia-experiences-with-opennebula-and-bacula/ which didn't quite fit the requirment.

Script should: 

1. snapshot the VM
2. export the snapshot to disk
3. delete the snapshot
4. extract the files within the image (if using -f)
5. output the image/files path to backup to bareos/bacula for backup to tape/disk/whatever

Tested using Bareos, sample config:


```
Job {
  Name = "Backup_VM_grumpy"
  JobDefs = "Weekly"
  FileSet = "VM_grumpy"
  Schedule = "Weekly"
  ClientRunAfterJob  = "/usr/local/bin/removevm.sh grumpy"
}

FileSet {
  Name = "VM_grumpy"
  Include {
    Options {
      signature = MD5
      sparse = Yes
      mtimeonly = yes
    }
    File = "\\|/usr/local/bin/exportvm.sh -f -u 192.168.1.2 -i my-rbd-id -p my-rbd-pool grumpy"
  }
}
```

Note: be sure to increase "Client Connect Wait" from the default of 1800 seconds if backing up large VMs


![Python application](https://github.com/laurencegill/one-backup-ceph/workflows/Python%20application/badge.svg)
