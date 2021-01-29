package DataMan;
use strict;
use warnings;

# DataMan Class
# this class loads the known bitlocker and veracrypt drive list into
# the hashes containing bitlocker and vera drives.
# If the file does not exist, then the default file is created.
# responsibilities:
# 1. loads the current known bitlocker drives and veracrypt files into the respective hashes
#    if the file is not found as in the first invocation, a default one is created.
# 2. bitlocker and vera drives can be added to the resource file.
# 3. bitlocker and vera drives can be deleted from the resource file.
# 4. bitlocker and vera drives can be edited in the resource file.
#
# resource file: /root/.mbldata.rc
#
# the hashes for the data
# %allbldev{partuuid} = [diskmountpt, disklabel]
# %vdevice{partition_label} = [drive mountpoint, {verafile => vera_mountpoint}]
#
# format of mbldata.rc
# each line:
# for bitlocker drive:
# b:partuuid:mount point:partition label
#
# for verafile:
# v:partition label:partition mount point:full verafile name:vera mountpiont

# resource file
my $rcfile = "$ENV{'HOME'}/.mbldata.rc";

# constructor.
# read the file and fill the %allbldev and %vdevice hashes
# if the file does not exist, call the method to create a default one
# the constructor takes no parameters.
sub new {
	my $class = shift;
	

}
