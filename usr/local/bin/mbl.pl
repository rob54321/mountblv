#!/usr/bin/perl
# script to mount bitlocker drives at mountpoints and vera encrtypted containers
# the drives can also be unmounted with the correct switches
use strict;
use warnings;
use Getopt::Std;
use lib "./";
use PassMan;

# passManger
my $passman;

# the version
my $version = "1.41";

# get /etc/mtab to check for mounted devices
my $mtab = `cat /etc/mtab`;

# for bitlocker drives
# the key is the partuuid
# hash format  for each record: partuuid => [mountpoint disk_label]
# if mount point is not given then /mnt/drive1, /mnt/drive2, etc will be used
my %allbldev = ("7150343d-01" => [qw(/mnt/axiz axiz)],
	    "dd816708-01" => [qw(coahtr3552 "")],
            "7f8f684f-78e2-4903-903a-c5d9ab8f36ee" => [qw(/mnt/drivec drivec)],
	    "0007ae00-01" => [qw(/mnt/ssd ssd)],
            "766349ae-03" => [qw("" ddd)],
	    "3157edd8-01" => [qw(/mnt/chaos chaos)],
	    "78787878-01" => [qw(/mnt/ver4 ver4)]);

# the hash vdevice contains 
# partition label => [drive mountpoint, {verafile => verafile_mountpoint}]
my %vdevice = ( 
	 ssd    => ['/mnt/ssd',  {'/mnt/ssd/vera'                => '/mnt/verassd'}]	,
	 hd3    => ['/mnt/hd3',  {'/mnt/hd3/backups/lynn/vera'   => '/mnt/verahd3'}]	,
	 hd2    => ['/mnt/hd2',  {'/mnt/hd2/backups/lynn/vera'   => '/mnt/verahd2'}]	,
	 hdint  => ['/mnt/hdint',{'/mnt/hdint/backups/lynn/vera' => '/mnt/verahdint'}]	,
	 ad64   => ['/mnt/ad64', {'/mnt/ad64/vera'               => '/mnt/veraad64'	,
						 '/mnt/ad64/backups/vera'       => '/mnt/veraad641'	,
			          	 '/mnt/ad64/v2/vera'            => '/mnt/veraad642'	,
			          	 '/mnt/ad64/v3/vera'            => '/mnt/veraad643'	,
			            	 '/mnt/ad64/v4/vera'            => '/mnt/veraad644'	,
			          	 '/mnt/ad64/v5/vera'            => '/mnt/veraad645'	,
			          	 '/mnt/ad64/v6/vera'            => '/mnt/veraad646'}]	,
	 win    => ['/mnt/win',  {'/mnt/win/lynn/vera'           => '/mnt/verawin'}]	,
	 tosh   => ['/mnt/tosh', {'/mnt/tosh/backups/lynn/vera'  => '/mnt/veratosh'}]	,
	 trans  => ['/mnt/trans',{'/mnt/trans/vera'              => '/mnt/veratrans'	,
          				 '/mnt/trans/backups/vera'      => '/mnt/veratrans1'	,
			                '/mnt/trans/v2/vera'           => '/mnt/veratrans2'	,
				           '/mnt/trans/v3/vera'     	  => '/mnt/veratrans3'	,
				           '/mnt/trans/v4/v2/vera'        => '/mnt/veratrans4'	,
				           '/mnt/trans/v4/v3/vera'        => '/mnt/veratrans5'}]	,
	 can    => ['/mnt/can',  {'/mnt/can/backups/lynn/vera'   => '/mnt/veracan'}]	,
	 rootfs => ['/',         {'/home/robert/vera'            => '/mnt/verah' 		,
                               '/home/robert/v2/vera'         => '/mnt/verah1'		,
                               '/home/robert/v3/vera'         => '/mnt/verah2'		,
                               '/home/robert/v4/vera'         => '/mnt/verah3'		,
                               '/home/robert/v2/v3/vera'      => '/mnt/verah4'		,
                               '/home/robert/v2/v3/v4/vera'   => '/mnt/verah5'}])	;

