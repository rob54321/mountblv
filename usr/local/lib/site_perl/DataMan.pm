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

# class variables
my $blref;
my $vfref;

# constructor.
# read the file and fill the %allbldev and %vdevice hashes
# if the file does not exist, call the method to create a default one
# the constructor takes two parameters
# DataMan(\%bitlockerdevs, \%veradevs)
sub new {
	my $class = shift;
	$blref = shift;
	$vfref = shift;
	
	# if the resource file exists, open and read it
	# else create a default one
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
				$vfref->{$record[1])} = [$record[2], {$record[3] => $record[4]}];
			} else {
				# unknown record
				print "$line is unkown\n";
			}
		} # end while
		close DATA;
	} else {
		# resource file does not exist
		# create a new one.
		$class->createdefaultdata()
	} # end if open
	
	return bless {}, $class;
}

# method to create a default resource file
# the only parameter is the ref to the class
sub createdefaultdata {
	my $self = shift;
	
# obligatory end of class
1;
