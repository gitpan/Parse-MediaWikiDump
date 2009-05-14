package Parse::MediaWikiDump::link;

#you must pass in a fully populated link array reference
sub new {
	my ($class, $self) = @_;

	bless($self, $class);

	return $self;
}

sub from {
	my ($self) = @_;
	return $$self[0];
}

sub namespace {
	my ($self) = @_;
	return $$self[1];
}

sub to {
	my ($self) = @_;
	return $$self[2];
}

1;