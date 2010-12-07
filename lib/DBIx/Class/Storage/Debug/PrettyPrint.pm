package DBIx::Class::Storage::Debug::PrettyPrint;

use strict;
use warnings;

use base 'DBIx::Class::Storage::Statistics';

use SQL::Abstract::Tree;
use Log::Structured;
use Log::Sprintf;

__PACKAGE__->mk_group_accessors( simple => '_sqlat' );
__PACKAGE__->mk_group_accessors( simple => '_clear_line_str' );
__PACKAGE__->mk_group_accessors( simple => '_executing_str' );
__PACKAGE__->mk_group_accessors( simple => '_show_progress' );
__PACKAGE__->mk_group_accessors( simple => '_last_sql' );
__PACKAGE__->mk_group_accessors( simple => 'squash_repeats' );
__PACKAGE__->mk_group_accessors( simple => '_structured_logger' );

my %code_to_method = (
  C => 'log_package',
  c => 'log_category',
  d => 'log_date',
  F => 'log_file',
  H => 'log_host',
  L => 'log_line',
  l => 'log_location',
  M => 'log_subroutine',
  P => 'log_pid',
  p => 'log_priority',
  r => 'log_milliseconds_since_start',
  R => 'log_milliseconds_since_last_log',
);

sub new {
   my $class = shift;
   my $args  = shift;

   my $clear_line = $args->{clear_line} || "\r\x1b[J";
   my $executing  = $args->{executing}  || (
      eval { require Term::ANSIColor } ? do {
          my $c = \&Term::ANSIColor::color;
          $c->('blink white on_black') . 'EXECUTING...' . $c->('reset');
      } : 'EXECUTING...'
   );
   my $show_progress = $args->{show_progress};

   my $squash_repeats = $args->{squash_repeats};
   my $sqlat = SQL::Abstract::Tree->new($args);
   my $self = $class->next::method(@_);
   $self->_clear_line_str($clear_line);
   $self->_executing_str($executing);
   $self->_show_progress($show_progress);

   if ($args->{format}) {

      my $log_sprintf = Log::Sprintf->new({ format => $args->{format} });

      my $per_line_log_sprintf = Log::Sprintf->new({
         format => $args->{multiline_format}
      });

      my %formats = %{{
         map { $_->{conversion} => 1 }
         grep { ref $_ }
         map @{$log_sprintf->_formatter->format_hunker->($log_sprintf, $_)},
            grep $_,
            $log_sprintf->{format},
            $per_line_log_sprintf->{format}
      }};

      $self->_structured_logger(
         Log::Structured->new({
            category     => 'DBIC',
            priority     => 'TRACE',
            caller_depth => 2,
            log_event_listeners => [sub {
               my %struc = %{$_[1]};
               my (@msg, undef) = split /\n/, delete $struc{message};
               if ($args->{multiline_format}) {
                  $self->debugfh->print($log_sprintf->sprintf({
                     %struc,
                     message => shift @msg,
                  }) . "\n");
                  $self->debugfh->print($per_line_log_sprintf->sprintf({
                     %struc,
                     message => $_,
                  }) . "\n") for @msg;
               } else {
                  $self->debugfh->print($log_sprintf->sprintf({
                     %struc,
                     message => $_,
                  }) . "\n") for @msg;
               }
            }],
            map { $code_to_method{$_} => 1 }
            grep { exists $code_to_method{$_} }
            keys %formats
         })
      );
   }
   $self->squash_repeats($squash_repeats);

   $self->_sqlat($sqlat);
   $self->_last_sql('');

   return $self
}

sub print {
  my $self = shift;
  my $string = shift;
  my $bindargs = shift || [];

  my ($lw, $lr);
  ($lw, $string, $lr) = $string =~ /^(\s*)(.+?)(\s*)$/s;

  local $self->_sqlat->{fill_in_placeholders} = 0 if defined $bindargs->[0]
    && $bindargs->[0] eq q('__BULK_INSERT__');

  my $use_placeholders = !!$self->_sqlat->fill_in_placeholders;

  my $sqlat = $self->_sqlat;
  my $formatted;
  if ($self->squash_repeats && $self->_last_sql eq $string) {
     my ( $l, $r ) = @{ $sqlat->placeholder_surround };
     $formatted = '... : ' . join(', ', map "$l$_$r", @$bindargs)
  } else {
     $self->_last_sql($string);
     $formatted = $sqlat->format($string, $bindargs);
     $formatted = "$formatted : " . join ', ', @{$bindargs}
        unless $use_placeholders;
  }

  if ($self->_structured_logger) {
     $self->_structured_logger->log_event({
        message => "$lw$formatted$lr",
     })
  } else {
     $self->next::method("$lw$formatted$lr", @_)
  }
}

sub query_start {
  my ($self, $string, @bind) = @_;

  if(defined $self->callback) {
    $string =~ m/^(\w+)/;
    $self->callback->($1, "$string: ".join(', ', @bind)."\n");
    return;
  }

  $string =~ s/\s+$//;

  $self->print("$string\n", \@bind);

  $self->debugfh->print($self->_executing_str) if $self->_show_progress
}

sub query_end {
  $_[0]->debugfh->print($_[0]->_clear_line_str) if $_[0]->_show_progress
}

1;

=pod

=head1 NAME

DBIx::Class::Storage::Debug::PrettyPrint - Pretty Printing DebugObj

=head1 SYNOPSIS

 DBIC_TRACE_PROFILE=~/dbic.json perl -Ilib ./foo.pl

Where dbic.json contains:

 {
   "profile":"console",
   "show_progress":1,
   "squash_repeats":1
 }

=head1 METHODS

=head2 new

 my $pp = DBIx::Class::Storage::Debug::PrettyPrint->new({
   show_progress  => 1,             # tries it's best to make it clear that a SQL
                                    # statement is still running
   executing      => '...',         # the string that is added to the end of SQL
                                    # if show_progress is on.  You probably don't
                                    # need to set this
   clear_line     => '<CR><ESC>[J', # the string used to erase the string added
                                    # to SQL if show_progress is on.  Again, the
                                    # default is probably good enough.

   squash_repeats => 1,             # set to true to make repeated SQL queries
                                    # be ellided and only show the new bind params

   format => '[%d][%c]%n ** %m',    # both format and multiline format take the
   multiline_format => '   %m',     # formats defined in Log::Sprintf.  If only
                                    # format is defined it will be used for each
                                    # line of the log; if both are defined, format
                                    # will be used for the first line, and
                                    # multiline_format will be used for the rest
   # any other args are passed through directly to SQL::Abstract::Tree
 });