our ($opt_l, $opt_m, $opt_h, $opt_v, $opt_u, $opt_V, $opt_a);

# each (key,value) of %vmounts is dlabel => {vfile => vmtpt}
my %vmounts = ();     # %vmounts = (dlabel => {vfile => vmtpt})
my @vdiskmounts = (); # @vdiskmounts = (dmtpt1, dmtpt2,..)
my %blmounts = ();    # %blmounts = (dmtpt => [dlabel, encmountpt, created])
# declare global empty lists for the values
# attachedveralabels contains a list of attached disk labels with vera containers on them
my @attachedveralabels = ();
my @attachedverafiles = ();
my @attachedveramtpts = ();


# attachedblmtpts: blmtpts => [device, disk_label]
# devices are attached, and known to allbldev
my %attachedblmtpts = ();


# get no of command line arguments
my $no = @ARGV;

# sub to umount vera container, update vmounts, mtab and check
# if the disk can be unmounted. The correct line is removed from /tmp/veralist
# the call: umountveracontainer(vera_mtpt)
sub umountveracontainer {
	my $vmtpt = shift;

	# un mount if not mounted
	if ($mtab =~ /\s+$vmtpt\s+/) {
		system("veracrypt -d $vmtpt");
		rmdir "$vmtpt";
		# get the label and vera file
		my ($dlabel, $verafile) = getlabelvfilefromvmtpt($vmtpt);
		print "umounted $verafile mounted at $vmtpt\n";
		print "removed $vmtpt\n";
		# delete line in /tmp/veralist with vera mtpt in it
		$vmtpt =~ s/\//\\\//g;
		# file lines label:dmtpt:vera_file:vera_mtpt
		system("sed -i -e '/:$vmtpt\$/d' /tmp/veralist");
		# delete this entry in hash %vmounts so it is up to date
		delete $vmounts{$dlabel}->{$verafile};
		# check if disk with vera container should be unmounted

		###########################################
		# testing
		#foreach my $label (keys(%vmounts)) {
		#	foreach my $vfile (keys(%{$vmounts{$label}})) {
		#		print "$label => $vfile => $vmounts{$label}->{$vfile}\n";
		#	}
		#}
		############################################
		if (! keys(%{$vmounts{$dlabel}})) {
			my $dmtpt = $vdevice{$dlabel}->[0];
			if (grep /^$dmtpt$/, @vdiskmounts) {
				system("umount $dmtpt");
				print "umount $dmtpt\n";
				# remove line from /tmp/veradrivelist
				$dmtpt =~ s/\//\\\//g;
				system("sed -i -e '/$dmtpt/d' /tmp/veradrivelist");
				# is it necessary to remove $dmtpt from @vdiskmounts
				# i don't think so
			}
		# update $mtab
		$mtab = `cat /etc/mtab`;
		}
	} else {
		print "$vmtpt is not mounted\n";
	}

}
# sub to make lists of mounted devices.
# values are read from the files /tmp/veradrivelist, /tmp/veralist, /tmp/bitlockermounted
sub listmounteddev {
	# make a hash of vera mounts: dlabel => {vfile => vmtpt} for each pair
	if (open (VERALIST, "/tmp/veralist")) {
		while (my $line = <VERALIST>) {
			chomp ($line);
			my ($dlabel, $dmtpt, $verafile, $veramtpt) = split /:/, $line;
			$vmounts{$dlabel}->{$verafile} = $veramtpt;
		}
		# close
		close(VERALIST);
	}

	# make list of vdiskmounts
	# these are the disks mounted by mbl.pl to mount vera containers
	if (open(VDRIVELIST, "/tmp/veradrivelist")) {
		while (my $vlabel = <VDRIVELIST>) {
			chomp($vlabel);
			push @vdiskmounts, $vlabel;
		}
		# close
		close(VDRIVELIST);
	}
	# make a list of bit locker drives
	if ( open (BLOCKMOUNTED, "/tmp/bitlockermounted")) {
		while (my $line = <BLOCKMOUNTED>) {
			chomp($line);
			my ($dlabel, $mdir, $encmount, $created) = split(/:/, $line);
			# add elements to hash mdir => [encrypted file, creatation status]
			$blmounts{$mdir} = [$dlabel, $encmount, $created];
		}
		# close
		close (BLOCKMOUNTED);
	}
	######################################################
	# testing #
	#foreach my $dlabel (keys(%vmounts)) {
	#	print "$dlabel: $vmounts{$dlabel}\n";
	#	while (($verafile, $vmtpt) = each (%{$vmounts{$dlabel}})) {
	#		print "dlabel $dlabel $verafile $vmtpt\n";
	#	}
	#}
	#
	#print "vdiskmounts @vdiskmounts\n";
	#foreach my $mdir (keys(%blmounts)) {
	#	print "mdir $mdir: encfile $blmounts{$mdir}->[0]: created $blmounts{$mdir}->[1]\n";
	#}
	######################################################
}
# sub to umount a bitlocker drive.
# The mount point is unmounted and removed if it was created
# the encrypted file is then unmounted and the directory removed
# The line from /tmp/bitlockermounted file is deleted
# the call mountbl(dmtpt, encfilemtpt)
sub umountbl {
	my $dmtpt = shift;
	my $encfilemtpt = shift;

	# unmount mountpoint then encrypted file
	system("umount $dmtpt");
	print "umounted $dmtpt\n";
	if ($blmounts{$dmtpt}->[2] eq "created") {
		# mbl.pl create directory, remove it
		rmdir "$dmtpt";
		print "removed $dmtpt\n";
	}
	# unmount encrypted file and remove directory
	system("umount $encfilemtpt");
	rmdir "$encfilemtpt";
	print "removed $encfilemtpt\n";
	# delete line with mountpoint in /tmp/bitlockermounted
	$dmtpt =~ s/\//\\\//g;
	system("sed -i -e '/:$dmtpt:/d' /tmp/bitlockermounted");

}
	
