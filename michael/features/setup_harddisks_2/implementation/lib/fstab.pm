#!/usr/bin/perl -w

#*********************************************************************
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# A copy of the GNU General Public License is available as
# `/usr/share/common-licences/GPL' in the Debian GNU/Linux distribution
# or on the World Wide Web at http://www.gnu.org/copyleft/gpl.html. You
# can also obtain it by writing to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
#*********************************************************************

use strict;

################################################################################
#
# @file fstab.pm
#
# @brief Generate an fstab file as appropriate for the configuration
#
# $Id$
#
# @author Christian Kern, Michael Tautschnig
# @date Sun Jul 23 16:09:36 CEST 2006
#
################################################################################

package FAI;

################################################################################
#
# @brief this function generates the fstab file from our representation of the
# partitions to be created.
#
# @reference config Reference to our representation of the partitions to be
# created
#
# @return list of fstab lines
#
################################################################################
sub generate_fstab {

  # config structure is the only input
  my ($config) = @_;

  # the file to be returned, a list of lines
  my @fstab = ();
      
  # wait for udev to set up all devices
  push @FAI::commands, "udevsettle --timeout=10";

  # walk through all configured parts
  # the order of entries is most likely wrong, it is fixed at the end
  foreach my $c ( keys %$config ) {

    # entry is a physical device
    if ( $c =~ /^PHY_(.+)$/ ) {
      my $device = $1;

      # make sure the desired fstabkey is defined at all
      defined( $config->{$c}->{fstabkey} )
        or die "INTERNAL ERROR: fstabkey undefined\n";

      # create a line in the output file for each partition
      foreach my $p ( sort keys %{ $config->{$c}->{partitions} } ) {

        # keep a reference to save some typing
        my $p_ref = $config->{$c}->{partitions}->{$p};

        # skip extended partitions
        next if ( $p_ref->{size}->{extended} );

        # skip entries without a mountpoint
        next if ( $p_ref->{mountpoint} eq "-" );

        # each line is a list of values
        my @fstab_line = ();

        # write the device name as the first entry; if the user prefers uuids
        # or labels, use these if available
        my @uuid = ();
        &execute_command_std(
          "/lib/udev/vol_id -u $device" . $p_ref->{number},
          \@uuid, 0 );

        # every device must have a uuid, otherwise this is an error (unless we
        # are testing only)
        ( $FAI::no_dry_run == 0 || scalar(@uuid) == 1 )
          or die "Failed to obtain UUID for $device"
          . $p_ref->{number} . "\n";

        # get the label -- this is likely empty
        my @label = ();
        &execute_command_std(
          "/lib/udev/vol_id -l $device" . $p_ref->{number},
          \@label, 0 );

        # using the fstabkey value the desired device entry is defined
        if ( $config->{$c}->{fstabkey} eq "uuid" ) {
          chomp( $uuid[0] );
          push @fstab_line, "UUID=" . $uuid[0];
        } elsif ( $config->{$c}->{fstabkey} eq "label" && scalar(@label) == 1 ) {
          chomp( $label[0] );
          push @fstab_line, "LABEL=" . $label[0];
        } else {
          # otherwise, use the usual device path
          push @fstab_line, $device . $p_ref->{number};
        }

        # next is the mountpoint
        push @fstab_line, $p_ref->{mountpoint};

        # the filesystem to be used
        push @fstab_line, $p_ref->{filesystem};

        # add the mount options
        push @fstab_line, $p_ref->{mount_options};

        # never dump
        push @fstab_line, 0;

        # order of filesystem checks; the root filesystem gets a 1, the others 2
        push @fstab_line, 2;
        $fstab_line[-1] = 1 if ( $p_ref->{mountpoint} eq "/" );

        # join the columns of one line with tabs, and push it to our fstab line array
        push @fstab, join( "\t", @fstab_line );

        # set the ROOT_PARTITION variable, if this is the mountpoint for /
        $FAI::disk_var{ROOT_PARTITION} = $fstab_line[0]
          if ( $p_ref->{mountpoint} eq "/" );

        # add to the swaplist, if the filesystem is swap
        $FAI::disk_var{SWAPLIST} .= " " . $device . $p_ref->{number}
          if ( $p_ref->{filesystem} eq "swap" );
      }
    } elsif ( $c =~ /^VG_(.+)$/ ) {
      my $device = $1;

      # create a line in the output file for each logical volume
      foreach my $l ( sort keys %{ $config->{$c}->{volumes} } ) {

        # keep a reference to save some typing
        my $l_ref = $config->{$c}->{volumes}->{$l};

        # skip entries without a mountpoint
        next if ( $l_ref->{mountpoint} eq "-" );

        # each line is a list of values
        my @fstab_line = ();

        # resolve the symlink to the real device
        # and write it as the first entry
        &execute_command_std(
          "readlink -f /dev/$device/$l", \@fstab_line, 0 );
        
        # remove the newline
        chomp( $fstab_line[0] );

        # make sure we got back a real device
        ( $FAI::no_dry_run == 0 || -b $fstab_line[0] ) 
          or die "Failed to resolve /dev/$device/$l\n";

        # next is the mountpoint
        push @fstab_line, $l_ref->{mountpoint};

        # the filesystem to be used
        push @fstab_line, $l_ref->{filesystem};

        # add the mount options
        push @fstab_line, $l_ref->{mount_options};

        # never dump
        push @fstab_line, 0;

        # order of filesystem checks; the root filesystem gets a 1, the others 2
        push @fstab_line, 2;
        $fstab_line[-1] = 1 if ( $l_ref->{mountpoint} eq "/" );

        # join the columns of one line with tabs, and push it to our fstab line array
        push @fstab, join( "\t", @fstab_line );

        # set the ROOT_PARTITION variable, if this is the mountpoint for /
        $FAI::disk_var{ROOT_PARTITION} = $fstab_line[0]
          if ( $l_ref->{mountpoint} eq "/" );

        # add to the swaplist, if the filesystem is swap
        $FAI::disk_var{SWAPLIST} .= " " . $fstab_line[0]
          if ( $l_ref->{filesystem} eq "swap" );
      }
    } elsif ( $c eq "RAID" ) {

      # create a line in the output file for each device
      foreach my $r ( sort keys %{ $config->{$c}->{volumes} } ) {

        # keep a reference to save some typing
        my $r_ref = $config->{$c}->{volumes}->{$r};

        # skip entries without a mountpoint
        next if ( $r_ref->{mountpoint} eq "-" );

        # each line is a list of values
        my @fstab_line = ();

        # write the device name as the first entry
        push @fstab_line, "/dev/md" . $r;

        # next is the mountpoint
        push @fstab_line, $r_ref->{mountpoint};

        # the filesystem to be used
        push @fstab_line, $r_ref->{filesystem};

        # add the mount options
        push @fstab_line, $r_ref->{mount_options};

        # never dump
        push @fstab_line, 0;

        # order of filesystem checks; the root filesystem gets a 1, the others 2
        push @fstab_line, 2;
        $fstab_line[-1] = 1 if ( $r_ref->{mountpoint} eq "/" );

        # join the columns of one line with tabs, and push it to our fstab line array
        push @fstab, join( "\t", @fstab_line );

        # set the ROOT_PARTITION variable, if this is the mountpoint for /
        $FAI::disk_var{ROOT_PARTITION} = "/dev/md" . $r
          if ( $r_ref->{mountpoint} eq "/" );

        # add to the swaplist, if the filesystem is swap
        $FAI::disk_var{SWAPLIST} .= " /dev/md$r"
          if ( $r_ref->{filesystem} eq "swap" );
      }
    } else {
      die "INTERNAL ERROR: Unexpected key $c\n";
    }
  }

  # cleanup the swaplist (remove leading space and add quotes)
  $FAI::disk_var{SWAPLIST} =~ s/^\s*/"/;
  $FAI::disk_var{SWAPLIST} =~ s/\s*$/"/;

  # sort the lines in @fstab to enable all sub mounts
  @fstab = sort { [split("\t",$a)]->[1] cmp [split("\t",$b)]->[1] } @fstab;

  # add a nice header to fstab
  unshift @fstab,
    "# <file sys>\t<mount point>\t<type>\t<options>\t<dump>\t<pass>";
  unshift @fstab, "#";
  unshift @fstab, "# /etc/fstab: static file system information.";

  # return the list of lines
  return @fstab;
}

1;
