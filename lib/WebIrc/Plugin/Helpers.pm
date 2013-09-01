package WebIrc::Plugin::Helpers;

=head1 NAME

WebIrc::Plugin::Helpers - Mojo's little helpers

=cut

use Mojo::Base 'Mojolicious::Plugin';
use WebIrc::Core::Util qw(format_time);
use constant DEBUG => $ENV{WIRC_DEBUG} ? 1 : 0;

my %AVATAR_CACHE;

my $URL_RE = do {
  # Modified regex from RFC 3986
  no warnings; # Possible attempt to put comments
  qw!https?:(//([^/?\#\s]*))?([^?\#\s]*)(\?([^\#\s]*))?(\#(\S+))?!;
};

my $YOUTUBE_INCLUDE
  = '<iframe width="390" height="220" src="//www.youtube-nocookie.com/embed/%s?rel=0&amp;wmode=opaque" frameborder="0" allowfullscreen></iframe>';

=head1 HELPERS

=head2 id_as

See L<WebIrc::Core::Util/id_as>.

=head2 as_id

See L<WebIrc::Core::Util/as_id>.

=head2 form_block

  %= form_block $name, class => [$str, ...] begin
  ...
  % end

The code above will create this markup:

  <div class="@$class" title="$error">
    ...
  </div>

In addition, <@$class> will contain "error" if C<$error> can be fetched from the
stash hash C<errors>, using C<$name> as key.

=cut

sub form_block {
  my $content = pop;
  my ($c, $field, %args) = @_;
  my $error = $c->stash->{errors}{$field} // '';
  my $classes = $args{class} ||= [];

  push @$classes, 'error' if $error;

  $c->tag(div => class => join(' ', @$classes), title => $error, $content);
}

=head2 format_conversation

  $c->format_conversation(\&iterator, \&callback);

Takes a list of JSON strings and turns them into a list of hash-refs where the
"message" key contains a formatted version with HTML and such. The result will
be passed on to the C<$callback>.

=cut

sub format_conversation {
  my($c, $conversation, $cb) = @_;
  my $delay = Mojo::IOLoop->delay;
  my @messages;

  while (my $message = $conversation->()) {
    $message->{embed} = '';
    $message->{uuid} ||= '';
    $message->{message} = _parse_message($c, $message, $delay) if $message->{message};

    push @messages, $message;
  }

  $delay->once(finish => sub { $c->$cb(\@messages) });
  $delay->begin->();    # need to do at least one step
}

sub _parse_message {
  my($c, $message, $delay) = @_;
  my $last = 0;
  my @chunks;

  _message_avatar($c, $message, $delay);
  $message->{highlight} ||= 0;

  # http://www.mirc.com/colors.html
  $message->{message} =~ s/\x03\d{0,15}(,\d{0,15})?//g;
  $message->{message} =~ s/[\x00-\x1f]//g;

  while($message->{message} =~ m!($URL_RE)!g) {
    my $url = $1;
    my $now = pos $message->{message};

    push @chunks, Mojo::Util::xml_escape(substr $message->{message}, $last, $now - length $url);
    push @chunks, _message_url($c, $url, $message, $delay);
    $last = $now;
  }

  push @chunks, Mojo::Util::xml_escape(substr $message->{message}, $last);
  return join '', @chunks;
}

sub _message_avatar {
  my($c, $message, $delay) = @_;
  my($lookup, $cache, $cb);

  $message->{avatar} = '//gravatar.com/avatar/0000000000000000000000000000?s=40&d=retro';
  $message->{nick} or return; # do not want to insert avatar unless a user sent the message
  $message->{host} or return; # old data does not have "host" stored because of a bug
  $lookup = join '@', @$message{qw/ user host /};
  $lookup =~ s!^~!!;
  $cache = $AVATAR_CACHE{$lookup} ||= {};

  if(defined $cache->{avatar}) {
    $message->{avatar} = $cache->{avatar};
    return;
  }
  if(!$cache->{messages}) {
    $cb = $delay->begin;
    $c->redis->get(
      "avatar:$lookup",
      sub {
        my($redis, $email) = @_;
        my $avatar = Mojo::Util::md5_sum($email || $lookup);
        $cache->{avatar} = "//gravatar.com/avatar/$avatar?s=40&d=retro";
        $_->{avatar} = $cache->{avatar} for @{ $cache->{messages} };
        $cb->();
      }
    );
  }

  push @{ $cache->{messages} }, $message;
}

sub _message_url {
  my($c, $url, $message, $delay) = @_;
  my $embed_ua = $c->stash->{embed_ua} ||= Mojo::UserAgent->new(request_timeout => 2, connect_timeout => 2);
  my $cb;

  if($url =~ m!youtube.com\/watch?.*?\bv=([^&]+)!) {
    $message->{embed} = sprintf $YOUTUBE_INCLUDE, $1;
  }
  else {
    $cb = $delay->begin;
    $embed_ua->head(
      $url => sub {
        my $ct = $_[1]->res->headers->content_type || '';
        $message->{embed} = $c->image($url, alt => 'Embedded media') if $ct =~ /^image/;
        $cb->();
      }
    );
  }

  return $c->link_to($url, $url, target => '_blank');
}

=head2 logf

See L<WebIrc::Core::Util/logf>.

=head2 redis

Returns a L<Mojo::Redis> object.

=cut

sub redis {
  my $c = shift;

  $c->stash->{redis} ||= do {
    my $log = $c->app->log;
    my $redis = Mojo::Redis->new(server => $c->config->{redis});

    $redis->on(
      error => sub {
        my ($redis, $err) = @_;
        $log->error('[REDIS ERROR] ' . $err);
      }
    );

    $redis;
  };
}

=head2 send_partial

Will render "partial" and L<send|Mojolicious::Controller/send> the result.

=cut

sub send_partial {
  my $c = shift;

  eval {
    $c->send($c->render(@_, partial => 1)->to_string)
  } or do {
    $c->app->log->error($@);
  };
}

=head2 timestamp_span

Returns a "E<lt>span>" tag with a timestamp.

=cut

sub timestamp_span {
  my ($c, $timestamp) = @_;

  return $c->tag(
    'span',
    class => 'timestamp',
    title => format_time($timestamp, '%e. %B'),
    format_time($timestamp, '%e. %b %H:%M:%S')
  );
}

=head1 METHODS

=head2 register

Will register the L</HELPERS> above.

=cut

sub register {
  my ($self, $app) = @_;

  $app->helper(form_block          => \&form_block);
  $app->helper(format_conversation => \&format_conversation);
  $app->helper(logf                => \&WebIrc::Core::Util::logf);
  $app->helper(format_time => sub { shift; format_time(@_); });
  $app->helper(redis => \&redis);
  $app->helper(as_id => sub { shift; WebIrc::Core::Util::as_id(@_) });
  $app->helper(id_as => sub { shift; WebIrc::Core::Util::id_as(@_) });
  $app->helper(send_partial => \&send_partial);
  $app->helper(timestamp_span => \&timestamp_span);
}

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;
