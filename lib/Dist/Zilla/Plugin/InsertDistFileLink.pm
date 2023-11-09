package Dist::Zilla::Plugin::InserDistFileLink;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use Moose;
with (
    'Dist::Zilla::Role::FileMunger',
    'Dist::Zilla::Role::GetSharedFileURL',
    'Dist::Zilla::Role::FileFinderUser' => {
        default_finders => [':InstallModules', ':ExecFiles'],
    },
);

has hosting => (is => 'rw', default => sub {'metacpan'});
has include_files => (is => 'rw');
has exclude_files => (is => 'rw');
has include_file_pattern => (is => 'rw');
has exclude_file_pattern => (is => 'rw');

sub mvp_multivalue_args { qw(include_files exclude_files) }

use namespace::autoclean;

use File::Slurper qw(read_binary);
use URI;

sub munge_files {
    require HTML::Entities;

    my $self = shift;

    # check hosting configuration
    my $hosting = $self->hosting;

    my ($authority, $dist_name, $dist_version);
    my ($github_user, $github_repo);
    my ($gitlab_user, $gitlab_proj);
    my ($bitbucket_user, $bitbucket_repo);

    if ($hosting eq 'metacpan') {
        $authority = $self->zilla->distmeta->{x_authority};
        $self->$self->log_fatal(["Distribution doesn't have x_authority metadata"]) unless $authority;
        $self->$self->log_fatal(["x_authority is not cpan:"]) unless $authority =~ s/^cpan://;
        $dist_name = $self->zilla->name;
        $dist_version = $self->zilla->version;
    } elsif ($hosting eq 'github' || $hosting eq 'gitlab' || $hosting eq 'bitbucket') {
        my $resources = $self->zilla->distmeta->{resources};
        $self->log_fatal(["Distribution doesn't have resources metadata"]) unless $resources;
        $self->log_fatal(["Distribution resources metadata doesn't have repository"]) unless $resources->{repository};
        $self->log_fatal(["Repository in distribution resources metadata is not a hash"]) unless ref($resources->{repository}) eq 'HASH';
        my $type = $resources->{repository}{type};
        $self->log_fatal(["Repository in distribution resources metadata doesn't have type"]) unless $type;
        my $url = $resources->{repository}{url};
        $self->log_fatal(["Repository in distribution resources metadata doesn't have url"]) unless $url;
        if ($hosting eq 'github') {
            $self->log_fatal(["Repository type is not git"]) unless $type eq 'git';
            $self->log_fatal(["Repository URL is not github"]) unless ($github_user, $github_repo) = $url =~ m!github\.com/([^/]+)/([^/]+)\.git!;
        } elsif ($hosting eq 'gitlab') {
            $self->log_fatal(["Repository type is not git"]) unless $type eq 'git';
            $self->log_fatal(["Repository URL is not gitlab"]) unless ($gitlab_user, $gitlab_proj) = $url =~ m!gitlab\.com/([^/]+)/([^/]+)\.git!;
        } elsif ($hosting eq 'bitbucket') {
            $self->log_fatal(["Repository type is not git (mercurial not yet supported)"]) unless $type eq 'git';
            $self->log_fatal(["Repository URL is not bitbucket"]) unless ($bitbucket_user, $bitbucket_repo) = $url =~ m!bitbucket\.org/([^/]+)/([^/]+)\.git!;
        }
    } elsif ($hosting eq 'data') {
    } else {
        $self->log_fatal(["Unknown hosting value '%s'", $hosting]);
    }

    my $code_insert = sub {
        my ($path) = @_;
        $path =~ s!\\!/!g; # windows

        my $url = $self->get_shared_file_url($path);

        "=begin html\n\n<a href=\"$url\">" . HTML::Entities::encode_entities($path) . "</a><br />\n\n=end html\n\n";
    };

  FILE:
    for my $file (@{ $self->found_files }) {
        if ($self->include_files && @{ $self->include_files }) {
            unless (grep {$_ eq $file->name} @{$self->include_files}) {
                $self->log_debug(["Skipped file %s (not in include_files)", $file->name]);
                next FILE;
            }
        }
        if ($self->exclude_files && @{ $self->exclude_files }) {
            if (grep {$_ eq $file->name} @{$self->exclude_files}) {
                $self->log_debug(["Skipped file %s (in include_files)", $file->name]);
                next FILE;
            }
        }
        if (my $pat = $self->include_file_pattern) {
            unless ($file->name =~ /$pat/) {
                $self->log_debug(["Skipped file %s (doesn't match include_file_pattern)", $file->name]);
                next FILE;
            }
        }
        if (my $pat = $self->exclude_file_pattern) {
            if ($file->name =~ /$pat/) {
                $self->log_debug(["Skipped file %s (matches exclude_file_pattern)", $file->name]);
                next FILE;
            }
        }

        my $content = $file->content;
        if ($content =~ s{^#\s*FILE(?:\s*:\s*|\s+)(\S.+?)\s*$}{$code_insert->($1)}egm) {
            $self->log(["inserting file link into '%s'", $file->name]);
            $file->content($content);
        }
    }
}

__PACKAGE__->meta->make_immutable;
1;
# ABSTRACT: Insert links to distribution shared files into POD as HTML snippets

=for Pod::Coverage .+

=head1 SYNOPSIS

In F<share>, put some files e.g. F<foo.xlsx> and F<share/img1.png>.

In F<dist.ini>:

 [InsertDistFileLink]
 ;hosting=metacpan
 ;include_files=...
 ;exclude_files=...
 ;include_file_pattern=...
 ;exclude_file_pattern=...

In F<lib/Qux.pm> or F<script/quux>:

 ...

 # FILE: share/foo.xlsx
 # FILE: share/

 ...

After build, F<lib/Foo.pm> will contain:

 ...

 =begin html

 <a href="https://st.aticpan.org/source/CPANID/Your-Dist-Name-0.123/share/foo.xlsx" />foo.xlsx</a><br />

 =end html

 =begin html

 <a href="https://st.aticpan.org/source/CPANID/Your-Dist-Name-0.123/share/images/img1.png">image/img1.png</a><br />

 =end html


=head1 DESCRIPTION

This plugin finds C<# FILE> directive in your POD/code and replace it with a POD
containing HTML snippet to link to the file, using the selected hosting
provider's URL scheme.

Rationale: sometimes it's convenient to link to the distribution shared files in
HTML documentation. In POD there's currently no mechanism to do this.

The C<#FILE> directive must occur at the beginning of line and must be followed
by path to the image (relative to the distribution's root).

Shared files deployed inside a tarball (such as one created using
L<Dist::Zilla::Plugin::ShareDir::Tarball>) are not yet supported.


=head1 CONFIGURATION

=head2 hosting => str (default: metacpan)

Choose hosting provider. Available choices:

=over

=item * metacpan

This is the default because all distributions uploaded to PAUSE/CPAN will
normally show up on L<metacpan.org>. Note that some people advise not to abuse
metacpan.org to host images because metacpan.org is not an image hosting
service. However, at the time of this writing, I couldn't find any mention of
this in the metacpan.org FAQ or About pages.

=item * github

This can only be used if the distribution specifies its repository in its
metadata, and the repository URL's host is github.com.

=item * gitlab

This can only be used if the distribution specifies its repository in its
metadata, and the repository URL's host is gitlab.com.

=item * bitbucket

This can only be used if the distribution specifies its repository in its
metadata, and the repository URL's host is bitbucket.org.

=back

=head2 include_files => str+

=head2 exclude_files => str+

=head2 include_file_pattern => re

=head2 exclude_file_pattern => re


=head1 SEE ALSO
