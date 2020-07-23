#!/usr/bin/perl -w

# script to un mount bitlocker and veracrypt drives that were mounted.
# the file /tmp/listmounted must exist
# the file /tmp/veradirlist lists all the directores created for vera drives
# they are also deleted.


# unmount all veracrypt files and delete the created directories
system("veracrypt -d");
# the file /tmp/veralist has lines: dlabel:dmtpt:vfile:vmtpt
if (open (VERALIST, "/tmp/veralist")) {
	# rmdir dir from each line
	while (my $line = <VERALIST>) {
		chomp ($line);
		my $vmtpt = (split /:/, $line)[3];
		print "removing directory $vmtpt\n";
		rmdir $vmtpt;
	}
	# for spacing
	print "\n";
	# close and delete file
	close(VERALIST);
	unlink("/tmp/veralist");
}

# unmount all disk drives that were mounted for vera files
# only drives that were mounted by mbl.pl will be unmounted
if (open(VDRIVELIST, "/tmp/veradrivelist")) {

	# unmount each disk drive
	while ($path = <VDRIVELIST>) {
		chomp($path);
		print "unmounting $path\n";
		system("umount $path");
	}
	# for spacing
	print "\n";
	# close and delete
	close(VDRIVELIST);
	unlink "/tmp/veradrivelist";
}

# unmount bitlocker drives
# open list for reading
if ( open (BLOCKMOUNTED, "/tmp/bitlockermounted")) {

	# read each line and unmount
	while ($line = <BLOCKMOUNTED>) {

		# read directory and file mounted
		chomp($line);
		($mdirectory, $file, $created) = split(/:/, $line);
		print "umount $mdirectory\n";
		system ("umount $mdirectory");
		print "umount $file\n";
		system ("umount $file");
		rmdir ("$mdirectory") if $created eq "created";
		rmdir ("$file");
	}
	# close and unlink
	close (BLOCKMOUNTED);
	unlink "/tmp/bitlockermounted";

}
