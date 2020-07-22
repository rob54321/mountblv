#!/usr/bin/perl -w
# script to mount bitlocker drives at mountpoints and vera encrtypted containers
# the drives can also be unmounted with the correct switches

use Getopt::Std;

# sub to make lists of mounted devices.
# values are read from the files /tmp/veradrivelist, /tmp/veradirlist, /tmp/bitlockermounted
sub listmounteddev {
	our @vmounts = ();
	our @vmountlabels = ();
	our %blmounts = ();

	# make list of mounted vera mount points
	if (open (VERALIST, "/tmp/veralist")) {
		while (my $line = <VERALIST>) {
			chomp ($line);
			push @vmounts, [split /:/, $line];
		}
		# close
		close(VERALIST);
	}

	# make list of vmountlabels
	if (open(VDRIVELIST, "/tmp/veradrivelist")) {
		while (my $vlabel = <VDRIVELIST>) {
			chomp($vlabel);
			push @vmountlabels, $vlabel;
		}
		# close
		close(VDRIVELIST);
	}
	# make a list of bit locker drives
	if ( open (BLOCKMOUNTED, "/tmp/bitlockermounted")) {
		while (my $line = <BLOCKMOUNTED>) {
			chomp($line);
			my ($mdir, $encfile, $created) = split(/:/, $line);
			# add elements to hash mdir => [encrypted file, creatation status]
			$blmounts{$mdir} = [$encfile, $created];
		}
		# close
		close (BLOCKMOUNTED);
	}
	######################################################
	# testing #
	#foreach my $line (@vmounts) {
	#	print "line $line\n";
	#	print "$line->[0]:$line->[1]:$line->[2]:$line->[3]\n";
	#}
	#print "vmountlabels @vmountlabels\n";
	#foreach my $mdir (keys(%blmounts)) {
	#	print "mdir $mdir: encfile $blmounts{$mdir}->[0]: created $blmounts{$mdir}->[1]\n";
	#}
	######################################################
}
	
# sub umountparser($opt_u) parses the input argument
# and determines what to unmount
sub umountparser {
	# get arguments
	my @ulist = @_;

	# make a list of mounted drives, vera mountpoints and bitlocker mountpoints
	listmounteddev();

	# if all is passed unmount all.
	if ($ulist[0] eq "all") {
		system("veracrypt -d");
		# remove all vera mtpts
		foreach my $aref (@vmounts) {
			rmdir $aref->[3];
			print "removed $aref->[3]\n";
		}
		unlink "/tmp/veralist";
		print "\n";

		#un mount all drives that were mounted
		# with vera containers
		# and delete file
		foreach my $label (@vmountlabels) {
			system("umount $label");
			print "umounted vera $label\n";
		}
		unlink "/tmp/veradrivelist";
		print "\n";

		# un mount all bit locker drives
		# first the mountpoint, then the encrypted file
		foreach my $dmtpt (keys(%blmounts)) {
			system("umount $dmtpt");
			print "umounted $dmtpt\n";
			if ($blmounts{$dmtpt}->[1] eq "created") {
				rmdir ("$dmtpt");
				print "removed $dmtpt\n";
			}
			system("umount $blmounts{$dmtpt}->[0]");
			print "umounted $blmounts{$dmtpt}->[0]\n";
			rmdir ("$blmounts{$dmtpt}->[0]");
			print "removed $blmounts{$dmtpt}->[0]\n";
		}
		unlink "/tmp/bitlockermounted";
		print "\n";
	} else {
		# a list was given to un mount
		# umount each element in the list
		# if the element is a label, umount all vera files
		# unmount disk only if all vera containers for that disk are unmounted
		foreach $arg (@ulist) {
			# is $arg a vera mtpt or vera container or disk label of bitlocker mountpoint
			if (grep /^$arg$/, @vmounts) {
				print "\n";
			}
		}
	}	
}		
	

