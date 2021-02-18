package DataMan;
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
my $blref;
my $vfref;

# constructor.
# loads the default values for bitlocker and vera files.
# if there are addtional bitlocker and/or vera files in /root/.mbldata.rc, they are loaded as well
# the constructor takes two parameters
# DataMan(\%bitlockerdevs, \%veradevs)
# %bitlockerdevs = (part_uuid => [disk_mtpt, disk_label])
#%veradevs = (disk_label => [disk_mtpt, {verafile => veramtpt}])
sub new {
	my $class = shift;
	$blref = shift;
	$vfref = shift;
	
	##########################################################
	# default values for bitlocker and vera files
	##########################################################
	# for bitlocker drives
	# the key is the partuuid
	# hash format  for each record: partuuid => [mountpoint disk_label]
	# if mount point is not given then /mnt/drive1, /mnt/drive2, etc will be used
	%{$blref} = ("7f8f684f-78e2-4903-903a-c5d9ab8f36ee" => [qw(/mnt/drivec drivec)]);

	# the hash vdevice contains 
	# partition label => [drive mountpoint, {verafile => verafile_mountpoint}]
	%{$vfref} = ( 
		 ssd    => ['/mnt/ssd',  {'/mnt/ssd/vera'                => '/mnt/verassd'}]	,
		 hd3    => ['/mnt/hd3',  {'/mnt/hd3/backups/lynn/vera'   => '/mnt/verahd3'}]	,
		 hd2    => ['/mnt/hd2',  {'/mnt/hd2/backups/lynn/vera'   => '/mnt/verahd2'}]	,
		 hdint  => ['/mnt/hdint',{'/mnt/hdint/backups/lynn/vera' => '/mnt/verahdint'}]	,
		 win    => ['/mnt/win',  {'/mnt/win/lynn/vera'           => '/mnt/verawin'}]	,
		 can    => ['/mnt/can',  {'/mnt/can/backups/lynn/vera'   => '/mnt/veracan'}]);

	# if the resource file exists, open and read it
	if (open DATA, "<", $rcfile) {
		# get line
		while (my $line = <DATA>) {
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
				$blref->{$record[1]} = [$record[2], $record[3]];
			} elsif ($record[0] eq "v") {
				# the record is a vera file
				# %vdevice{partition_label} = [drive mountpoint, {verafile => vera_mountpoint}]
				# each line:
				# v:partition label:partition mount point:full verafile name:vera mountpiont
				#
				# if the key $record[1] (part label) exists in the hash,
				# then the hash {verafile => vera_mountpoint }must be expanded instead.

				if (exists($vfref->{$record[1]})) {
					# key exists, so elements must be added to {verafile => vera_mountpoint}
					# check if the partition mount point is correct
					if ($vfref->{$record[1]}[0] eq $record[2]) {
						# part mount point correct, insert into inner hash
						# record[3] = verafile
						# record[4] = vera mountpoint
						$vfref->{$record[1]}[1]->{$record[3]} = $record[4];
					} else {
						# partition mount not the same
						# error in data
						print "error in $ENV{'HOME'}/.mbldata.rc for verafile $record[3]\n";
						print "actual mtpt: $vfref->{$record[1]}[0] file mtpt: $record[2]\n";
						print "\n";
						sleep 1;
					}
				} else {
					# key does not exist, a new key can be added
					$vfref->{$record[1]} = [$record[2], {$record[3] => $record[4]}];
				} # end if else exists
				
			} # end if else record eq b
		} # end while
		close DATA;
	} # end if open
	####################################
	# testing #
	####################################
	#foreach my $key (keys(%{$vfref})) {
	#	foreach my $vfile (keys(  %{$vfref->{$key}[1]}  )) {
	#		print "$key $vfref->{$key}[0] $vfile $vfref->{$key}[1]->{$vfile}\n";
	#	}
	#}
	####################################
	# end of testing #
	####################################
	
	return bless {}, $class;
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
			print "deleting\n";
		} elsif ($entry eq "l") {
			# list file
			system("cat $rcfile");
			print "\n";
		} elsif ($entry eq "e") {
			# edit file
			print "editing\n";
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
		# check each line of mbldata for a duplicate vera file
		# or a duplicate bitlocker mount point
		# for vera:      $entry[3] = verafile
		# for bitlocker: $entry[2] = disk mount point
		my $dupentry = "false";
		foreach my $line (@mbldata) {
			if ((($line =~ /^v/) and ($line =~ /:$entry[3]:/))
			      or (($line =~ /^b/) and ($line =~ /:$entry[2]:/))) {
				# duplicate entry found
				print "\n$vinput is a duplicate entry\n\n";
				$dupentry = "true";
				last;
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
1;
