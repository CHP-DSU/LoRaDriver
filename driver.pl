use strict;
use warnings;
use Device::SerialPort qw( :PARAM :STAT 0.07);
use Socket;
use IO::Select;

#communication flags
my $ENQ = 'ENQ'; #enquire, is radio alive
my $ACK = 'ACK'; #acknowledge, yes
my $NAK = 'NAK'; #negative acknowledge, no
my $AVL = 'AVL'; #available, is there a radio message to read
my $MLN = 'MLN'; #message length, how long is the message that the radio has
my $TXO = 'TXO'; #ask radio to send message
my $RRQ = 'RRQ'; #read request, ask to see the message

#set up the IPC for the connected home server
my $port = 9150;
my $ip_address = '127.0.0.1';
my $socket;
socket($socket, 2,1,6);
bind($socket, 
	pack_sockaddr_in($port, inet_aton($ip_address)))
	or die "Could not bind to $ip_address:$port";
listen($socket, 1);
print "Connect on 127.0.0.1:9150...\n";
my $client = accept(CLIENT_SOCK, $socket);
print "Connected to client\n";

my $selector = IO::Select->new;
$selector->add(\*CLIENT_SOCK);

my $comname = '/dev/ttyACM0';

my $device = Device::SerialPort->new($comname);

if(!defined($device)) {
	print CLIENT_SOCK "Could not connect to radio\n";
	CLIENT_SOCK->flush();
	shutdown(CLIENT_SOCK, 2);
	close CLIENT_SOCK;
	shutdown($socket, 2);
	close $socket;
	die "Could not open serial connection";
}

#these params work for the M0 feather
$device->baudrate(9600);
$device->databits(8);
$device->parity('none');
$device->stopbits(1);

#$device->read_interval(10);
$device->read_char_time(250);
$device->read_const_time(2000);

$device->write_settings();

#test our connection to the device
my $write_count = $device->write($ENQ);
print "Write failed\n" unless $write_count == 3;

(my $byte_count, my $response) = $device->read(3);

if($response eq $ACK) {
	print "Connected to LoRa Radio\n"
} else {
	$device->close();
	print CLIENT_SOCK "Could not connect to radio\n";
	CLIENT_SOCK->flush();
	shutdown(CLIENT_SOCK, 2);
	close CLIENT_SOCK;
	shutdown($socket, 2);
	close $socket;
	die "Could not connect to radio";
}

#we are connected, begin the main loop
while(1) {
	#ask for a message and print it if there is one
	select(STDOUT);
	$device->write($AVL);
	($byte_count, $response) = $device->read(3);
	#print "Read $byte_count bytes: '$response'\n";
	if($response eq $ACK) {
		#ask for message length
		$device->write($MLN);
		($byte_count, $response) = $device->read(4);
		print "MLN response: '$response'\n";
		my $num_bytes = int($response);
		#ask for message
		$device->write($RRQ);
		($byte_count, $response) = $device->read($num_bytes);
		select(CLIENT_SOCK);
		print "Message from radio: $response\n";
		CLIENT_SOCK->flush();
		select(STDOUT);
	} elsif($byte_count != 3) {
		print "ERROR: bad response from device\n";
	}
	#try and read data from the socket
	my @readers = $selector->can_read(0);
	my $numreaders = @readers;
	if($numreaders == 1) {
		my $instruction = <CLIENT_SOCK>;
		if(defined($instruction) && $instruction ne '') {
			chomp $instruction;
			select(STDOUT);
			$device->write("TXO $instruction");
			print "client wants to send '$instruction'\n";
			#sleep(2);
			($byte_count, $response) = $device->read(4);
			print "$response: ";
			select(CLIENT_SOCK);
			if($response eq "OTXO") {
				print("OK\n");
			} elsif($response eq "ETXF") {
				print("FAIL\n");
			} else {
				print("UKNOWN\n");
			}
			CLIENT_SOCK->flush();
			select(STDOUT);
		}
	}
}