# sub to get the disk label from the vera mountpoint for attached vera disks
# the label and vera file are returned or undef if the label or verafile is not found
# the call getlabelvfilefromvmtpt(vera container)
sub getlabelvfilefromvmtpt {
	my $veramtpt = shift;

	# search all attached labels for the the vera mountpoint
	foreach my $label (@attachedveralabels) {
		foreach my $verafile (keys(%{$vdevice{$label}->[1]})) {
			return ($label, $verafile) if $veramtpt eq $vdevice{$label}->[1]->{$verafile}->[0];
		}
	}
	# either label or verafile not found
	return (undef, undef);
}

# sub to get the the disk label given a vera file container of an attached vera disk
# the label is returned or undef if the label is not found
# the call getlabelfromvfile(vera container)
sub getlabelfromvfile {
	my $verafile = shift;

	# search all attached labels of vera disks
	foreach my $label (@attachedveralabels) {
		foreach my $key (keys(%{$vdevice{$label}->[1]})) {
			return $label if $key eq $verafile;
		}
	}
	# label not found
	return undef;
}

#bit locker drives are mounted at /mnt/bde1, /mnt/bde2, etc
# this sub finds the next available /mnt/bde$index directory.
# the index is returned.
# the start index is passed as a parameter
#the directory /mnt/bde$index must be empty
# the call: getNextbde(++$index) where $index was initialiased to 0
sub getNextbde {
	# only argument is the index
	my $index = shift;

	# search for the first non existent directory /mnt/bde$index
	# the directory /mnt/bde$index has to be empty to mount a bit locker drive
	while (-d "/mnt/bde" . $index) {
		# increment index until a non existent directory is found
		$index++;
	}
	# /mnt/bde$index/bde1 not found
	# and is available
	return $index;
}
# for bit locker file system
# this sub makes a hash partuuid => device path of all known bitlocker drives
# the call: attacheddevices();
sub attachedbldevices {
	# attachedbldev contains a hash of partuuids => device of attached but not mounted bit locker drives
	# the partuuid must exist in allbldev hash
	# attachedveralabels contains a list of attached disk labels with vera containers on them
	our %attachedbldev = ();

	# for bitlocker devices only
	my @devlist = `lsblk -o PATH,PARTUUID,FSTYPE`;

	# for each element (line) in the list split it into a key value pair
	# if the key is blank do not add it to the hash
	foreach $ele (@devlist) {
		chomp($ele);
	    	my ($device, $partuuid, $fstype) = split /\s+/, $ele;
		# only add to the hash for fstype = BitLocker
		if ($fstype and ($fstype eq "BitLocker")) {

			# if bitlocker device is not in allbldev, do not include it in the hash
			# of attached bit locker devices
			if ($partuuid and exists $allbldev{$partuuid}) {
				# add it to the list of attachedbldev
				$attachedbldev{$partuuid} = $device;
			} else {
				# partuuid does not exist in hash
				print "unknown BitLocker drive $device\n";
			}
		} 
	}

}

# this sub operates on the list @ARGV
# all the switches in the ARGV list are checked to see if they have arguments
# if they do not have arguments, the default arguments are inserted into ARGV
# so that getopts will not fail.
# no parameters are passed and none are returned.

sub defaultparameter {

	# hash supplying default arguments to switches
	# -b is for mounting bit locker drives
	# -v is for mounting vera containers
	# -u is for unmounting any drive
	# the default argument, if not given on the command line is all drives
	my %defparam = ( -b => "all",
			 -v => "all",
			 -u => "all");

	# for each switch in the defparam hash find it's index and insert default arguments if necessary
	foreach my $switch (keys(%defparam)) {
		# find index of position of -*
		my $i = 0;
		foreach my $param (@ARGV) {
			# check for a -b and that it is not the last parameter
			if ($param eq $switch) {
				if ($i < $#ARGV) {
					# -* has been found at $ARGV[$i] and it is not the last parameter
					# if the next parameter is a switch -something
					# then -* has no arguments
					# check if next parameter is a switch
					if ($ARGV[$i+1] =~ /^-/) {
						# -* is followed by a switch and is not the last switch
						# insert the 2 default filenames as a string at index $i+1
						my $index = $i + 1;
						splice @ARGV, $index, 0, $defparam{$switch};
					}
				} else {
					# the switch is the last in the list so def arguments must be appended
					my $index = $i + 1;
					splice @ARGV, $index, 0, $defparam{$switch}; 
				}
			}
			# increment index counter
			$i++;
		}
	}
} 

