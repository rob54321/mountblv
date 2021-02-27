#!/usr/bin/perl
# script to mount bitlocker drives at mountpoints and vera encrtypted containers
# the drives can also be unmounted with the correct switches
use strict;
use warnings;
use Getopt::Std;
use PassMan;
use DataMan;

# global vars
my $passman;
my $dataman;

# the version
my $version = "2.18";

# read fstab into array to check for disk mounts in fstab
# only used in mountveracontainer

my @fstab = ();

# for bitlocker drives
# the key is the partuuid
# hash format  for each record: partuuid => [mountpoint disk_label]
# if mount point is not given then /mnt/drive1, /mnt/drive2, etc will be used
my %allbldev = ();

# the hash vdevice contains 
# partition label => [drive mountpoint, {verafile => verafile_mountpoint}]
my %vdevice = ();

our ($opt_d, $opt_c, $opt_l, $opt_m, $opt_h, $opt_v, $opt_u, $opt_V, $opt_a);

# each (key,value) of %vmounts is dlabel => {vfile => vmtpt}
my %vmounts = ();     # vera disks mounted by mbl.pl: %vmounts = (dlabel => {vfile => vmtpt})
my @vdiskmounts = (); # vera disks mounted by mbl.pl: @vdiskmounts = (dmtpt1, dmtpt2,..)
my %blmounts = ();    # hash of mounted bit locker drives: %blmounts = (dmtpt => [dlabel, encmountpt])
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

