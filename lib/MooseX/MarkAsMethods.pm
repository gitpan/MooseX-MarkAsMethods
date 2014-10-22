#
# This file is part of MooseX-MarkAsMethods
#
# This software is Copyright (c) 2011 by Chris Weyl.
#
# This is free software, licensed under:
#
#   The GNU Lesser General Public License, Version 2.1, February 1999
#
package MooseX::MarkAsMethods;
{
  $MooseX::MarkAsMethods::VERSION = '0.12';
}

# ABSTRACT: Mark overload code symbols as methods

use warnings;
use strict;

use namespace::autoclean;

use B::Hooks::EndOfScope;
use Moose 0.94 ();
use Moose::Util::MetaRole;

# debugging
#use Smart::Comments '###', '####';

{
    package MooseX::MarkAsMethods::MetaRole::MethodMarker;
{
  $MooseX::MarkAsMethods::MetaRole::MethodMarker::VERSION = '0.12';
}
    use Moose::Role;
    use namespace::autoclean;

    sub mark_as_method {
        my $self = shift @_;

        $self->_mark_as_method($_) for @_;
        return;
    }

    sub _mark_as_method {
        my ($self, $method_name) = @_;

        do { warn "$method_name is already a method!"; return }
            if $self->has_method($method_name);

        my $code = $self->get_package_symbol({
            name  => $method_name,
            sigil => '&',
            type  => 'CODE',
        });

        do { warn "$method_name not found as a CODE symbol!"; return }
            unless defined $code;

        $self->add_method($method_name =>
            $self->wrap_method_body(
                associated_metaclass => $self,
                name => $method_name,
                body => $code,
            ),
        );

        return;
    }
}

sub init_meta {
    my ($class, %options) = @_;
    my $for_class = $options{for_class};

    Moose::Util::MetaRole::apply_metaroles(
        for => $for_class,
        class_metaroles => {
           class => ['MooseX::MarkAsMethods::MetaRole::MethodMarker'],
        },
        role_metaroles => {
            role => ['MooseX::MarkAsMethods::MetaRole::MethodMarker'],
        },
    );

    return $for_class->meta;
}

sub import {
    my ($class, %args) = @_;

    my $target = scalar caller;
    return if $target eq 'main';
    $class->init_meta(for_class => $target);

    on_scope_end {

        my $meta = Class::MOP::Class->initialize($target);

        ### metaclass: ref $meta
        my %methods   = map { ($_ => 1) } $meta->get_method_list;
        my %symbols   = %{ $meta->get_all_package_symbols('CODE') };
        my @overloads = grep { /^\(/ } keys %symbols;

        ### %methods
        ### %symbols
        ### @overloads

        foreach my $overload_name (@overloads) {

            next if $methods{$overload_name};

            ### marking as method: $overload_name
            $meta->mark_as_method($overload_name);
            $methods{$overload_name} = 1;
            delete $symbols{$overload_name};
        }

        return;
    };

    namespace::autoclean->import(-cleanee => $target)
        if $args{autoclean};

    return;
}

1;



=pod

=head1 NAME

MooseX::MarkAsMethods - Mark overload code symbols as methods

=head1 VERSION

version 0.12

=head1 SYNOPSIS

    package Foo;
    use Moose;

    # mark overloads as methods and wipe other non-methods
    use MooseX::MarkAsMethods autoclean => 1;

    # define overloads, etc as normal

    package Baz;
    use Moose::Role;
    use MooseX::MarkAsMethods autoclean => 1;

    # overloads defined in a role will "just work" when the role is
    # composed into a class

    use constant foo => 'bar';

    # additional methods generated outside Class::MOP/Moose can be marked, too
    __PACKAGE__->meta->mark_as_method('foo');

    package Bar;
    use Moose;

    # order is important!
    use namespace::autoclean;
    use MooseX::MarkAsMethods;

    # ...

=head1 DESCRIPTION

MooseX::MarkAsMethods allows one to easily mark certain functions as Moose
methods.  This will allow other packages such as L<namespace::autoclean> to
operate without blowing away your overloads.  After using
MooseX::MarkAsMethods your overloads will be recognized by L<Class::MOP> as
being methods, and class extension as well as composition from roles with
overloads will "just work".

By default we check for overloads, and mark those functions as methods.

If 'autoclean => 1' is passed to import on use'ing this module, we will invoke
namespace::autoclean to clear out non-methods.

=for Pod::Coverage init_meta

=head1 TRAITS APPLIED

use'ing this package causes a trait to be applied to your metaclass (for both
roles and classes), that provides a mark_as_method() method.  You can use this
to mark newly generated methods at runtime (e.g. during class composition)
that some other package has created for you.

mark_as_method() is invoked with one or more names to mark as a method.  We die
on any error (e.g. name not in symbol table, already a method, etc).  e.g.

    __PACKAGE__->meta->mark_as_method('newly_generated');

e.g. say you have some sugar from another package that creates accessors of
some sort; you could mark them as methods via a method modifier:

    # called as __PACKAGE__->foo_generator('name', ...)
    after 'foo_generator' => sub {

        shift->meta->mark_as_method(shift);
    };

=head1 IMPLICATIONS FOR ROLES

Using MooseX::MarkAsMethods in a role will cause Moose to track and treat your
overloads like any other method defined in the role, and things will "just
work".  That's it.

=head1 CAVEATS

=head2 meta->mark_as_method()

B<You almost certainly don't need or want to do this.>  CMOP/Moose are fairly
good about determining what is and what isn't a method, but not perfect.
Before using this method, you should pause and think about why you need to.

=head2 namespace::autoclean

As currently implemented, we run our "method maker" at the end of the calling
package's compile scope (L<B::Hooks::EndOfScope>).  As L<namespace::autoclean>
does the same thing, it's important that if namespace::autoclean is used that
it be use'd BEFORE MooseX::MarkAsMethods, so that its end_of_scope block is
run after ours.

e.g.

    # yes!
    use namespace::autoclean;
    use MooseX::MarkAsMethods;

    # no -- overloads will be removed
    use MooseX::MarkAsMethods;
    use namespace::autoclean;

The easiest way to invoke this module and clean out non-methods without having
to worry about ordering is:

    use MooseX::MarkAsMethods autoclean => 1;

=head1 SEE ALSO

L<overload>, L<B::Hooks::EndOfScope>, L<namespace::autoclean>, L<Class::MOP>,
L<Moose>.

L<MooseX::Role::WithOverloading> does allow for overload application from
roles, but it does this by copying the overload symbols from the (not
namespace::autoclean'ed role) the symbols handing overloads during class
composition; we work by marking the overloads as methods and letting
CMOP/Moose handle them.

=head1 BUGS

Please report any bugs or feature requests to
C<bug-moosex-markasmethods at rt.cpan.org>, or through
the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=MooseX-MarkAsMethods>.

=head1 AUTHOR

Chris Weyl <cweyl@alumni.drew.edu>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2011 by Chris Weyl.

This is free software, licensed under:

  The GNU Lesser General Public License, Version 2.1, February 1999

=cut


__END__


