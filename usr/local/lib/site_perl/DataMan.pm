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
	%{$blref} = ("7150343d-01" => [qw(/mnt/axiz axiz)],
				"7f8f684f-78e2-4903-903a-c5d9ab8f36ee" => [qw(/mnt/drivec drivec)],
				"766349ae-03" => [qw(/mnt/ddd ddd)],
				"3157edd8-01" => [qw(/mnt/chaos chaos)],
		       	"78787878-01" => [qw(/mnt/ver4 ver4)]);

	# the hash vdevice contains 
	# partition label => [drive mountpoint, {verafile => verafile_mountpoint}]
	%{$vfref} = ( 
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
				$vfref->{$record[1]} = [$record[2], {$record[3] => $record[4]}];
			} else {
				# unknown record
				print "$line is unkown\n";
			}
		} # end while
		close DATA;
	} # end if open
	
	return bless {}, $class;
}

1;