# sub umount($opt_u) parses the input argument
# and determines what to unmount
sub umount {
	# get arguments
	my @ulist = split /\s+/, $_[0];

	# make a list of mounted drives, vera mountpoints and bitlocker mountpoints
	listmounteddev();

	# if all is passed unmount all.
	if ($ulist[0] eq "all") {
		system("veracrypt -d");
		# remove all vera mtpts
		foreach my $dlabel (keys(%vmounts)) {
			foreach my $verafile (keys(%{$vmounts{$dlabel}})) {
				print "umounted $verafile mounted at $vmounts{$dlabel}->{$verafile}\n";
				rmdir "$vmounts{$dlabel}->{$verafile}";
				print "removed $vmounts{$dlabel}->{$verafile}\n";
			}
		}
		unlink "/tmp/veralist";
		print "\n";

		#un mount all drives that were mounted
		# with vera containers
		# and delete file
		foreach my $dmtpt (@vdiskmounts) {
			system("umount $dmtpt");
			print "umounted vera $dmtpt\n";
		}
		unlink "/tmp/veradrivelist";
		print "\n";

		# un mount all bit locker drives
		# first the mountpoint, then the encrypted file
		foreach my $dmtpt (keys(%blmounts)) {
			umountbl($dmtpt, $blmounts{$dmtpt}->[1]);
		}
		unlink "/tmp/bitlockermounted";
		print "\n";
	} else {
		# a list was given to un mount
		# umount each element in the list
		# if the element is a label, umount all vera files
		# unmount disk only if all vera containers for that disk are unmounted
		foreach my $arg (@ulist) {
			# is $arg a vera mtpt or vera container or disk label of bitlocker mountpoint?
			if (grep /^$arg$/, @attachedveramtpts) {
				umountveracontainer($arg);

			} elsif (grep /^$arg$/, @attachedverafiles) {
				# arg is a verafile
				# un mount if not mounted
				my $dlabel = getlabelfromvfile($arg);
				# must use vdevice instead of vmounts because verafile may have been umounted
				my $vmtpt = $vdevice{$dlabel}->[1]->{$arg};
				umountveracontainer($vmtpt);

			} elsif (exists $vdevice{$arg}) {
				# arg is a disk label. umount all vera containers associated with the label
				foreach my $verafile (keys(%{$vdevice{$arg}->[1]})) {
					my $vmtpt = $vdevice{$arg}->[1]->{$verafile};
					umountveracontainer($vmtpt);
				} # end of foreach

			} elsif (exists $blmounts{$arg}) {
				# arg is the mount point of a mounted bitlocker drive
				umountbl($arg, $blmounts{$arg}->[1]);
			} else {
				# arg may be a bitlocker drive label
				# %blmounts = (dmtpt => [dlabel, encmountpt, created
				# check if dlabel is in blmounts
				my $notdlabel = "true";
				foreach my $dmtpt (keys(%blmounts)) {
					if ($arg eq $blmounts{$dmtpt}->[0]) {
						# arg is a dlabel, umount it
						umountbl($dmtpt, $blmounts{$dmtpt}->[1]);
						$notdlabel = "false";
					}
				}
				print "$arg is not mounted\n" if $notdlabel eq "true";
			}
		} # end foreach
	} # end if else
}		
	

