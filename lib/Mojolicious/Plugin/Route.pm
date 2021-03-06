package Mojolicious::Plugin::Route;

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util 'camelize';
use Mojo::Loader 'load_class';
use Carp;

use constant BASE => {
    files      => [],
    references => {}
};

our $VERSION = '0.09';

sub register {
    my ($self, $app, $conf) = @_;

    my ($moniker, $moniker_path) = $self->_get_moniker($app, $conf);
    my $namespace                = $conf->{namespace} // 'Route';
    my $inverse                  = $conf->{inverse} // undef;
    my $path_routes              = $app->home . '/lib/' . $moniker_path;

    croak "Routes path ($path_routes) does not exist!" unless -d $path_routes;

    $path_routes =~ s/\/$//;
    $path_routes .= '/' . $namespace;

    croak "Namespace ($namespace) does not exist!" unless -d $path_routes;

    $self->_find_files($path_routes);

    $self->_load_routes($app, $moniker, $namespace, $inverse);
    
    $self->_clean_base;
}

sub _find_files {
    my ($self, $path, $find) = @_;

    my $more;
    $find ||= '';

    # find files and folders
    for my $file ( glob($path . '/*' . $find) ) {
        if (-d $file) {
            $more = '/*';

            next;
        }

        push(@{BASE->{files}}, $1) if $file =~ /\/lib\/([\w\/]+)\.pm$/;
    }

    if ($more) {
        $find .= $more;
        $self->_find_files($path, $find);
    }
}

sub _load_routes {
    my ($self, $app, $moniker, $namespace, $inverse) = @_;

    my $base = $moniker . '::' . $namespace;
    
    my $routes = $app->routes;

    for my $file (@{BASE->{files}}) {
        $file =~ s/\//::/g;

        my $class = $self->_load_class($file);

        if ($class && $class->isa('MojoX::Route')) {            
            my $ref = $class->new(app => $app);

            $self->_any($routes, $ref, $file, $base, $inverse)   if $class->can('any');
            $self->_under($routes, $ref, $file, $base, $inverse) if $class->can('under');
            $self->_route($routes, $ref, $file, $base, $inverse) if $class->can('route');
        }
    }
}

sub _clean_base {
    @{BASE->{files}} = ();
    %{BASE->{references}} = ();
}

sub _any {
    my ($self, $routes, $ref, $file, $base, $inverse) = @_;

    my ($name, $ref_name) = $self->_ref_name($file, $base);
    
    my @params;
    push(@params, BASE->{references}->{$ref_name}) if $self->_valid_reference($ref_name);
    push(@params, $routes);    

    my $any = $ref->any($inverse ? reverse(@params) : @params);

    BASE->{references}->{$name} = $any if $any;
}

sub _under {
    my ($self, $routes, $ref, $file, $base, $inverse) = @_;

    my ($name, $ref_name) = $self->_ref_name($file, $base);
    
    my @params;
    push(@params, BASE->{references}->{$ref_name}) if $self->_valid_reference($ref_name);
    push(@params, $routes);    

    my $under = $ref->under($inverse ? reverse(@params) : @params);

    BASE->{references}->{$name} = $under if $under;
}

sub _route {
    my ($self, $routes, $ref, $file, $base, $inverse) = @_;

    my ($name, $ref_name) = $self->_ref_name($file, $base);
    
    my @params;
    push(@params, BASE->{references}->{$name})     if $self->_valid_reference($name);
    push(@params, BASE->{references}->{$ref_name}) if $self->_valid_reference($ref_name);
    push(@params, $routes);

    $ref->route($inverse ? reverse(@params) : @params);
}

sub _ref_name {
    my ($self, $name, $base) = @_;

    $name =~ s/${base}:://;
    my ($ref_name) = $name =~ /^([\w:]+)::\w+$/;

    return ($name, $ref_name);
}

sub _load_class {
    my ($self, $class) = @_;

    # load class
    my $e = load_class $class;

    return $class unless $e;

    return;
}

sub _get_moniker {
    my ($self, $app, $conf) = @_;

    # set path lib
    my $path = $app->home . '/lib/';

    # check if moniker is defined
    return ($conf->{moniker}, $conf->{moniker}) if $conf->{moniker} && -d $path . $conf->{moniker};

    # check if need camelize moniker
    my $moniker = camelize($app->moniker);
    
    # generate moniker path
    my $moniker_path = $moniker;
    $moniker_path    =~ s/::/\//g;
    
    return ($app->moniker, $app->moniker) unless -d $path . $moniker_path;

    return ($moniker, $moniker_path);
}

sub _valid_reference {
    my ($self, $name) = @_;
    
    return $name && defined BASE->{references}->{$name};
}

1;

__END__

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Route - Plugin to loader files of routes.

=head1 SYNOPSIS

    package MyApp::Route::Bar;
    use Mojo::Base 'MojoX::Route';

    sub under {
        my ($self, $r) = @_;

        $r->under('/bar');
    }

    1;

    package MyApp::Route::Bar::Foo;
    use Mojo::Base 'MojoX::Route';

    sub route {
        my ($self, $bar) = @_;

        $bar->get('/foo'); # GET /bar/foo
    }

    1;

