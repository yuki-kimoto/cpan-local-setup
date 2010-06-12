package CPAN::Local::Setup::Base; # Copied from Mojo::Base

use strict;
use warnings;

# No imports because we get subclassed, a lot!
require Carp;

# Kids, you tried your best and you failed miserably.
# The lesson is, never try.
sub new {
    my $class = shift;

    # Instantiate
    return bless
      exists $_[0] ? exists $_[1] ? {@_} : {%{$_[0]}} : {},
      ref $class || $class;
}

# Performance is very important for something as often used as accessors,
# so we optimize them by compiling our own code, don't be scared, we have
# tests for every single case
sub attr {
    my $class   = shift;
    my $attrs   = shift;
    my $default = shift;

    # Check for more arguments
    Carp::croak('Attribute generator called with too many arguments') if @_;

    # Shortcut
    return unless $class && $attrs;

    # Check default
    Carp::croak('Default has to be a code reference or constant value')
      if ref $default && ref $default ne 'CODE';

    # Allow symbolic references
    no strict 'refs';

    # Create attributes
    $attrs = ref $attrs eq 'ARRAY' ? $attrs : [$attrs];
    my $ws = '    ';
    for my $attr (@$attrs) {

        Carp::croak(qq/Attribute "$attr" invalid/)
          unless $attr =~ /^[a-zA-Z_]\w*$/;

        # Header
        my $code = "sub {\n";

        # No value
        $code .= "${ws}if (\@_ == 1) {\n";
        unless (defined $default) {

            # Return value
            $code .= "$ws${ws}return \$_[0]->{'$attr'};\n";
        }
        else {

            # Return value
            $code .= "$ws${ws}return \$_[0]->{'$attr'} ";
            $code .= "if exists \$_[0]->{'$attr'};\n";

            # Return default value
            $code .= "$ws${ws}return \$_[0]->{'$attr'} = ";
            $code .=
              ref $default eq 'CODE'
              ? '$default->($_[0])'
              : '$default';
            $code .= ";\n";
        }
        $code .= "$ws}\n";

        # Store value
        $code .= "$ws\$_[0]->{'$attr'} = \$_[1];\n";

        # Return invocant
        $code .= "${ws}return \$_[0];\n";

        # Footer
        $code .= '};';

        # We compile custom attribute code for speed
        *{"${class}::$attr"} = eval $code;

        # This should never happen (hopefully)
        Carp::croak("Mojo::Base compiler error: \n$code\n$@\n") if $@;

        # Debug mode
        if ($ENV{MOJO_BASE_DEBUG}) {
            warn "\nATTRIBUTE: $class->$attr\n";
            warn "$code\n\n";
        }
    }
}

package CPAN::Local::Setup;

use strict;
use warnings;

our @ISA = ('CPAN::Local::Setup::Base');

use Carp 'croak';
use File::Copy 'move';
use File::Spec;
use File::Path 'mkpath';
use File::Basename 'basename';

__PACKAGE__->attr(
    cpan_conf_file => sub { shift->home . "/.cpan/CPAN/MyConfig.pm" });
__PACKAGE__->attr(
    cpan_urls => sub {
        ['ftp://ftp.yz.yamagata-u.ac.jp/pub/lang/cpan/',
         'ftp://ftp.ring.gr.jp/pub/lang/perl/CPAN/']
    }
);
__PACKAGE__->attr(install_dir     => sub { shift->home . "/local" });
__PACKAGE__->attr(os              => $^O);
__PACKAGE__->attr(shell           => sub { shift->_guess_shell });
__PACKAGE__->attr(shell_conf_file => sub { shift->_guess_shell_conf_file });
__PACKAGE__->attr(home            => $ENV{HOME});

sub setup {
    my $self = shift;
    
    # Not support Windows
    die "Not support Windows" if $self->os eq 'MSWin32';
    
    # Create install directory
    my $install_dir = $self->install_dir;
    unless (-d $install_dir) {
        mkpath $install_dir
          or die "Cannot create '$install_dir': $!";
    }
    
    # Edit CPAN.pm config file
    $self->edit_cpan_conf_file;
    
    # Edit shell config file
    $self->edit_shell_conf_file;
    
    # Message
    warn $self->success_message;
}

sub edit_cpan_conf_file {
    my $self = shift;
    
    # CPAN.pm config file
    my $conf_file = $self->cpan_conf_file;

    # Create CPAN.pm config file(for CPAN now)
    `echo | cpan` unless -f $conf_file;

    # Create CPAN.pm config file(for CPAN old?)
    `echo no | cpan` unless -f $conf_file;
    
    # Cannot create CPAN.pm config file
    croak "Cannot create CPAN.pm config file" unless -f $conf_file;
    
    # Temp file
    my $tmp_file = File::Spec->catfile(File::Spec->tmpdir, 
                                       basename($conf_file));
    
    # Open CPAN.pm config file
    open my $conf_fh, '<', $conf_file
      or die "Cannot open '$conf_file': $!";
    
    # Open output file
    open my $tmp_fh, '>', $tmp_file
      or croak "Cannot open '$tmp_file': $!";
    
    my $install_dir = $self->install_dir;
    
    # CPAN mirror URLs
    my @cpan_urls = map { "q[$_]" } @{$self->cpan_urls};
    my $cpan_urls = join ', ', @cpan_urls;
    
    # Read Config file
    while (my $line = <$conf_fh>) {
        
        # Edit CPAN.pm config file
        if($line =~ /^\s*\};/){
            print $tmp_fh 
                  "  'make_install_arg' => q[SITEPREFIX=$install_dir],\n" .
                  "  'makepl_arg' => q[INSTALLDIRS=site " .
                  "LIB=$install_dir/lib/perl5 PREFIX=$install_dir],\n" .
                  "  'mbuildpl_arg' => " .
                  "q[./Build --install_base $install_dir],\n" .
                  "  'urllist' => [$cpan_urls],\n" .
                  "};\n";
        }
        elsif($line !~ /^\s*'make_install_arg'/
           && $line !~ /^\s*'makepl_arg'/
           && $line !~ /^\s*'mbuildpl_arg'/
           && $line !~ /^\s*'urllist'/
        )
        {
            print $tmp_fh $line;
        }    
    }
    
    # Close
    close $conf_fh;
    close $tmp_fh;
    
    # Write temp file to config file
    move($tmp_file, $conf_file)
      or croak "Cannot move '$tmp_file' to '$conf_file': $!";
}

