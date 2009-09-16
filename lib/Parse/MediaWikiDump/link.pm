package Parse::MediaWikiDump::link;

our $VERSION = '0.93';

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

=head1 NAME

Parse::MediaWikiDump::link - Object representing a link from one article to another

=head1 ABOUT

This object is used to access the data associated with each individual link between articles in a MediaWiki instance. 

=head1 METHODS

=over 4

=item $link->from

Returns the article id (not the name) that the link orginiates from.

=item $link->namespace

Returns the namespace id (not the name) that the link points to

=item $link->to

Returns the article title (not the id and not including the namespace) that the link points to