=head1 DESCRIPTION

Mojolicious::Plugin::Route - Allows you to create routes through files that will be automatically loaded.

=head1 METHODS

=head2 route

    package MyApp::Route::Foo;
    use Mojo::Base 'MojoX::Route';

    sub route {
        my ($self, $r) = @_;

        # will create route /foo
        $r->get('/foo' => sub ($c) {...});
    }

    1;

Method route only creates routes, but the reference not is saved.

=head2 any

    package MyApp::Route::Baz;
    use Mojo::Base 'MojoX::Route';

    sub any {
        my ($self, $r) = @_;

        $r->any('/baz' => sub ($c) {...});
    }

    1;

    package MyApp::Route::Baz::Child;
    use Mojo::Base 'MojoX::Route';

    sub route {
        # receive reference of parent that is MyApp::Route::Baz
        my ($self, $baz) = @_;

        # will create route /baz/child
        $baz->get('/child' => sub ($c) {...});
    }

    1;

Reference of the method any will be saved to be used in the files with the same namespace, not to be saved you need return undef.

=head2 under

    package MyApp::Route::Bar;
    use Mojo::Base 'MojoX::Route';

    sub under {
        my ($self, $r) = @_;

        $r->under('/bar' => sub ($c) {...});
    }

    1;

    package MyApp::Route::Bar::Child;
    use Mojo::Base 'MojoX::Route';

    sub route {
        # receive reference of parent that is MyApp::Route::Bar
        my ($self, $bar) = @_;

        # will create route /bar/child
        $bar->get('/child' => sub ($c) {...});
    }

    1;

Similar to method any, the reference of the method under will be saved to be used in the files with the same namespace, not to be saved you need return undef.

=head1 OPTIONS

=head2 inverse

    # Mojolicious::Lite
    plugin Route => {inverse => 1};
    
Inverse option will pass the parameters with inverse format.

If you define inverse to L<Example 2|https://metacpan.org/pod/Mojolicious::Plugin::Route#Example-2> your methods need to receive parameters like this:

    sub under {
        my ($self, $r, $base) = @_; # parameters inverse
    }    

    sub route {    
        my ($self, $r, $base, $under_above) = @_; # parameters inverse
    }

=head2 namespace

    # Mojolicious::Lite
    plugin Route => {namespace => 'Foo'}; # $moniker::Foo

Namespace to load routes from, defaults to $moniker::Route.

=head1 EXAMPLES

=head2 Example 1

    package MyApp::Route::Admin;
    use Mojo::Base 'MojoX::Route';

    sub under {
        my ($self, $r) = @_;

        my $under = $r->under('/admin' => sub {
            my $c = shift;

            return 1 if $c->req->url->to_abs->userinfo eq 'Admin:Password';
            
            $c->res->headers->www_authenticate('Basic');
            $c->render(text => 'Authentication required!', status => 401);
            
            return;
        });
    }

    sub route {
        my ($self, $under_above, $r) = @_;
        
        $r->get('/login' => sub {
            shift->render(text => 'Login');
        });
        
        $under_above->get('/' => sub {
            shift->render(text => 'Admin');
        });
    }

    1;
    
=head2 Example 2

    package MyApp::Route::Base;
    use Mojo::Base 'MojoX::Route';

    sub under {
        my ($self, $r) = @_;

        $r->under('/base');
    }  
    
    1;
    
    package MyApp::Route::Base::Page;
    use Mojo::Base 'MojoX::Route';

    sub under {
        my ($self, $base, $r) = @_;

        $base->under('/page');
    }    
    
    sub route {    
        my ($self, $under_above, $base, $r) = @_;
        
        # will create route /base/page/foo
        $under_above->get('/foo' => sub {
            shift->render(text => 'Foo');
        }); 
        
        # will create route /base/bar
        $base->get('/bar' => sub {
            shift->render(text => 'Bar');
        });
        
        # will create route /baz
        $r->get('/baz' => sub {
            shift->render(text => 'Baz');
        });                       
    }
    
    1;
    
=head2 Example 3

    package MyApp::Route::Base;
    use Mojo::Base 'MojoX::Route';

    sub under {
        my ($self, $r) = @_;

        $r->under('/base');
    }

    1; 
    
    package MyApp::Route::Foo;
    use Mojo::Base 'MyApp::Route::Base';

    sub route {
        my ($self, $base) = @_;

        # will create route /base/foo
        $base->get('/foo' => sub {
            shift->render(text => 'Foo');
        });
    }

    1;
    
    package MyApp::Route::Baz;
    use Mojo::Base 'MyApp::Route::Base';

    sub route {
        my ($self, $base) = @_;

        # will create route /base/baz
        $base->get('/baz' => sub {
            shift->render(text => 'Baz');
        });
    }

    1;    
      

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Routes::Route>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=head1 AUTHOR

Lucas Tiago de Moraes, C<lucastiagodemoraes@gmail.com>.

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2021 by Lucas Tiago de Moraes.

This is free software; you can redistribute it and/or modify it under the same terms as the Perl 5 programming language system itself.

=cut
