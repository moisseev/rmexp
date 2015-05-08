#============================================================= -*-perl-*-
#
# lib::Rmexp package
#
# DESCRIPTION
#
#   This module implements the rmexp actions.
#
# AUTHOR
#   Alexander Moisseev <moiseev@mezonplus.ru>
#
# COPYRIGHT
#   Copyright (C) 2015  Alexander Moisseev
#   Copyright (C) 2001-2013  Craig Barratt
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
#
# Module version 0.0.1, released 27 Mar 2015.
#
#========================================================================

package lib::Rmexp v0.0.1;

use strict;
use warnings;

use lib::Lib;

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw( &ConfigDataRead &BackupExpire %Conf $opt_d );

our ( %Conf, $opt_d );

my @Backups;

# Declarations for sub BackupExpire and sub BackupFullExpire
my $XferLOG;
my %opts = ( v => 1 );
*LOG = *STDOUT;

#
# Get an instance of BackupPC::Lib and get some shortcuts.
#
die("lib::Lib->new failed\n") if ( !( my $bpc = lib::Lib->new ) );

sub ConfigDataRead {
    unless ( my $ret = do "@_" ) {
        warn "Couldn't execute @_: $@" if $@;
        warn "Couldn't open @_: $!"    if $!;
        die;
    }
}