# this sub mounts a vera container that is attached
# and mounts the disk drive if necessary.
# The mounted container is written to /tmp/verafilelist
# and the directory created for the mountpoint is written to /tmp/veradirlist
# The two files are used for unmounting and deleting the created directories
# the call: mountveracontainer( disk_label, vera_file )
sub mountveracontainer {
	my $dlabel = shift;
	my $verafile = shift;

	# get vera mountpoint
	my $veramtpt = $vdevice{$dlabel}->[1]->{$verafile}->[0];
	my $password = $vdevice{$dlabel}->[1]->{$verafile}->[1];

	# mount disk if necessary
	if ($mtab !~ /$dlabel/) {
		# mount disk
		my $dmount = "mount " . $vdevice{$dlabel}->[0];
		system($dmount);
		print "mounted $vdevice{$dlabel}->[0]\n";
		# append mountpoint to /tmp/veradrivelist
		print VDRIVELIST $vdevice{$dlabel}->[0] . "\n";

		# mtab has been altered and must be read again
		$mtab = `cat /etc/mtab`;

	}

	# if the file exists and is not mounted, mount it
	if ( -f $verafile) {
		if ( $mtab !~ /$veramtpt/) {
			# mount vera file
			# add vera mountpoint for removal later
			print VERALIST "$dlabel:$vdevice{$dlabel}->[0]:$verafile:$veramtpt\n";

			# mkdir mountpoint if it does not exist
			if (! -d $veramtpt) {
				mkdir $veramtpt;
			}		
                	system("veracrypt -k \"\" --fs-options=uid=robert,gid=robert,umask=007 --pim=0 --protect-hidden=no -p $password $verafile $veramtpt");
			print "mounted $verafile at $veramtpt\n";
		} else {			
			print "$verafile is already mounted\n";
		}
	} else {
		print "$verafile does not exist\n";
	}
}

# make lists of attached vera disk labels, vera files and their respective mountpoints
# whether they are mounted or not.
# The lists are used with the command line arguments to determine
# if the argument is a label, vera file or vera mount point.
# the individual vera files can be then be mounted.
# no parameters are passed and none are returned.
sub makeattachedveralists {
	# declare global empty lists for the values
	our @attachedveralabels = ();
	our @attachedverafiles = ();
	our @attachedveramtpoints = ();

	# make a list of attached devices labels if they contain vera containers
	my @vlist = `lsblk -o LABEL`;
	foreach my $label (@vlist) {
		chomp($label);
		if ($label and exists $vdevice{$label}) {
			push @attachedveralabels, $label;
		}
	}

	# for each attached disk label make a list of vera files and vera mountpoints
	foreach my $label (@attachedveralabels) {
		my @vfilelist = keys(%{$vdevice{$label}->[1]});
		push @attachedverafiles, @vfilelist;

		foreach my $mtptref (values(%{$vdevice{$label}->[1]})) {
			push @attachedveramtpoints, $mtptref->[0];
		}
	}
}

# this sub mounts all known attached vera containers if all is passed as a parameter.
# it mounts specific ones if the parameter passed is a list to mount
# the disk is also mounted if necessary
# hash containing all the devices that have veracrypted files on them
# format: disk label => [device disk mountpoint, vera file, vera mountpoint, password]
# parameters passed: either 'all' or a list of vera mountpoints to mount
# none returned