# sub to get the disk label from the vera mountpoint for attached vera disks
# the label and vera file are returned or undef if the label or verafile is not found
# the call getlabelvfilefromvmtpt(vera container)
sub getlabelvfilefromvmtpt {
	my $veramtpt = shift;

	# search all attached labels for the the vera mountpoint
	foreach my $label (@attachedveralabels) {
		foreach my $verafile (keys(%{$vdevice{$label}->[1]})) {
			return ($label, $verafile) if $veramtpt eq $vdevice{$label}->[1]->{$verafile};
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

	# for bitlocker devices only
	my @devlist = `lsblk -o PATH,PARTUUID,FSTYPE`;

	# for each element (line) in the list split it into a key value pair
	# if the key is blank do not add it to the hash
	foreach my $ele (@devlist) {
		chomp($ele);
	    	my ($device, $partuuid, $fstype) = split /\s+/, $ele;
		# only add to the hash for fstype = BitLocker
		if ($fstype and ($fstype eq "BitLocker")) {

			# if bitlocker device is not in allbldev, do not include it in the hash
			# of attached bit locker devices
			if ($partuuid and exists $allbldev{$partuuid}) {
				# add it to the list of attachedblmtps: blmtpts => [device, disk_label]
				$attachedblmtpts{$allbldev{$partuuid}->[0]} = [$device,
										$allbldev{$partuuid}->[1]];
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
	my %defparam = ( -m => "all",
			 -b => "all",
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
	my $veramtpt = $vdevice{$dlabel}->[1]->{$verafile};
	my $dmtpt = $vdevice{$dlabel}->[0];

	# mount disk if necessary
	if ($mtab !~ /\s+$dmtpt\s+/) {
		# mount disk
		my $dmount = "mount " . $dmtpt;
		system($dmount);
		print "mounted $dmtpt\n";
		# append mountpoint to /tmp/veradrivelist
		print VDRIVELIST $dmtpt . "\n";

		# mtab has been altered and must be read again
		$mtab = `cat /etc/mtab`;
	}

	# if the file exists and is not mounted, mount it
	if ( -f $verafile) {
		if ( $mtab !~ /\s+$veramtpt\s+/) {
			# mount vera file
			# add vera mountpoint for removal later
			my $password = $passman->getpwd($verafile);
			print VERALIST "$dlabel:$vdevice{$dlabel}->[0]:$verafile:$veramtpt\n";

			# mkdir mountpoint if it does not exist
			if (! -d $veramtpt) {
				mkdir $veramtpt;
			}		
              	system("veracrypt -k \"\" --fs-options=uid=robert,gid=robert,umask=007 --pim=0 --protect-hidden=no -p $password $verafile $veramtpt");		
			print "mounted $verafile at $veramtpt\n";
			# mtab has been altered and must be read again
			$mtab = `cat /etc/mtab`;
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

		foreach my $vmtpt (values(%{$vdevice{$label}->[1]})) {
			push @attachedveramtpts, $vmtpt;
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
	my @veralist = @_;

	# file for vera files: dlabel:dmountpt:verafile:veramtpt
	open (VERALIST, ">>/tmp/veralist");

	# file for mounted drives with veracrypt on them
	# so they can be unmounted later
	open (VDRIVELIST, ">>/tmp/veradrivelist");

	# if the argument all is passed then
	# all vera files on all attached labels must be mounted
	if ($veralist[0] and ($veralist[0] eq "all")) {
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
		foreach my $arg (@veralist) {
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

			} elsif (grep(/^$arg$/, @attachedveramtpts)) {
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
# the call: mountbl(device dlabel password mountpoint index)

sub mountbl {
	# parameters passed $device, $index in list
	my(@command, $device, $dlabel, $password, $mountpoint, $index);
	$index = pop @_;
	$mountpoint = pop @_;
	$password = pop @_;
	$dlabel = pop @_;
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
			print LISTMOUNTED "$dlabel:$mountpoint:/mnt/bde$index:created\n";
		}
		else {
 			# append a list of mounted directories for unmounting later
			# mountpoint directory was not created	
			print LISTMOUNTED "$dlabel:$mountpoint:/mnt/bde$index:exists\n";
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
# sub to mount bit locker drives.
# bit locker drive mounted in two stages
# 1. mount the device at /mnt/bde[index]
# 2. mount /mnt/bde/bde[index] at disk mount point
# this sub takes a list of bitlocker mount points
# and foreach mountpoint gets the password, device and next available index
# it calls mountbl(device dlabel password mountpoint index) if the drive is not mounted
sub findbitlockerdevices {

	# drivelist contains 'all' or a space separated list of drive mountpoints to be mounted
	# all drives are attached and may or may not be mounted
	my @blmtpts = @_;

        # set the no of bitlocker devices found
	my $nobl = keys(%attachedblmtpts);

	# open file for appending list of mounted drives for unmounting later
	open (LISTMOUNTED, ">>/tmp/bitlockermounted");

	# index to count the number of drives mounted
	# it is also used when mounting each drive is mounted at /mnt/bde$index
	# the directories /mnt/bde$index must be checked to see if they are being used.
	my $index = 0;

	# for each bit locker mountpoint in cl args mount drive if it is  not mounted
	foreach my $blmtpt (keys(%attachedblmtpts)) {
		my $device = $attachedblmtpts{$blmtpt}->[0];
		my $dlabel = $attachedblmtpts{$blmtpt}->[1];

		if (($blmtpts[0] eq "all") or (grep /^$blmtpt$/, @blmtpts)) {

			# mount drive
			# get next available /mnt/bde$index directory
			$index = getNextbde(++$index);

			# mount all drives if passwords are defined
			# only if it is not mounted
			if ($mtab !~ /\s+$blmtpt\s+/) {
				# get password of bitlocker drive to be mounted
				my $password = $passman->getpwd($dlabel);
				mountbl ($device, $dlabel, $password, $blmtpt, $index);
			} else {
				# drive is already mounted
				print "$blmtpt is already mounted\n";
			} # end if mtab
		} # end if blmtpts
	}
	close(LISTMOUNTED);
	# for spacing
	print "\n";
	print "No more BitLocker drives found to mount\n" if $nobl == 0;
}

############################
# main entry point
############################

# check to see if default arguments must be supplied to -b -v -u
#print "before: @ARGV\n";
defaultparameter();
#print "after:  @ARGV\n";

# get command line options
getopts('lm:u:hV');

# usage for -h or no command line parameters
if ($opt_h or $no == 0) {
	print "mbl.pl -m to mount all or list to mount [veralabel|vmtpt|verafile|blmtpt|bllabel]\n";
	print "mbl.pl -u to umount everthing that was mounted or [veralabel|veramtpt|verfile|bitlocker_mtpt]\n";
	print "mbl.pl -l list all mounted bitlocker drives and veracrypt containers";
	print "mbl.pl -h to get this help\n";
	print "mbl.pl -V to get the version number\n";
	exit 0;
}

# to get the version no
if ($opt_V) {
	print "Version $version\n";
	exit 0;
}


# to unmount devices
if ($opt_u) {
	# unmount bitlocker drives and / or vera containers.
	# if the disk was mounted by this programme then it will be unmounted as well
	# the argument can be all or
	# any one of: veramtpt, vera container, disk label, bit locker mountpoint
	makeattachedveralists();
	umount($opt_u);
}
# to list all bitlocker drives and veracrypt containers
if ($opt_l) {
	# read mounted devices from files
	listmounteddev();

	# %vmounts = (dlabel => {vfile => veramtpt})
	# %blmounts = (dmtpt => [dlabel, encmountpt, created])
	# @vdiskmounts = [dmtpt1, dmtpt2, dmtpt3....]
	# display veracontainter mounted devices
	foreach my $dlabel (keys(%vmounts)) {
		# print disk was mounted if mbl mounted the disk
		# vdiskmounts has mountpoint of drive mounted by mbl
		# %vdevice: partition label => [drive mountpoint, {verafile => verafile_mountpoint}]

		my $dmtpt = $vdevice{$dlabel}->[0];
		if (grep /^$dmtpt$/, @vdiskmounts) {
			# disk containing vera containers was mounted by mbl
			print "$dlabel: mounted by mbl.pl:\n";
		} else {
			# disk was already mounted
			print "$dlabel: previously mounted\n";
		}
		printf "%-35s\t\t %s\n", "veracrypt file", "mount point";		
		foreach my $vfile (keys(%{$vmounts{$dlabel}})) {
			printf "%-35s\t\t %s\n", $vfile, $vmounts{$dlabel}->{$vfile};
			
		}
		print "\n";
	}
	# display all bitlocker drives
	my $no_keys = keys(%blmounts);
	if ($no_keys == 0) {
		print "no bitlocker drives mounted\n";
	} else {
		printf "%-35s\t\t %-20s %s\n", "disk label", "enc mount point", "disk mount point";
		foreach my $dmtpt (keys(%blmounts)) {
			printf "%-35s\t\t %-20s %s\n", $blmounts{$dmtpt}->[0], $blmounts{$dmtpt}->[1], $dmtpt;
		}
	}
}

# if -m given to mount everything or any combo of bitlocker drives or vera containers
if ($opt_m) {
	# create PassManger
	$passman = new PassMan();
	
	attachedbldevices();
	makeattachedveralists();
	if ($opt_m eq "all") {
		findbitlockerdevices("all");
		mountvera ("all");
	} else {
		# a string of vera_mtpts|vera_files|vera_disk_labels|bitlocker_mtpts|bitlocker_label
		# was given in the command line parameter
		# make a list of bit locker arguments @bllist
		# and make a list of vera mtpts/vera files/vera labels
		# make a list of command line parameters
		my @cllist = split /\s+/, $opt_m;
		my @blmtpts = ();
		my @vlist = ();

		# make a list of known bit locker disk mount points in cllist that are attached
		foreach my $blmtpt (keys(%attachedblmtpts)) {
			my $dlabel = $attachedblmtpts{$blmtpt}->[1];
			# push bl mountpoint onto blmtpts if blmtpt is a mountpoint or disk label
			push @blmtpts, $blmtpt if grep /^$blmtpt$/, @cllist;
			push @blmtpts, $blmtpt if grep /^$dlabel$/, @cllist;
		} # end of foreach blmtpt
			
		# check the cllist for vera arguments add them to vlist
		# make a list of all possible vera arguments
		my @veraargs = (@attachedveralabels, @attachedverafiles, @attachedveramtpts);
		foreach my $arg (@cllist) {
			push @vlist,  $arg if grep /^$arg$/, @veraargs;
		}
		# only call the subs if there are devices to mount
		findbitlockerdevices(@blmtpts) if defined $blmtpts[0];
		mountvera(@vlist) if defined $vlist[0];
	}
	# all mounted, so exit
	exit 0;
}
