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
my $rcfile = "mbl.rc";

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
	$cipher = new Crypt::CBC(-key    => $key,
						-cipher => 'Blowfish');
						
	return bless {}, $class;
}

# method to find file in mbl.rc
# returns undef if not found
# returns the decrypted password if found
# searchrc(file)
sub searchrc {
	my $self = shift;
	my $vfile = shift;
	# open resource file for reading
	if (open RCFILE, "<", $rcfile) {
		
		# search for for verafile
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
	# vera file not found return undef
	return undef;
}

# method to get the pwd if it exits in mbl.rc
# if it does not exist, it must be created.
# mbl.rc:  filename:encrypted_password
# getpwd(verafile)
sub getpwd {
	my $self = shift;
	my $vfile = shift;
		
	# search for password
	my $pwd = $self->searchrc($vfile);
	return $pwd if $pwd;
	
	# filename not found
	#prompt for the password
	print "password not found for $vfile\n";
	print "Enter password for $vfile\n";
	$pwd = <STDIN>;
	chomp($pwd);

	# encrypt the password
	my $encpwd = $cipher->encrypt_hex($pwd);

	# open in current directory for appending
	# create it if it does not exist
	open AFILE, ">>", $rcfile;
		
	#append it to the file
	print AFILE "$vfile:$encpwd\n";
	close AFILE;
	
	# return the password
	return $pwd;
}

# delete a password in the resource file
# delpwd(filename)
# returns true if successfull
# returns undef if filename not found
sub delpwd {
	my $self = shift;
	my $vfile = shift;

	# search for verafile
	my $pwd = $self->searchrc($vfile);
	return undef unless $pwd;
		
	# replace / with \/ for sed
	# delete password line in file
	$vfile =~ s/\//\\\//g;
	system("sed -i -e '/$vfile/d' $rcfile");
	return 1;
}
1;
