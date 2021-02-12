package PassMan;
# PassMan class
# new opens mbl.rc for appending. Creates a new one if it does not exist
# new will prompt for the encryption key.
# getpwd(verafile) returns the if it exists
# getpwd will prompt for the password if not found in mbl.rc. It will then append the encrypted password
# delpwd(verafile) deletes a password.

use strict;
use warnings;
use Crypt::Blowfish;
use Crypt::CBC;
use Crypt::Digest;

# cipher
my $cipher;

# resource file
my $rcfile = "$ENV{'HOME'}/.mbl.rc";

# constructor
sub new {
	my $class = shift;
	my $pwddigest = "d6977fa7c0d49739f6adaf8dc14814f94b5595cb34ae3b39fd44432e616cf24c";
	# digest object
	my $di = new Crypt::Digest('SHA256');
	
	# prompt for a pass phrase for encryption
	
	print "Enter passphrase\n";
	my $key = <STDIN>;
	chomp($key);
	# check the password
	$di->reset();
	$di->add($key);
	my $keydigest = $di->hexdigest();

	# if the password is not valid
	while ($keydigest ne $pwddigest ) {
		print "Incorrect, try again\n";
		$key = <STDIN>;
		chomp($key);
		# check the password
		$di->reset();
		$di->add($key);
		$keydigest = $di->hexdigest();
	}
	
	# create cipher to check pass word
	$cipher = new Crypt::CBC(-pbkdf  => 'pbkdf2',
				          -key    => $key,
						-cipher => 'Blowfish');
						
	return bless {}, $class;
}

# method to find a device password in mbl.rc
# returns the decrypted password if found else returns undef
# searchrc(file)
sub searchrc {
	my $self = shift;
	my $vfile = shift;
	# open resource file for reading
	if (open RCFILE, "<", $rcfile) {
		
		# search for for verafile or bllabel
		while (my $line = <RCFILE>) {
			chomp($line);
			my ($file, $encpwd) = split /:/, $line;
			if ($file eq $vfile) {
				# vera file found
				# decrypt password and return it
				my $pwd = $cipher->decrypt_hex($encpwd);
				close RCFILE;
				return $pwd;
			}
		} # end while
		close RCFILE;
	
	} # end if
	# file not found return undef
	return undef;
}

# method to get the pwd if it exits in mbl.rc
# if it does not exist, it must be prompted for
# mbl.rc:  filename:encrypted_password
# getpwd(verafile)
sub getpwd {
	my $self = shift;
	my $device = shift;
		
	# search for password
	my $pwd = $self->searchrc($device);
	return $pwd if $pwd;
	
	# filename not found
	#prompt for the password
	print "password not found for $device\n";
	print "Enter password for $device\n";
	$pwd = <STDIN>;
	chomp($pwd);
	# write it to the file
	$self->writepwd($device, $pwd);
	
	# return the password
	return $pwd;
}
# write encrypted password to .mbl.rc
# requires: (device_file, password)
sub writepwd {
	my $self = shift;
	my $device = shift;
	my $pwd = shift;

	# encrypt the password
	my $encpwd = $cipher->encrypt_hex($pwd);

	# open in current directory for appending
	# create it if it does not exist
	open AFILE, ">>", $rcfile;
		
	#append it to the file
	print AFILE "$device:$encpwd\n";
	close AFILE;
}	

# delete a password in the resource file
# delpwd(vera_filename)
# returns true if successfull
# returns undef if filename not found
sub delpwd {
	my $self = shift;
	my $file = shift;

	# if file eq "all"
	# remove rcfile
	if ($file eq "all") {
		print "Answer yes if you want to delete $rcfile:\n";
		my $answer = <STDIN>;
		chomp($answer);
		if ($answer eq "yes") {
			unlink($rcfile);
			print "deleted $rcfile\n";
		}
	}	
	# search for verafile
	my $pwd = $self->searchrc($file);
	return undef unless $pwd;
		
	# replace / with \/ for sed
	# delete password line in file
	$file =~ s/\//\\\//g;
	system("sed -i -e '/$file/d' $rcfile");
	return 1;
}

# method to change a password in the .mbl.rc file
# this method requires a verafile or bllabel
# if the current password is found in the file
# a new password is prompted for, encrypted and placed in the file
# if the current password is not found, it is also prompted for.
# a list is returned (old password, new password)
sub changepwd {
	my $self = shift;
	my $device = shift;

	# check if the current password exists in the .mbl.rc file
	my $curpwd = $self->searchrc($device);

	# if password not found prompt for current password
	if (! $curpwd) {
		print "Current password not found for $device, enter it:\n";
		$curpwd = <STDIN>;
		chomp($curpwd);
	} else {
		# current password found, delete it
		$self->delpwd($device);
	}

	# prompt for the new password
	print "Enter the new password for $device\n";
	my $newpwd = <STDIN>;
	chomp($newpwd);

	# encrypt the new password and write it to the file
	$self->writepwd($device, $newpwd);
	return ($curpwd, $newpwd);	
}
	
1;
