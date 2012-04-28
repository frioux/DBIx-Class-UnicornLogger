package DBIx::Class::UnicornLogger::FromProfile;

use Moo;

extends 'DBIx::Class::UnicornLogger';

sub get_profile {
   my ($self, $profile_name) = @_;

   my $ret = {};
   if ($profile_name) {
      if (my $profile = $self->profiles->{$profile_name}) {
         $ret = $profile
      } else {
         warn "no such profile: '$_[1]', using empty profile instead";
      }
   }
   return $ret
}

sub profiles {
   my @good_executing = (
      executing =>
      eval { require Term::ANSIColor } ? do {
          my $c = \&Term::ANSIColor::color;
          $c->('blink white on_black') . 'EXECUTING...' . $c->('reset');
      } : 'EXECUTING...'
   );
   return {
      console => {
         tree => { profile => 'console' },
         clear_line => "\r\x1b[J",
         show_progress => 1,
         @good_executing,
      },
      console_monochrome => {
         tree => { profile => 'console_monochrome' },
         clear_line => "\r\x1b[J",
         show_progress => 1,
         @good_executing,
      },
      plain => {
         tree => { profile => 'console_monochrome' },
         clear_line => "DONE\n",
         show_progress => 1,
         executing => 'EXECUTING...',
      },
      demo => {
         tree => { profile => 'console' },
         format => '[%d][%F:%L]%n%m',
         clear_line => "DONE\n",
         show_progress => 1,
         executing => 'EXECUTING...',
      },
   }
}

sub BUILDARGS {
   my ($self, @rest) = @_;

   my %args = (
      @rest == 1
         ? %{$rest[0]}
         : @rest
   );

   %args = (
      %{$self->get_profile(delete $args{unicorn_profile})},
      %args,
   );

   return $self->next::method(\%args)
}

1;