# sub to umount vera container, update vmounts
# if the disk can be unmounted. The correct line is removed from /tmp/veralist
# the call: umountveracontainer(vera_mtpt)
sub umountveracontainer {
	my $vmtpt = shift;

	# un mount if not mounted
	my $rc = system("findmnt -l --all $vmtpt > /dev/null 2>&1");
	if ($rc == 0) {
		# get the label and vera file
		my ($dlabel, $verafile) = getlabelvfilefromvmtpt($vmtpt);
		my $rc = system("sudo veracrypt -d $vmtpt > /dev/null 2>&1");

		#check if umount was successfull
		if ($rc == 0) {
			rmdir "$vmtpt";
			printf "%-40s\t\t %s\n", "unmounted $verafile", "$vmtpt";

			# delete this entry in hash %vmounts so it is up to date
			delete $vmounts{$dlabel}->{$verafile};
			# check if disk with vera container should be unmounted

			if (! keys(%{$vmounts{$dlabel}})) {
				my $dmtpt = $vdevice{$dlabel}->[0];
				if (grep /^$dmtpt$/, @vdiskmounts) {
					my $rc = system("sudo umount $dmtpt");
					# check if un mounted
					if ($rc == 0) {
						print "umount $dmtpt\n";
						# remove line from /tmp/veradrivelist
						$dmtpt =~ s/\//\\\//g;
						system("sed -i -e '/$dmtpt/d' /tmp/veradrivelist");
						# is it necessary to remove $dmtpt from @vdiskmounts
						# i don't think so
					} else {
						# disk count not be unmounted
						print "could not umount $dmtpt\n";
					}
				}
			}
		} else {
			# could not umount veracrypt file
			printf "%-40s\t\t %s\n", "could not umount $verafile", "$vmtpt";		
			
		}
	} else {
		print "$vmtpt is not mounted\n";
	}

}
# sub to make lists of mounted devices.
# values are read from the files /tmp/veradrivelist, veracrypt -l, findmnt for bit locker drives
sub listmounteddev {
	# make a hash of vera mounts: %vmounts = (dlabel => {vfile => vmtpt}) for each pair
	# make a list of mounted vera files using veracrypt -l
	# each line is: 1: verafile device_mapper veramtpt
	my @listofmtvera = `veracrypt -l 2>&1`;
	chomp(@listofmtvera);

	unless (grep /Error/,@listofmtvera) {
		foreach my $line (@listofmtvera) {
			my ($verafile, $veramtpt) = (split /\s+/,$line)[1,3];
			# get disk label of vera file
			my $dlabel = getdlabelfromvfile($verafile);
			# get disk mount point
			my $dmtpt = $vdevice{$dlabel}->[0];
			$vmounts{$dlabel}->{$verafile} = $veramtpt;
		}
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

	# make a list of bit locker drives that are mounted in blmounts{dmtpt} = [dlabel, encmountpoint]
	foreach my $partuuid (keys(%allbldev)) {
		# check if the dmtpt is mounted
		my $dmtpt = $allbldev{$partuuid}->[0];
		my $rc = system("findmnt -l --all $dmtpt > /dev/null 2>&1");
 		if ($rc == 0) {
 			# drive is mounted
			my $dlabel = $allbldev{$partuuid}->[1];
			my $bdefile = $dmtpt . "enc";
			# %blmounts = (dmtpt => [dlabel, bdefile])
			$blmounts{$dmtpt} = [$dlabel, $bdefile];
		}
	}
}
# sub to umount a bitlocker drive.
# The mount point is unmounted and removed if it was created
# the encrypted file is then unmounted and the directory removed
# the call mountbl(dmtpt, encfilemtpt)
sub umountbl {
	my $dmtpt = shift;
	my $encfilemtpt = shift;

	# unmount mountpoint then encrypted file
	my $rc = system("sudo umount $dmtpt > /dev/null 2>&1");
	# check if drive unmounted
	if ($rc == 0) {
		print "unmounted $dmtpt\n";
		# unmount encrypted file and remove directory
		my $rc = system("sudo umount $encfilemtpt");
		# remove directory if umount successfull
		rmdir $encfilemtpt if $rc == 0;
		# check if encrypted file was unmounted
		print "count not umount $encfilemtpt\n" unless $rc == 0;
	} else {
		# drive could not be unmounted
		print "count not umount $dmtpt\n";
	}
}
	
# sub umount($opt_u) parses the input argument
# and determines what to unmount
sub umount {
	# get arguments
	my @ulist = split /\s+/, $_[0];


	# if all is passed unmount all.
	if ($ulist[0] eq "all") {
		# unmount all vera volumes individually
		# this is done incase one of them does not dismount
		# veracrypt -d only indicates one dismount fail even if several could not be dismounted
	
		# unmount vera file and remove all vera mtpt 
		foreach my $dlabel (keys(%vmounts)) {
			foreach my $verafile (keys(%{$vmounts{$dlabel}})) {
				# unmount vera container
				umountveracontainer($vmounts{$dlabel}->{$verafile});
			}
		}
		print "\n";

		# un mount all bit locker drives
		# first the mountpoint, then the encrypted file
		foreach my $dmtpt (keys(%blmounts)) {
			umountbl($dmtpt, $blmounts{$dmtpt}->[1]);
		}
		print "\n";
	} else {
		# a list was given to un mount
		# umount each element in the list
		# if the element is a label, umount all vera files from that disk
		# unmount disk only if all vera containers for that disk are unmounted
		# the arg can be: verafile, vmtpt, dlabel, bllabel, bldlabel or unknown
		foreach my $arg (@ulist) {
			# is $arg a vera mtpt or vera container or disk label of bitlocker mountpoint?
			if (grep /^$arg$/, @attachedveramtpts) {
				# arg is a vera mountpoint
				umountveracontainer($arg);

			} elsif (grep /^$arg$/, @attachedverafiles) {
				# arg is a verafile
				# un mount if not mounted
				my $dlabel = getdlabelfromvfile($arg);
				# must use vdevice instead of vmounts because verafile may have been umounted
				my $vmtpt = $vdevice{$dlabel}->[1]->{$arg};
				umountveracontainer($vmtpt);

			} elsif (exists $vdevice{$arg}) {
				# arg is a vera disk label. umount all vera containers associated with the label
				foreach my $verafile (keys(%{$vdevice{$arg}->[1]})) {
					my $vmtpt = $vdevice{$arg}->[1]->{$verafile};
					umountveracontainer($vmtpt);
				} # end of foreach

			} elsif (exists $blmounts{$arg}) {
				# arg is the mount point of a mounted bitlocker drive
				umountbl($arg, $blmounts{$arg}->[1]);
			} else {
				# arg may be a bitlocker drive label
				# %blmounts = (dmtpt => [dlabel, encmountpt]
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
	

# sub to get the disk label and vera file from the vera mountpoint for attached vera disks
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
# the call getdlabelfromvfile(vera container)
sub getdlabelfromvfile {
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

# for bit locker file system
# this sub makes a hash %attachedblmtpts
# blmtpts => [device path, disk_label]
# of all attached and known bitlocker drives
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

				# attachedblmtps: blmtpts => [device, disk_label]
				$attachedblmtpts{$allbldev{$partuuid}->[0]} = [$device,
										$allbldev{$partuuid}->[1]];
			} else {
				# partuuid does not exist in hash
				print "unknown BitLocker drive $device\n";
			} # end if $partuuid
		} # end if $fstype
	} # end foreach my $ele
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
			 -c => "all",
			 -d => "all",
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
	my $rc = system("findmnt -l --all $dmtpt > /dev/null 2>&1");
	unless ($rc == 0) {

		# check that the disk mount point is in fstab
		# if not then the disk must be mounted manually
		# fstab could have
		#LABEL=ssd /mnt/ssd ...
		#UUID=xxxxx /mnt/ssd....
		mkdir $dmtpt unless -d $dmtpt;
		$rc = grep /^LABEL=$dlabel\s+$dmtpt|^UUID=[0-9a-f\-]+\s+$dmtpt/i, @fstab;
		if ($rc) {
			# disk entry in fstab
			system("sudo mount $dmtpt");
			print "mounted $dmtpt\n";
		} else {
			# entry not in fstab
			# mount it by: mount -L label /mnt/label
			system("sudo mount -L $dlabel $dmtpt");
			print "mounted $dmtpt, not in fstab\n";
		}
			
		# append mountpoint to /tmp/veradrivelist
		print VDRIVELIST $dmtpt . "\n";
	}

	# if the file exists and is not mounted, mount it
	if ( -f $verafile) {
		my $rc = system("findmnt -l --all $veramtpt > /dev/null 2>&1");
		unless ($rc == 0) {
			# mount vera file
			# add vera mountpoint for removal later
			# get password, if it is not in the .mbl.rc file
			# then the user will be prompted and the password
			# will be added to the file
			my $password = $passman->getpwd($verafile);

			# mkdir mountpoint if it does not exist
			if (! -d $veramtpt) {
				mkdir $veramtpt;
			}

			# mount vera file and check if successfull
              	my $vrc = system("sudo veracrypt -k \"\" --fs-options=uid=robert,gid=robert,umask=007 --pim=0 --protect-hidden=no -p $password $verafile $veramtpt | tee /tmp/veraerror.txt");
			if (open VOUT,"<","/tmp/veraerror.txt") {
				my @vout = <VOUT>;
				chomp(@vout);
				# check for Incorrect password
				if (grep /Incorrect password/i, @vout) {
					# the password in the resource file is wrong.
					# veracrypt will have prompted for a new password
					# and mounted the vera file. The new password is inacessable
					# so the password in the resource file must be deleted
					# and the next time the vera file is mounted it will be requested.
					$passman->delpwd($verafile);
					print "password for $verafile was incorrect, deleted password in $ENV{'HOME'}/.mbl.rc\n";
				}
				close VOUT;
			}

			printf "%-40s\t\t %s\n", "$verafile", "$veramtpt";		
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
# parameters passed: either 'all' or a list of verafiles|veramtpts|dlabels
# none returned

sub mountvera {
	# command line arguments to the -v parameter
	# string veralist = all | list of vera mountpoints
	my @veralist = @_;

	# read fstab so disk can be mounted using fstab or not
	open FILE, "<", "/etc/fstab" or die "cannot open fstab: $!\n";
	@fstab = <FILE>;
	chomp (@fstab);
	close FILE;

	# file for mounted drives with veracrypt on them
	# so they can be unmounted later
	open (VDRIVELIST, ">>/tmp/veradrivelist");

	# if the argument all is passed then
	# all vera files on all attached labels must be mounted
	if ($veralist[0] and ($veralist[0] eq "all")) {
		# mount all devices and all vera containers
		foreach my $label (@attachedveralabels) {
			print "\n";
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
				print "\n";
				foreach my $verafile (keys(%{$vdevice{$arg}->[1]})) {
					# mount vera file
					#print "arg is a label = $arg: verafile = $verafile\n";
					mountveracontainer($arg, $verafile);
				}
			} elsif (grep(/^$arg$/, @attachedverafiles)) {
				#argument is a vera container
				my $label = getdlabelfromvfile($arg);
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
}


# sub to mount bit locker devices
# if the drive is not mounted then mount it
# the device first gets mounted with bdemount as a file at mountpointenc
# then file mountpointenc/bde1 is mounted at mountpoint using a loop device

# the call: mountbl(device dlabel mountpoint)

sub mountbl {
	# parameters passed $device, $dlabel and $mountpoint
	my(@command, $device, $dlabel, $mountpoint);
	$mountpoint = pop @_;
	$dlabel = pop @_;
	$device = pop @_;


	# make directory if it does not exist for mounting the encrypted drive file
	# the mount directory will be $mountpoint + "enc"
	# so chaos will be mounted at /mnt/chaosenc and /mnt/chaos
	my $mtptenc = $mountpoint . "enc";
	my $bdefile = $mtptenc . "/bde1";
	
	mkdir ($mtptenc) unless -d $mtptenc;
	# check if encrypted file mounted
	my $rc = system("findmnt -l --all $mtptenc > /dev/null 2>&1");
	unless ($rc == 0) {
		# encrypted file not mounted
		# get password of bitlocker drive to be mounted
		my $password = $passman->getpwd($dlabel);

		system ("sudo bdemount -p $password $device $mtptenc > /tmp/bdemount 2>&1");
		sleep 2;
		print "\n";
		printf "%-40s\t\t %s\n", "$device mounted at", "$mtptenc";
	} else {
		# encrypted file is already mounted
		printf "%-40s\t\t %s\n", "$device is already mounted at", "$mtptenc";
	}

	# create the directory $mountpoint if the directory does not exist
	mkdir ($mountpoint) unless -d $mountpoint;

	# check if decrypted file mounted
	$rc = system("findmnt -l --all $mountpoint > /dev/null 2>&1");
	unless ($rc == 0) {
		# decrypted file not mounted
		# mount the decrypted file
		printf "%-40s\t\t %s\n", "mounted $bdefile", "$mountpoint";		
		system("sudo mount -o loop,ro,uid=robert,gid=robert,umask=007 $bdefile $mountpoint");
	} else {
		# decrypted file is mounted
		printf "%-40s\t\t %s\n", "$bdefile is already mounted at", "$mountpoint";		
	}
}
# sub to mount bit locker drives.
# bit locker drive mounted in two stages
# 1. mount the device at mountpointenc 
# 2. mount mountpointenc/bde1 at disk mount point using loop device
# this sub takes a list of bitlocker mount points
# and foreach mountpoint gets the device and disk label
# it calls mountbl(device dlabel mountpoint)
sub findbitlockerdevices {

	# drivelist contains 'all' or a space separated list of drive mountpoints to be mounted
	# all drives are attached and may or may not be mounted
	my @blmtpts = @_;

        # set the no of bitlocker devices found
	my $nobl = keys(%attachedblmtpts);

	# for each bit locker mountpoint in cl args mount drive if it is  not mounted
	foreach my $blmtpt (keys(%attachedblmtpts)) {
		my $device = $attachedblmtpts{$blmtpt}->[0];
		my $dlabel = $attachedblmtpts{$blmtpt}->[1];

		if (($blmtpts[0] eq "all") or (grep /^$blmtpt$/, @blmtpts)) {

			# mount drive
			mountbl ($device, $dlabel, $blmtpt);
		} # end if blmtpts
	}
	# for spacing
	print "\n";
}

# sub to get verafile(s) or bitlocker_labels from an input string
# parameters passed: inputstring, ref to empty hash
# all known vera file(s) and bllabels are returned in the hash

# the hash will be populated as follows:
# these are known and may or may not be attached
# verafile => [vfile1, vfile2, ...]
# bllabel  => [bllabel1, bllabel2,...]
# unknown  => [unknown1, unknown2, .....]

# returns ref to empty hash if nothing found
# returns a list containing the verafile or bitlocker_dlabel or a list of verafiles
# if a vera_dlabel was passed.
# if inputstring is all the full lists of verafiles and bllabels are returned in the hash
sub getvfilesandbllabels {
	my $inputstring = shift;
	my $href = shift; # ref to empty hash
	my @args = split /\s+/, $inputstring;
		
	# make a lists of all vera files, vera mtpts, bitlocker_dlabels and bitlocker_mtpts
	my @verafiles = ();
	my @veramtpts = ();
	my @bldlabels = ();
	my @blmtpts = ();
	
	# make a list of all known vera files and mtpts
	foreach my $dlabel (keys(%vdevice)) {
		push @verafiles, keys(%{$vdevice{$dlabel}->[1]});
		push @veramtpts, values(%{$vdevice{$dlabel}->[1]});
	}
	# make lists for bitlocker_dlabels and bitlocker_mtpts
	foreach my $partuuid (keys(%allbldev)) {
		push @blmtpts, $allbldev{$partuuid}->[0];
		push @bldlabels, $allbldev{$partuuid}->[1];
	}

	# if the input string is "all"
	if ($inputstring eq "all") {
		$href->{"verafile"} = \@verafiles;
		$href->{"bllabel"} = \@bldlabels;
	} else {	
		# the hash must be made up of verafile(s) or bllabel(s) with the appropriate key
		my @vfiles = ();
		my @bllabels = ();
		my @unknown = ();
		foreach my $arg (@args) {
			if ($vdevice{$arg}) {
				# item is a vera disk label
				# add all vera files for the label
				push @vfiles, keys(%{$vdevice{$arg}->[1]});
				
			} elsif (grep /^$arg$/, @verafiles) {
				# if item is a vera file
				push @vfiles, $arg;
				
			} elsif (grep /^$arg$/, @veramtpts) {
				# item is a vera mtpt, find verafile
				foreach my $dlabel (keys(%vdevice)) {
					foreach my $vfile (keys(%{$vdevice{$dlabel}->[1]})) {
						# add vera file for the particular mtpt to the delet list
						push @vfiles, $vfile if $vdevice{$dlabel}->[1]->{$vfile} eq $arg;
					}
				}
				
			} elsif (grep /^$arg$/, @bldlabels) {
				# item is a bitlocker disk label
				push @bllabels, $arg;
				
			} elsif (grep /^$arg$/, @blmtpts) {
				# item is a bitlocker mount point
				# find the disk label
				foreach my $partuuid (keys(%allbldev)) {
					push @bllabels, $allbldev{$partuuid}->[1] if $allbldev{$partuuid}->[0] eq $arg;
				}
				
			} else {
				# unknown arg
				push @unknown, $arg;
			}
		} # end foreach $arg
		$href->{"verafile"} = \@vfiles;
		$href->{"bllabel"} = \@bllabels;
		$href->{"unknown"} = \@unknown;
	} # end if inputstring
}
############################
# main entry point
############################
# check to see if default arguments must be supplied to -b -v -u print "before: @ARGV\n";
defaultparameter();
#print "after:  @ARGV\n";

# get command line options
# a -- data manager
# l -- list mounted devices
# m list|nothing -- mount devices
# u list|nothing -- un mount devices
# h -- help
# V -- version, exit
# d list|nothing -- delete password(s)
# c list|nothing -- change password(s)
getopts('alm:u:hVd:c:');

# usage for -h or no command line parameters
if ($opt_h or $no == 0) {
	print "-m to mount all or list to mount [veralabel|vmtpt|verafile|blmtpt|bllabel]\n";
	print "-u to umount everthing that was mounted or [veralabel|veramtpt|verfile|bitlocker_mtpt]\n";
	print "-l list all mounted bitlocker drives and veracrypt containers\n";
	print "-d delete all passwords or list [veralabel|vmtpt|verafile|bllabel]\n";
	print "-c change/set password of all vera devices/files or bitlocker drive or list [veralabel|veramtpt|verafile|bllabel]\n";
	print "-h to get this help\n";
	print "-V to get the version number\n";
	print "\n";
	print "mbl.pl uses sudo: /etc/sudoers.d/robert contains: robert ALL=(ALL) NOPASSWD:ALL\n";
	print "the file must be chmod 440 owner root.root\n";
	exit 0;
}

# to get the version no
if ($opt_V) {
	print "Version $version\n";
	exit 0;
}

# populate the default values for bitlocker and vera  devices
$dataman = DataMan->new(\%allbldev, \%vdevice);

# Data Manager to add delete or edit entries in the .mbldata.rc file
# -a -- to enter data manager
# -l -- list file	
# -b -- add bitlocker prompt for entries
# -v -- add vera file prompt for entries
# -d verafile|veramtpt|vdisk|bitlockerlabel|bitlockermtpt
# -q -- quit
if ($opt_a) {
	# data maintenance
	$dataman->menu();
	exit(0);
}

# create PassMan if -d, -c or -m given
# create PassManger
$passman = PassMan->new() if $opt_d or $opt_c or $opt_m;

# delete password or delete all passwords
# the parameter can be all, if no command line parameters are passed
# or verafile|veramtpt|vera_dlabel|bitlocker_dlabel|bitlocker_mtpt
if ($opt_d) {
	# delete resource file if all given
	if ($opt_d eq "all") {
		# delete the .mbl.rc file
		$passman->delpwd("all");
	} else {
		# get the hash of verafiles and bllabels from the input arguments for their password deletion
		# %files = ("verafile" => [list of vera files],
		#           "bllabel"  => [list of bitlocker labels],
		#           "unknown"  => [list of unknown labels])
		my %files = ();
		getvfilesandbllabels($opt_d, \%files);
		
		# delete verafile passwords
		for (my $i = 0; $i < @{$files{verafile}}; $i++) {
			my $rc = $passman->delpwd($files{"verafile"}->[$i]);
			print "deleted password for $files{verafile}->[$i]\n" if $rc;
			print "password not found for $files{verafile}->[$i]\n" unless $rc;
		}

		# delete bitlocker passwords
		for (my $i = 0; $i < @{$files{bllabel}}; $i++) {
			my $rc = $passman->delpwd($files{bllabel}->[$i]);
			print "deleted password for $files{bllabel}->[$i]\n" if $rc;
			print "password not found for $files{bllabel}->[$i]\n" unless $rc;
		}

		# print error message for unknowns
		for (my $i = 0; $i < @{$files{unknown}}; $i++) {
			print "$files{unknown}->[$i] is unknown\n";
		}
	} # end if opt_d
}
# to change or set the password of a known vera file or bitlocker device
# for vera files password will be written to .mbl.rc and changed on the vera file
# for bitlocker drives the password will be written to the .mbl.rc file only
# cannot change the password on the bitlocker drive.
if ($opt_c) {
	# %files = ("verafile" => [list of vera files],
	#           "bllabel"  => [list of bitlocker labels],
	#           "unknown"  => [list of unknown labels])
	my %files = ();
	# opt_c may be "all" or string of items

	# required to determine if the disk containing the vera file is available for mounting
	makeattachedveralists();
	getvfilesandbllabels($opt_c, \%files);

	# change the passwords for bitlocker devices
	for (my $i = 0; $i < @{$files{"bllabel"}}; $i++) {
		$passman->changepwd($files{"bllabel"}->[$i]);
	}

	# list of disks that need to be unmounted after password changes
	# disk_label => disk_mountpint
	my %disksmounted = ();

	# change passwords for vera files
	for (my $i = 0; $i < @{$files{"verafile"}}; $i++) {

		# get disk label to check if it is mounted
		my $vfile = $files{verafile}->[$i];		

		# get mount point
		my $dlabel = getdlabelfromvfile($vfile);	

		# the vera file must be available to change the password
		if (! grep /^$vfile$/, @attachedverafiles) {
			# vfile is not available
			print "$vfile is not available\n";
			print "\n";
		} else {
			# check if vera disk containing vera file is mounted			
			my $dmtpt = $vdevice{$dlabel}->[0];
			my $rc = system("findmnt -l --all $dmtpt > /dev/null 2>&1");
			unless ($rc == 0) {
				# disk containing vfile not mounted, mount it
				print "mounting $dlabel at $dmtpt\n";
				mkdir $dmtpt unless -d $dmtpt;
				$rc = system("sudo mount $dmtpt");

				# if disk cannot be mounted skip to next verafile
				if ($rc == 0) {
					# list of disks to be unmounted
					$disksmounted{$dlabel} = $dmtpt;
				} else {
					print "could not change password for $vfile, could not mount $dlabel\n";
					next;
				}
			} 
			# change the password
			my ($curpwd, $newpwd) = $passman->changepwd($vfile);
			print "changing password for $vfile\n";
			# find veracrypt for using as a random source
			# if not found use /usr/local/bin/mbl.pl
			my $filesource = `which veracrypt`;
			$filesource = "/usr/local/bin/mbl.pl" unless $filesource;
			chomp $filesource;
			system("veracrypt -C $vfile --new-password=$newpwd --password=$curpwd --new-keyfiles= --pim=0 --new-pim=0 --random-source=$filesource");
			print "\n";
		} # end if ! dlabel
	} # end for $i = 0

	# unmount disks that were mounted
	foreach my $dlabel (keys (%disksmounted)) {
		my $rc = system("sudo umount $disksmounted{$dlabel}");
		print "Could not umount $dlabel at $disksmounted{$dlabel}\n" unless $rc == 0;
	}
	
	# print error message for unknowns
	for (my $i = 0; $i < @{$files{"unknown"}}; $i++) {
		print "$files{unknown}->[$i] is unknown\n";
	}

}
# to unmount devices
if ($opt_u) {
	# unmount bitlocker drives and / or vera containers.
	# if the disk was mounted by this programme then it will be unmounted as well
	# the argument can be all or
	# any one of: veramtpt, vera container, disk label, bit locker mountpoint
	makeattachedveralists();
	# make a list of mounted drives, vera mountpoints and bitlocker mountpoints
	listmounteddev();
	umount($opt_u);
}
# to list all bitlocker drives and veracrypt containers
if ($opt_l) {
	# read mounted devices from files
	makeattachedveralists();
	listmounteddev();

	# %vmounts = (dlabel => {vfile => veramtpt})
	# %blmounts = (dmtpt => [dlabel, encmountpt)
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
		printf "%-40s\t\t %s\n", "veracrypt file", "mount point";		
		foreach my $vfile (keys(%{$vmounts{$dlabel}})) {
			printf "%-40s\t\t %s\n", $vfile, $vmounts{$dlabel}->{$vfile};
			
		}
		print "\n";
	}
	# display all bitlocker drives
	my $no_keys = keys(%blmounts);
	if ($no_keys == 0) {
		print "no bitlocker drives mounted\n";
	} else {
		printf "%-40s\t\t %-20s %s\n", "disk label", "enc mount point", "disk mount point";
		foreach my $dmtpt (keys(%blmounts)) {
			printf "%-40s\t\t %-20s %s\n", $blmounts{$dmtpt}->[0], $blmounts{$dmtpt}->[1], $dmtpt;
		}
	}
}

# if -m given to mount everything or any combo of bitlocker drives or vera containers
if ($opt_m) {
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
		# make a list of command line arguments
		my @clarg = split /\s+/, $opt_m;
		my @blmtpts = ();
		my @vlist = ();

		# for each command line argument
		# if it is bitlocker label of mountpoint - add mountpoint to @blmtpts
		# if it is a vera file or vera mount point or vera disk label -- add it to @vlist
		# print and error message for unknown command line parameters

		# make a list of all possible vera arguments
		my @veraargs = (@attachedveralabels, @attachedverafiles, @attachedveramtpts);

		# make a hash of attached bitlocker devices
		# disk_label => blmtpt
		my %bldevices = ();
		foreach my $blmtpt (keys(%attachedblmtpts)) {
			# get the disk label for the key
			my $disk_label = $attachedblmtpts{$blmtpt}->[1];

			# make the bldevices hash
			$bldevices{$disk_label} = $blmtpt;
		}
		
		# check each argument
		foreach my $clarg (@clarg) {
			# is argument a bitlocker or vera or unknown
			if (grep /^$clarg$/, @veraargs) {
				# arg is a valid vera device
				push @vlist,  $clarg ;

			# bldevices: disk_label => blmtpt
			} elsif (grep /^$clarg$/, (values(%bldevices))) {
				# clarg is bitlocker mount point
				push @blmtpts, $clarg;
				
			# bldevices: disk_label => blmtpt
			} elsif (grep /^$clarg$/, (keys(%bldevices))) {
				# clarg is bitlocker label
				# add the blmtpt
				push @blmtpts, $bldevices{$clarg};
			} else {
				# the argument is unknown
				print "$clarg is unknown\n"; 
			}
		}

		###########################################
		# testing
		###########################################
		# print "\@vlist = @vlist\n";
		# print "\@blmtpts = @blmtpts\n";

		###########################################
		# only call the subs if there are devices to mount
		findbitlockerdevices(@blmtpts) if defined $blmtpts[0];
		mountvera(@vlist) if defined $vlist[0];

	} # end if $opt_m
	# all mounted, so exit
	exit 0;
}