sub mountvera {
	# command line arguments to the -v parameter
	# string veralist = all | list of vera mountpoints
	my @veralist = split /\s+/, $_[0];

	# file for vera files: dlabel:dmountpt:verafile:veramtpt
	open (VERALIST, ">>/tmp/veralist");

	# file for mounted drives with veracrypt on them
	# so they can be unmounted later
	open (VDRIVELIST, ">>/tmp/veradrivelist");

	# if the argument all is passed then
	# all vera files on all attached labels must be mounted
	if ($veralist[0] eq "all") {
		# mount all devices and all vera containers
		foreach my $label (@attachedveralabels) {
			# for each label there could be multiple vera containers
			foreach my $verafile (keys(%{$vdevice{$label}->[1]})) {
				mountveracontainer($label, $verafile);
			}
		}
	} else {
		# there is a list of arguments following -v
		# verafile | vera_mountpoint | disk_label
		foreach $arg (@veralist) {
			# is the argument a disk label?
			if (grep (/^$arg$/, @attachedveralabels)) {
				# argument is a disk label
				# mount all vera files on disk label
				foreach my $verafile (keys(%{$vdevice{$arg}->[1]})) {
					# mount vera file
					#print "arg is a label = $arg: verafile = $verafile\n";
					mountveracontainer($arg, $verafile);
				}
			} elsif (grep(/^$arg$/, @attachedverafiles)) {
				#argument is a vera container
				my $label = getlabelfromvfile($arg);
				#print "arg is a verafile label = $label: verafile = $arg\n";
				mountveracontainer($label, $arg);

			} elsif (grep(/^$arg$/, @attachedveramtpoints)) {
				#argument is a vera mount point
				my ($label, $verafile) = getlabelvfilefromvmtpt($arg);
				#print "arg is a vmtpt label = $label: verafile = $verafile\n";
				mountveracontainer($label, $verafile);
			} else {
				# unkown argument
				print "$arg is unknown\n";
			}
		}
	}
	close(VDRIVELIST);
	close(VERALIST);
}


# sub to mount bit locker devices
# the device first gets mounted with bdemount as a file at /mnt/bde[index]/bde1
# then file /mnt/bde[index]/bde1 is mounted at /mnt/mountpoint using a loop device
# the mountpoint and bde_index are appended to the file  /tmp/bitlockermounted
# so they can be unmounted at a later stage
# the call: mountbl(device password mountpoint index)

sub mountbl {
	# parameters passed $device, $index in list
	my(@command, $device, $password, $mountpoint, $index);
	$index = pop @_;
	$mountpoint = pop @_;
	$password = pop @_;
	$device = pop @_;


	# make directory if it does not exist for mounting the encrypted drive file
	mkdir ("/mnt/bde$index") if ! -e "/mnt/bde$index";
	system ("bdemount -p $password $device /mnt/bde$index");
	sleep 2;
	print "mounted $device on /mnt/bde$index\n";

	# mount drive file under mountpoint if the variable $mountpoint is defined
	if ($mountpoint) {

		# create the directory $mountpoint if the directory does not exist
		# it must also be listed in the file /tmp/bitlockermounted for deletion
		# after un mounting
		if (! -e $mountpoint) {
			mkdir ($mountpoint);
			# append a list of mounted directories, so they can be un mounted later.
			# mark the directory as created
			print LISTMOUNTED "$mountpoint:/mnt/bde$index:created\n";
		}
		else {
 			# append a list of mounted directories for unmounting later
			# mountpoint directory was not created	
			print LISTMOUNTED "$mountpoint:/mnt/bde$index:exists\n";
		}
		# mount the decrypted file
		print "mounted /mnt/bde$index/bde1 on $mountpoint\n";
		system("mount -o loop,ro,uid=robert,gid=robert,umask=007 /mnt/bde$index/bde1 $mountpoint");
	} else {
		# $mountpoint is not defined so directory /mnt/drive$index is used
		# to mount the decrypted file.
		print "mounted /mnt/bde$index/bde1 on /mnt/drive$index\n";
		mkdir ("/mnt/drive$index") if ! -e "/mnt/drive$index";
		system("mount -o loop,ro,uid=robert,gid=robert,umask=007 /mnt/bde$index/bde1 /mnt/drive$index");

		# append a list of mounted directories, so they can be un mounted later.
		print LISTMOUNTED "/mnt/drive$index:/mnt/bde$index:created\n";
	}
}