#
# Decide which old backups should be expired.
#
sub BackupExpire
{
    my($client) = @_;

    my($cntFull, $cntIncr, $firstFull, $firstIncr, $oldestIncr,
       $oldestFull, $changes);

    @Backups = $bpc->BackupInfoRead($client);
    if ( $Conf{FullKeepCnt} <= 0 ) {
        print(LOG $bpc->timeStamp,
                  "Invalid value for \$Conf{FullKeepCnt}=$Conf{FullKeepCnt}; not expiring any backups\n");
	print(STDERR
            "Invalid value for \$Conf{FullKeepCnt}=$Conf{FullKeepCnt}; not expiring any backups\n")
			    if ( $opts{v} );
        return;
    }

    if ( $Conf{FullPeriod} <= 0 ) {
	print "Invalid value for \$Conf{FullPeriod}=$Conf{FullPeriod}.", "\n";
        return;
    }

    if ( $Conf{IncrKeepCnt} <= 0 ) {
	print "Invalid value for \$Conf{IncrKeepCnt}=$Conf{IncrKeepCnt}.", "\n";
        return;
    }

    if ( $Conf{IncrKeepCntMin} <= 0 ) {
	print "Invalid value for \$Conf{IncrKeepCntMin}=$Conf{IncrKeepCntMin}.", "\n";
        return;
    }
    while ( 1 ) {
	$cntFull = $cntIncr = 0;
	$oldestIncr = $oldestFull = 0;
	for ( my $i = 0 ; $i < @Backups ; $i++ ) {
            $Backups[$i]{preV4} = ($Backups[$i]{version} eq "" || $Backups[$i]{version} =~ /^[23]\./) ? 1 : 0;
            if ( $Backups[$i]{preV4} ) {
                if ( $Backups[$i]{type} eq "full" ) {
                    $firstFull = $i if ( $cntFull == 0 );
                    $cntFull++;
                } elsif ( $Backups[$i]{type} eq "incr" ) {
                    $firstIncr = $i if ( $cntIncr == 0 );
                    $cntIncr++;
                }
            } else {
                if ( !$Backups[$i]{noFill} ) {
                    $firstFull = $i if ( $cntFull == 0 );
                    $cntFull++;
                } else {
                    $firstIncr = $i if ( $cntIncr == 0 );
                    $cntIncr++;
                }
            }
	}

	# AM $oldestIncr and $oldestFull are age in days of oldest backup
	$oldestFull = (time - $Backups[$firstFull]{startTime}) / (24 * 3600)
                        if ( $cntFull > 0 );

	if ($cntIncr > 0) {
	    $oldestIncr = (time - $Backups[$firstIncr]{startTime}) / (24 * 3600);

        $XferLOG->write(\"BackupExpire: cntFull = $cntFull, cntIncr = $cntIncr, firstFull = $firstFull,"
                   . " firstIncr = $firstIncr, oldestIncr = $oldestIncr, oldestFull = $oldestFull\n")
                                        if ( $XferLOG );

        #
        # In <= 3.x, with multi-level incrementals, several of the
        # following incrementals might depend upon this one, so we
        # have to delete all of the them.  Figure out if that is
        # possible by counting the number of consecutive incrementals
        # that are unfilled and have a level higher than this one.
        #
        # In >= 4.x any backup can be deleted since the changes get
        # merged with the next older deltas, so we just do one at
        # a time.
        #
        my $cntIncrDel = 1;
        my $earliestIncr = $oldestIncr;

	for ( my $i = $firstIncr + 1 ; $i < @Backups ; $i++ ) {
            last if ( !$Backups[$i]{preV4} || $Backups[$i]{level} <= $Backups[$firstIncr]{level}
                          || !$Backups[$i]{noFill} );
            $cntIncrDel++;
            $earliestIncr = (time - $Backups[$i]{startTime}) / (24 * 3600);
        }

	if ( $cntIncr >= $Conf{IncrKeepCnt} + $cntIncrDel
		|| ($cntIncr >= $Conf{IncrKeepCntMin} + $cntIncrDel
		    && $earliestIncr > $Conf{IncrAgeMax}) ) {
            #
            # Only delete an incr backup if the Conf settings are satisfied
            # for all $cntIncrDel incrementals.  Since BackupRemove() updates
            # the @Backups array we need to do the deletes in the reverse order.
            # 
            for ( my $i = $firstIncr + $cntIncrDel - 1 ;
                    $i >= $firstIncr ; $i-- ) {
                print("removing unfilled backup $Backups[$i]{num}\n") if $opt_d;
                $XferLOG->write(\"removing unfilled backup $Backups[$i]{num}\n") if ( $XferLOG );
                last if ( BackupRemove($client, $i, 1) );
                $changes++;
            }
            next;
        }
      }

        #
        # Delete any old full backups, according to $Conf{FullKeepCntMin}
	# and $Conf{FullAgeMax}.
        #
	# First make sure that $Conf{FullAgeMax} is at least bigger
	# than $Conf{FullPeriod} * $Conf{FullKeepCnt}, including
	# the exponential array case.
        #
	my $fullKeepCnt = $Conf{FullKeepCnt};
	$fullKeepCnt = [$fullKeepCnt] if ( ref($fullKeepCnt) ne "ARRAY" );
	my $fullAgeMax;
	my $fullPeriod = int(0.5 + $Conf{FullPeriod});
        $fullPeriod = 7 if ( $fullPeriod <= 0 );
	for ( my $i = 0 ; $i < @$fullKeepCnt ; $i++ ) {
	    $fullAgeMax += $fullKeepCnt->[$i] * $fullPeriod;
	    $fullPeriod *= 2;
	}
	$fullAgeMax += $fullPeriod;	# add some buffer

        if ( $cntFull > $Conf{FullKeepCntMin}
               && $oldestFull > $Conf{FullAgeMax}
               && $oldestFull > $fullAgeMax
	       && $Conf{FullKeepCntMin} > 0
	       && $Conf{FullAgeMax} > 0 ) {
            #
            # Only delete a full backup if the Conf settings are satisfied.
            #
            # For pre-V4 we also must make sure that either this backup is the
            # most recent one, or the next backup is filled.
            # (In pre-V4 we can't deleted a full backup if the next backup is not
            # filled.)
            # 
            if ( !$Backups[$firstFull]{preV4} || (@Backups <= $firstFull + 1
                        || !$Backups[$firstFull + 1]{noFill}) ) {
                print("removing filled backup $Backups[$firstFull]{num}\n") if $opt_d;
                $XferLOG->write(\"removing filled backup $Backups[$firstFull]{num}\n") if ( $XferLOG );
                last if ( BackupRemove($client, $firstFull, 1) );
                $changes++;
                next;
            }
        }

        #
        # Do new-style full backup expiry, which includes the the case
	# where $Conf{FullKeepCnt} is an array.
        #
        last if ( !BackupFullExpire($client, \@Backups) );
        $changes++;
    }
    $bpc->BackupInfoWrite($client, @Backups) if ( $changes );
}

