#!perl
use lib '.';
use t::Helper;
use Convos::Core::Backend;

my $backend = Convos::Core::Backend->new;

my $connections;
$backend->connections_p->then(sub { $connections = shift })->$wait_success('connections_p');
is_deeply $connections, [], 'connections';

my $users;
$backend->users_p->then(sub { $users = shift })->$wait_success('users_p');
is_deeply $users, [], 'users';

my $messages;
$backend->messages_p({}, {})->then(sub { $messages = shift })->$wait_success('messages_p');
is_deeply $messages, {end => true, messages => []}, 'messages';

my $notifications;
$backend->notifications_p({}, {})->then(sub { $notifications = shift })
  ->$wait_success('notifications_p');
is_deeply $notifications, {end => true, messages => []}, 'notifications';

my $user = bless {};
my $saved;
$backend->save_object_p($user)->then(sub { $saved = shift })->$wait_success('save_object_p');
is $saved, $user, 'save_object_p';

my $loaded;
$backend->load_object_p($user)->then(sub { $loaded = shift })->$wait_success('load_object_p');
is $saved, $user, 'load_object_p';

my $deleted;
$backend->delete_object_p($user)->then(sub { $deleted = shift })->$wait_success('delete_object_p');
is $deleted, $user, 'delete_object_p';

my $err;
$backend->emit_to_class_p('foo')->catch(sub { $err = shift })->$wait_success('emit_to_class_p');
is $err, 'No event handler for foo.', 'emit_to_class_p';

my @args;
sub handle_foo_p { shift; @args = @_; return Mojo::Promise->resolve }

$backend->on(foo => 'main');
$backend->emit_to_class_p(foo => 3, 4)->$wait_success('emit_to_class_p');
isa_ok shift(@args), 'Convos::Core::Backend';
is_deeply \@args, [3, 4], 'emit_to_class_p arguments';

done_testing;
