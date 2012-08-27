package CoGeX::Result::ListAnnotation;

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 NAME

CoGeX::Result::ListAnnotation

=head1 SYNOPSIS

This object uses the DBIx::Class to define an interface to the C<list_annotation> table in the CoGe database.

=head1 DESCRIPTION

Object for interacting with the List Annotations table in the CoGe database.
Has columns:

C<list_annotation_id> (Primary Key)
Type: INT, Default: undef, Nullable: no, Size: 11

C<list_id>
Type: INT, Default: undef, Nullable: no, Size: 11

C<annotation_type_id>
Type: INT, Default: undef, Nullable: no, Size: 11

C<annotation>
Type: TEXT, Default: undef, Nullable: no

C<link>
Type: VARCHAR, Default: "", Nullable: yes, size: 1024



Belongs to CCoGeX::Result::AnnotationType> via C<annotation_type_id>

Belongs to CCoGeX::Result::List> via C<list_id>

=head1 USAGE

 use CoGeX;

=head1 METHODS

=cut

__PACKAGE__->table("list_annotation");
__PACKAGE__->add_columns(
  "list_annotation_id",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 11 },
  "list_id",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 11 },
  "annotation_type_id",
  { data_type => "INT", default_value => undef, is_nullable => 1, size => 11 },
  "annotation",
  { data_type => "TEXT", default_value => undef, is_nullable => 0 },
  "link",
  { data_type => "VARCHAR", default_value => "", is_nullable => 1, size => 1024 },
);
__PACKAGE__->set_primary_key("list_annotation_id");

__PACKAGE__->belongs_to( annotation_type => 'CoGeX::Result::AnnotationType', 'annotation_type_id');
__PACKAGE__->belongs_to( list => 'CoGeX::Result::List', 'list_id');



################################################ subroutine header begin ##

=head2 type

 Usage     : $Annotation_obj->type->AnnotationType_object_method_or_value
 Purpose   : Shorthand for getting an Annotation Type from an Annotation object.
 Returns   : AnnotationType object.
 Argument  : 
 Throws    : None.
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub type
  {
    shift->annotation_type(@_);
  }

1;


################################################ subroutine header begin ##

=head2 info

 Usage     : $self->info
 Purpose   : returns a string of information about the annotation.  

 Returns   : returns a string
 Argument  : none
 Throws    : 
 Comments  : To be used to quickly generate a string about the annotation

See Also   : 

=cut

################################################## subroutine header end ##

sub info
{
	my $self = shift;
	my $info;
	$info .= $self->annotation;
	return $info;

}


=head1 BUGS


=head1 SUPPORT


=head1 AUTHORS

 Matt Bomhoff
 Eric Lyons

=head1 COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.


=head1 SEE ALSO
