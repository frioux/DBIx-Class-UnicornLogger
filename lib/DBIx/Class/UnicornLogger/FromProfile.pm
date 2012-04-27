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
   my @simple_mf = ( multiline_format => '    %m'   );
   my @simple_cl = ( clear_line       => "\r\x1b[J" );
   my @good_executing = (
      executing =>
      eval { require Term::ANSIColor } ? do {
          my $c = \&Term::ANSIColor::color;
          $c->('blink white on_black') . 'EXECUTING...' . $c->('reset');
      } : 'EXECUTING...'
   );
   my @show_progress = ( show_progress => 1 );
   return {
      console => {
         @simple_mf,
         @simple_cl,
         @show_progress,
         @good_executing,
      },
      console_monochrome => {
         @simple_mf,
         @simple_cl,
         @show_progress,
         @good_executing,
      },
      plain => {
         @simple_mf,
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
