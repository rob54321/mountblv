package DataMan;

use Term::ReadKey;
use strict;
use warnings;

# DataMan Class
# this class loads the known default bitlocker and veracrypt drive list into
# the hashes containing bitlocker and vera drives.
# If a file /root/.mbl.data exists, it is loaded in addition to the default values
#
# responsibilities:
# 1. loads the current known bitlocker drives and veracrypt files into the respective hashes
#    if resource file exists load those bitlocker and vera files as well
# 2. bitlocker and vera drives can be added to the resource file.
# 3. bitlocker and vera drives can be deleted from the resource file.
# 4. bitlocker and vera drives can be edited in the resource file.
#
# resource file: /root/.mbldata.rc contains extra bitlocker and vera files which have been added by mbl.pl
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

# class variables
# %allbldev = (part_uuid => [dmtpt, dlabel])
my %allbldev = ();

# %vdevice = (dlabel => [dmtpt, {vfile => vmtpt}])
my %vdevice = ();

# constructor.
# loads the default values for bitlocker and vera files.
# if there are addtional bitlocker and/or vera files in /root/.mbldata.rc, they are loaded as well
# the constructor takes two parameters
# DataMan(\%bitlockerdevs, \%veradevs)
# %bitlockerdevs = (part_uuid => [disk_mtpt, disk_label])
#%veradevs = (disk_label => [disk_mtpt, {verafile => veramtpt}])
sub new {
	my $class = shift;
	my $self;
	##########################################################
	# default values for bitlocker and vera files
	##########################################################
	# for bitlocker drives
	# the key is the partuuid
	# hash format  for each record: partuuid => [mountpoint disk_label]
	# if mount point is not given then /mnt/drive1, /mnt/drive2, etc will be used
	%allbldev = ("333e0c31-d9f1-40dd-b26e-33f6b820da54" => [qw(/mnt/drivec drivec)]);

	# the hash vdevice contains 
	# partition label => [drive mountpoint, {verafile => verafile_mountpoint}]
	%vdevice = ( 
		 ssd    => ['/mnt/ssd',  {'/mnt/ssd/backups/lynn/vera'   => '/mnt/verassd'}]	,
		 hd3    => ['/mnt/hd3',  {'/mnt/hd3/backups/lynn/vera'   => '/mnt/verahd3'}]	,
		 hd2    => ['/mnt/hd2',  {'/mnt/hd2/backups/lynn/vera'   => '/mnt/verahd2'}]	,
		 can    => ['/mnt/can',  {'/mnt/can/backups/lynn/vera'   => '/mnt/veracan'}]);

	# if the resource file exists, open and read it
	if (open MBLDATA, "<", $rcfile) {
		# get line
		while (my $line = <MBLDATA>) {
			# check if line is a bitlocker or vera file
			chomp($line);
			my @record = split /:/,$line;
			if ($record[0] eq "b") {
				# the record is a bitlocker record
				# %allbldev{partuuid} = [diskmountpt, disklabel]
				# each line:
				# for bitlocker drive:
				# b:partuuid:mount point:partition label
				#
				$allbldev{$record[1]} = [$record[2], $record[3]];
			} elsif ($record[0] eq "v") {
				# the record is a vera file
				# %vdevice{partition_label} = [drive mountpoint, {verafile => vera_mountpoint}]
				# each line:
				# v:partition label:partition mount point:full verafile name:vera mountpiont
				#
				# if the key $record[1] (part label) exists in the hash,
				# then the hash {verafile => vera_mountpoint }must be expanded instead.

				if (exists($vdevice{$record[1]})) {
					# key exists, so elements must be added to {verafile => vera_mountpoint}
					# check if the partition mount point is correct
					if ($vdevice{$record[1]}->[0] eq $record[2]) {
						# part mount point correct, insert into inner hash
						# record[3] = verafile
						# record[4] = vera mountpoint
						$vdevice{$record[1]}->[1]->{$record[3]} = $record[4];
					} else {
						# partition mount not the same
						# error in data
						print "error in $ENV{'HOME'}/.mbldata.rc for verafile $record[3]\n";
						print "actual mtpt: $vdevice{$record[1]}->[0] file mtpt: $record[2]\n";
						print "\n";
						sleep 1;
					}
				} else {
					# key does not exist, a new key can be added
					$vdevice{$record[1]} = [$record[2], {$record[3] => $record[4]}];
				} # end if else exists
				
			} # end if else record eq b
		} # end while
		close MBLDATA;
	} # end if open
	
	# set $self to [ref_to_allbldev, ref_to_vdevices];
	$self = [\%allbldev	, \%vdevice];
	bless $self, $class;
	return $self;
}

sub menu {
	my $self = shift;
	
	# show DataMan menu and get options
	my $exit = "false";
	while ($exit eq "false") {
		# show menu
		print "\nenter: (a) add (d) delete (e) edit (l) list (q) quit\n";
		my $entry = <STDIN>;
		chomp($entry);
		if ($entry eq "q") {
			# quit
			$exit = "true";
		} elsif ($entry eq "a") {
			# add and entry
			$self->add();
		} elsif ($entry eq "d") {
			# delete
			$self->delentry();
		} elsif ($entry eq "l") {
			# list file
			system("cat $rcfile");
			print "\n";
		} elsif ($entry eq "e") {
			# edit file
			system("nano $rcfile");
			#print "editing\n";
		} else {
			# unknown entry
			print "unknown entry\n";
		}
	} # end while exit
}