#
# Handle full backup expiry, using exponential periods.
#
sub BackupFullExpire
{
    my($client, $Backups) = @_;
    my $fullCnt = 0;
    my $fullPeriod = $Conf{FillCycle} <= 0 ? $Conf{FullPeriod} : $Conf{FillCycle};
    my $startTimeDeviation = $fullPeriod < 1 ? $fullPeriod / 2 : 0.5;
    my $nextFull;
    my $fullKeepCnt = $Conf{FullKeepCnt};
    my $fullKeepIdx = 0;
    my(@delete, @fullList);

    #
    # Don't delete anything if $Conf{FillCycle}, $Conf{FullPeriod} or $Conf{FullKeepCnt}
    # are not defined - possibly a corrupted config.pl file.
    #
    return if ( !defined($Conf{FillCycle}) || !defined($Conf{FullPeriod})
                                           || !defined($Conf{FullKeepCnt}) );

    #
    # If regular backups are still disabled with $Conf{FullPeriod} < 0,
    # we still expire backups based on a safe FullPeriod value - daily.
    #
    $fullPeriod = 1 if ( $fullPeriod <= 0 );

    $fullKeepCnt = [$fullKeepCnt] if ( ref($fullKeepCnt) ne "ARRAY" );

    for ( my $i = 0 ; $i < @$Backups ; $i++ ) {
        if ( $Backups[$i]{preV4} ) {
            next if ( $Backups->[$i]{type} ne "full" );
        } else {
            next if ( $Backups->[$i]{noFill} );
        }
        push(@fullList, $i);
    }
    for ( my $k = @fullList - 1 ; $k >= 0 ; $k-- ) {
        my $i = $fullList[$k];
        my $prevFull = $fullList[$k-1] if ( $k > 0 );
        #
        # For pre-V4 don't delete any full that is followed by an unfilled backup,
        # since it is needed for restore.
        #
        my $noDelete = $i + 1 < @$Backups ? $Backups->[$i+1]{noFill} : 0;
        $noDelete = 0 if ( !$Backups[$i]{preV4} );

        if ( !$noDelete && 
              ($fullKeepIdx >= @$fullKeepCnt
              || $k > 0
                 && defined($nextFull)
                 && $Backups->[$nextFull]{startTime} - $Backups->[$prevFull]{startTime}
                             < ($fullPeriod + $startTimeDeviation) * 24 * 3600
               )
            ) {
            #
            # Delete the full backup
            #
            #print("Deleting backup $i (" . ($k > 0 ? $prevFull : "") . ")\n");
            unshift(@delete, $i);
        } else {
            $fullCnt++;
            $nextFull = $i;
            while ( $fullKeepIdx < @$fullKeepCnt
                     && $fullCnt >= $fullKeepCnt->[$fullKeepIdx] ) {
                $fullKeepIdx++;
                $fullCnt = 0;
                $fullPeriod = 2 * $fullPeriod;
            }
        }
    }
    #
    # Now actually delete the backups
    #
    for ( my $i = @delete - 1 ; $i >= 0 ; $i-- ) {
        print("removing filled backup $Backups->[$delete[$i]]{num}\n") if $opt_d;
        $XferLOG->write(\"removing filled backup $Backups->[$delete[$i]]{num}\n") if ( $XferLOG );
        BackupRemove($client, $delete[$i], 1);
    }
    return @delete;
}

#
# Removes a specific backup
#
sub BackupRemove {
    my ( $client, $idx ) = @_;

    if ( $Backups[$idx]{startTime} eq "" ) {
        print "BackupRemove: ignoring empty backup start time for idx $idx.",
          "\n";
        return;
    }

    my $ret =
      ::BackupRemove( $Backups[$idx]{num}, $client, $Backups[$idx]{startTime} );

    delete $BackupList{$client}{ $Backups[$idx]{startTime} };
    splice( @Backups, $idx, 1 );
    return $ret;
}

1;