# sub to find bitlocker devices.
# devices are found by executing lsb -o PATH,FSTYPE,PARTUUID
# if FSTYPE = Bitlocker then the device is a bitlocker device.
# PARTUUID is the key to the hash allbldev which contains the password and mountpoint
# On the command line if -b has no arguments then all drives found will be mounted
# if -b has a list of arguments then only those drives will be mounted if found
# number of bitlocker devices found
# the call: findbitlockerdevices(drivelist), the drivelist can be all.
sub findbitlockerdevices {


	#################################
	# for testing
	#################################
	#foreach my $item (keys(%attachedbldev)) {
	#	print "attached devices: $item $attachedbldev{$item}\n";
	#}
	#################################

	# drivelist contains 'all' or a space separated list of drive mountpoints to be mounted
	# drives to be mounted
	my $drivelist = shift;

        # set the no of bitlocker devices found
	my $nobl = keys(%attachedbldev);

	# open file for appending list of mounted drives for unmounting later
	open (LISTMOUNTED, ">>/tmp/bitlockermounted");

	# index to count the number of drives mounted
	# it is also used when mounting each drive is mounted at /mnt/bde$index
	# the directories /mnt/bde$index must be checked to see if they are being used.
	my $index = 0;

	# for each attached drive, if the password exists, mount it if drivelist is all
	# or mount it if the mountpoint is in drivelist
	foreach $partuuid (keys(%attachedbldev)) {
		my $mountpoint = $allbldev{$partuuid}->[1];
		my $password = $allbldev{$partuuid}->[0];
		my $device = $attachedbldev{$partuuid};

		if (($drivelist eq "all") or ($drivelist =~ /$mountpoint/)) {

			# mount drive if there is a password and the argument for -b is all
			if($password) {
				# get next available /mnt/bde$index directory
				$index = getNextbde(++$index);

				# mount all drives if passwords are defined
				# only if it is not mounted
				if ($mtab !~ /$mountpoint/) {
					mountbl ($device, $password, $mountpoint, $index);
				} else {
					# drive is already mounted
					print "$mountpoint is already mounted\n";
				}
			} else {
				print "Could not mount $device, unknown password\n";
			}
		}
	}
	close(LISTMOUNTED);
	# for spacing
	print "\n";
	print "No more BitLocker drives found to mount\n" if $nobl == 0;
}

############################
# main entry point
############################
# the hash contains password and mount point for bitlocker drives.
# the key is the partuuid
# hash format  for each record: partuuid => [password mountpoint]
# if mount point is not given then /mnt/drive1, /mnt/drive2, etc will be used
our %allbldev = ("7150343d-01" => [qw(coahtr3552  /mnt/axiz)],
	    "dd816708-01" => [qw(coahtr3552 "")],
            "7f8f684f-78e2-4903-903a-c5d9ab8f36ee" => [qw(panda108 /mnt/drivec)],
	    "0007ae00-01" => [qw(coahtr3552 /mnt/ssd)],
            "766349ae-03" => [qw(coahtr3552 "")],
	    "3157edd8-01" => [qw(coahtr3552 /mnt/chaos)],
	    "78787878-01" => [qw(coahtr3552 /mnt/ver4)]);

