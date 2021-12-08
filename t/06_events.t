#!/usr/bin/perl

use warnings;
use strict;
use Test::More;
use POSIX;
use FindBin;
use Mojo::File qw(tempfile path);
use lib ("$FindBin::Bin/lib", "../lib", "lib");
use Mojo::IOLoop::ReadWriteProcess qw(process);
use Mojo::IOLoop::ReadWriteProcess::Session qw(session);
use Mojo::IOLoop::ReadWriteProcess::Test::Utils qw(attempt);

subtest SIG_CHLD => sub {
  my $test_script = "$FindBin::Bin/data/process_check.sh";
  plan skip_all =>
    "You do not seem to have bash, which is required (as for now) for this test"
    unless -e '/bin/bash';
  plan skip_all =>
"You do not seem to have $test_script. The script is required to run the test"
    unless -e $test_script;
  my $reached;
  my $collect = 0;

  my $p = process(sub { print "Hello\n" });
  $p->session->collect_status(0);
  $p->on(collect_status => sub { $collect++ });
  $p->session->on(
    SIG_CHLD => sub {
      my $self = shift;
      $reached++;
      waitpid $p->pid, 0;
    });

  $p->start;
  attempt {
    attempts  => 20,
    condition => sub { defined $reached && $reached == 1 },
    cb        => sub { $p->signal(POSIX::SIGTERM); sleep 1; }
  };

  is $reached, 1, 'SIG_CHLD fired';
  is $collect, 0, 'collect_status not fired';

  is(Mojo::IOLoop::ReadWriteProcess::Session->singleton->all_orphans->size, 0);
  is(Mojo::IOLoop::ReadWriteProcess::Session->singleton->all->size,         1);

  session->reset;
  my $p2 = process(execute => $test_script);
  $p2->session->collect_status(1);

  $reached = 0;

  $p2->on(
    SIG_CHLD => sub {
      my $self = shift;
      $reached++;
    });

  $p2->start;

  attempt {
    attempts  => 20,
    condition => sub { defined $reached && $reached == 1 },
    cb        => sub { $p2->signal(POSIX::SIGTERM); sleep 1; }
  };

  is $reached, 1, 'SIG_CHLD fired';
  ok defined($p2->exit_status), 'SIG_CHLD fired';

  is(Mojo::IOLoop::ReadWriteProcess::Session->singleton->all_orphans->size, 0);
  is(Mojo::IOLoop::ReadWriteProcess::Session->singleton->all->size,         1);
};

subtest collect_status => sub {
  session->reset;

  my $sigcld;
  my $p = process(sub { print "Hello\n" });
  $p->session->collect_status(0);
  $p->session->on(
    SIG_CHLD => sub {
      $sigcld++;
      waitpid $p->pid, 0;
    });
  $p->start;

  attempt {
    attempts  => 10,
    condition => sub { defined $sigcld && $sigcld == 1 },
    cb        => sub { $p->signal(POSIX::SIGTERM); sleep 1 }
  };

  is $sigcld, 1, 'SIG_CHLD fired';

  is(Mojo::IOLoop::ReadWriteProcess::Session->singleton->all_orphans->size, 0);
  is(Mojo::IOLoop::ReadWriteProcess::Session->singleton->all->size,         1);
};

subtest collect_from_signal_handler => sub {
  my $p = process(execute => '/usr/bin/true');
  my $collected = 0;
  my $orphan = 0;
  my $sig_chld = 0;
  $p->session->reset();
  $p->session->collect_status(1);
  $p->session->on(SIG_CHLD => sub { $sig_chld++});
  $p->session->on(collected => sub { $collected++ });
  $p->session->on(collected_orphan => sub { $orphan++ });
  $p->start();

  sleep 1;
  is($collected, 1, "Event collected apear without doing active wait()");
  is($orphan, 0, "No orphans where collected");

  $p->wait_stop();
  is($collected, 1, "No more collect events emitted");
  is($orphan, 0, "No more orphans events emitted");
  is($p->exit_status, 0 , '/usr/bin/true exited with 0');

  if (fork() == 0) {
      exec ('/usr/bin/true');
  }
  sleep 1;
  is($collected, 1, "No more collect events emitted (2)");
  is($orphan, 1, "Collect one orphan");
};

subtest emit_from_sigchld_off => sub {
  my $p = process(execute => '/usr/bin/true');
  my $collected = 0;
  my $orphan = 0;
  my $sig_chld = 0;
  $p->session->reset();
  $p->session->collect_status(1);
  $p->session->emit_from_sigchld(0);
  $p->session->on(SIG_CHLD => sub { $sig_chld++});
  $p->session->on(collected => sub { $collected++ });
  $p->session->on(collected_orphan => sub { $orphan++ });
  $p->start();

  sleep 1;
  is($collected, 0, "Event collected didn't appear from sighandler");
  is($orphan, 0, "No orphans where collected");

  $p->wait_stop();
  is($collected, 1, "No more collect events emitted");
  is($orphan, 0, "No more orphans events emitted");
  is($p->exit_status, 0 , '/usr/bin/true exited with 0');

  exec ('/usr/bin/true') if (fork() == 0);
  sleep 1;
  is($collected, 1, "No more collect events emitted (2)");
  is($orphan, 0, "collect_orphan didn't appear from sighandler");

  $p->session->consume_collected_info();
  is($collected, 1, "No more collect events emitted (3)");
  is($orphan, 1, "Collect one orphan");
};

done_testing();