sub edit_shell_conf_file {
    my $self = shift;
    
    # Shell config file
    my $conf_file = $self->shell_conf_file;
    croak "Cannot find '$conf_file'" unless -f $conf_file;
    
    # Stamp
    my $stamp = '# @@ Added by CPAN local setup tool @@';
    
    # Temp file
    my $tmp_file = File::Spec->catfile(File::Spec->tmpdir, 
                                       basename($conf_file));
    
    # Open shell config file
    open my $conf_fh, '<', $conf_file
      or die "Cannot open '$conf_file': $!";
    
    # Open temp file
    open my $tmp_fh, '>', $tmp_file
      or croak "Cannot open file '$tmp_file': $!";
    
    # Print lines exept
    while (my $line = <$conf_fh>) {
        print $tmp_fh $line unless $line =~ /$stamp/;
    }
    
    # Install directory
    my $install_dir = $self->install_dir;
    
    # Lines
    my @lines;
    
    # Perl Library and PATH setting
    push @lines, $self->_set_env_command('PATH', "$install_dir/bin:\$PATH");
    push @lines, $self->_set_env_command('PERL5LIB',
                                         "$install_dir/lib/perl5:" .
                                         "$install_dir/lib/perl5/site_perl:" . 
                                         "\$PERL5LIB");
    
    # Free BSD
    if ($self->os eq 'freebsd') {
        # Prevent BSDPAN errors
        push @lines, $self->_set_env_command('PKG_DBDIR',
                                             "$install_dir/var/db/pkg");
        push @lines, $self->_set_env_command('PORT_DBDIR',
                                             "$install_dir/var/db/pkg");
        push @lines, $self->_set_env_command('INSTALL_AS_USER');
        push @lines, $self->_set_env_command('LD_LIBRARY_PATH',
                                             "$install_dir/lib");
    }
    
    # Print lines
    foreach my $line (@lines) { print $tmp_fh "$line $stamp\n" }
    
    # Close
    close $conf_fh;
    close $tmp_fh;
    
    # Write temp file to config file
    move $tmp_file, $conf_file
      or croak "Cannot move '$tmp_file' to '$conf_file': $!";
}

sub success_message {
    my $self = shift;
    
    my $message = "Setup is success!\n" .
                  "Excute the folloing command " .
                  "to reflect this setting to shell config file.\n" .
                  "source " . $self->shell_conf_file . "\n";
}

sub _guess_shell {
    my $self = shift;
    
    my $path = $ENV{SHELL};
    my $shell = $path =~ /\/sh/   ? 'sh' :
                $path =~ /\/ksh/  ? 'ksh' :
                $path =~ /\/bash/ ? 'bash' :
                $path =~ /\/zsh/  ? 'zsh' :
                $path =~ /\/csh/  ? 'csh' :
                $path =~ /\/tcsh/ ? 'tcsh' :
                undef;
    
    return $shell;
}

sub _guess_shell_conf_file {
    my $self = shift;
    
    # Shell
    my $shell = $self->shell;
    
    # Shorcut
    return unless $shell;
    
    # Config files
    my $conf_files = {
        sh   => '.profile',
        ksh  => '.kshrc',
        bash => '.bashrc',
        zsh  => '.zshrc',
        csh  => '.cshrc',
        tcsh => '.tcshrc'
    };
    
    # Config file
    my $conf_file = $self->home . "/" . $conf_files->{$shell};
    
    return $conf_file;
}

sub _set_env_command {
    my ($self, $name, $value) = @_;
    
    # Shell
    my $shell = $self->shell;
    
    # Shortcut
    return unless $shell;
    
    # Commands
    my $commands = {
        sh   => '_set_env_command_export',
        bash => '_set_env_command_export',
        ksh  => '_set_env_command_export',
        zsh  => '_set_env_command_export',
        csh  => '_set_env_command_setenv',
        tcsh => '_set_env_command_setenv'
    };
    
    # Command
    my $command = $commands->{$shell};
    
    # Command not found
    return unless $command;
    
    return $self->$command($name, $value);
}

sub _set_env_command_export {
    my ($self, $name, $value) = @_;
    
    # Shortcut
    return unless $name;
    
    # Command for setting env
    my $command = "$name=$value;" if $value;
    $command   .= "export $name;";
    
    return $command;
}

sub _set_env_command_setenv {
    my ($self, $name, $value) = @_;
    
    # Sortcut
    return unless $name;
    
    # Comman for setting env
    my $command = "setenv $name";
    $command   .= " $value" if $value;
    $command   .= ";";
    
    return $command;
}

package main;

use strict;
use warnings;

# Setup
CPAN::Local::Setup->new->setup;

1;