# the hash vdevice contains 
# partition label => drive mountpoint, verafile, verafile mountpoint, password
our %vdevice = ( 
	 ssd    => ['/mnt/ssd',  {'/mnt/ssd/vera'                => ['/mnt/verassd',   'coahtr3552']}],
	 hd3    => ['/mnt/hd3',  {'/mnt/hd3/backups/lynn/vera'   => ['/mnt/verahd3',   'coahtr3552']}],
	 hd2    => ['/mnt/hd2',  {'/mnt/hd2/backups/lynn/vera'   => ['/mnt/verahd2',   'coahtr3552']}],
	 hdint  => ['/mnt/hdint',{'/mnt/hdint/backups/lynn/vera' => ['/mnt/verahdint', 'coahtr3552']}],
	 ad64   => ['/mnt/ad64', {'/mnt/ad64/vera'               => ['/mnt/veraad64',  'coahtr3552'],
			          '/mnt/ad64/backups/vera'       => ['/mnt/veraad641', 'coahtr3552'],
			          '/mnt/ad64/v2/vera'            => ['/mnt/veraad642', 'coahtr3552'],
			          '/mnt/ad64/v3/vera'            => ['/mnt/veraad643', 'coahtr3552']}],
	 win    => ['/mnt/win',  {'/mnt/win/lynn/vera'           => ['/mnt/verawin',   'coahtr3552']}],
	 tosh   => ['/mnt/tosh', {'/mnt/tosh/backups/lynn/vera'  => ['/mnt/veratosh',  'coahtr3552']}],
	 trans  => ['/mnt/trans',{'/mnt/trans/vera'              => ['/mnt/veratrans', 'coahtr3552'],
				  '/mnt/trans/backups/vera'      => ['/mnt/veratrans1','coahtr3552'],
			          '/mnt/trans/v2/vera'           => ['/mnt/veratrans2','coahtr3552'],
				  '/mnt/trans/v3/vera' 		 => ['/mnt/veratrans3','coahtr3552'],
				  '/mnt/trans/v4/v2/vera'        => ['/mnt/veratrans4','coahtr3552'],
				  '/mnt/trans/v4/v3/vera'        => ['/mnt/veratrans5','coahtr3552']}],
	 can    => ['/mnt/can',  {'/mnt/can/backups/lynn/vera'   => ['/mnt/veracan',   'coahtr3552']}]);

our ($opt_h, $opt_v, $opt_u);
# get no of command line arguments
my $no = @ARGV;

# check to see if default arguments must be supplied to -b -v -u
#print "before: @ARGV\n";
defaultparameter();
#print "after:  @ARGV\n";

# get command line options
getopts('b:v:u:h');

# usage for -h or no command line parameters
if ($opt_h or $no == 0) {
	print "mbl.pl -b to mount all bitlocker devices or list = [mountpoint ...]\n";
	print "mbl.pl -v to mount all vera containers or list =[label|vera mountpoint|disk mountpoint|vera file|]\n";
	print "mbl.pl -h to get this help\n";
	exit 0;
}


# testing #
#print "for bitlocker\n";
#foreach my $key (keys(%attachedbldev)) {
#	print "partuuid = $key: device path = $attachedbldev{$key}\n";
#}

#print "for vera containers\n";
#foreach my $key (keys(%attachedveradev)) {
#	print "disk label = $key: disk mountpoint = $attachedveradev{$key}\n";
#}

# get /etc/mtab to check for mounted devices
our $mtab = `cat /etc/mtab`;

# find and mount bitlocker devices and mount them
if ($opt_b) {
	# find attached known bit locker devices
	attachedbldevices();
	findbitlockerdevices($opt_b);
}

# if -v given
if($opt_v) {
	# make a list of known attached vera files and vera mount_points
	# so individual arguments can be mounted
	makeattachedveralists();
	# mount vera containers
	mountvera ($opt_v);
}

# to unmount devices
if ($opt_u) {
	# unmount bitlocker drives and / or vera containers.
	# if the disk was mounted by this programme then it will be unmounted as well
	# the argument can be all or
	# any one of: veramtpt, vera container, disk label, bit locker mountpoint
	umountparser($opt_u);
}
