#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Get::OMPI_Snapshot;

use strict;
use Cwd;
use File::Basename;
use MTT::Messages;
use MTT::Files;
use MTT::FindProgram;
use Data::Dumper;

# Checksum filenames
my $md5_checksums = "md5sums.txt";
my $sha1_checksums = "sha1sums.txt";

# snapshot filename
my $latest_filename = "latest_snapshot.txt";

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $force) = @_;

    my $ret;
    my $data;
    $ret->{success} = 0;

    # See if we got a url in the ini section
    my $url = $ini->val($section, "url");
    if (!$url) {
        $ret->{result_message} = "No URL specified in [$section]; skipping";
        Warning("$ret->{result_message}\n");
        return $ret;
    }
    Debug(">> OMPI_Snapshot got url: $url\n");

    # Make some dirs
    my $tarball_dir = MTT::Files::mkdir("tarballs");
    my $data_dir = MTT::Files::mkdir("data");
    Debug("Tarball dir: $tarball_dir\n");

    chdir($data_dir);
    unlink($latest_filename);
    MTT::Files::http_get("$url/$latest_filename");
    Abort("Could not download latest snapshot number -- aborting")
        if (! -f $latest_filename);
    $ret->{version} = `cat $latest_filename`;
    chomp($ret->{version});

    # see if we need to download the tarball
    my $tarball_name = "openmpi-$ret->{version}.tar.gz";
    my $found = 0;
    foreach my $mpi_section (keys(%{$MTT::MPI::sources})) {
        Debug(">> checking section: [$section]\n");
        next
            if ($section ne $mpi_section);

        my $source = $MTT::MPI::sources->{$section};
        if ($source->{module_name} eq "MTT::MPI::Get::OMPI_Snapshot" &&
            basename($source->{module_data}->{tarball}) eq
            $tarball_name) {

            # If we find one of the same name, that's good enough
            # -- OMPI snapshot tarballs are named such that
            # something of the same tarball name is guaranteed to
            # be the same tarball
            Debug(">> we have previously downloaded this tarball\n");

            # We have this tarball already.  If we're not forcing,
            # return nothing.
            if (!$force) {
                $ret->{success} = 1;
                $ret->{have_new} = 0;
                $ret->{result_message} = "Snapshot tarball has not changed (did not re-download)";
                return $ret;
            }
            Debug(">> but we're forcing, so we'll get a new one\n");
            
            # If we are forcing, then reset to get a new copy
            $found = 1;
            last;
        }

        # If we found one, bail
        last
            if ($found);
    }
    Debug(">> we have not previously downloaded this tarball\n")
        if (!$found);
    $ret->{have_new} = 1;

    # Download the tarball
    chdir($tarball_dir);
    unlink("$tarball_dir/$tarball_name");
    MTT::Files::http_get("$url/$tarball_name");
    Abort ("Could not download tarball -- aborting")
        if (! -f $tarball_name);
    chdir($data_dir);
        
    # get the checksums
    unlink($md5_checksums);
    MTT::Files::http_get("$url/$md5_checksums");
    
    unlink($sha1_checksums);
    MTT::Files::http_get("$url/$sha1_checksums");

    # compare the md5sum
    my $md5_file = `grep $ret->{version}.tar.gz $md5_checksums | cut -d\\  -f1`;
    chomp($md5_file);
    my $md5_actual = MTT::Files::md5sum("$tarball_dir/$tarball_name");
    Abort("md5sum from checksum file does not match actual ($md5_file != $md5_actual)")
        if ($md5_file ne $md5_actual);
    Debug(">> Good md5sum\n");

    # compare the sha1sum
    my $sha1_file = `grep $ret->{version}.tar.gz $sha1_checksums | cut -d\\  -f1`;
    chomp($sha1_file);
    my $sha1_actual = MTT::Files::sha1sum("$tarball_dir/$tarball_name");
    Abort("sha1sum from checksum file does not match actual ($sha1_file != $sha1_actual)")
        if ($sha1_file ne $sha1_actual);
    Debug(">> Good sha1sum\n");

    # now adjust the tarball name to be absolute
    $ret->{module_data}->{tarball} = "$tarball_dir/$tarball_name";
    $ret->{prepare_for_install} = "MTT::MPI::Get::OMPI_Snapshot::PrepareForInstall";

    # All done
    Debug(">> OMPI_Snapshot complete\n");
    $ret->{success} = 1;
    $ret->{result_message} = "Success";
    return $ret;
} 

#--------------------------------------------------------------------------

sub PrepareForInstall {
    my ($source, $build_dir) = @_;

    # Extract the tarball
    Debug(">> OMPI_Snapshot extracting tarball to $build_dir\n");
    my $orig = cwd();
    chdir($build_dir);
    my $ret = MTT::Files::unpack_tarball($source->{module_data}->{tarball}, 1);
    chdir($orig);
    Debug(">> OMPI_Snapshot finished extracting tarball\n");
    return $ret;
}

1;
