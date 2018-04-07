#========================================================================
#
# Rmexp::Lib package
#
# DESCRIPTION
#
#   This library defines a Rmexp::Lib class and a variety of utility
#   functions used by BackupExpire and BackupFullExpire subs.
#
# AUTHOR
#   Alexander Moisseev <moiseev@mezonplus.ru>
#
# COPYRIGHT
#   Copyright (C) 2015  Alexander Moisseev
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#========================================================================

package Rmexp::Lib;

use strict;

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(%BackupList);
our (%BackupList);

sub new {
    my $class = shift;
    my $self  = {};
    bless $self, $class;
    return $self;
}

sub timeStamp {
    return "";
}

sub BackupInfoRead {
    my ( $bpc, $client ) = @_;
    my @Backups;

    # AM: sub BackupExpire requires sorted backups array (oldest first).
    map {
        push @Backups, {

            startTime => $_,
            num       => $BackupList{$client}{$_}{fileName},
            level     => $BackupList{$client}{$_}{level},
            type      => ( $BackupList{$client}{$_}{level} ? "incr" : "full" ),
            noFill    => ( $BackupList{$client}{$_}{level} ? 1 : 0 ),
            version   => "",    # Empty means preV4
        };
    } sort keys %{ $BackupList{$client} };

    return @Backups;
}

sub BackupInfoWrite {
    #my ( $bpc, $client, @Backups ) = @_;
    #map { print $_->{num}, "\n" } @Backups;
}

1;