# this sub takes no parameters
# it displays the input format, accepts input, checks for duplicates,
# checks to see if input is malformed, formats the input and writes it to the rcfile.
# an error message is printed if a duplicate is entered
sub add {
	# read .mbldata.rc into a list
	# much easier to check
	open MBLDATA, "<", "$rcfile";
	my @mbldata = <MBLDATA>;
	close MBLDATA;
	chomp @mbldata;
	
	print "\nfor vera enter: v disk_label disk_mtpt vera_file vera_mtpt\n";
	print "for bit locker: b part_uuid disk_mtpt disk_label\n\n";
	my $vinput = <STDIN>;
	chomp($vinput);
	my @entry = split /\s+/,$vinput;

	# first check the validity of the input
	# then check for duplicate entries
	#check input: 5 items for vera, 4 items for bitlocker
	if (($entry[0] eq 'v' and @entry == 5) or ($entry[0] eq 'b' and @entry == 4)) {
		# check each line of mbldata for a duplicate vera file or vera mount point
		# or a duplicate bitlocker mount point
		# for vera:      $entry[3] = verafile, $entry[4] = vera_mtpt
		# for bitlocker: $entry[2] = disk mount point

		# entry: v dlabel dmtpt vfile vmtpt
		# or     b part_uuid dmtpt dlabel
		
		my $dupentry = "false";
		foreach my $line (@mbldata) {
			# check entry for vera file
			# entry v dlabel dmtpt vera_file vera_mtpt
			chomp($line);
			if ($entry[0] eq "v") {
				# search for vera_file or vera_mtpt in mbldata.rc
				# search between :xxx: and end of line $
				# also search for disk_label or disk_mtpt in mbldata.rc
				# ONLY in b records.
				if (($line =~ /:$entry[3]:|:$entry[3]$|:$entry[4]:|:$entry[4]$|
					^b.*:$entry[1]:|^b.*:$entry[1]$|^b.*:$entry[2]:|^b.*:$entry[2]$/)) {
					# duplicate entry found
					print "\n$vinput is a duplicate entry\n\n";
					$dupentry = "true";
					last;
				}
			# check entry for bit locker files
			# entry b partuui dmtpt dlabel
			} elsif ($entry[0] eq "b") {
				if (($line =~ /:$entry[2]:|$entry[2]$|:$entry[3]:|:$entry[3]$/)) {
					# duplicate entry found
					print "\n$vinput is a duplicate entry\n\n";
					$dupentry = "true";
					last;
				}
			}
		} # end foreach $line

		# append entry if it is not duplicated
		if ($dupentry eq "false") {
			# entry not a duplicate
			# format and append entry
			$vinput =~ s/\s+/:/g;
			print "adding: $vinput\n";
			open MBLDATA, ">>","$rcfile";
			print MBLDATA "$vinput\n";
			close MBLDATA;
		}
	} else {
		print "Entry malformed\n";
	}
}

# sub to delete entries in .mbldata.rc
# if a disk label is entered all those entries are deleted
sub delentry {
	# read data the file into an array
	# for easier matching
	open MBLDATA, "<", "$rcfile";
	my @mbldata = <MBLDATA>;
	chomp (@mbldata);
	close MBLDATA;

	print "\nEnter one or more of: mtpt|disk label|vera file|part_uuid\n";
	my $linput = <STDIN>;
	chomp($linput);
	my @input = split /\s+/, $linput;

	# no of items to delete, lines
	my $count = 0;

	#count how many lines match
	# display which lines will be deleted
	# make a list of lines to be deleted
	my @linestodel = ();

	foreach my $line (@mbldata) {
		foreach my $item (@input) {
			# each entry could be begining, middle or end of line
			# eg: v:trans:/mnt/trans:/mnt/trans/vera:/mnt/veratrans
			if ($line =~ /:$item:|:$item$|^$item:/) {
				$count++;
				push @linestodel, $line;
				print "$line\n";
			}
		}
	}

	print "\nDelete the above $count line(s)?(n/y)";
	ReadMode 4;
	my $input;
	while (not defined ($input = ReadKey(-1))) {}

	ReadMode 0;
	
	if ($input =~ /y|Y/) {
		# delete the lines
		# write mbldata list to file, excluding the lines to be deleted
		unlink $rcfile;
		open MBLDATA, ">>", "$rcfile";
		foreach my $line (@mbldata) {
			print MBLDATA "$line\n" unless grep /^$line$/, @linestodel;
		}
		close MBLDATA;
		print "\ndeleted\n";
	} else {
		print "\naborted\n";
	}
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
	my $self = shift;
	my $inputstring = shift;
	my $href = shift; # ref to empty hash
	my @args = split /\s+/, $inputstring;
		
	# make a lists of all known vera files, vera mtpts, bitlocker_dlabels and bitlocker_mtpts
	my @verafiles = ();
	my @veramtpts = ();
	my @bldlabels = ();
	my @blmtpts = ();
	
	# make a list of all known vera files and mtpts
	foreach my $dlabel (keys(%vdevice)) {
		push @verafiles, keys(%{$vdevice{$dlabel}->[1]});
		push @veramtpts, values(%{$vdevice{$dlabel}->[1]});
	}
	# make lists of all known bitlocker_dlabels and bitlocker_mtpts
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
1;
