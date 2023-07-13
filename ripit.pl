#!/usr/bin/env perl
########################################################################
#
# LICENSE
#
# Copyright (C) 2005 Felix Suwald
#
#
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or (at
# your option) any later version.
#
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307,
# USA.
#
########################################################################
#
# TODO 4.1
#
# Check filesystem on mixed mode CDs and copy data content (video, jpgs)
# to the sound directory.
#
# Should postprocessing of wav files be enabled, e.g. using sox for
# adding fade on lead-in or lead-out, create an option wavcmd?
#
# Different cover (sizes) for different formats / qualities.
#
# Allow operator to "back_encode" track names to "lower" formats, i.e.
# to ascii in case files shall be moved to different systems.
#
# Change ripopt to an array for a more conveniant switch of rippers.
#
# If option verify is used, why not test decoding of flac files and
# inform operator if decoding fails on some tracks. Or just, in case
# flac is used, test decoding.
#
# Add support for opus, speex, ttaenc or bonk and xspf playlist files.
#
# Ensure all comments of a playlist file are copied to a new playlist
# file when re-encoding.
#
########################################################################
#
# CODE
#
# ripit.pl - Rips audio CD and encodes files, following steps can be
#            performed (unsorted list):
#            1) Query CDDB data or text for album/artist/track info
#            2) Rip the audio files from the CD
#            3) Encode the wav files
#            4) ID3 tag the encoded files
#            5) Extract possible hidden tracks
#            6) Optional: Create a playlist (M3U) file.
#            7) Optional: Prepares and sends a CDDB submission.
#            8) Optional: saves the CDDB file
#            9) Optional: creates a toc (cue) file to burn a CD in DAO
#               with text
#           10) Optional: analyze the wavs for gaps and splits them into
#               chunks and/or trim lead-in/out (experimental)
#           11) Optional: merges wavs for gapless encoding
#           12) Optional: normalizes the wavs before encoding.
#           13) Optional: adds coverart to tags of sound files and
#               copies albumcover to encoding directories.
#           14) Optional: calculates album gain for sound files.
#           15) Optional: creates a md5sum for each type of sound files.
#
#
# Version 4.0.0_rc_20161009 - October 9th 2016 - Felix Suwald, thanks for input:
#                                  N. Heberle
#                                  D. Armstrong
#                                  T. Kukuk (encoding detection)
#                                  S. Oosthoek (CD-text)
#                                  S. Noé
#                                  P. Reinholdtsen
#
# Version 3.9.0 - July 14th 2010 - Felix Suwald, thanks for input:
#                                  F. Sundermeyer
#                                  S. Noé
# Version 3.8.0 - September 28th 2009 - Felix Suwald
#
# Version 3.7.0 - May 6th 2009 - Felix Suwald, thanks for input:
#                                C. Blank
#                                A. Gillis
#                                and to all the bug-reporters!
# Version 3.6.0 - June 16th 2007 - Felix Suwald, thanks for input:
#                                  C. Blank
#                                  G. Edwards
#                                  G. Ross
# Version 3.5.0 - June 6th 2006 - Felix Suwald, credits to
#                                 E. Riesebieter (deb-package)
#                                 C. Walter (normalize option)
#                                 S. Warten (general support & loop)
#                                 S. Warten (signal handling)
# Version 3.4 - December 3rd 2005 - Felix Suwald, credits to
#                                   M. Bright (infolog file)
#                                   M. Kaesbauer (lcdproc) and
#                                   C. Walter (config file).
# Version 2.5 - November 13th 2004 - Felix Suwald
# Version 2.2 - October 18th 2003 - Mads Martin Joergensen
# Version 1.0 - February 16th 1999 - Simon Quinn
#
#
########################################################################
#
# User configurable variables:
# Keep these values and save your own settings in a config file with
# option --save!
#
my $cddev     = "/dev/cdrom";# Path of CD device.
my $scsi_cddev = "";         # Path of CD device for non audio commands.
my $outputdir = "";         # Where the sound should go to.
my $ripopt    = "";         # Options for audio CD ripper.
my $offset    = 0;          # Sample offset to be used for drive.
my $accuracy  = 0;          # Check accuracy of rip using Morituri.
my $verify    = 1;          # Rip track $verify times or until identical
                            # rip has been detected / riped.
my $span      = "";         # Options for track spans.
my $ripper    = 1;          # 0 - dagrab, 1 - cdparanoia,
                            # 2 - cdda2wav, 3 - tosha, 4 - cdd.
my @coder     = (0);        # 0 - Lame, 1 - Oggenc, 2 - Flac,
                            # 3 - Faac, 4 - mp4als, 5 - Musepack,
                            # 6 - Wavpack, 7 - ffmpeg,
                            # comma separated list.
my $coverart  = 0;          # Add cover meta data, (1 yes, 0 no),
                            # comma separated list in same order as
                            # list of encoders.
my $coverpath = "";         # Path to cover to be added to sound files.
my $copycover = "";         # Path to album cover source.
my $coverorg  = 0;          # Check for album art at coverartarchive.org
my $bitrate   = 128;        # Bitrate for lame, if --vbrmode used,
                            # bitrate is equal to the -b option.
my $maxrate   = 0;          # Bitrate for lame using --vbrmode,
                            # maxrate is equal to the -B option.
my @quality   = (5,3,5,100,0,5);# Quality for lame in vbr mode (0-9), best
                            # quality = 0, quality for oggenc (1-10),
                            # best = 10; or compression level for Flac
                            # (0-8), lowest = 0, quality for Faac
                            # (10-500), best = 500, no values for
                            # Wavpack and ffmpeg.
my $qualame   = 5;          # Same as above, more intuitive. Use quotes
my $qualoggenc= 3;          # if values shall be comma separated lists.
my $quaflac   = 5;          #
my $quafaac   = 100;        #
my $quamp4als = 0;          #
my $quamuse   = 5;          #
my $lameopt   = "";         #
my $oggencopt = "";         #
my $flacopt   = "";         #
my $flacdecopt = "-s";      # Options if flac files shall be used for
                            # re-encoding.
my $faacopt   = "";         #
my $mp4alsopt = "";         #
my $museopt   = "";         #
my $wavpacopt = "-y";       #
my $ffmpegopt = "";         #
my $ffmpegsuffix = "";      # The suffix of the encoder used
my $musenc    = "mpcenc";   # The default Musepack encoder.
my $mp3gain   = "";         # The mp3 album gain command with options.
my $vorbgain  = "";         # The vorbis album gain command with options.
my $flacgain  = "";         # The flac album gain command with options.
my $aacgain   = "";         # The aac album gain command with options.
my $mpcgain   = "";         # The mpc album gain command with options.
my $wvgain    = "";         # The wv album gain command with options.
my $lcd       = 0;          # Use lcdproc (1 yes, 0 no).
my $chars     = "XX";       # Exclude special chars in file names.
my $verbose   = 3;          # Normal output: 3, no output: 0, minimal
                            # output: 1, normal without encoder msgs: 2,
                            # normal: 3, verbose: 4, extremely verbose: 5
my $commentag = "";         # Comment ID3 tag.
my $genre     = "";         # Genre of Audio CD for ID3 tag.
my $year      = "";         # Year of Audio CD for ID3 tag.
my @flactags   = ();        # Add special flac tags.
my @mp3tags   = ();         # Add special mp3 tags.
my @oggtags   = ();         # Add special ogg tags using vorbiscomment.
my $utftag    = 1;          # Keep Lame-tags in utf or decode them to
                            # ISO8895-1 (1 yes, 0 no).
my $vatag     = 0;          # Detect VA style for tagging (1 yes, 0 no,
                            # 2 backward style (trackname / artist)).
my $vastring  = "\\bVA\\b|Variou*s|Various Artists|Soundtrack|OST";
my $eject     = 0;          # Eject the CD when done (1 yes, 0 no).
my $ejectcmd  = "eject";    # Command to use for eject
my $ejectopt  = "{cddev}";  # Options to above
my $quitnodb  = 0;          # Quit if no CDDB entry found (1 yes, 0 no).
my $overwrite = "n";        # Overwrite existing directory / rip
                            # (n no, y yes, e eject if directory exists)
my $halt      = 0;          # Shutdown machine when finished
                            # (1 yes, 0 no).
my $nice      = 0;          # Set nice for encoding process.
my $nicerip   = 0;          # Set nice for ripping process.
my $savenew   = 0;          # Saved passed parameters to new config
                            # file (1 yes, 0 no).
my $savepara  = 0;          # Save parameters passed in config file
                            # (1 yes, 0 no).
my $config    = 1;          # Use config file to read parameters
                            # (1 yes, 0 no).
my $confdir   = "";         # Full path to the users config file.
my $confname  = "config";   # File name of config file.
my $submission= 1;          # Send CDDB submission
                            # (1 yes, 0 no).
my $parano    = 1;          # Use paranoia mode in cdparanoia
                            # (1 yes, 0 no).
my $playlist  = 1;          # Do create the m3u playlist file
                            # (1 yes, 0 no, 2 no full path in file name).
my $book      = 0;          # Merge all tracks into a single file and
                            # write a chapter file (1 yes, 0 no).
my $resume    = 0;          # Resume a previously started session
                            # (1 yes, 0 no).
my $infolog   = "";         # Full path to a text file logging system
                            # calls and process information.
my $interaction = 1;        # If 0 do not ask anything, take the 1st
                            # CDDB entry found or use default names!
                            # (1 yes, 0 no).
my $underscore = 0;         # Use _ instead of spaces in file names
                            # (1 yes, 0 no).
my $lowercase = 0;          # Lowercase file names
                            # (1 yes for all (1+2), 0 no, 2 only files
                            # of tracktemplate, 3 only dirs of
                            # dirtemplate).
my $uppercasefirst = 0;     # Uppercase first char in file names
                            # (1 yes, 0 no).
my $archive   = 0;          # Save CDDB files in ~/.cddb dir
                            # (1 yes, 0 no).
my $mb        = 0;          # Use the Musicbrainz DB instead of freedb
                            # (1 yes, 0 no).
my $mbrels    = 0;          # Use the Musicbrainz relationship "work" &
                            # check for featured artists (1 yes, 0 no).
my $mirror    = "freedb";   # The host (a freedb mirror) that
                            # shall be used instead of freedb.
my $transfer  = "cddb";     # Transfer mode, cddb or http, will set
                            # default port to 8880 or 80 (for http).
my $vbrmode   = "";         # Variable bitrate, only used with lame,
                            # (new or old), see lame manpage.
my $proto     = 6;          # CDDB protocol level for CDDB query.
my $proxy     = "";         # Set proxy.
my $CDDB_HOST = "freedb.org"; # Set cddb host
my $mailad    = "";         # Users return e-mail address.
my @threads   = 1;          # Number of encoding processes for each box
my @sshlist   = ();         # List of remote machines.
my $scp       = 0;          # Use scp to access files (1 yes, 0 no).
my $local     = 1;          # Encode on locale machine (1 yes, 0 no).
my $wav       = 0;          # Keep the wav files (1 yes, 0 no).
my $encode    = 1;          # Encode the wav files (1 yes, 0 no).
my $rip       = 1;          # Rip the CD files (1 yes, 0 no).
my $cue       = 0;          # Create a cue-sheet with single tracks
                            # (1 yes, 0 no).
my $cdcue     = 0;          # Create a cue-file from CD (1 yes, 0 no).
my $cdid      = "";         # The disc-id passed by operator if flac or
                            # or wav shall be re-encoded including tag
                            # update.
my $cdtoc     = 0;          # Create a cd.toc for CDRDAO (1 yes, 0 no).
my $inf       = 0;          # Create inf files for wodim (1 yes, 0 no).
my $loop      = 0;          # Restart ripit as soon as the previous CD
                            # is done. This option will force ejection!
                            # (1 yes, 0 no, 2 immediate restart after
                            # ripping, experimental, use with caution!).
my $ghost     = 0;          # Check and extract ghost songs from all
                            # tracks (1 yes, 0 no).
my $prepend   = 2.0;        # Extend ghost songs by 2 seconds at the
                            # beginning.
my $extend    = 2.0;        # Extend ghost songs by 2 seconds at the
                            # end.
my $dpermission = "0755";   # Directory permissions.
my $fpermission = "";       # Audio and text file permissions.
my $md5sum    = 0;          # Generate MD5 sums for every sound file
                            # not deleted (1 yes, 0 no).
my @suffix    = ();         # Array of suffixes according to coders.
my $execmd    = "";         # Execute a command when done.
my $precmd    = "";         # Execute a command before ripping.
my $multi     = 0;          # Not yet official. Do not use!
my $mbname    = "";         # Musicbrainz login name.
my $mbpass    = "";         # Musicbrainz password for ISRC submission.
my $isrc      = 0;          # Detect ISRC with icedax (1 yes, 0 no).
my $mailopt   = "-t";       # Define options for sendmail
my $cdtext    = 0;          # Check for CD text if no DB entry found
my $coversize = "";         # Change cover size to an XxY format
my $discno    = 0;          # Use disc numbering (0 no or number > 0)
#
# New options step 1: Add global variables here above or below in case
# they shouldn't be user configurable.
#
#
#
# Directory and track template variables:
# Contains the format the track names will be written as.
# The '" and "' are important and must surround the template.
# Example variables to use are: $tracknum, $album, $artist, $genre,
# $trackname or $year.
# E.g. following setting of $tracktemplate produces a track name of
# "07 The Game - Swandive" :
# $tracktemplate  = '"$tracknum $trackname - $artist"';
#
my @dirtemplate = '"$artist - $album"';
my $tracktemplate  = '"$tracknum $trackname"';
my $trackoffset = 0;
my $addtrackoffset = 0;
#
#
# LCDproc settings:
#
my $lcdhost   = "localhost";
my $lcdport   = "13666";
my $lcdline1  = "   [initializing]   ";
my $lcdline2  = " ripit-lcd-module     ";
my $lcdline3  = "          2005 ";
my $lcdoline1 = "";
my $lcdoline2 = "";
my $lcdoline3 = "";
my $lcdproc;
my $lcdtrackno       = 0;
#
#
#
# Normalize settings:
#
my $normalize = 0;           # normalize CD, needs 'normalize' in $path.
my $normcmd   = "normalize"; # This might differ for other distros.
my $normopt   = "-b";        # Additional options for normalize.
my $subdir    = "Unsorted";
#
#
########################################################################
#
# System variables, no user configurable variables below.
#
use Encode;                 # Needed for decode_utf8 calls.
use Encode::Guess;          # Needed for guess_encoding.
use Fcntl;                  # Needed for sysopen calls.
use File::Copy;
use Getopt::Long qw(:config no_ignore_case);
use IO::Socket;
use strict;
use warnings;
#
# Initialize paths.
#
my $homedir = "$ENV{HOME}";
my $workdir = "$ENV{PWD}";
my $usename = "$ENV{USER}";
# The hostname is not so important and not available on Ubuntu(s) (?).
my $hostnam = "";
if($ENV{HOSTNAME}) {
   $hostnam = "$ENV{HOSTNAME}";
}
elsif($ENV{HOST}) {
   $hostnam = "$ENV{HOST}";
}
my $charset = "";
if($ENV{G_FILENAME_ENCODING}) {
   $charset = "$ENV{G_FILENAME_ENCODING}";
}
else {
   $charset = "$ENV{LANG}";
}
if($charset =~ /UTF-8/) {
   $charset = "UTF-8";
}
elsif($charset  =~ /ISO-8859-15/) {
   $charset = "ISO-8859-15";
}
else {
   $charset = "ISO-8859-1";
}
#print ($_,$ENV{$_},"\n") foreach (keys %ENV);

#
# Initialize global variables.
#
my $version          = "4.0.0_rc_20161009";
my $album_utf8       = "";
my $artist_utf8      = "";
my $distro           = "";  # Linux distribution
my $categ            = "";  # CDDB category
my $cddbid           = 0;   # Freedb-ID needed in several subroutines
my $discid           = "";  # MB-discID needed in several subroutines
my $lameflag         = 0;   # Flag to check if lame is used, some users
                            # are not aware that lame is needed for mp3!
my $oggflag          = 0;   # Flag to check if oggenc is used. Needed to
                            # load modules if coverart for ogg is used.
my $wvpflag          = 0;   # Flag to check wavpack version and its
                            # coverart support.
my $trackselection   = "";  # Passed from command line
my @tracksel         = ();  # Array of all track numbers, including
                            # those not explicitly stated.
my @seltrack         = ();  # Array of all track numbers, including
                            # those not explicitly stated and ghost
                            # songs found by ripper needed by encoder.
my @framelist        = ();  # Needed in several subroutines
my @framelist_orig   = ();  # Needed in several subroutines
my @secondlist       = ();  # Needed in several subroutines
my @tracklist        = ();  # Needed in several subroutines
my @tracklist_modif  = ();  # Needed when re-encoding
my @tracktags        = ();  # Needed in several subroutines
my %cd               = ();  # HoH of all CD-data.
my $cddbsubmission   = 2;   # If zero then data for CDDB submission is
                            # incorrect, if 1: submission OK, if 2: CDDB
                            # entry not changed (edited)
my $wpreset          = "";  # Preset written into config file.
my $wcoder           = "";  # Use a comma separated string to write the
                            # coder-array into the config file.
my $wthreads         = "";  # Use a comma separated string to write the
                            # threads-array into the config file.
my $wsshlist         = "";  # As above for the list of remote machines.
my $sshflag          = 0;   # Ssh encoding OK if sshflag == 1.
my %sshlist          = ();  # Hash of remote machines.
my $hiddenflag       = 0;
my $logfile          = "";  # Used with not *to-use* option --multi.
my $help             = 0;   # Print help and exit if 1.
my $printver         = 0;   # Print version and exit if 1.
my @delname          = ();  # List of track names being processed, i.e.
                            # ready for deletion.
my @skip             = ();  # List of merged tracks.
my @globopt          = ();  # All encoder options sorted according to
                            # encoder.
my @sepdir           = ();  # Array of sound directories sorted
                            # according to encoder.
my $wavdir           = "";  # (Default) directory for sound.
my $inputdir         = "";  # Directory of snd files (wav or flac)
                            # for re-encoding process.
my $limit_flag       = 0;   # Directory and file length flag.
my $va_flag          = 0;   # VA style flag.
my $va_delim         = "/"; # VA style delimiter.
my @isrcs            = ();  # ISRC array.
my @idata            = ();  # Array for the MB track IDs.
my @audio            = ();  # Array of audio / data tracks.
#
# New options step 2: Add global variables here in case they shouldn't
# be user configurable; additional modules can be added right below.
#
#
# Initialize subroutines without ().
#
sub ask_subm;
sub check_bitrate;
sub check_cddev;
sub check_chars;
sub check_vbrmode;
sub choose_genre;
sub copy_cover;
sub del_wav;
sub disp_info;
sub extract_comm;
sub get_cdid;
sub get_cover;
sub get_rev;
sub get_isrcs;
sub init_mod;
sub init_var;
sub lame_preset;
sub main_sub;
sub merge_wav;
sub write_cddb;
sub write_wavhead;
#
# New options step 3: Do not forget to initialize new subroutines.
#
#
# Define the variables which catch the command line input.
# The p stands for passed (from command line).
my (
   $parchive,       $pbitrate,       $pmaxrate,         $PCDDB_HOST,
   $pcddev,         $pcdtoc,         @pcoder,           $pcommentag,
   $pconfig,        @pdirtemplate,   $ptracktemplate,   $peject,
   $pencode,        $pfaacopt,       $pflacopt,         $plameopt,
   $poggencopt,     $pgenre,         $phalt,            $pinfolog,
   $pinteraction,   $plcdhost,       $plcdport,         $plcd,
   $plocal,         $ploop,          $plowercase,       $pmirror,
   $pmailad,        $pmulti,         $pnice,            $pnormalize,
   $pnormopt,       $poutputdir,     $pparano,          $pplaylist,
   $ppreset,        $pproto,         $pproxy,           @pquality,
   $pripopt,        $prip,           $pripper,          $psavenew,
   $psavepara,      $pscp,           @psshlist,         $psubdir,
   $psubmission,    $ptransfer,      $punderscore,      $putftag,
   $pvbrmode,       $pverbose,       $pwav,             $pyear,
   $presume,        $pmerge,         $pghost,           $pprepend,
   $pextend,        $pejectopt,      $pejectcmd,        $pdpermission,
   $pfpermission,   $pmd5sum,        $pnicerip,         @pthreads,
   $pnormcmd,       $pmb,            $puppercasefirst,  $pexecmd,
   $pspan,          $poverwrite,     $pquitnodb,        $pbook,
   $pmusenc,        $pmp4alsopt,     $pmuseopt,         $pinf,
   $pscsi_cddev,    $pwavpacopt,     $pffmpegopt,       $pffmpegsuffix,
   $pprecmd,        $pcoverart,      $pcoverpath,       $pcdcue,
   $pvatag,         $pvastring,      $pmp3gain,         $pvorbgain,
   $pflacgain,      $paacgain,       $pmpcgain,         $pwvgain,
   @pmp3tags,       $pcopycover,     $ptrackoffset,     $pmbname,
   $pmbpass,        $pisrc,          $pinputdir,        $pcdid,
   $pflacdecopt,    $paccuracy,      $paddtrackoffset,  $pverify,
   $poffset,        $pmailopt,       @pflactags,        @poggtags,
   $pcdtext,        $pmbrels,        $pcoverorg,        $pconfdir,
   $pconfname,      $pcoversize,     $pdiscno,          $pcue,
);
#
# New options step 4: For distinction of variables passed on the command
# line and those from the configuration file, introduce for each new
# option the variable name prefixed with 'p', 'p' stands for passed.
#
#
########################################################################
#
# Get the parameters from the command line.
#
# available:             E       jJkK
# already used: aAbBcCdDe fFgGhiI    lLmMnNoOpPqQrRsStTuUvVwWxXyYzZ
#
GetOptions(
   "accuracy|Q!"            => \$paccuracy,
   "archive|a!"             => \$parchive,
   "bitrate|b=s"            => \$pbitrate,
   "book|A=i"               => \$pbook,
   "maxrate|B=i"            => \$pmaxrate,
   "chars|W:s"              => \$chars,
   "cddbserver|C=s"         => \$PCDDB_HOST,
   "cdcue=i"                => \$pcdcue,
   "cue=i"                  => \$pcue,
   "cdid=s"                 => \$pcdid,
   "cdtext=i"               => \$pcdtext,
   "cdtoc=i"                => \$pcdtoc,
   "config!"                => \$pconfig,
   "confdir=s"              => \$pconfdir,
   "confname=s"             => \$pconfname,
   "coder|c=s"              => \@pcoder,
   "coverart=s"             => \$pcoverart,
   "coverorg=i"             => \$pcoverorg,
   "coverpath=s"            => \$pcoverpath,
   "coversize|F=s"          => \$pcoversize,
   "copycover=s"            => \$pcopycover,
   "comment=s"              => \$pcommentag,
   "device|d=s"             => \$pcddev,
   "dirtemplate|D=s"        => \@pdirtemplate,
   "discno=i"               => \$pdiscno,
   "eject|e!"               => \$peject,
   "ejectcmd=s"             => \$pejectcmd,
   "ejectopt=s"             => \$pejectopt,
   "encode!"                => \$pencode,
   "execmd|X=s"             => \$pexecmd,
   "extend=f"               => \$pextend,
   "faacopt=s"              => \$pfaacopt,
   "flacopt=s"              => \$pflacopt,
   "flactags=s"             => \@pflactags,
   "flacdecopt=s"           => \$pflacdecopt,
   "lameopt=s"              => \$plameopt,
   "oggencopt=s"            => \$poggencopt,
   "oggtags=s"              => \@poggtags,
   "mp4alsopt=s"            => \$pmp4alsopt,
   "musenc=s"               => \$pmusenc,
   "museopt=s"              => \$pmuseopt,
   "wavpacopt=s"            => \$pwavpacopt,
   "ffmpegopt=s"            => \$pffmpegopt,
   "ffmpegsuffix=s"         => \$pffmpegsuffix,
   "mp3gain=s"              => \$pmp3gain,
   "vorbgain=s"             => \$pvorbgain,
   "flacgain=s"             => \$pflacgain,
   "aacgain=s"              => \$paacgain,
   "mpcgain=s"              => \$pmpcgain,
   "wvgain=s"               => \$pwvgain,
   "genre|g=s"              => \$pgenre,
   "ghost|G!"               => \$pghost,
   "halt"                   => \$phalt,
   "help|h"                 => \$help,
   "inf=i"                  => \$pinf,
   "infolog=s"              => \$pinfolog,
   "inputdir=s"             => \$pinputdir,
   "interaction|i!"         => \$pinteraction,
   "isrc=i"                 => \$pisrc,
   "lcd!"                   => \$plcd,
   "lcdhost=s"              => \$plcdhost,
   "lcdport=s"              => \$plcdport,
   "lowercase|l=i"          => \$plowercase,
   "uppercasefirst!"        => \$puppercasefirst,
   "local!"                 => \$plocal,
   "loop=i"                 => \$ploop,
   "mb!"                    => \$pmb,
   "mbrels=i"               => \$pmbrels,
   "md5sum!"                => \$pmd5sum,
   "merge=s"                => \$pmerge,
   "mirror|m=s"             => \$pmirror,
   "mail|M=s"               => \$pmailad,
   "mailopt=s"              => \$pmailopt,
   "mbname=s"               => \$pmbname,
   "mbpass=s"               => \$pmbpass,
   "mp3tags=s"              => \@pmp3tags,
   "multi"                  => \$pmulti,
   "nice|n=s"               => \$pnice,
   "nicerip=s"              => \$pnicerip,
   "normalize|N!"           => \$pnormalize,
   "normcmd=s"              => \$pnormcmd,
   "normopt|z=s"            => \$pnormopt,
   "subdir=s"               => \$psubdir,
   "offset=i"               => \$poffset,
   "outputdir|o=s"          => \$poutputdir,
   "overwrite|O=s"          => \$poverwrite,
   "dpermission=s"          => \$pdpermission,
   "fpermission=s"          => \$pfpermission,
   "playlist|p:s"           => \$pplaylist,
   "precmd=s"               => \$pprecmd,
   "prepend=f"              => \$pprepend,
   "preset|S=s"             => \$ppreset,
   "proxy|P=s"              => \$pproxy,
   "protocol|L=i"           => \$pproto,
   "quality|q=s"            => \@pquality,
   "quitnodb=i"             => \$pquitnodb,
   "resume|R"               => \$presume,
   "rip!"                   => \$prip,
   "ripper|r=s"             => \$pripper,
   "ripopt=s"               => \$pripopt,
   "savenew"                => \$psavenew,
   "save"                   => \$psavepara,
   "scp"                    => \$pscp,
   "scsidevice=s"           => \$pscsi_cddev,
   "sshlist=s"              => \@psshlist,
   "span|I=s"               => \$pspan,
   "submission|s!"          => \$psubmission,
   "threads=s"              => \@pthreads,
   "tracktemplate|T=s"      => \$ptracktemplate,
   "trackoffset=i"          => \$ptrackoffset,
   "addtrackoffset!"        => \$paddtrackoffset,
   "transfer|t=s"           => \$ptransfer,
   "underscore|u!"          => \$punderscore,
   "utftag|U!"              => \$putftag,
   "vatag=i"                => \$pvatag,
   "vastring=s"             => \$pvastring,
   "vbrmode|v=s"            => \$pvbrmode,
   "verbose|x=i"            => \$pverbose,
   "version|V"              => \$printver,
   "verify|Y=i"             => \$pverify,
   "year|y=i"               => \$pyear,
   "wav|w!"                 => \$pwav,
   "disable-paranoia|Z:i"   => \$pparano,
)
or exit print_usage();
#
# New options step 5: Add the command line option here (above).
#
#
########################################################################
#
# Evaluate the command line parameters if passed. We need to do it this
# way, because passed options have to be saved (in case user wants to
# save them in the config file) before config file is read to prevent
# overriding passed options with options from config file. The passed
# options shall be stronger than the config file options!
# Problems arise with options that can be zero. Because a usual if-test
# can not distinguish between zero or undef, use the defined-test!
#
# New options step 6: force use of command line options if passed.
#
#
# First for the normal options, e. g. options which are never zero.
#
# The check of array @coder will be done in the subroutine!
$faacopt = $pfaacopt if($pfaacopt);
$flacopt = $pflacopt if($pflacopt);
$flacdecopt = $pflacdecopt if($pflacdecopt);
$lameopt = $plameopt if($plameopt);
$mailopt = $pmailopt if($pmailopt);
$oggencopt = $poggencopt if($poggencopt);
$mp4alsopt = $pmp4alsopt if($pmp4alsopt);
$musenc = $pmusenc if($pmusenc);
$museopt = $pmuseopt if($pmuseopt);
$wavpacopt = $pwavpacopt if($pwavpacopt);
$ffmpegopt = $pffmpegopt if($pffmpegopt);
$ffmpegsuffix = $pffmpegsuffix if($pffmpegsuffix);
$oggencopt = " " unless($oggencopt); # Oops, only to prevent warnings...
$mp3gain = $pmp3gain if($pmp3gain);
$vorbgain = $pvorbgain if($pvorbgain);
$flacgain = $pflacgain if($pflacgain);
$aacgain = $paacgain if($paacgain);
$mpcgain = $pmpcgain if($pmpcgain);
$wvgain = $pwvgain if($pwvgain);
$CDDB_HOST = $PCDDB_HOST if($PCDDB_HOST);
$cddev = $pcddev if($pcddev);
$overwrite = $poverwrite if($poverwrite);
$verify = $pverify if($pverify);
#
# Get the default "no-argument" values.
# Note, that subroutine clean_all already purges ;><" and \015.
$chars = "NTFS" if($chars eq "");
$chars = "" if($chars eq "off");
$commentag = $pcommentag if($pcommentag);
$confname = $pconfname if($pconfname);
$confdir = $pconfdir if($pconfdir);
$copycover = $pcopycover if($pcopycover);
$coverpath = $pcoverpath if($pcoverpath);
$coversize = $pcoversize if($pcoversize);
@dirtemplate = @pdirtemplate if($pdirtemplate[0]);
$tracktemplate = $ptracktemplate if($ptracktemplate);
$execmd = $pexecmd if($pexecmd);
$precmd = $pprecmd if($pprecmd);
@flactags = @pflactags if($pflactags[0]);
$halt = $phalt if($phalt);
$inputdir = $pinputdir if($pinputdir);
$infolog = $pinfolog if($pinfolog);
$lcdhost = $plcdhost if($plcdhost);
$lcdport = $plcdport if($plcdport);
$mailad = $pmailad if($pmailad);
$mbname = $pmbname if($pmbname);
$mbpass = $pmbpass if($pmbpass);
@mp3tags = @pmp3tags if($pmp3tags[0]);
$mirror = $pmirror if($pmirror);
$normcmd = $pnormcmd if($pnormcmd);
$normopt = $pnormopt if($pnormopt);
@oggtags = @poggtags if($poggtags[0]);
$outputdir = $poutputdir if($poutputdir);
my $preset = $ppreset if($ppreset);
$ripopt = $pripopt if($pripopt);
$dpermission = $pdpermission if($pdpermission);
$fpermission = $pfpermission if($pfpermission);
$proto = $pproto if($pproto);
$proxy = $pproxy if($pproxy);
# Check for variable $psshlist will be done in the subroutine!
# Check for variable $pthreads will be done in the subroutine!
$transfer = $ptransfer if($ptransfer);
$vbrmode = $pvbrmode if($pvbrmode);
$year = $pyear if($pyear);
#
# Options which might be zero.
$bitrate = $pbitrate if($pbitrate);
$book = $pbook if($pbook);
$cdcue = $pcdcue if defined $pcdcue;
$cue = $pcue if defined $pcue;
$cdid = $pcdid if defined $pcdid;
$cdtext = $pcdtext if defined $pcdtext;
$cdtoc = $pcdtoc if defined $pcdtoc;
$coverart = $pcoverart if defined $pcoverart;
$coverorg = $pcoverorg if defined $pcoverorg;
$extend = $pextend if defined $pextend;
$genre = $pgenre if defined $pgenre;
$inf = $pinf if defined $pinf;
$isrc = $pisrc if defined $pisrc;
$loop = $ploop if defined $ploop;
$lowercase = $plowercase if defined $plowercase;
$md5sum = $pmd5sum if defined $pmd5sum;
$maxrate = $pmaxrate if defined $pmaxrate;
$nice = $pnice if defined $pnice;
$nicerip = $pnicerip if defined $pnicerip;
$offset = $poffset if defined $poffset;
$parano = $pparano if defined $pparano;
$playlist = $pplaylist if defined $pplaylist;
$playlist = 1 if($playlist eq "");
$prepend = $pprepend if defined $pprepend;
$quitnodb = $pquitnodb if defined $pquitnodb;
$resume = $presume if defined $presume;
$ripper = $pripper if defined $pripper;
$savepara = $psavepara if defined $psavepara;
$savenew = $psavenew if defined $psavenew;
$scp = $pscp if defined $pscp;
$discno = $pdiscno if defined $pdiscno;
if(defined $pscsi_cddev) {
   $scsi_cddev = $pscsi_cddev;
}
else {
   $scsi_cddev = $pcddev if($pcddev);
}
$span = $pspan if defined $pspan;
$trackoffset = $ptrackoffset if defined $ptrackoffset;
$verbose = $pverbose if defined $pverbose;
$vatag = $pvatag if defined $pvatag;
#
# And for the negatable options.
$addtrackoffset = $paddtrackoffset if defined $paddtrackoffset;
$accuracy = $paccuracy if defined $paccuracy;
$archive = $parchive if defined $parchive;
$config = $pconfig if defined $pconfig;
$encode = $pencode if defined $pencode;
$eject = $peject if defined $peject;
$ejectcmd = $pejectcmd if defined $pejectcmd;
$ejectopt = $pejectopt if defined $pejectopt;
$ghost = $pghost if defined $pghost;
$interaction = $pinteraction if defined $pinteraction;
$lcd = $plcd if defined $plcd;
$local = $plocal if defined $plocal;
$mb = $pmb if defined $pmb;
$uppercasefirst = $puppercasefirst if defined $puppercasefirst;
$multi = $pmulti if defined $pmulti;
$normalize = $pnormalize if defined $pnormalize;
$rip = $prip if defined $prip;
$submission = $psubmission if defined $psubmission;
$underscore = $punderscore if defined $punderscore;
$utftag = $putftag if defined $putftag;
$wav = $pwav if defined $pwav;
#
########################################################################
#
# Preliminary start: print version, read (and write) config file.
#
# To have the version printed first of all other (warning-) messages,
# find out if verbosity is set off or not, either by command line or
# by config file.
#
my $ripdir = "";
if($confdir ne "") {
   $ripdir = $confdir . "/" . $confname;
}
elsif($confname ne "config") {
   $ripdir = $homedir . "/.ripit/" . $confname;
}
else {
   $ripdir = $homedir . "/.ripit/config"
}
# Fallback:
$ripdir = $homedir . "/.ripit/config" unless(-r "$ripdir");
$ripdir = "/etc/ripit/config" unless(-r "$ripdir");
if(-r "$ripdir" && $config == 1) {
   open(CONF, "$ripdir") || print "Can not read config file!\n";
   my @conflines = <CONF>;
   close(CONF);
   chomp($verbose = join('', grep(s/^verbose=//, @conflines)))
      unless(defined $pverbose);
   if(defined $pinfolog && $pinfolog ne "") {
      # Do nothing, use argument passed.
   }
   else {
      chomp($infolog = join('', grep(s/^infolog=//, @conflines)));
   }
}
#
print "\n\n\nRipIT version $version.\n" if($verbose >= 1);
# Preliminary creation of the infolog path.
# No log_system call here because this would try to write to the infolog
# file not yet created.
if($infolog) {
   my($log_path, $filename) = $infolog =~ m/(.*\/)(.*)$/;
   system("mkdir -m 0755 -p \"$log_path\"") and
   print "Can not create directory \"$log_path\": $!\n";
}
log_info("RipIT version $version infolog-file.\n");
if($loop == 0) {
   my $ripstart = sprintf "%02d:%02d:%02d",
      sub {$_[2], $_[1], $_[0]}->(localtime);
   my $date = sprintf("%04d-%02d-%02d",
      sub {$_[5]+1900, $_[4]+1, $_[3]}->(localtime));
   chomp($date);
   log_info("$date $ripstart\n");
}
#
#
# Do some checks before writing a new config file (if wanted):
#
# First check if arguments of option merge are OK.
my @dummy = skip_tracks(1) if($pmerge);
#
# Then the options that will be written to the config file.
if($help ne 1 && $printver ne 1) {
   check_coder();           # Check encoder array.
   check_quality();         # Check if quality is valid.
   check_proto();           # Check if protocol level is valid.
   check_sshlist();         # Check list of remote machines.
   check_preset() if($preset);     # Check preset settings.
#
# To be able to save a new config file we have to write it before
# reading the parameters not yet passed from the config file.
#
   $chars = "" if($chars eq "XX" && ($savenew == 1 || $savepara == 1));
   #
   if($savenew == 1) {
      $verbose = 3; # Set back to default value.
      $infolog = ""; # Set back to default value.
      save_config();
      print "Saved a new config file!\n\n" if($verbose >= 3);
   }
#
# Read the config file.
#
   read_config() if($config == 1);
   check_enc("lame", "mp3");
#   check_enc("faac", "m4a");
#
# Check if the necessary modules are installed properly.
#
   init_mod;
#
#
# Security check for new options: give them default value if empty.
# This can happen, if the config file is not yet up-to date.
# This will go away again in version 4.1.0. This is also done to prevent
# warnings.
#
# New options step 7: not mandatory, might be useful.
#
   $discno = 0 unless($discno);
   $accuracy = 0 unless($accuracy);
   $cue = 0 unless($cue);
   $cdtext = 0 unless($cdtext);
   $copycover = "" unless($copycover);
   $coverorg = 0 unless($coverorg);
   $coversize = "" unless($coversize);
   $mbrels = 0 unless($mbrels);
   $dpermission = "0755" unless($dpermission);
   $uppercasefirst = 0 unless($uppercasefirst);
   $isrc = 0 unless($isrc);
   $resume = 0 unless($resume);
   $musenc = "mpcenc" unless($musenc);
   $quamp4als = 0 unless($quamp4als);
   $quamuse = 5 unless($quamuse);
   $trackoffset = 0 unless($trackoffset);
   $addtrackoffset = 0 unless($addtrackoffset);
   $vatag = 0 unless($vatag);
   $pcdid = 0 unless($pcdid);
   $verify = 1 unless($verify);
   $mailopt = "-t" unless($mailopt);
#
#
# Save the config file.
#
   save_config() if($savepara == 1);
   print "Updated the config file!\n\n"
      if($verbose >= 3 && $savepara == 1);
#
# It might be a good to x-check settings from config file because they
# can be edited manually.
#
   check_coder();           # Check it again for lame cbr vs vbr.
   check_quality();         # Check it again if quality is valid.
   check_sshlist();         # Check it again to create the hash.
   check_options();         # Sort the options according to the encoder.
   check_distro();          # Check for the distribution used.

}
#
########################################################################
#
# MAIN ROUTINE
#
########################################################################
#
if($printver) {
   print "\n";
   exit 2;
}

if($verbose >= 2) {
   print "Process summary:\n", "-" x 16, "\n" unless($help == 1);
}

if($help == 1) {
   print "\nThis is a shorten man page. Refer to the full manpage ",
         "for more details.\n";
   print_help();
   exit 3;
}

if(!$pcddev && $cddev eq "") {
   # Condition change in 4.0: Why is $cddev from config not considered?
   check_cddev;
}
else {
   my $closeopt = $cddev if($ejectopt eq '{cddev}');
   $closeopt = "-t " . $closeopt if($ejectcmd =~ /^eject$/);
   $closeopt = $closeopt . " close" if($ejectcmd =~ /cdcontrol/);
   log_system("$ejectcmd $closeopt > /dev/null 2>&1");
}

if($scsi_cddev eq "") {
   $scsi_cddev = $cddev;
}

if($chars) {
   check_chars;
}

if($lcd == 1) {
   init_lcd();
}

if($outputdir eq "") {
   $outputdir = $homedir;
   chomp $outputdir;
}

if($outputdir =~ /^\.\//) {
   $outputdir =~ s/^\./$workdir/;
}
elsif($outputdir =~ /^\.\s*$/) {
   $outputdir =~ s/^\./$workdir/;
}

if($outputdir =~ /^~\//) {
   $outputdir =~ s/^~/$homedir/;
}

if($outputdir =~ /^\$HOME/) {
   $outputdir =~ s/^\$HOME/$homedir/;
}

if($copycover =~ /^~\//) {
   $copycover =~ s/^~/$homedir/;
}

if($copycover =~ /^\$HOME/) {
   $copycover =~ s/^\$HOME/$homedir/;
}

if($coverpath =~ /^~\//) {
   $coverpath =~ s/^~/$homedir/;
}

if($coverpath =~ /^\$HOME/) {
   $coverpath =~ s/^\$HOME/$homedir/;
}

# New options step 8: Add a message about selected options if needed.

if(length($year) > 0 && length($year) != 4 ) {
   print STDERR "Warning: year should be in 4 digits - $year.\n"
      if($verbose >= 1);
}

if($pdpermission && $verbose >= 2) {
   # Print this message only, if a dpermission has been passed on CL.
   $dpermission = sprintf("%04d", $dpermission);
   print "Directory permission will be set to $dpermission.\n";
}

if($fpermission && $verbose >= 2) {
   $fpermission = sprintf("%04d", $fpermission);
   print "File permission will be set to $fpermission.\n";
}

if($resume == 1 && $verbose >= 2) {
   print "Resuming previous session.\n";
}

if($span && $verbose >= 2) {
   print "Partial wav files will be ripped.\n" unless($span =~ /\d-$/);
   print "Accuracy check not possible with option span, switched off.\n"
      if($accuracy == 1 && $span !~ /\d-$/);
   $accuracy = 0;
}

if($pmerge && $verbose >= 2) {
   print "Some tracks will be merged according $pmerge.\n";
   print "Accuracy check not possible with option merge, switched off.\n"
      if($accuracy == 1);
   $accuracy = 0;
}

if($wav == 1 && $verbose >= 2) {
   print "Wav files will not be deleted.\n";
}

if($rip == 0) {
   if($inputdir ne "") {
      if(! -d "$inputdir") {
         die "\nQuitting, inputdir \"$inputdir\" can not be found.\n\n";
      }
      print "Re-encoding of existing files.\n";
      if($cdid ne "") {
         print "Track tags will be updated if possible using the ",
               "given ID $cdid.\n" if($verbose > 1);
         unless($pcdid =~ /[0-9a-f]/ && length($pcdid) == 8) {
            print "\nWarning: the cdid given seems not to be a valid ",
                  "discid which has to be 28 chars long and ends with ",
                  "a hyphen.\n" unless($pcdid =~ /\-$/ && length($pcdid) == 28);
         }
         # Don't touch existing playlist files. No, update playlist
         # because tags might be updated.
#         $playlist = -1;
         $normalize = 0;
      }
   }
   else {
      print "\nOption --norip needs an --inputdir to read from.\n";
      exit print_usage();
   }
}

if($verify > 1 && $verbose >= 2) {
   print "Checking each ripped file until 2 consecutive rips give the same md5sum.\n";
}

if($mb == 1 && $verbose >= 2) {
   print "Checking MusicBrainz instead of freedb.org.\n";
}

if($cdtext == 1 && $verbose >= 2) {
   print "Checking for CD text if no DB entry found.\n";
}

if($normalize == 1 && $verbose >= 2) {
   print "Normalizeing the CD-tracks.\n";
}

if($addtrackoffset == 1 && $mb == 1 && $verbose >= 2) {
   print "Checking for multi disc release and addition of offset in ",
         "track numbers if detected.\n";
}

if($discno > 0 && $verbose >= 2) {
   if($mb == 1) {
      print "Checking for multi disc release and adding a disc number ",
            "to the tags if detected.\n";
   }
   else {
      print "Adding disc number $discno to the tags.\n";
   }
}

if($book >= 1 && $verbose >= 2) {
   print "All tracks will be merged into one file and a chapter file ",
         "written.\n";
   $pmerge = "1-";
   $ghost = 0;
   print "Accuracy check not possible with option merge, accuracy",
         " will be switched off.\n" if($accuracy == 1);
   $accuracy = 0;
}

if($cdcue > 0 && $verbose >= 2) {
   print "All tracks will be merged into one file and a cue-file ",
         "written.\n";
   $pmerge = "1-" if($cdcue == 2);
   $ghost = 0;
   $ghost = 1 if($cdcue == 1);
   print "Accuracy check not possible with option cdcue == 2, accuracy",
         " will be switched off.\n" if($accuracy == 1 and $cdcue > 1);
   $accuracy = 0 if($accuracy == 1 and $cdcue > 1);
}

if($cue > 0 && $verbose >= 2) {
   print "A cue-file will be written for all tracks.\n";
}

if($accuracy > 0 && $verbose >= 2) {
   if($ripper == 1 || $ripper == 4) {
      print "Accuracy check will be done after ripping.\n";
   }
   else {
      print "Accuracy check not possible with other ripper than ",
            "cdparanoia, accuracy will be switched off.\n";
      $accuracy = 0 if($accuracy == 1);
   }
}

if($cdtoc > 0 && $verbose >= 2) {
   print "A toc file will be written.\n";
}

if($inf > 0 && $verbose >= 2) {
   print "Inf files will be written for each track.\n";
}

if($ghost == 1) {
   print "Tracks will be analyzed for ghost songs. " if($verbose >= 2);
   print "Forced by option --cdcue." if($cdcue == 1 && $verbose >= 2);
   print "\n" if($verbose >= 2);
}

if($utftag == 0 && $verbose >= 2 && "@coder" =~ /0/) {
   print "Lame-tags will be encoded to ISO8859-1.\n";
}

if($flactags[0] && $verbose >= 2 ) {
   print "Additional track tags will be added to flac files.\n";
}

if($mp3tags[0] && $verbose >= 2 ) {
   print "Special track tags will be added to mp3 files.\n";
}

if($oggtags[0] && $verbose >= 2 ) {
   print "Additional track tags will be added to mp3 files.\n";
}

if($vatag > 0 && $verbose >= 2 ) {
   print "Track tags will be analyzed for VA style.\n";
}

if($playlist >= 1 && $verbose >= 2) {
   print "Playlist (m3u) file will be written.\n";
}

if($md5sum == 1 && $verbose >= 2) {
   print "MD5SUMs of sound files will be calculated.\n";
}

if($copycover && $verbose >= 2) {
   print "Copying a cover picture to encoder directories.\n";
}

if($coverorg =~ /1/ && $verbose >= 2) {
   print "Retrieving coverart from coverartarchive.org.\n";
}

if($coversize =~ /^\d+$/ && $verbose >= 2) {
   print "Resizing coverart to $coversize.\n";
}

if($coverart =~ /1/ && $verbose >= 2) {
   print "Adding coverart to sound files (if provided).\n";
}

if(($mp3gain || $vorbgain || $flacgain || $aacgain || $mpcgain || $wvgain)
   && $encode == 1 && $verbose >= 2) {
   print "Adding album gain tags to sound files.\n";
}

if($parano >= 3 && $verbose >= 2 ) {
   print "Warning: paranoia argument unknown, will use paranoia.\n";
   $parano = 1;
}

if($halt == 1 && $verbose >= 2) {
   print "Halting machine when finished.\n";
}

if($eject == 1 || $loop >= 1) {
   print "CD will be ejected when finished.\n" if($verbose >= 2);
   $ejectcmd = "eject -v" if($ejectcmd =~ /eject/ && $verbose >= 4);
}

if($loop >= 1) {
   print "Restarting and ejection of each CD.\n" if($verbose >= 2);
   print "\n" if($verbose >= 2);
   while($loop >= 1) {
      main_sub;
      last if($loop == 0);
      init_var;
      # This is the light version without eating the disc.
      print "Please insert a new CD!\n" if($verbose >= 1);
      while( not cd_present() ) {
         sleep(6);
      }
      # Do it again in case operator changed something in between.
      if($config == 1) {
         read_config();
         print "Rereading config file.\n" if($verbose > 3);
      }
   }
}
else {
   print "\n" if($verbose >= 2);
   main_sub;
}
exit;
#
########################################################################
#
# Main subroutine.
#
########################################################################
#
sub main_sub {
   if($loop > 0) {
      my $ripstart = sprintf "%02d:%02d:%02d",
         sub {$_[2], $_[1], $_[0]}->(localtime);
      my $date = sprintf("%04d-%02d-%02d",
         sub {$_[5]+1900, $_[4]+1, $_[3]}->(localtime));
      chomp $date;
      log_info("$date $ripstart\n");
   }

   if(@ARGV) {
      $trackselection = $ARGV[0];
   }

   if($bitrate ne "off" && $lameflag == 1) {
      check_bitrate;
   }

   if($vbrmode ne "" && $lameflag == 1) {
      check_vbrmode;
   }

   if($preset) {
      lame_preset;
   }

   if($rip == 1 && $loop == 0) { # Condition added in 4.0
      unless( cd_present() ) {
         print "\nPlease insert an audio CD!\n" if($verbose > 0);
         while( not cd_present() ) {
            check_cddev;
            sleep(12);
         }
      }
   }

   if($rip == 0) { ### and $cdid eq "") {
      # Main idea of re-encoding:
      # Re-encoding means needing for tags, only possibly here within
      # flac files, no way to extract track names from wav file names.
      # In this way let's suppose the meta data look-up makes sense. And
      # in case of flac it makes sense to check Musicbrainz, updating
      # tags with freedb would not really improve the quality.
      # So this means less of work: for a freedb look-up without disc in
      # the drive we would not only need the discid, but the complete
      # framelist (toc) for all tracks. This means, a freedb look-up
      # without disc is only possible after reading a local copy in the
      # archive: operator gives discid --> archive --> selection of
      # disc --> readout of toc and save it in an array -->
      # return to freedb look-up --> choose again release with probably
      # no significant quality improvement. Or the toc is assembled from
      # MB data to ensure genre retrieval. This could make sense if we
      # have only wav and an discid from a log file.
      #
      # The idea of passing a discid is only meant as a workaround in
      # case operator has no other meta data with this info.
      # Giving a MB-discid will lead to an online look-up, an discid will
      # enable a local archive look-up.
      # The detection of an existing id won't be done in this case.
      #
      # So start here if no id is passed and an id should be detected.
      # Come here only if operator did not pass any CD-ID.
      # First: try to find a cue, m3u or toc file, finally analyze
      # existing flac or wav files.
      # Hm, should we let operator decide if tags shall be checked?
      #
      # What if operator has flac with tags? Then
      # look-up will possibly update tags -- how does ripit show a
      # diff?
      get_cdid;
      # If no CDID passed or detected and only wav or flac without
      # tags are present, then after sub disp_info operator may enter
      # tags.
      # What should happen, if flacs with tags are present but no
      # discid. Nothing, reuse the tags.
      # If a discid is found (or exists), then update tags this way:
      # If mbreid is given/found and option --mb is on: make a look-up.
      # If cdid is given/found and option -a is on: check archive.
   }

   if($rip == 1 || ($rip == 0 && $cdid ne "")) {
      # Sorry, replication of code snippet from sub get_cdid.
      # Final clean-up of IDs.
      if($rip == 0) {
         print "Cleaning cddbid and discid found locally.\n" if($verbose > 4);
         if($cdid =~ /[0-9a-f]/ && length($cdid) == 8) {
            $cddbid = $cdid;
            $cd{id} = $cddbid;
         }
         else{
            $discid = $cdid;
            $discid = "" unless($discid =~ /\-$/ && length($discid) == 28);
            $cdid = "";
            $cd{discid} = $discid if($discid ne "");
         }
      }
      if($archive == 1 && $multi == 0) {
         print "Checking local archive.\n" if($verbose > 4);
         get_arch();
      }
      else {
         # Place interaction here if DB update should happen or not?
         # TODO
         print "Checking external DBs...\n" if($verbose > 4);
         # Don't go in when re-encoding.
         get_cdinfo() if($mb == 0 && $rip == 1);
         get_mb() if($mb == 1);
      }
   }
   disp_info;
   create_seltrack($trackselection);
   ask_subm();
   my $answer = create_dirs();
   @framelist_orig = @framelist if($rip == 0);

   if($answer eq "go") {
      if($precmd) {
         $precmd =~ s/\$/\\\$/g;
         log_system("$precmd");
      }
      get_cover if($coverorg > 0 and $mb == 1);
      # This is where we would expect the resize_cover call, but if no
      # coverart is found, we want the command to take effect even if
      # operator adds a cover manually.
      if($loop > 0 && $interaction == 1) {
         my $startover = -1;
         while($startover < 0 || $startover > 1) {
            print "\nRestart to choose another DB source? [y/n] (n) ";
            $startover = <STDIN>;
            chomp $startover;
            $startover = 0 if($startover eq "");
            $startover = 1 if($startover eq "y");
            $startover = -1 unless($startover =~ /^0|1$/);
            print "\n";
         }
         return if($startover == 1);
      }

      if(-f "$copycover" && -s "$copycover") {
         # First check existence of base file:
         my $msg = "\nChecking for files to be copied from copycover " .
               "path $copycover.";
         check_copy("$copycover") if($interaction == 1);
         resize_cover("$copycover")
            if(defined $coversize && $coversize =~ /^\d+$/);
         copy_cover;
         # Once album art is copied, make sure that it is available
         # under the given $coverpath:
         # But this does not really make sense if several destination
         # directories exist. Test at least one to make sure copy_cover
         # did the job.
         $msg = "\nCheck for album cover with path coverpath " .
               "$coverpath.";
         check_cover("$coverpath", $msg) if($interaction == 1);
      }
      elsif($copycover ne "") {
         print "\nChecking for album cover to be copied from ",
               "copycover $copycover." if($verbose > 2);
         if($interaction == 1) {
            my $msg = "\nChecking for files to be copied from " .
                  "copycover path $copycover.";
            check_copy("$copycover", $msg);
            resize_cover("$copycover")
               if(defined $coversize && $coversize =~ /^\d+$/);
            copy_cover if(-f "$copycover" && -s "$copycover");
            $msg = "\nChecking again for album cover with path " .
                  "coverpath $coverpath.";
            check_copy("$coverpath", $msg);
         }
      }
      elsif(!-f "$coverpath" && $coverpath ne "") {
         my $msg = "\nChecking for album cover with path coverpath " .
               "$coverpath.";
         check_cover($coverpath, $msg) if($interaction == 1);
         resize_cover("$copycover")
            if(defined $coversize && $coversize =~ /^\d+$/);
      }
      if($normalize == 1 or $cdcue > 0) {
         rip_cd();
         norm_cd();
         enc_cd();
      }
      else {
         if($rip == 1) {
            rip_cd();
         }
         else {
            decode_tracks();
            enc_cd();
         }
      }
      # In case non public option multi is used make sure covers are
      # copied if not present at process beginning.
      if($multi == 1 && -f "$copycover" && -s "$copycover") {
         copy_cover;
      }
   }
   elsif($answer eq "next") {
      print "\nFound tracks of release $cd{artist} - $cd{title} ",
            "already done, giving up.\n" if($verbose > 0);
      log_info("Directory already present, giving up.");
      log_info("*" x 72, "\n");
   }
   elsif($answer eq "unknown") {
      print "\nRelease unknown, giving up.\n" if($verbose > 0);
      log_info("Release unknown, giving up.");
      log_info("*" x 72, "\n");
   }

   if($eject == 1 or $loop >= 1
                  or $overwrite eq "e" and $answer eq "next") {
      my $ejectopt = $cddev if($ejectopt eq '{cddev}');
      $ejectopt = $ejectopt . " eject" if($ejectcmd =~ /cdcontrol/);
      log_system("$ejectcmd $ejectopt");
   }

   return if($answer eq "next" or $answer eq "unknown");

   if($loop == 2) {
      my $pid = fork();
      if(not defined $pid) {
         print "\nResources not available, will quit.\n";
      }
      elsif($pid != 0) {
         finish_process($pid);
      }
      else {
         # Child: restart process.
         return;
         # Problem: being recursive, we won't come back! Hello zombie.
         exit(0);
      }
   }
   else {
      finish_process();
   }
   $loop = 0 if($loop == 2);
   return;
}
#
########################################################################
#
# SUBROUTINES
#
########################################################################
#
# New options step 9: Add new code as a subroutine somewhere below,
# the very end might be appropriate.
#
########################################################################
#
# Check local .cddb directory for cddb files with album, artist, discID
# and track titles.
#
sub get_arch {

   # Get cddbid and number of tracks of CD.
   my $trackno;
   if($rip == 0) {
      $trackno = substr($cddbid, 6);
      $trackno = hex($trackno);
   }
   else {
      ($cddbid, $trackno) = get_cddbid();
   }

   my ($artist, $album);
   my @comment = ();

   if($pgenre) {
      $genre = $pgenre;
   }
   else {
      $genre = "";
   }
   if($pyear) {
      $year = $pyear;
   }
   else {
      $year = "";
   }

   my $usearch = "x";
   my @categs = ();

   print "\nChecking for a local DB entry, please wait...\n\n"
      if($verbose > 1);
   log_system("mkdir -m 0755 -p $homedir/.cddb")
      or print "Can not create directory $homedir/.cddb: $!\n";
   opendir(CDDB, "$homedir/.cddb/")
      or print "Can not read in $homedir/.cddb: $!\n";
   @categs = grep(/\w/i, readdir(CDDB));
   close(CDDB);
   my @cddbid = ();
   foreach (@categs) {
      if(-d "$homedir/.cddb/$_") {
         opendir(CATEG, "$homedir/.cddb/$_")
            or print "Can not read in $homedir/.cddb: $!\n";
         my @entries = grep(/$cddbid$/, readdir(CATEG));
         close(CATEG);
         push @cddbid, $_ if($entries[0]);
      }
      elsif(-f "$homedir/.cddb/$_" && -s "$homedir/.cddb/$_") {
         push @cddbid, $_ if($_ =~ /$cddbid/);
      }
   }
   my $count = 1;
   my @dirflag = ();
   my $openflag = "no";
   if($cddbid[0] and $cddbid =~ /[0-9a-f]/ and length($cddbid) == 8) {
      print "Found local entry $cddbid in $homedir/.cddb !\n"
         if($interaction == 1);
      print "This CD could be:\n\n" if($interaction == 1);
      foreach (@cddbid) {
         if(-s "$homedir/.cddb/$_/$cddbid") {
            open(LOG, "$homedir/.cddb/$_/$cddbid");
            $openflag = "ok";
            $dirflag[$count-1] = 1;
         }
         elsif(-s "$homedir/.cddb/$cddbid") {
            open(LOG, "$homedir/.cddb/$cddbid");
            $_ = "no category found!";
            $openflag = "ok";
            $dirflag[$count-1] = 0;
         }
         if($openflag eq "ok") {
            my @loglines = <LOG>;
            close(LOG);
            # Here we should test if @loglines is a good entry!
            # If there are empty files, we get warnings!
            chomp(my $artist = join(' ', grep(s/^DTITLE=//, @loglines)));
            $artist = clean_all($artist);
            chomp(my $agenre = join(' ', grep(s/^DGENRE=//, @loglines)));
            $agenre =~ s/[\015]//g;
            $agenre = "none" unless($agenre);
            print "$count: $artist (genre: $agenre, category: $_)\n"
               if($interaction == 1);
            $count++;
            $agenre = "";
            $openflag = "ko";
         }
      }
      if($openflag eq "no") {
         $usearch = 0;
         print "No valid entries found for CDDBID $cddbid.\n"
            if(defined $cddbid && $verbose >= 3);
      }
      print "\n0: Search online DB instead.\n"
         if($interaction == 1);
      if($interaction == 0) {
         $usearch = 1;
         $usearch = 0 if($openflag eq "no");
      }
      else {
         while($usearch !~ /\d/ || $usearch >= $count) {
            print "\nChoose: (1) ";
            $usearch = <STDIN>;
            chomp $usearch;
            $usearch = 1 if($usearch eq "");
            print "\n";
         }
      }
   }
   else {
      print "No local entry with ID <$cddbid> found.\n";
      get_cdinfo() if($mb == 0 && $rip == 1);
      get_mb() if($mb == 1 && $rip == 1);
      log_info("No local entry with ID <$cddbid> found.");
      return;
   }

   if($usearch != 0) {
      # We use "musicbrainz" as key when reading entry if coming from
      # MB section (below). So if we have a ~/.cddb/musicbrainz
      # directory this will give problems, use word "archive" for the
      # category name instead.
      my $ctg = $cddbid[$usearch-1];
      log_info("Local entry found in $ctg/$cddbid.");
      $ctg = "archive" if($ctg =~ /musicbrainz/);
      if($dirflag[$usearch-1] == 1) {
         read_entry("$homedir/.cddb/$cddbid[$usearch-1]/$cddbid",
            $ctg, $trackno);
      }
      elsif($dirflag[$usearch-1] == 0) {
         read_entry("$homedir/.cddb/$cddbid", $ctg, $trackno);
      }
      $categ = $cd{cat} = $cddbid[$usearch-1];
   }
   else {
      get_cdinfo() if($mb == 0);
      get_mb() if($mb == 1);
      return;
   }

   # Actually this is useless if MB failed and local archive is
   # fallback... shouldn't go here in in this case as we will fail
   # again.
   # So retrieve the discid if not yet done, although we should have it
   # in case $mb == 1...
   if($mb == 1 && $rip == 1 && $discid eq "") {
      open(DISCID, "discid $scsi_cddev|");
      my @response = <DISCID>;
      close(DISCID);
      chomp($cd{discid} = join("", grep(s/^DiscID\s*:\s//, @response)));
      $discid = $cd{discid};
      # Fill up the track->id array @idata in case we want to submit
      # ISRCs after sub disc_info, but only if ripit found one single
      # match.
      if($isrc == 1) {
         eval {
            my $ws = WebService::MusicBrainz::Release->new();
            my $result = $ws->search({ DISCID => $cd{discid} });
            my @releases = @{$result->release_list->releases};
            if(scalar(@releases) == 1) {
               my $release = $releases[0];
               my @tracks = @{$release->track_list->tracks};
               for(my $i = 0; $i < scalar(@tracks); $i++) {
                  my $track = $tracks[$i];
                  push(@idata, $track->id);
               }
            }
         }
      }
   }
}
########################################################################
#
# Read the album, artist, discID and track titles via the get_CDDB()
# module.
#
sub get_cdinfo {
   my $writecddb = shift; # Passed when calling this sub from get_mb.
   $writecddb = 0 unless($writecddb);
   my %config = ();

   # Items to import into callers namespace by default.
   CDDB_get->import( qw( get_cddb get_discids ) );

   # Get cddbid and number of tracks of CD.
   my $trackno;
   if($rip == 0) {
      $trackno = substr($cddbid, 6);
      $trackno = hex($trackno);
   }
   else {
      ($cddbid, $trackno) = get_cddbid();
   }
   my $diskid = hex($cddbid);

   my ($artist, $album, $revision);
   my ($CDDB_INPUT, $CDDB_MODE, $CDDB_PORT);
   my @comment = ();

   if($pgenre) {
      $genre = $pgenre;
   }
   else {
      $genre = "";
   }
   if($pyear) {
      $year = $pyear;
   }
   else {
      $year = "" unless($writecddb == 0);
   }

   #Configure CDDB_get parameters
   if($CDDB_HOST eq "freedb2.org") {
      $config{CDDB_HOST} = $CDDB_HOST;
   }
   elsif($CDDB_HOST eq "musicbrainz.org") {
      $config{CDDB_HOST} = "freedb." . $CDDB_HOST;
   }
   else {
      $config{CDDB_HOST} = $mirror . "." . $CDDB_HOST;
   }
   while($transfer !~ /^cddb$|^http$/) {
      print "Transfer mode not valid!\n";
      print "Enter cddb or http : ";
      $transfer = <STDIN>;
      chomp $transfer;
   }
   if($transfer eq "cddb") {
      $CDDB_PORT = 8880;
      $CDDB_MODE = "cddb";
   }
   elsif($transfer eq "http") {
      $CDDB_PORT = 80;
      $CDDB_MODE = "http";
   }
   $config{CDDB_MODE} = $CDDB_MODE;
   $config{CDDB_PORT} = $CDDB_PORT;
   $config{CD_DEVICE} = $scsi_cddev;
   $config{HTTP_PROXY}= $proxy if($proxy);
   if($interaction == 0) {
      $CDDB_INPUT = 0;
   }
   else {
      $CDDB_INPUT = 1;
   }
   $config{input} = $CDDB_INPUT;
   $config{PROTO_VERSION} = $proto;

   # Change to whatever, but be aware to enter exactly 4 words!
   # E.g. username hostname clientname version
   my $hid = "RipIT www.suwald.com/ripit/ripit.html RipIT $version";
   my @hid = split(/ /, $hid);
   if($hid[4]) {
      print "There are more than 4 words in the \"HELLO_ID\".\n",
            "The handshake with the freeDB-server will fail!\n\n";
   }
   $config{HELLO_ID} = $hid;

   # Add the framelist to the calling sequence in case of re-encoding
   # with no disc to be read out. Remember, the framelist has been
   # assembled in the get_MB subroutine.
   my @toc;
   if($rip == 0) {
      my $totaltime = substr($cddbid, 2, 4);
      $totaltime = hex($totaltime);
      push(@framelist, $totaltime * 75);
      @toc = create_toc(@framelist);
   }
   print "\nChecking for a DB entry \@ $config{CDDB_HOST}...\n"
      if($verbose >= 1 && $writecddb != 0);
   if($rip == 0) {
      eval {%cd = get_cddb(\%config, [$diskid, $trackno, \@toc]);};
   }
   else {
      # use Data::Dumper;
      # print Dumper(%config);
      eval {%cd = get_cddb(\%config);};
   }
   if($@) {
      $@ =~ s/db:\s/db:\n/;
      $@ =~ s/at\s\//at\n\//;
      print "No connection to internet? The error message is:\n",
            "$@\n" if($verbose >= 1);
      $submission = 0;
   }
   #
   # Thanks to Frank Sundermeyer
   # If wanting to write the CDDB data (archive=1) but having set
   # interaction=0, the CDDB data will not get modified, so it
   # is safe to write it now.
   # But this routine is also called from get_mb (for getting a genre)
   # with $interaction temporarily set to 0. We call it with a parameter
   # set to zero (0) when calling it from get_mb. This parameter is
   # saved to $writecddb. Therefore do not write the entry if
   # $writecddb == 0, i.e. if we came from MB part.
   #
   if($interaction == 0 && $archive == 1 && defined $cd{title}) {
      write_cddb() unless($writecddb == 0);
   }

   if($multi == 1) {
      my $cddevno = $cddev;
      $cddevno =~ s/\/dev\///;
      $cddevno =~ s/(\d)/0$1/ unless($cddevno =~ /\d\d/);
      $logfile = $outputdir . "/" . $cddevno;
      read_entry($logfile, "multi");
   }
}
########################################################################
#
# Read the album, artist, discID and track titles from MusicBrainz.
#
sub get_mb {
   print "Querying MusicBrainz DB.\n" if($verbose >= 3);
   my ($mbreid, $trackno, $totaltime);

   # Get cddbid and number of tracks of CD; note: $cddbid is global and
   # might exist in case of re-encoding.
   if($rip == 0) {
      $trackno = substr($cddbid, 6);
      $trackno = hex($trackno);
      $totaltime = substr($cddbid, 2, 4);
      $totaltime = hex($totaltime);
   }
   else {
      ($cddbid, $trackno, $totaltime) = get_cddbid();
   }
   # Using the perl module to retrieve the MB discid.
   my $submit_url = 0;
   my $disc;
   if($rip == 0) {
      # TODO:
      # Manually compose the MB submission url in case operator needs
      # to submit missing data.
      $submit_url = ""
   }
   else {
      eval {$disc = new MusicBrainz::DiscID($scsi_cddev);};
      if($@) {
         # Use the libdiscid command discid to retrieve the MB discid.
         print "Discid detection with the libdiscid command.\n"
            if($verbose > 5);
         open(DISCID, "discid $scsi_cddev|");
         my @response = <DISCID>;
         close(DISCID);
         chomp($discid = join("", grep(s/^DiscID\s*:\s//, @response)));
         chomp($submit_url = join("", grep(s/^Submit\svia\s*:\s//, @response)));
      }
      else {
         print "Discid detection with module MusicBrainz::DiscID ",
            "successful.\n" if($verbose > 5);
         if($disc->read() == 0) {
            print "Error: %s\n", $disc->error_msg();
            get_cdinfo();
            return;
         }
         $discid = $disc->id();
         $submit_url = $disc->submission_url();
      }
   }
   print "\nChecking for a DB entry \@ MusicBrainz.org...\n"
      if($verbose >= 1);
   my $service;
   eval {$service = WebService::MusicBrainz::Release->new();};
   my $discid_response;
   eval {
      $discid_response = $service->search({ DISCID => $discid });
   };
   if($@){
      print "\nMusicBrainz look-up failed... 2nd try in 3s.",
            "\nError message is: $@.\n" if($verbose > 3);
      sleep 3;
      eval {$discid_response = $service->search({ DISCID => $discid });};
      if($@){
         print "\nMusicBrainz look-up failed.\n" if($verbose > 3);
         print "Using freedb instead.",
         "\nError message is: $@.\n" if($verbose > 3 && $rip > 0);
         # Do not try freedb in case $rip == 0 as we do not have the toc.
         get_cdinfo() unless($rip == 0);
         return;
      }
   }
   else {
      print "DiscID retrieved.\n" if($verbose > 4);
      print "Discid is: $discid\n" if($verbose > 3);
   }

   my $AoH;
   eval {
      my $relH = $discid_response->release_list();
      foreach my $medium (@{$relH->releases()}) {
         my $a = $medium->artist->name();
         my $i = $medium->id();
         my $t = $medium->title();
         push(@{$AoH}, {'artist' => $a, 'id' => $i, 'title' => $t});
         # MBREID needed for following conditions. Use the first one
         # presented, this is the one that will be used if only one
         # release is found.
         $mbreid = $i unless(defined $mbreid && $mbreid ne "");
      }
   };
   if($@){
      print "\nMusicBrainz does not know this discid. Use\n",
            "$submit_url for submission!\n" if($verbose > 1);
      # Do not try freedb in case $rip == 0 as we do not have the toc.
      get_cdinfo() unless($rip == 0);
      return;
   }
   # This should not happen.
   elsif(!defined $mbreid or $mbreid eq "") {
      print "\nNo discid $discid found at MusicBrainz. Use\n",
            "$submit_url for submission!\n" if($verbose > 1);
   }
   elsif($#{$AoH} > 0 && $interaction == 1) {
      print "\nMore than one release found:\n";
      my $i = 0;
      while($i > $#{$AoH}+1 || $i <= 0) {
         $i = 0;
         foreach (@{$AoH}) {
            $i++;
            printf(" %2d", $i);
            print ": ", $_->{artist}, ": ", $_->{title}, " (MBREID: ", $_->{id}, ")\n";
         }
         print "\nChoose [1-$i]: ";
         $i = <STDIN>;
         chomp $i;
      }
      $mbreid = ${$AoH}[$i-1]->{id};
      print "MBREID is: $mbreid.\n" if($verbose > 3);
      $cd{mbreid} = $mbreid;
   }
   else {
      print "MBREID is: $mbreid.\n" if($verbose > 3);
      $cd{mbreid} = $mbreid;
   }
   if(defined $mbreid and $mbreid ne "" and $verbose > 4) {
      print "\nUse\n",
            "$submit_url for submission!\n";
   }
   # Intermezzo (could be done further below).
   # Figure out number of disks and possible track offset.
   # Code based on Don Armstrongs submission.
   my $prev_discno = $discno;
   my $xml;
   my $ua = LWP::UserAgent->new();
   if(defined $mbreid && $mbreid ne "") {
      print "\nChecking for a multi disc release \@ MusicBrainz.org...\n"
      if($verbose >= 1 && $addtrackoffset == 1);
      eval {
         $ua->env_proxy();
         $ua->agent("ripit/$version");
         my $response = $ua->get("http://musicbrainz.org/ws/2/release/$mbreid?inc=media+discids+release-group-rels");
         use XML::Simple qw(:strict);
         $xml = XMLin($response->content(), ForceArray => 0, KeyAttr => []);
         if(defined $xml->{release}{'medium-list'}{count} && $xml->{release}{'medium-list'}{count} > 1) {
            foreach my $medium (@{$xml->{release}{'medium-list'}{medium}}) {
               # The discS in the disc-list can be an array. This needs
               # to be checked first.
               my $lastflag = 0;
               if(exists $medium->{'disc-list'}{count} and
                  $medium->{'disc-list'}{count} > 1) {
                  foreach my $discarray (@{$medium->{'disc-list'}{disc}}) {
                     if(exists $discarray->{$discid} or
                        exists $discarray->{id} and
                        $discarray->{id} eq $discid) {
                        $lastflag = 1;
                     }
                  }
               }
               # Else the regular case with only one disc, probably
               # not needed anymore.
               else{
                  if(exists $medium->{'disc-list'}{disc}{$discid} or
                     exists $medium->{'disc-list'}{disc}{id} and
                     $medium->{'disc-list'}{disc}{id} eq $discid) {
                     $lastflag = 1;
                  }
               }
               $discno += $medium->{'disc-list'}{count}
                  if($discno == 1 && $medium->{'disc-list'}{count} > 0);
               last if($lastflag > 0);
               $trackoffset += $medium->{'track-list'}{count}
                  if($addtrackoffset == 1);
            }
         }
      };
      print "Adding trackoffset $trackoffset to track numbers.\n"
         if($trackoffset > 0 && $verbose > 2);
      print "Setting discno to $discno.\n"
         if($discno > 1 && $prev_discno != $discno && $verbose > 2);
   }
   # Instead of pulling out the data from the release_list response
   # above, get a new response according to the MBREID choosen, sorry
   # for the additional traffic.
   eval {
      $discid_response = $service->search(
         { MBID => $mbreid,
           INC => 'artist+release-events+tracks+url-rels' });
   };
   if($@){
      print "\nMusicBrainz look-up failed... 2nd try in 3s.",
            "\nError message is: $@.\n" if($verbose > 3);
      sleep 3;
      eval {$discid_response = $service->search(
         { MBID => $mbreid,
           INC => 'artist+release-events+tracks+url-rels' });
      ;};
      if($@){
         print "\nMusicBrainz look-up failed.\n" if($verbose > 3);
         print "Using freedb instead.",
         "\nError message is: $@.\n" if($verbose > 3 && $rip > 0);
         # Do not try freedb in case $rip == 0 as we do not have the toc.
         get_cdinfo() unless($rip == 0);
         return;
      }
   }
   else {
      print "DiscID retrieved.\n" if($verbose > 4);
      print "Discid is: $discid\n" if($verbose > 3);
   }

   my $release = $discid_response->release();
   my $artist = $release->artist()->name();
   my $album = $release->title();
   my $asin = $release->asin();
   my $language = $release->text_rep_language();
   $artist =~ s/^The\s+// unless($artist =~ /^The\sThe/);
   $language = "English" unless($language);
   $language = "English" if($language eq "ENG");
   $language = "French" if($language eq "FRA");
   $language = "German" if($language eq "DEU");

   my $content = $release->release_event_list();
   my $reldate = "";
   my $barcode = "";
   my $catalog = "";
   if($content) {
      eval {$reldate = ${$content->events()}[0]->date();};
      eval {$barcode = ${$content->events()}[0]->barcode();};
      eval {$catalog = ${$content->events()}[0]->catalog_number();};
   }
   my @urls;
   my $dgid = "";
   my $asinurl = "";
   eval {
      $content = $release->relation_list->relations();
      if($content) {
         for my $url (@{$content}) {
            if(exists $url->{'target'}) {
               push(@urls, $url->{'target'});
            }
         }
      }
      foreach(@urls) {
         s:^.*discogs.com/release/::;
         $dgid = $_ if(/^\d+$/);
         $asinurl = $_ if(/www\.amazon\./);
      }
   };
   my $mb_year = $reldate;
   $mb_year =~ s/-.*$// if($mb_year);
   # Do not overwrite a year passed on CL.
   $year = $mb_year unless($year =~ /\d{4}/ );

   # Why this? Actually, I don't know. Thought that in the 21st
   # century there should be no UTF-8 problem anymore... But getting
   # e.g. track names with pure ascii in one track, latin chars in an
   # other track and even true wide chars in a third one will totally
   # mess up encoder tags and even the file names used by the ripper.
   my $temp_file = "/tmp/ripit-MB-$$\.txt";
   open(TMP, '>:utf8', "$temp_file") or print "$temp_file $!";
   print TMP "artist: $artist\n";
   print TMP "album: $album\n";
   print TMP "category: musicbrainz\n";
   print TMP "cddbid: $cddbid\n";
   print TMP "discid: $discid\n";
   print TMP "MBREID: $mbreid\n";
   print TMP "asin: $asin\n" if($asin);
   print TMP "asinurl: $asinurl\n" if($asinurl);
   print TMP "discogs: $dgid\n" if($dgid);
   print TMP "year: $year\n" if($year);
   print TMP "language: $language\n";
   print TMP "reldate: $reldate\n" if($reldate);
   print TMP "barcode: $barcode\n" if($barcode);
   print TMP "catalog: $catalog\n" if($catalog);
   print TMP "totaltime: $totaltime\n" if($totaltime);
   print TMP "disc-number: $discno\n" if($discno > 0);
   print TMP "trackoff: $trackoffset\n" if($trackoffset > 0);

   my $track_list = $release->track_list();
   my $mb_trackno = $#{$track_list->tracks()} + 1;

   my $i=0;
   my $j=0;
   @framelist = 150;
   my $frame = 150;
   print "Retrieving track relationships for each track, this might ",
         "take a while...\n" if($verbose > 2 && $mbrels > 0);
   foreach my $track (@{$track_list->tracks()}) {
      $i++;
      next if($i <= $trackoffset && $addtrackoffset == 1);
      $_ = $track->title();
      my $track_id = $track->id();

      if($mbrels > 0) {
         my $rela_artist = "";
         my $rela_work = "";

         eval {
            $ua->env_proxy();
            $ua->agent("ripit/$version");
            my $response = $ua->get("http://musicbrainz.org/ws/2/recording/" . $track->id() . "?inc=recording-rels+artist-rels+work-rels");
            $xml = XMLin($response->content(), ForceArray => ['relation-list'], KeyAttr => []);
            for my $rel (@{$xml->{recording}{'relation-list'}}) {
               if(exists $rel->{'relation'}{'artist'}{'name'}) {
                  $rela_artist = $rel->{'relation'}{'artist'}{'name'};
               }
               if(exists $rel->{'relation'}{'artist'}{'work'}) {
                  $rela_work = $rel->{'relation'}{'artist'}{'name'};
               }
            }
         };

         if($rela_artist ne "") {
            $_ .= " (featuring $rela_artist)";
         }
         if($rela_work ne "") {
            $_ .= " [covering $rela_work]";
         }
      }
      # Various artist style
      $j++;
      if($track->artist) {
         # TODO: Fill array track artist here.
         # What happens if no track artist is found? Album artist as
         # filler.
         print TMP "track $i: ", $track->artist->name(), " / $_\n";
         print "\nVarious artist style detected:\n" if($verbose > 4);
         print "track $i: ", $track->artist->name(), " / $_\n"
            if($verbose > 4);
         $va_flag = 2;
         $va_delim = "/";
      }
      # Normal tracklist style.
      else {
         my $j = $i;
         $j += $trackoffset if($trackoffset > 0 and $addtrackoffset == 0);
         print TMP "track $j: $_\n";
      }
      # For ISRC detection/submission use the track IDs.
      push(@idata, $track->id);
      push(@framelist, int($track->duration / 1000 * 75 + $frame + 0.5));
      $frame += $track->duration / 1000 * 75 + 0.5;
   }
   $trackno = $j if($rip == 0);
   $i++;
   # MusicBrainz does not state data tracks. Let's continue to fill up
   # the tracklist in the %cd-hash.
   while($i <= $trackno) {
      print TMP "track $i: data\n";
      $i++;
      $j++;
      # Oops, we're lost in case we want to fill the framelist...
   }
   print TMP "trackno: $trackno\n";

   # Some people insist in getting a genre, but MB does not supply one.
   # Don't go in here when re-encoding, no way to make a freedb look-up.
   # OK, it is possible, in case we have the cdid from freedb which
   # gives us total playing time. Now having all durations from MB
   # (except lead-out) we can calculate lead-out and therefor provide
   # the full toc, i.e. array [$diskid, $trackno, $toc] in the
   # sub get_cdinfo above. Of course we do not know the pre-gap too, so
   # just use the most common one (150s).
   if($rip == 1 and $genre eq "" and $framelist[0] =~ /\d+/) {
      my $save_inter = $interaction;
      $interaction = 0;
      print "Retrieving a genre from freedb.org.\n" if($verbose > 2);
      get_cdinfo(0);
      $interaction = $save_inter;
      $genre = $cd{genre};
      $year = $cd{year} unless($year =~ /\d{4}/);
   }
   # Actually, do not override existing genre as we have to refer to
   # freedb and from there one might get back crap. If a genre exists
   # from existing tags, keep it as it might be fulfill operators
   # wishes.
   elsif($rip == 0 && $genre eq "" && $cddbid ne "") {
      my $save_inter = $interaction;
      $interaction = 0;
      print "Retrieving a genre from freedb.org.\n" if($verbose > 2);
      get_cdinfo(0);
      $interaction = $save_inter;
      $genre = $cd{genre};
      $year = $cd{year} unless($year =~ /\d{4}/ );
   }
   print TMP "genre: $genre\n" if($genre);

   close(TMP);
   read_entry("$temp_file", "musicbrainz", $trackno);
   unlink("$temp_file");
}
########################################################################
#
# Read CD-text with code submitted by S. Oosthoek
#
sub get_cdtext {
   %cd = ();
   print "\nChecking for CD-text...\n" if($verbose > 1);
   my $cdinfoexe = `which cd-info`;
   chomp $cdinfoexe;
   if(-x $cdinfoexe) {
      open(CDTXT, "cd-info --no-cddb |");
      my $cdtextfound = 0;
      my $currentinfo = "";
      my $diff_cn = 0;
      my $prev_perf = "";
      my $tracknr = 1;
      my $prev_trnr = 0;
      while(<CDTXT>) {
         chomp;
         print "\n$_\n" if($verbose > 5);
         $cdtextfound = ($_ =~ /CD-TEXT/ || $cdtextfound) ? 1 : 0;
         if($cdtextfound) {
            if(/Disc/) {
               $currentinfo = "disk";
            }
            elsif(/Track\s+(?<tracknum>\d+):/) {
               $currentinfo = "track";
               $tracknr = $+{tracknum};
            }
            elsif(/^\s+(?<tag>\w+):\s+(?<content>.*)/) {
               my $tag = $+{tag};
               my $content = $+{content};
               if($currentinfo =~ /disk/) {
                  $cd{artist} = $content if($tag =~ /PERFORMER/);
                  $cd{title} = $content if($tag =~ /TITLE/);
               }
               elsif($currentinfo =~ /track/) {
                  # In case CD-text could not be read out completely
                  # add dummy entries for complete arrays.
                  while($prev_trnr < $tracknr) {
                     if($#{$cd{track}} > - 1 and $#{$cd{track}} < ($prev_trnr - 1)) {
                        push(@{$cd{track}}, "unknown track");
                     }
                     if($#{$cd{track_artist}} > - 1 and $#{$cd{track_artist}} < ($prev_trnr - 1)) {
                        # TODO: should the album artist be used (if defined) instead of placeholders?
                        push(@{$cd{track_artist}}, "unknown performer");
                     }
                     $prev_trnr++;
                     last if($prev_trnr > 100);
                  }
                  # Regular array filling.
                  push(@{$cd{track}}, "$content") if($tag =~ /TITLE/);
                  push(@{$cd{track_artist}}, $content) if($tag =~ /PERFORMER/);
                  $diff_cn++ if($prev_perf ne $content and $tag =~ /PERFORMER/);
                  $prev_perf = $content if($tag =~ /PERFORMER/);
                  $prev_trnr = $tracknr;
               }
               else {
                  print "No track info found on CD.\n" if($verbose > 5);
               }
            }
            else {
               print "No CDTEXT found.\n" if($verbose > 5);
            }
         }
      }
      if($cdtextfound == 0 or !defined $cd{artist} or !defined $cd{title}) {
         print "\nNo CDTEXT found.\n" if($verbose > 3);
      }
      elsif($cd{artist} eq "" && $cd{title} ne "" && $cd{track}[0] ne "" && $diff_cn > 1) {
         $cd{artist} = "Various Artists";
      }
      elsif($cd{artist} eq "" && $cd{title} eq "" && $cd{track}[0] ne "") {
         $cd{artist} = "Unknown Artist";
         $cd{title} = "Unknown Album";
      }
      elsif($cd{artist} eq "" && $cd{title} ne "" && $cd{track}[0] ne "") {
         $cd{artist} = "Unknown Artist";
      }
      elsif($cd{artist} ne "" && $cd{title} eq "" && $cd{track}[0] ne "") {
         $cd{title} = "Unknown Album";
      }
      # Check for VA style
      if($diff_cn > 1) {
         my @tra_art = @{$cd{track_artist}};
         print "Compilation detected from CD-text.\n" if($verbose > 2);
         foreach my $track (@{$cd{track}}) {
            $track = shift(@tra_art) . " / " . $track;
         }
      }
      $cd{cat} = "CDTEXT";
   }
   else {
      print "cd-info (from cdda2wav or cdio-utils package) not ",
            "installed!\n" if($verbose > 0);
   }
}
########################################################################
#
# Display CDDB info.
#
#
sub disp_info {
   my $enc_name;
   my ($artist, $album, %config, $revision);
   my ($id, $trackno, $toc, $totaltime);
   my @comment = ();

   if($rip == 1) {
      CDDB_get->import( qw( get_cddb get_discids ) );
      my $cd = get_discids($scsi_cddev);
      ($id, $trackno, $toc) = ($cd->[0], $cd->[1], $cd->[2]);
      $cddbid = sprintf("%08x", $id);
      $totaltime = sprintf("%02d:%02d",$toc->[$trackno]->{min},$toc->[$trackno]->{sec});
   }
   else {
      if($cddbid) {
         $trackno = $cddbid;
         $trackno =~ s/.*(..)$/$1/;
         $totaltime = substr($cddbid, 2, 4);
         $totaltime = hex($totaltime);
      }
   }

   if(!defined $cd{title} && $cdtext == 1 && $rip == 1) {
      get_cdtext;
   }

   if(defined $cd{title}) {
      $album = clean_all($cd{title});
      $artist = clean_all($cd{artist});
      # Remember: use of lowercase was supposed for file/dir names only,
      # tags should not be lowercase (what for?). But option
      # ucfirst is useful if DB entry is in uppercase only, and tags
      # in uppercase are rather ugly.
      $album = change_case($cd{title}, "t") if($uppercasefirst == 1);
      $artist = change_case($cd{artist}, "t") if($uppercasefirst == 1);
      $categ = $cd{cat};

      # Set the year if it wasn't passed on command line.
      unless($year) {
         $year = $cd{year} if($cd{year});
         $year =~ s/[\015]//g if($year);
      }

      # Set the genre if it wasn't passed on command line.
      if(!defined $pgenre && defined $cd{genre}) {
         $genre = $cd{genre};
         $genre =~ s/[\015]//g if($genre);
      }
      elsif(defined $pgenre && !defined $cd{genre}) { # New in 4.0
         $cd{genre} = $pgenre if($pgenre ne "");
      }

      @comment = extract_comm;
      $revision = get_rev() unless($cd{discid});
      # In case of corrupted (local) DB files.
      $revision = "unknown" unless($revision);
   }
   else {
      if($submission == 0) {
         print "\nNo CDDB info chosen or found for this CD\n"
            if($verbose > 0);
      }
      # Set submission OK, will be set to 0 if default names are used.
      $cddbsubmission = 1;
      # Don't ask for default settings, use them ...
      if($interaction == 0) {
         create_deftrack(1);
      }
      # ... or ask whether 1) default or 2) manual entries shall be used
      # or entered.
      else {
         create_deftrack(2);
      }
      $album = $cd{title};
      $artist = $cd{artist};
      $revision = $cd{revision};
   }

   if($cd{discid}) {
      # We do nothing anymore because we read the data from a file.
   }
   else {
      # The strings from archive files should be OK, because the files
      # should be written in the corresponding encoding. Only strings
      # from CDDB_get must be treated.
      # But still, this gives the error:
      # Cannot decode string with wide characters at
      # /usr/lib/perl5/5.8.8/i586-linux-threads-multi/Encode.pm line 186.
      # So do it here to be sure to analyze manually entered data!
      #
      # Create a string with the DB data to be analyzed for true UTF-8
      # (wide) characters.
      my $char_string =  $cd{title} . $cd{artist};
      $char_string .= $_ foreach (@{$cd{track}});
      $enc_name = check_encoding($char_string);
      print "\n Encoding looks like $enc_name\n" if($verbose > 6);
      Encode::from_to($artist, $enc_name, 'UTF-8') if($enc_name);
      Encode::from_to($album, $enc_name, 'UTF-8') if($enc_name);
   }


# Resetting the album and artist in the %cd-hash will screw up all the
# track titles (e.g. Bang Bang). Can you believe it? Change album and
# artist and track names will blow up. That's life, that's Perl.
# Again: we need a save copy of the string as it is now! What is wrong
# changing an entry of a hash? Why are all other entries of that
# hash screwed up?

   $album_utf8 = $album;
   $artist_utf8 = $artist;

   my $genreno = "";
   unless($artist =~ /unknown.artist/i && $album =~ /unknown.album/i && $quitnodb == 1) {
      if($genre eq "" && $interaction == 1 && $lameflag >= 0) {
         print "\nPlease enter a valid ID3v2 genre (or none): ";
         $genre = <STDIN>;
         chomp $genre;
         $cd{genre} = $genre;
      }
      if($genre) {
         $genre =~ s/[\015]//g;
         ($genre,$genreno) = check_genre($genre);
      }
   }
   if($verbose >= 1) {
      print "\n", "-" x 17, "\nCDDB and tag Info", "\n", "-" x 17, "\n";
      print "Artist: $artist_utf8\n";
      print "Album: $album_utf8\n";
      print "Category: $categ\n" if($verbose >= 2);
      if($genre && $genre ne "") {
         print "ID3-Genre: $genre ($genreno)\n" if($lameflag >= 0);
         print "Genre-tag: $genre\n" if($lameflag == -1);
         if(lc($genre) ne lc($cd{genre})) {
            print "CDDB-Genre: $cd{genre}\n";
         }
      }
      else{
         print "ID3-Genre: none\n";
      }
      print "ASIN: $cd{asin}\n" if($cd{asin});
      print "ASIN-url: $cd{asinurl}\n" if($cd{asinurl});
      print "discogs: $cd{dgid}\n" if($cd{dgid});
      print "Barcode: $cd{barcode}\n" if($cd{barcode});
      print "Catalog: $cd{catalog}\n" if($cd{catalog});
      print "Language: $cd{language}\n" if($cd{language});
      print "Release date: $cd{reldate}\n" if($cd{reldate});
      print "Year: $year\n" if($year);
      print "Revision: $revision\n" if($verbose >= 2);
      # It happens, that the ID from CDDB is NOT identical to the ID
      # calculated from the frames of the inserted CD...
      if($rip == 1) {
         if(defined $cd{id} && $cddbid ne $cd{id}) {
            print "CDDB id: $cd{id}\n";
         }
      }
      print "CD ID: $cddbid\n";
      print "DiscID: $discid\n" if($discid);
      print "MB ID: ", $cd{mbreid}, "\n" if($cd{mbreid});
      if(@comment && $verbose >= 2) {
         foreach (@comment) {
            print "Comment: $_\n" if($_);
         }
      }
      print "CD length: $totaltime\n";
      print "CD number: $discno\n" if($discno > 0);
      print "\n";
   }
   log_info("\nArtist: $artist");
   log_info("Album: $album");
   log_info("ID3-Genre: $genre ($genreno)") if($genre);
   log_info("ID3-Genre: none") unless($genre);
   log_info("Category: $categ");
   log_info("ASIN: $cd{asin}") if($cd{asin});
   log_info("CD id: $cddbid");
   log_info("Disc id: $cd{discid}")
      if($cd{discid} && $cd{discid} ne $cddbid);
   log_info("MB rel id: $cd{mbreid}") if($cd{mbreid});
   log_info("CD length: $totaltime\n");
   log_info("CD number: $discno\n") if($discno > 0);

   # Read out pre-gap before calculating track lengths.
   # Prevent double filled framelist arrays when sub read_entry
   # already filled @framelist.
   my $frameflag = 0;
   $frameflag = 1 if($framelist[0]);
   my $frames = 150; # The hard way if $rip == 0 (no disc to be read).
   if($rip == 1) {
      $frames = $toc->[0]->{'frames'};
      check_audio();
   }
   push @framelist, "$frames" if($frameflag == 0);
   if($frames > 400) {
      my $second = int($frames/75);
      my $frame = $frames - $second * 75;
      my $minute = int($second/60);
      $second -= $minute * 60;
      printf("%s %02d:%02d %s %d %s\n",
         "There might be a hidden track", $minute, $second,
         "long,\nbecause offset of track 01 has", $frames,
         "frames\nintstead of typically 150 (equals 2 seconds).\n")
         if($verbose >= 1);
      my $riptrackname = "Hidden Track";
      $riptrackname = change_case($riptrackname, "t");
      $riptrackname =~ s/ /_/g if($underscore == 1);
      if("@audio" =~ /\*/ && $rip == 1) {
         printf(" %s %02d: [%02d:%02d.%02d] %s\n", " ",
                "00", $minute, $second, $frame, $riptrackname)
            if($verbose > 1);
      }
      else {
         printf("%s: [%02d:%02d.%02d] %s\n",
            "00", $minute, $second, $frame, $riptrackname)
            if($verbose >= 1);
      }
      $second = int($frames/75);
      $hiddenflag = 1 if($trackselection eq ""
         || $trackselection =~ /^0/
         || $trackselection =~ /\D0/
         || $trackselection =~ /1-a/);
      # We can't add this track to seltrack and framelist, because this
      # would break (re-) submission of CDDB.
      # Note: seltrack is not yet defined... But we start to fill the
      # @secondlist array (yet empty) with track lengths in seconds.
      # TODO: push the pre-gap seconds to the list in any case, then we
      # don't need to differentiate between the case hiddenflag == 1 or
      # hiddenflag == 0 while choosing track names.
      push(@secondlist, "$second") if($hiddenflag == 1);
      # No need to: unshift(@audio, ' ');
      # here, printout has already been done for the hidden track...
   }
   # In case of $rip == 0 and archive entry found:

   # Print track information.
   my $n = 1;
   $n = 0 if($rip == 0 and $hiddenflag == 1);
   foreach (@{$cd{track}}) {
      $_ = clean_all($_);
      $_ = change_case($_, "t") if($uppercasefirst == 1);

      # Print track in case of re-encoding only if track is present.
      # If no flac present, @tracksel is not yet filled and we would
      # miss all track names, track tags etc.
      # TODO: should array @tracksel be filled in the sub get_cdid also
      # if no flac are present?
      my $nextflag = 0;
      if($rip == 0 && defined $tracksel[0]) {
         foreach my $num (@tracksel) {
            $nextflag = 1 if($num == $n && $nextflag == 0);
            $nextflag = 1 if($num == $n+1 && $nextflag == 0 && $hiddenflag == 1);
         }
         $n++ if($nextflag == 0); # Needed in case only a track 1 and e.g. a track 8 are present
         next if($nextflag == 0);
      }

      Encode::from_to($_, $enc_name, 'UTF-8') if($enc_name);
      push(@tracktags, $_);

      # Get frames and total time.
      my $frames = 0;
      if($rip == 1) {
         $frames = $toc->[$n]->{'frames'};
      }
      else {
         $frames = $secondlist[$n - 1] * 75 if($secondlist[$n - 1]);
         $frames = $framelist[$n] unless($frames);
         # In case $rip == 0 and no tag-update shall happen, array
         # framelist only consists of the initialized value and
         # consecutive tracks will have length -2 s... rather make them
         # zero length.
         $frames = 150 unless($frames);
      }
      push(@framelist, "$frames") if($frameflag == 0);
      $frames = $frames - $framelist[$n - 1];
      my $second = int($frames / 75);
      push(@secondlist, "$second") if($rip == 1);
      my $frame = $frames - $second * 75;
      $frame = 0 if($frame < 0);
      my $minute = int($second / 60);
      $second -= $minute * 60;
      $_ = clean_chars($_) if($chars);
      if("@audio" =~ /\*/ && $rip == 1) {
         printf(" %s %02d: [%02d:%02d.%02d] %s\n", $audio[$n],
                $n + $trackoffset, $minute, $second, $frame, $_)
            if($verbose > 1);
      }
      else {
         printf("%02d: [%02d:%02d.%02d] %s\n",
                $n + $trackoffset, $minute, $second, $frame, $_)
            if($verbose > 1);
      }
      $_ = clean_name($_);
      $_ = change_case($_, "t");
      $_ =~ s/ /_/g if($underscore == 1);
      # Why do we do this? We need an array @tracklist in case operator
      # wants to alter the track-tags (and this implies the track-names
      # in the encoder process) in sub create_deftrack.
      # So, do this as before not only if $rip == 1.
      push(@tracklist, $_);
      $n++;
   }
   if("@audio" =~ /\*\s+\*/ && $rip == 1) {
      print "\n * Detected data tracks (will be omitted in case ",
            "trackselection is 1-a)." if($verbose > 1);
   }
   elsif("@audio" =~ /\*/ && $rip == 1) {
      print "\n * Detected data track (will be omitted in case ",
            "trackselection is 1-a)." if($verbose > 1);
   }
   print "\n\n" if($verbose >= 1);

   # Some more error checking.
   if($artist eq "") {
      die "Error: No artist found!\n";
   }
   if(!defined $tracklist[0]) {
      die "Error: No tracks found!\n" if($rip == 1); # New in 4.0
   }

   get_isrcs if($isrc == 1 && $mb == 1 && $rip == 1);

   # LCDproc
   if($lcd == 1) {
      $lcdline1 = $artist . "-" . $album;
      $lcdline2 = "R00|00.0%|----------";
      $lcdline3 = "E00|00.0%|----------";
      ulcd();
   }
}
########################################################################
#
# Create the track selection from the parameters passed on the command-
# line, i. e. create an array with all track numbers including those not
# explicitly stated at the command line.
#
sub create_seltrack {
   if($rip == 0) {
      # Check what is present, nothing more needs to be done, but
      # sub check_va would respond even if all values tested are zero.
      return;
   }
   else {
      print "\nGot @_ as ARG.\n" if($verbose > 5 and "@_" ne "");
   }
   my($tempstr, $intrack);
   ($tempstr) = @_;
   if($_[0] eq "-") {
         die "Invalid track selection \"-\"!\n\n";
   }
   elsif($tempstr =~ /\d+-a/) {
      my $first_tn = $tempstr;
      $first_tn =~ s/\D*//g;
      $tempstr = "";
      my $tcn = 0;
      foreach (@audio) {
         $tempstr .= "$tcn," if($_ ne "*" and $tcn >= $first_tn);
         $tcn++;
      }
      $tempstr =~ s/,$//;
      $tempstr =~ s/^0,//;
   }

   if(($tempstr =~ /,/) || ($tempstr =~ /\-/)) {
      my @intrack = split(/,/ , $tempstr);
      # If last character is a , add an other item with a -
      if($tempstr =~ /,$/) {
         push @intrack, ($intrack[$#intrack]+1) . "-";
      }
      foreach $intrack (@intrack) {
         if($intrack =~ /\-/) {
            my @outrack = split(/-/ , $intrack);
            # If last character is a -, add last track to $outrack
            if($#outrack == 0) {
               $outrack[1] = $#tracklist + 1;
               if($outrack[0] > ($#tracklist + 1)) {
                  die "Track selection higher than number of tracks ",
                      "on CD.\n\n";
               }
            }
            for(my $i = $outrack[0]; $i <= $outrack[1]; $i++) {
               push(@seltrack, $i);
            }
         }
         else {
            push(@seltrack, $intrack);
         }
      }
   }
   elsif($tempstr eq '') {
      for(my $i = 1; $i <= ($#tracklist + 1); $i++) {
         $seltrack[$i - 1] = $i;
      }
   }
   elsif($tempstr =~ /^[0-9]*[0-9]$/) {
      $seltrack[0] = $tempstr;
   }
   else {
      die "Track selection invalid!\n";
   }

   @seltrack = sort {$a <=> $b} @seltrack;

   # Check the validity of the track selection.
   foreach (@seltrack) {
      if($_ > ($#tracklist + 1)) {
         die "Track selection higher than number of tracks on CD.\n\n";
      }
      elsif($_ == 0) {
         shift @seltrack;
      }
   }
   return;
}
########################################################################
#
# Ask if CDDB submission shall be done. Either because one might change
# some settings a last time before writing to directories and files (if
# there was no DB entry and operator entered all by hand) or because
# DB entry had some typos! Also x-check for VA-style and let operator
# change settings according to meta data retrieved (in case interaction
# is on) and finally submit ISRCs to MusicBrainz if login info available
# and the ISRCs are OK.
#
sub ask_subm {
   my $index = 2;
   my $save_archive = $archive;
   unless($cddbsubmission == 0 || $interaction == 0) {
      while($index !~ /^[0-1]$/) {
         print "\nDo you want to edit or submit the CDDB entry?";
         print "\nTo confirm each question type Enter.\n\n";
         print "1: Yes, and I know about the naming-rules of ";
         print "freedb.org!\n\n";
         print "0: No\n\nChoose [0-1]: (0) ";
         $index = <STDIN>;
         chomp $index;
         if($index eq "") {
            $index = 0;
         }
         print "\n";
      }
      if($index == 1) {
         my $revision = get_rev() unless($cd{discid});
         if($revision) {
            print "\nPlease change some settings.";
            print "\nYou may confirm CDDB settings with \"enter\".\n";
            create_deftrack(0);
         }
         else {
            print "\nPlease change some settings.";
            print "\nYou may confirm given settings with \"enter\".\n";
            create_deftrack(0);
         }
      }
      elsif($index == 0) {
         #
         # CDDB data does not get modified, write the existing data to
         # the local CDDB if wanted.
         if($archive == 1 && defined $cd{title}) {
            write_cddb();
         }
      }
      else {
         print "Choose 0 or 1!\n";
      }
   }
   if($index == 1) {
      pre_subm();
   }
   elsif($archive == 1 && defined $cd{title} && $mb == 1 && $index == 2) {
      write_cddb();
   }
   $archive = $save_archive;
   # Once the meta data has been altered (optionally), check for
   # VA style.
   # Delimiters to be checked for various artists style.
   my $delim_colon = 0;
   my $delim_hyphen = 0;
   my $delim_slash = 0;
   my $delim_parenthesis = 0;
   my $n = 0;
   if($vatag > 0) {
      # We call check_va only to print detected results if verbosity is
      # switched on.
      my $trackno =  $#tracklist + 1;
      my ($delim, $delim_cn) = check_va(1);
      $delim_cn = 0 unless(defined $delim_cn);
      unless($artist_utf8 =~ /unknown.artist/i && $album_utf8 =~ /unknown.album/i && $quitnodb == 1) {
         if($interaction == 1) {
            $index = 9;
            while($index !~ /^[0-8]$/) {
               print "\nDelimiter $delim found on $delim_cn of ",
                     "$trackno tracks." if(defined $delim and $delim_cn > 0);
               print "\nAll tracks have a delimiter: suggestion: use 1 ",
                     "(2) or 5 (6)." if(defined $delim && defined $delim_cn && $delim_cn > 0 && $delim_cn >= $trackno);
               print "\nOnly some tracks have a delimiter: suggestion: ",
                     "use 3 (4) or 7 (8)." if($delim_cn > 0 && $delim_cn < $trackno);
               print "\nDo you want to change option --vatag to alter ",
                     "detection of compilation style?",
                     "\n\nChoose [0-8]: ($vatag) ";
               $index = <STDIN>;
               chomp $index;
               if($index eq "") {
                  $index = $vatag;
               }
               print "\n";
               $vatag = $index if($index =~ /[0-8]/);
            }
         }
      }
   }
   return;
}
########################################################################
#
# Create the directory where the sound files shall go.
# Directory created will be: /outputdir/$dirtemplate[$c] .
# We first check the wavdir and set the counter $c for the encoder
# depending arrays @sepdir, @suffix, @globopt to -1. In this way,
# directory names will not be suffixed with a counter if they shall be
# the same for wavs and encoded files (condition $soundir ne $wavdir and
# the exception handling below).
#
sub create_dirs {
   my $c = -1;
   my $save_overwrite = $overwrite;

   # Get cddbid and number of tracks of CD, needed e.g. with option
   # --precmd.
   my $trackno;
   if($rip == 1) {
      ($cddbid, $trackno) = get_cddbid();
   }
   else {
      if($cddbid ne "") {
         $trackno = substr($cddbid, 6);
         $trackno = hex($trackno);
      }
      else {
         $trackno = $tracklist[$#tracklist];
      }
   }

   foreach("wav", @coder) {
      my $suffix = $suffix[$c] if(defined $suffix[$c]);
      $suffix = "wav" if($_ eq "wav");
      my $quality = $globopt[$c] if(defined $globopt[$c]);
      $quality = "" if($_ eq "wav");

      # Why this? Remember, we have worked a lot with encoding of artist
      # and album names!
      my $album = clean_all($album_utf8);
      my $artist = clean_all($artist_utf8);
      $album = clean_name($album);
      $artist = clean_name($artist);
      $album = clean_chars($album) if($chars);
      $artist = clean_chars($artist) if($chars);
      $artist = change_case($artist, "d");
      $album = change_case($album, "d");
      $album =~ s/ /_/g if($underscore == 1);
      $artist =~ s/ /_/g if($underscore == 1);

      # Define variable for initial letter of artist.
      my $iletter = $artist;
      $iletter =~ s/\s*(.).*/$1/;
      if($iletter =~ /\d/) {
         my @words = split(/ /, $artist);
         shift(@words);
         foreach (@words) {
            $iletter = $_;
            $iletter =~ s/\s*(.).*/$1/;
            last if($iletter =~ /\w{1}/);
         }
      }
      $iletter = "A" unless($iletter);
      $iletter = "\u$iletter" unless($lowercase == 1 or $lowercase == 3);

      # Take the last dirtemplate for missing ones and for wav.
      my $dirindex = $c;
      if($suffix eq "wav") {
         $dirindex = $#dirtemplate;
      }
      elsif($c > $#dirtemplate) {
         $dirindex = $#dirtemplate;
      }

      # Check and create the full path where the files will go.
      # Check the dirtemplate and use the actual year as default if
      # $year is in the template and none is given!
      if(($dirtemplate[$dirindex] =~ /\$year/ or
          $tracktemplate =~ /\$year/) && !$year) {
         $year = sprintf("%04d", sub {$_[5]+1900}->(localtime));
      }
      # Do the same for the genre.
      if(($dirtemplate[$dirindex] =~ /\$genre/ or
          $tracktemplate =~ /\$genre/)) {
         $genre = "Other" if($genre eq "");
         chomp $genre;
      }

      my $dir;
      if(!eval("\$dir = $dirtemplate[$dirindex]")) {
         die "Directory template incorrect, caused eval to fail: $!\n";
      }
      $dir =~ s,\s-\s/,/,g; # Do this in any case, even if all chars are
      $dir =~ s,\s-\s$,,g;  # allowed.
      $dir =~ s,\s+/,/,g; # Do this in any case, even if all chars are
      $dir =~ s,\s+, ,g;  # allowed.
      $dir =~ s,\s-\s-\s*, ,g;
      # Change case again only if lowercase wanted! Else we will get
      # lower case of special dirtemplates like: $iletter/$artist: here
      # artist would be converted to lowercase, since we check for words!
      $dir = change_case($dir, "t") if($lowercase == 1 or $lowercase == 3);
      $dir = clean_chars($dir) if($chars);
      $dir =~ s/ /_/g if($underscore == 1);

      $dir =~ s/\.+$// if($chars =~ /NTFS/);
      $dir =~ s/^\///;
      my $soundir = $outputdir . "/" . $dir if($outputdir !~ /\/$/);
      $soundir = $outputdir . $dir if($outputdir =~ /\/$/);
      # Check if the soundir already exists, if it does, try "soundir i"
      # with i an integer until it works, unless option resume is given.
      #
      # TODO: What if two identical named discs shall be done, but with
      # different number of tracks (different track names will be too
      # difficult to distinguish!)? Maybe we should test here the number
      # of tracks in an existing directory with same name...
      # E.g. Nouvelle Vague: Bande à part, EU version, US version,
      # LTD. Ed, initial release version... all have the same name but
      # different track names/numbers.
      #
      my $cdexistflag = 0;
      my $i = 1;
      my $nsoundir = $soundir;
      my $sfx = "";
      while(defined(opendir(TESTDIR, $nsoundir)) &&
            # $rip == 1 && # No overwriteing while re-encoding.
            $resume == 0 && $soundir ne $wavdir) {
         $sfx = " " . $i if($underscore == 0);
         $sfx = "_" . $i if($underscore == 1);
         $sfx = clean_chars($sfx) if($chars);
         $nsoundir = $soundir . $sfx;
         $i++;
         $cdexistflag = 1;
      }
      # In case a multi-disc release is ripped using trackoffset it
      # would be nice to rip to the existing directories, but how to
      # detect if those tracks have already been ripped?
      # Note that operator could have first ripped the n-th disc and
      # the first disc is the last one to be added to the directory, so
      # it would not be a good idea to say that the n-th track number
      # should not exist.
      if($addtrackoffset == 1 && $overwrite ne "y" ) {
         my $riptracktag = $tracktags[0];
         $riptracktag = $tracktags[1] if($hiddenflag == 1);
         my $artistag;
         my ($delimiter, $dummy) = check_va(0) if($vatag > 0);
         my $delim = quotemeta($delimiter) if(defined $delimiter);
         $vatag = 0 if(!defined $delim or $delim eq "");

         # Split the tracktag into its artist part and track part if
         # VA style is used.
         if(defined $delim && $va_flag > 0 && $riptracktag =~ /$delim/) {
            ($artistag, $riptracktag) = split_tags($riptracktag, $delim);
         }
         $artistag = clean_all($artist_utf8) unless(defined $artistag);
         my $trackartist = clean_all($artistag);
         $trackartist = clean_name($trackartist);
         $trackartist = clean_chars($trackartist);
         my $tracktitle = clean_all($riptracktag);
         $tracktitle = clean_name($tracktitle);
         $tracktitle = clean_chars($tracktitle);
         $trackartist =~ s/ /_/g if($underscore == 1);
         $tracktitle =~ s/ /_/g if($underscore == 1);
         my $riptrackname = get_trackname(1, $tracklist[0], 0, $trackartist, $tracktitle);
         $riptrackname = get_trackname(0, $tracklist[1], 0, $trackartist, $tracktitle)
            if($hiddenflag == 1);
         $riptrackname = $album if($book == 1 or $cdcue == 2);
         $cdexistflag = 0;
         # Note that the "original" $soundir (existing) is tested here
         # and not the new $nsoundir with suffix (not yet existing).
         $cdexistflag = 1 if(-f "$soundir/$riptrackname.$suffix");
         $overwrite = "y" if($cdexistflag == 0);
      }
      return "next" if($cdexistflag == 1 && $overwrite =~ /^e|q$/);
      return "unknown" if($artist =~ /unknown.artist/i && $album =~ /unknown.album/i && $quitnodb == 1);

      $nsoundir = $soundir if($overwrite eq "y");
      # Exception handling: if the $wavdir is identical to the
      # $nsoundir apart from a suffixed counter, use the $wavdir as
      # $soundir instead of the incremented $nsoundir!
      esc_char($soundir, 0);
      my $qwavdir = $wavdir;
      my $qsoundir = $soundir;
      $qwavdir =~ s/\|/\\|/g;
      $qsoundir =~ s/\|/\\|/g;
      $nsoundir = $wavdir if($qwavdir =~ /$qsoundir.\d+/);

      if($multi == 1 && $_ eq "wav") {
         if($overwrite =~ /^y$/) {
            $cdexistflag = 0;
            $sfx = "";
            # Delete existing error.log file to prevent ripping of
            # more than one slot at once.
            if(-f "$wavdir/error.log") {
               unlink("$wavdir/error.log");
            }
         }
         my $aadir = $dir . $sfx;
         if($cdexistflag == 1) {
            $i--;
            open(SRXY,"$logfile") or
               print "Can not open \"$logfile\"!\n";
            my @srxylines = <SRXY>;
            close(SRXY);
            chomp(my $orig_album = join(' ', grep(/^album:\s/, @srxylines)));
            grep(s/^album:\s(.*)$/album: $1 $i/, @srxylines)
               if($underscore == 0);
            grep(s/^album:\s(.*)$/album: $1_$i/, @srxylines)
               if($underscore == 1);
            open(SRXY,">$logfile")
               or print "Can not write to file \"$logfile\"!\n";
            print SRXY @srxylines;
            print SRXY "Original-$orig_album\n";
            close(SRXY);
         }
         log_system("cp \"$logfile\" \"$soundir/$dir.db\"");
         open(SRXY,">>$logfile")
            or print "Can not append to file \"$logfile\"!\n";
         print SRXY "\n\nArtist - Album:$aadir";
         close(SRXY);
      }
      $soundir = $nsoundir;
      $soundir =~ s;/$;;g;
      $overwrite = $save_overwrite;

      # Problem: multi level directory creation should set permission to
      # each directory level. I thought the easiest way would be to
      # alter permissions using umask and then set it back. I did not
      # succeed.
      #
      # Save machines umask for reset.
      my $umask = umask();

      # Get the default permission mode.
      my $dperm = sprintf("%04o", 0777 & ~umask());

      # Do not create the wav directory in case rip (Morituri) is used,
      # else Morituri will give up on existing directories.
      if($suffix eq "wav" && $ripper == 3) {
         print "\nNo wav directory created when using Morituri, the ",
               "ripper will take care of it.\n" if($verbose > 3);
      }
      elsif(!opendir(TESTDIR, $soundir)) {
         # Explicitly log soundir creation.
         log_info("new-mediadir: $soundir");

         # The so called Holzhacker-Method: create dir level by level.
         # TODO: Let me know the good way to do it, thanks.
         my $growing_dir = "";
         foreach (split(/\//, $soundir)) {
            next if($_ eq " ");
            # Should we allow relative paths?
            if($_ =~ /^\.{1,2}$/ && $growing_dir eq "") {
               $growing_dir .= "$_";
            }
            else {
               $growing_dir .= "/$_";
            }
            $growing_dir =~ s;//;/;g;
            if(!opendir(TESTDIR, $growing_dir)) {
               log_system("mkdir -m $dpermission -p \"$growing_dir\"");
               if(! -d "$growing_dir") {
                  print "\nWill try to trim length of directory.\n"
                     if($verbose > 4);
                  while(length($_) > 250) {
                     chop;
                     chop($growing_dir);
                  }
                  log_system("mkdir -m $dpermission -p \"$growing_dir\"")
                     or die "Can not create directory $growing_dir: $!\n";
                  $limit_flag = 255;
               }
            }
         }
         # In case $growing_dir needed to be shorten.
         $soundir = $growing_dir;
         # Do it again for security reasons.
         log_system("mkdir -m $dpermission -p \"$soundir\"")
            or die "Can not create directory $soundir: $!\n";
         # What if strange chars appear like backslash?
         # Can the created dir be accessed with $sounddir?
         if(!defined(opendir(SND, "$soundir"))) {
            print "Can not read in $soundir: $!\n";
            exit;
         }
         close(SND);
      }
      else {
         closedir(TESTDIR);
      }
      # Reset umask
      #umask($umask) if defined $umask;
      $sepdir[$c] = $soundir unless($_ eq "wav");
      $wavdir = $soundir if($_ eq "wav");
      $c++;

      # New in 4.0
      del_wav if($overwrite =~ /^y$/ && $suffix eq "wav" && $rip == 1);
      # This might not be the best place to set up the pre- and exe-
      # command and the coverpath but this is where most variables are
      # available. The same goes for the copycover variable.
      if($execmd && $suffix eq "wav") {
         my $exec;
         if(!eval("\$exec = $execmd")) {
            print "execmd incorrect, caused eval to fail: $!\n";
         }
         $execmd = esc_char($exec, 1);
      }
      if($precmd && $suffix eq "wav") {
         my $prec;
         print "\nEvaluating $precmd.\n" if($verbose > 4);
         if(!eval("\$prec = $precmd")) {
            print "precmd <$prec> incorrect, caused eval to fail: $!\n";
         }
         $precmd = esc_char($prec, 1);
      }
      # Test the coverart only once, use suffix wav to prevent repeated
      # checks. This will be omitted in case rip (Morituri) is used.
      if($coverpath && $suffix eq "wav") {
         if($coverpath =~ /\$/) {
            my $covp;
            if(!eval("\$covp = $coverpath")) {
               print "coverpath incorrect, caused eval to fail: $!\n";
            }
            $coverpath = $covp;
         }
         else {
            print "No further checks to be done on coverpath $coverpath.\n"
               if($verbose > 4);
         }
      }
      if($copycover && $suffix eq "wav") {
         if($copycover =~ /\$/) {
            my $copy;
            if(!eval("\$copy = $copycover")) {
               print "copycover path incorrect, caused eval to fail: $!\n";
            }
            $copycover = $copy;
         }
         else {
            print "No further checks to be done on copycover $copycover.\n"
            if($verbose > 4);
         }
      }
      # Reset suffix:
      $suffix = "";
   }
   return("go");
}
########################################################################
#
# Create the full-path track file name from the tracktemplate variable.
#
sub get_trackname {
   my($trnum, $trname, $riptrname, $shortflag, $trackartist, $tracktitle);

   ($trnum, $trname, $shortflag, $trackartist, $tracktitle) = @_;
   $shortflag = 0 unless($shortflag);

   my $album = clean_all($album_utf8);
   my $artist = clean_all($artist_utf8);
   $album = clean_name($album);
   $artist = clean_name($artist);
   $album = clean_chars($album) if($chars);
   $artist = clean_chars($artist) if($chars);
   $album =~ s/ /_/g if($underscore == 1);
   $artist =~ s/ /_/g if($underscore == 1);

   # Fill VA parameters in case they're empty, does not hurt if not
   # needed at all. Switched condition in 4.0.
   $trackartist = $artist unless(defined $trackartist && $trackartist ne "");
   $tracktitle = $trname unless(defined $tracktitle && $tracktitle ne "");

   # Create the full file name from the track template, unless
   # the disk is unknown.
   if($trname =~ /short/ && $shortflag =~ /short/) {
      $riptrname = $trname;
   }
   elsif(defined $cd{title}) {
      # We do not need to lowercase the track template because all
      # variables are already lowercase!
      $tracktemplate =~ s/ /\\_/g if($underscore == 1);
      # We have to update tracknum and track name because they're
      # evaluated by the track template!
      my $tracknum = sprintf("%02d", $trnum + $trackoffset);
      my $trackname = $trname;
      if(!eval("\$riptrname = $tracktemplate")) {
         die "\nTrack Template incorrect, caused eval to fail: $!.\n";
      }
   }
   else {
      $trname  = change_case($trname, "t");
      $trname =~ s/ /_/g if($underscore == 1);
      $riptrname = $trname;
   }

   if($limit_flag == 255) {
      $riptrname = substr($riptrname, 0, 250);
   }

   # No counters if option book or cdcue is used:
   if($book == 1 or $cdcue > 0) {
      $riptrname =~ s/^\d+[\s|_]// if($tracktemplate =~ /^\$tracknum/);
   }
   return $riptrname;
}
########################################################################
#
# Rip the CD.
#
sub rip_cd {
   my($ripcom, $riptrackname, $riptracktag);
   my $startenc = 0;
   my $failflag = 0;
   my $resumerip = $resume;
   my $trackstart = 0;
   my $cue_point = 0;
   # Cleaning.
   my $albumtag = clean_all($album_utf8);
   my $artistag = clean_all($artist_utf8);
   my $album = $albumtag;
   $album = clean_name($album);
   my $artist = $artistag;
   $artist = clean_name($artist);
   $album = clean_chars($album) if($chars);
   $artist = clean_chars($artist) if($chars);
   $album =~ s/ /_/g if($underscore == 1);
   $artist =~ s/ /_/g if($underscore == 1);
   # New parameters for tracktemplate used for file names only, i.e.
   # less verbose than the corresponding tags $artistag and tracktag.
   my $trackartist;
   my $tracktitle;

   # Delete existing md5 files in case of resuming.
   if($md5sum == 1 && $resume == 1) {
      if($wav == 1) {
         my @paths = split(/\//, $wavdir);
         my $md5file =  $paths[$#paths] . " - wav" . ".md5";
         $md5file =~ s/ /_/g if($underscore == 1);
         unlink("$wavdir/$md5file");
      }
      for(my $c = 0; $c <= $#coder; $c++) {
         my @paths = split(/\//, $sepdir[$c]);
         my $md5file =  $paths[$#paths] . " - " . $suffix[$c] . ".md5";
         $md5file =~ s/ /_/g if($underscore == 1);
         unlink("$sepdir[$c]/$md5file");
      }
   }

   # Delete machine.lock files.
   if($resume == 1) {
      opendir (DIR, "$wavdir") or print "Can't open $wavdir $!\n";
      my @lockfiles = grep(/\.lock_\d+$/, readdir(DIR));
      @lockfiles = grep(/\.lock$/, readdir(DIR)) unless($lockfiles[0]);
      closedir(DIR);
      unlink("$wavdir/$_") foreach(@lockfiles);
   }

   # Delete existing ghost.log file unless we're resuming. Nevertheless
   # this might lead to corrupted content if $resume == 1.
   if(-r "$wavdir/ghost.log" && $resume == 0) {
      unlink("$wavdir/ghost.log");
   }

   # Get delimiter for VA style.
   # We need it here only in case merge is used.
   # No messages to be printed.
   my ($delimiter, $dummy) = check_va(0) if($vatag > 0);
   my $delim = quotemeta($delimiter) if(defined $delimiter);
   $vatag = 0 if(!defined $delim or $delim eq "");
   # Define an array with intervals and the tracks to be skipped.
   # First clean-up array @framelist, may contain strange characters
   # appearing when printed values get screwed up.
   if($book == 1 || $cdcue == 2) {
      # The array of tracks to skipped needs to be filled somewhere, but
      # not too early (failure if no track numbers exist) and not too
      # late too. So somewhere in between.
      my @dummy = skip_tracks(1) if($pmerge);
   }
   s/\D//g foreach(@framelist);
   my @merge = ();
   my @skip = ();
   # If merge is used, we need to calculate the true track length for
   # the chaptermark and playlist file. An copy of the original values
   # is needed.
   @framelist_orig = @framelist;
   if($pmerge) {
      # If hidden track supposed, try to merge it too in case operator
      # wants a book or a cdcue.
      $pmerge = "0-" if($hiddenflag == 1 && ($book == 1 || $cdcue == 2));
      @skip = skip_tracks(0);
      @merge = split(/,/, $pmerge);
      # Define a string to concatenate the track names.
      my $concat = " + ";
      $concat =~ s/ /_/g if($underscore == 1);
      $concat = clean_chars($concat) if($chars);
      foreach(@merge) {
         my @bea = split(/-|\+/, $_);
         my $beg = $bea[0] - 1;
         $beg = 0 if($beg < 0); # If nerds want to merge hidden tracks.
         while($bea[0] < $bea[1]) {
            $secondlist[$beg] += $secondlist[$bea[0]];
            # Framelist is already a summed list and we do not want to
            # spoil indices of tracks kept, alter subsequent tracks
            # merged.
            $framelist[$beg+1] = $framelist[$bea[1]];
            # Don't merge all track names if option book or cdcue is
            # used.
            if($vatag == 0) {
               $tracklist[$beg] = $tracklist[$beg] . $concat .
                  $tracklist[$bea[0]] unless($book == 1 or $cdcue == 2);
               $tracktags[$beg] = $tracktags[$beg] . " + " .
                  $tracktags[$bea[0]] unless($book == 1 or $cdcue == 2);
            }
            else {
               $tracklist[$beg] = $tracklist[$beg] . $concat .
                  $tracklist[$bea[0]] unless($book == 1 or $cdcue == 2);
               my $delim_l_close = $delim;
               my $delim_t_close = $delim;
               if($delim =~ /[([{]/) {
                  $delim_l_close =~ tr/\({\[/)}]/;
                  $delim_t_close =~ tr/\({\[/)}]/;
#                   $delim_l_close = chop($tracklist[$beg]) if($tracktags[$beg] =~ /[)}\]]$/);
#                   $delim_t_close = chop($tracktags[$beg]) if($tracktags[$beg] =~ /[)}\]]$/);
               }
               # Syntax: Left/Right_List/Tag_Prev/New
               my ($l_t_p,$r_t_p) = split(/$delim/, $tracktags[$beg]);
               my ($l_t_n,$r_t_n) = split(/$delim/, $tracktags[$bea[0]]);
               $tracktags[$beg] = $l_t_p . $concat . $l_t_n . $delimiter . $r_t_p . $concat . $r_t_n . $delim_t_close unless($book == 1 or $cdcue == 2);
               $tracktags[$beg] =~ s/\s+/ /g;
            }
            $bea[0]++;
         }
      }
   }
   # Display info which tracks are going to be ripped. Because of option
   # merge we have to work hard to make it look nice:
   @tracksel = @seltrack; # Use a copy of @seltrack to work with.
   my @printracks;        # A new array in nice print format.
   my $trackcn;
   my $prevtcn = -1;
   # Add the hidden track to @tracksel if a nerd wants it to merge, i.e.
   # operator entered it in the merge argument.
   unshift(@tracksel, 0) if($pmerge && $pmerge =~ /^0/ && $hiddenflag == 1);
   foreach $trackcn (@tracksel) {
      next if($trackcn <= $prevtcn);
      my $trackno;
      # Check if next track number is in the skip array of tracks being
      # merged. If so, add a hyphen.
      my $increment = 1;
      if($skip[0] && ($trackcn + $increment) =~ /^$skip[0]$/) {
         $trackno = $trackcn . "-";
         shift(@skip);
         $trackcn++;
         # Is the next track number the last of the interval of merged
         # tracks? If not, continue to increase the track number.
         while($skip[0] && ($trackcn + $increment) =~ /^$skip[0]$/) {
           $trackcn++;
           shift(@skip);
         }
         $trackno = $trackno . $trackcn;
         $prevtcn = $trackcn;
      }
      else {
         $trackno = $trackcn;
      }
      push(@printracks, $trackno);
   }

   print "\n" if($verbose > 0);
   if($#seltrack == 0 && $hiddenflag == 0) {
      print "Track @printracks will be ripped.\n\n" if($verbose > 0);
   }
   elsif(!@seltrack && $hiddenflag == 1) {
      print "Track 0 will be ripped.\n\n" if($verbose > 0);
   }
   elsif($pmerge && $pmerge =~ /^0/ && $hiddenflag == 1) {
      print "Tracks @printracks will be ripped.\n\n" if($verbose > 0);
   }
   elsif($hiddenflag == 1) {
      print "Tracks 0 @printracks will be ripped.\n\n" if($verbose > 0);
   }
   else {
      print "Tracks @printracks will be ripped.\n\n" if($verbose > 0);
   }

   # Prevent failure if hald occupies drive.
   sleep 6 if($loop == 2);
   # Get the time when ripping started, and save it in the error.log.
   my $ripstart = sprintf("%02d:%02d", sub {$_[2], $_[1]}->(localtime));
   my $date = sprintf("%04d-%02d-%02d",
      sub {$_[5]+1900, $_[4]+1, $_[3]}->(localtime));

   # If accurate rip is wanted, no way to parallelize the process, but
   # checks on each track still must be done afterwards.
   # It could be done though, just alter the main part in the loop
   # to look for wav files done and somehow block / mv them to a secure
   # place in case Morituri wants to delete them because of failed
   # checksums... but then: what should the clean-up rule be?
   # As of version 0.2.2 rip will cancel process in case wav directory
   # is present. So creation of wav directory must be prevented and done
   # by rip (Morituri) i.e. rip needs to be started before writing
   # headers of any descripitve files. In earlier versions of ripit
   # this snippet was positioned right before the foreach(@tracksel)
   # loop.
   my $mori_dirs = "";
   if($ripper == 3 && $rip == 1) {
      print "\nRipping to \"$wavdir\" using rip:\n" if($verbose > 3);
       $ripcom = "rip cd -d $cddev rip --profile=wav -U \\
       --track-template=\"%t\_Morituri-Rip\" \\
       --disc-template=\"\" --offset=$offset \\
       -O \"$wavdir\"";
       $ripcom .= " $ripopt" if($ripopt ne "");
       $ripcom = "nice -n $nicerip " . $ripcom if($nicerip != 0);
       unless(log_system("$ripcom")) {
          die "Morituri (rip) failed.";
       }
      print "Ripping complete.\n" if($verbose > 3);
      # Is this a rip (Morituri) bug? All meta files have no name and
      # become hidden. Probably due to the empty disc template.
      foreach ("cue", "log", "m3u") {
         if(-f "$wavdir/.$_") {
            log_system("mv \"/$wavdir/.$_\" \\
                       \"$wavdir/Morituri.$_\"");
         }
         else {
            # If we did not die above, Morituri might have placed files
            # somewhere else...
            opendir(RIP, "$wavdir") or
               print "Can not read in $wavdir: $!\n";
            my @mori_dirs = grep {/^\s*\(/i} readdir(RIP);
            $mori_dirs = $mori_dirs[0];
            close(RIP);
            if(-f "$wavdir/$mori_dirs/.$_") {
               log_system("mv \"/$wavdir/$mori_dirs/.$_\" \\
                          \"$wavdir/Morituri.$_\"");
            }
            else {
               print "Did not detect file: $wavdir/$mori_dirs/.$_\n"
                  if($verbose > 3);
            }
         }
      }
   }

   # Write the start time to error.log only when all directories exist.
   open(ERO, ">$wavdir/error.log")
      or print "Can not write to file \"$wavdir/error.log\"!\n";
      print ERO "Ripping started: $ripstart\n";
   close(ERO);
   if($multi == 1) {
      open(SRXY, ">>$logfile")
         or print "Can not append to file \"$logfile\"!\n";
      print SRXY "\nRipping started: $ripstart";
      close(SRXY);
   }

   # Write a toc-file.
   if($cdtoc == 1) {
      my $cdtocartis = $artistag;
      oct_char($cdtocartis);
      my $cdtocalbum = $albumtag;
      oct_char($cdtocalbum);
      # Again, in case we have a multi disc release and operator wants
      # to merge discs in directory using $trackoffset, it might be
      # appropriate not to merge the cd.toc (as it is done for the play
      # list file), but to backup the existing file and write a new one.
      if(-f "$wavdir/cd.toc"
         and ($addtrackoffset == 1 or $trackoffset > 0)) {
         my $medium = 1; # TODO: use the medium counter from MB part.
         my $fmedium = sprintf("%02d", $medium);
         while(-f "$wavdir/cd_$fmedium.toc") {
            $medium++;
            last if($medium > 20); # Hard coded exit condition...
            $fmedium = sprintf("%02d", $medium);
         }
         print "Existing cd.toc will be renamed to cd_$fmedium.toc.\n"
            if($verbose > 3);
         rename("$wavdir/cd.toc", "$wavdir/cd_$fmedium.toc");
      }
      open(CDTOC, ">$wavdir/cd.toc")
         or print "Can not write to file \"$wavdir/cd.toc\"!\n";
      print CDTOC "CD_DA\n//Ripit $version cd.toc file generated ",
                  "$date at $ripstart.",
                  "\n//Use command >cdrdao scanbus< to detect device.",
                  "\n//Assume the device found is:  1,0,0 : _NEC  ",
                  " then use e. g. command",
                  "\n//>cdrdao write --device 1,0,0 ",
                  "--speed 4 cd.toc< to burn the CD.",
                  "\n//Note: Not all CD (DVD) burners are able to burn",
                  " CD-text!\n//Test your device!";
      print CDTOC "\n//CDDBID=$cddbid";
      print CDTOC "\n//DISCID=$discid" if($discid ne ""); # New 4.0
      print CDTOC "\n\n//CD Text:\nCD_TEXT{LANGUAGE_MAP {0 : EN}\n\t";
      print CDTOC "LANGUAGE 0 {\n\t\tTITLE \"$cdtocalbum\"\n\t\t";
      print CDTOC "PERFORMER \"$cdtocartis\"\n";
#      print CDTOC "\t\tGENRE \"$genreno\"\n" if($genreno);
      print CDTOC "\t\tDISC_ID \"$cddbid\"\n\t}\n}\n";
      close(CDTOC);
   }

   # Start to rip the hidden track if there's one: First check if
   # cdparanoia is available.
   if($ripper != 1) {
      unless(log_system("cdparanoia -V")) {
         print "Cdparanoia not installed? Can't rip the hidden track ";
         print "without cdparanoia!\n"
            if($hiddenflag == 1);
         $hiddenflag = 0;
      }
   }

   # Get delimiter for VA style.
   # No messages to be printed.
   ($delim, $dummy) = check_va(0) if($vatag > 0);
   $delim = quotemeta($delim) if(defined $delim);

   # Check if the hidden track has been done in a previous session.
   my $checknextflag = 0;
   if($resumerip) {
      $riptrackname = "Hidden Track";
      $riptrackname = change_case($riptrackname, "t");
      $riptrackname =~ s/ /_/g if($underscore == 1);
      $riptrackname = get_trackname(0, $riptrackname, 0, $artist, "Hidden Track");
      if(-r "$wavdir/$riptrackname.rip") {
         unlink("$wavdir/$riptrackname.rip");
         print "Found $riptrackname.rip.\n" if($verbose >= 1);
      }
      elsif(-r "$wavdir/$riptrackname.wav") {
         $checknextflag = 1;
         print "Found $riptrackname.wav.\n" if($verbose >= 1);
         md5_sum("$wavdir", "$riptrackname.wav", 0)
            if($md5sum == 1 && $wav == 1);
      }
      else{
         for(my $c=0; $c<=$#coder; $c++) {
            if(-r "$sepdir[$c]/$riptrackname.$suffix[$c]") {
               $checknextflag = 1;
               print "Found file $riptrackname.$suffix[$c].\n";
            }
         }
      }
      if($checknextflag == 1) {
         $riptrackname = "Hidden Track";
         unshift(@tracktags, $riptrackname);
         unshift(@seltrack, 0);
         unshift(@tracklist, $riptrackname);
      }
   }

   # Define some counters:
   # Because cdtoc is written in different subroutines, define a counter
   # for each track written into the toc file. This way, ghost songs are
   # sorted in the toc file, while they aren't in the @seltrack array.
   my $cdtocn = 0 + $trackoffset;

   # Write header of cue-file.
   if($cdcue > 0) {
      # Again, in case we have a multi disc release and operator wants
      # to merge discs in directory using $trackoffset, it might be
      # appropriate not to merge the cd.cue (as it is done for the play
      # list file), but to backup the existing file and write a new one.
      if(-f "$wavdir/cd.cue"
         and ($addtrackoffset == 1 or $trackoffset > 0)) {
         my $medium = 1; # TODO: use the medium counter from MB part.
         my $fmedium = sprintf("%02d", $medium);
         while(-f "$wavdir/cd_$fmedium.cue") {
            $medium++;
            last if($medium > 20); # Hard-coded exit condition...
            $fmedium = sprintf("%02d", $medium);
         }
         print "Existing cd.cue will be renamed to cd_$fmedium.cue.\n"
            if($verbose > 3);
         rename("$wavdir/cd.cue", "$wavdir/cd_$fmedium.cue");
      }
      open(CDCUE, ">$wavdir/cd.cue")
         or print "Can not write to file \"$wavdir/cd.cue\"!\n";
      print CDCUE "TITLE \"$albumtag\"\nPERFORMER \"$artistag\"\n",
                  "FILE \"$wavdir/$album.wav\" WAVE\n";
      close(CDCUE);
   }
   # Process a possible hidden (first) track.
   if($hiddenflag == 1 && $checknextflag == 0) {
      $riptrackname = "Hidden Track";
      unshift @tracktags, $riptrackname;
      my $cdtocname = $riptrackname;
      $riptrackname = change_case($riptrackname, "t");
      $riptrackname =~ s/ /_/g if($underscore == 1);
      unshift @seltrack, 0;
      unshift @tracklist, $riptrackname;
      $riptrackname = get_trackname(0, $tracklist[0], 0, $artist, "Hidden Track");
      # If a cuefile shall be created, use album for the track name.
      $riptrackname = $album if($book == 1 or $cdcue == 2);
      my $start_point = "[00:00]";
      # What if the operator wants to merge a hidden track with the 1st
      # and so on tracks? Calculate the number of the last track to be
      # merged with the hidden track.
      my $endtrackno = 0;
      if($pmerge) {
         my @bea = split(/-|\+/, $merge[0]);
         # Hm, always confused. Should we use defined here to enter the
         # condition in case $bea[0] is defined, but zero?
         #if($bea[0] && $bea[0] == 0) {
         if(defined $bea[0] && $bea[0] == 0) {
            $endtrackno = $bea[1];
            $endtrackno =~ s/^0.//;
            $endtrackno++ unless($endtrackno == $seltrack[$#seltrack]);
            $start_point .= "-$endtrackno";
         }
      }
      # Assemble the command for cdparanoia to rip the hidden track.
      my $saveripopt = $ripopt;
      $ripopt .= " -Z" if($parano == 0);
      $ripopt .= " -q" if($verbose <= 1 && $ripopt !~ /\s-q/);
      $ripopt .= " -O $offset" if($offset < 0 || $offset > 0);
      $ripcom = "cdparanoia $ripopt -d $cddev $start_point \\
                \"$wavdir/$riptrackname.rip\"";
      printf "\n%02d:%02d:%02d: ", sub {$_[2], $_[1], $_[0]}->(localtime)
         if($verbose >= 1 && $rip == 1);
      if($ripper == 3) {
         print "Checking ripfile \"$riptrackname\"...\n"
            if($verbose >= 1 && $rip == 1);
      }
      else {
         print "Ripping \"$riptrackname\"...\n"
            if($verbose >= 1 && $rip == 1);
      }

      unless(log_system("$ripcom")) {
         if($parano == 2) {
            $ripopt .= " -Z" if($parano == 2);
            $ripopt .= " -O $offset" if($offset < 0 || $offset > 0);
            $ripcom = "cdparanoia $ripopt -d $cddev $start_point \\
                      \"$wavdir/$riptrackname.rip\"";
            print "\n\nTrying again without paranoia.\n"
               if($verbose > 1);
            unless(log_system("$ripcom")) {
               # If no success, shift the hidden track stuff out of
               # arrays.
               $hiddenflag = 0;
               shift(@secondlist);
               shift(@seltrack);
               shift(@tracklist);
               shift(@tracktags);
            }
         }
         else {
            # If no success, shift the hidden track stuff out of arrays.
            $hiddenflag = 0;
            shift(@secondlist);
            shift(@seltrack);
            shift(@tracklist);
            shift(@tracktags);
         }
      }

      # Write to the toc file.
      if($cdtoc == 1 && $hiddenflag == 1) {
         open(CDTOC ,">>$wavdir/cd.toc")
            or print "Can not append to file \"$wavdir/cd.toc\"!\n";
         print CDTOC "\n//Track 0:\nTRACK AUDIO\nTWO_CHANNEL_AUDIO\n";
         print CDTOC "CD_TEXT {LANGUAGE 0 {\n\t\tTITLE \"$cdtocname\"";
         print CDTOC "\n\t\tPERFORMER \"$artistag\"\n\t}\n}\n";
         print CDTOC "FILE \"$riptrackname.wav\" 0\n";
         close(CDTOC);
      }
      # Check the hidden track for gaps. We do not care about option
      # merge... should we? Yes, we should. If option merge has been
      # chosen for this track, splitting is not allowed, while
      # extracting one chunk of sound may be desired.
      my @times = (0);
      if($ghost == 1 && $hiddenflag == 1) {
            @times = get_chunks(0, $riptrackname);
            unless($times[0] eq "blank") {
               (my $shorten, @times) =
                  split_chunks(0, "$riptrackname", 0, @times);
               ($cdtocn, $cue_point) =
                  rename_chunks(0, "$riptrackname", "$riptrackname", 0,
                     $cue_point, $shorten, $artistag, $riptrackname,
                     @times);
               }
      }
      if($hiddenflag == 1) {
         rename("$wavdir/$riptrackname.rip",
                "$wavdir/$riptrackname.wav");
      }
      $ripopt = $saveripopt;
   }

   # If ripping did not fail (on whatever track of the whole disc),
   # write the hidden track info to the cue file.
   if($cdcue ==  2 && $hiddenflag == 1) {
      my $points = track_length($framelist_orig[1] - $framelist_orig[0], 2);
      # TODO: What if option span is used?
      open(CDCUE ,">>$wavdir/cd.cue")
         or print "Can not append to file \"$wavdir/cd.cue\"!\n";
      print CDCUE "TRACK 01 AUDIO\n",
                  "   TITLE \"Hidden Track\"\n",
                  "   PERFORMER \"$artistag\"\n",
                  "   INDEX 01 $points\n";
      close(CDCUE);
   }
   # End preparation of ripping process.
   #
   #
   # Start ripping each track. Note that we have to skip a possible
   # hidden track. To prevent re-ripping ghost songs pushed into the
   # @seltrack array, make a copy which will not be altered.
   @tracksel = @seltrack;

   # Encoder messages are printed into a file which will be read by the
   # ripper to prevent splitting ripper-messages. Lines already printed
   # will not be printed again, use counter $encline.
   my $encline = 0;
   $trackcn = 0;

   foreach(@tracksel) {
      next if($_ == 0); # Skip hidden track.
      $trackcn++;
      $riptracktag = $tracktags[$_ - 1];
      $riptracktag = $tracktags[$_] if($hiddenflag == 1);

      # Split the tracktag into its artist part and track part if
      # VA style is used.
      if(defined $delim && $va_flag > 0 && $riptracktag =~ /$delim/) {
         ($artistag, $riptracktag) = split_tags($riptracktag, $delim);
      }
      $artistag = clean_all($artist_utf8) unless(defined $artistag);
      $trackartist = clean_all($artistag);
      $trackartist = clean_name($trackartist);
      $trackartist = clean_chars($trackartist);
      $tracktitle = clean_all($riptracktag);
      $tracktitle = clean_name($tracktitle);
      $tracktitle = clean_chars($tracktitle);
      $trackartist =~ s/ /_/g if($underscore == 1);
      $tracktitle =~ s/ /_/g if($underscore == 1);

      $riptrackname = get_trackname($_, $tracklist[$_ - 1], 0, $trackartist, $tracktitle);
      $riptrackname = get_trackname($_, $tracklist[$_], 0, $trackartist, $tracktitle)
         if($hiddenflag == 1);
      $riptrackname = $album if($book == 1 or $cdcue == 2);

      my $riptrackno = $_;
      # If we use option merge, skip a previously merged track:
      my $skipflag = 0;
      if($pmerge) {
         @skip = skip_tracks(0);
         foreach my $skip (@skip) {
            $skipflag = 1 if($_ == $skip);
         }
      }
      if(($cdtoc == 1 || $cdcue > 0) && $failflag == 0) {
         $cdtocn++;
      }
      # Don't write the cue entry again in case ripper failed with
      # paranoia and retries ripping without.
      if($cdcue == 2 && $failflag == 0) {
         my $points =
            track_length($framelist_orig[$_ - 1] - $framelist_orig[0], 2);
         # In case span argument is used, update the cue file after
         # ripping. Remember, in normal case cdcue == 1 and detection
         # for ghost songs subroutine will ensure correct track lengths.
         # This should only be needed in case cdcue == 2 and option
         # span defined.
         $points = "cue-span-seconds" if($span);
         my $cuetrackno = sprintf("%02d", $cdtocn);
         open(CDCUE, ">>$wavdir/cd.cue")
            or print "Can not append to file \"$wavdir/cd.cue\"!\n";
         print CDCUE "TRACK $cuetrackno AUDIO\n",
                     "   TITLE \"$riptracktag\"\n",
                     "   PERFORMER \"$artistag\"\n",
                     "   INDEX 01 $points\n";
         close(CDCUE);
      }

      # Remember: $riptrackno is the track number passed to the encoder.
      # If we want to merge, we substitute it with the interval, with a
      # hyphen for cdparanoia and a plus sign for cdda2wav.
      my $saveriptrackno = $riptrackno;
      if($pmerge && $merge[0]) {
         my @bea = split(/-|\+/, $merge[0]);
         if($bea[0] && $riptrackno == $bea[0]) {
            $riptrackno = shift(@merge);
            $riptrackno =~ s/-/\+/ if($ripper == 2);
            $riptrackno =~ s/\+/-/ if($ripper == 1);
            # TODO: check for dagrab and sox...
         }
      }
      # LCDproc
      if($lcd == 1) {
         my $_lcdtracks = scalar(@tracksel);
         $lcdtrackno++;
         my $lcdperc;
         if($_lcdtracks eq $lcdtrackno) {
            $lcdperc = "*100";
         }
         else {
            $lcdperc = sprintf("%04.1f", $lcdtrackno/$_lcdtracks*100);
         }
         $lcdline2 =~ s/\|\d\d.\d/\|$lcdperc/;
         my $lcdtracknoF = sprintf("%02d", $lcdtrackno);
         $lcdline2 =~ s/\r\d\d/\r$lcdtracknoF/;
         substr($lcdline2,10,10) = substr($riptrackname,3,13);
         ulcd();
      }

      # There is a problem with too long file names encountered e. g.
      # with some classical CDs. Cdparanoia cuts the length of the file
      # name, cdda2wav too...  but how should RipIT know? Therefore use
      # a shorter track name if total length (including the full path)
      # > 190 characters.
      my $rip_wavdir = $wavdir;
      my $rip_wavnam = $riptrackname;
      if(length($riptrackname) + length($wavdir) > 190) {
         print "Warning: output track name is longer than 190 chars,\n",
               "Ripit will use a temporary output name for the ",
               "WAV-file.\n"
            if($verbose > 2);
         $riptrackname = get_trackname($_, $_ . "short", "short", $trackartist, $tracktitle);
         # We still have problems in case total path is too long:
         $rip_wavdir = "/tmp"
            if(length($riptrackname) + length($wavdir) > 250);
      }
      # Worse, if the directory name has periods in, cdda2wav freaks
      # out completely.
      if($ripper == 2 && $wavdir =~ /\./) {
         $rip_wavdir = "/tmp";
      }
      # Write the toc entry only if wav present, don't write it again in
      # case ripper failed with paranoia and retries ripping without.
      # In case we check for ghost songs, these might be deleted, so
      # don't write the toc file here.
      if($cdtoc == 1 && $failflag == 0 && $ghost == 0) {
         my $cdtoctitle = $riptracktag;
         oct_char($cdtoctitle);
         my $cdtocartis = $artistag;
         oct_char($cdtocartis);
         my $cdtoctrckartis = $trackartist;
         oct_char($cdtoctrckartis);
         my $points = 0;
         $points =
            track_length($framelist_orig[$_ - 1] - $framelist_orig[0], 2)
            . " " .
            track_length($framelist_orig[$_] - $framelist_orig[$_ - 1], 2)
            if($book > 0 || $cdcue > 0);
         open(CDTOC, ">>$wavdir/cd.toc")
            or print "Can not append to file \"$wavdir/cd.toc\"!\n";
         print CDTOC "\n//Track $cdtocn:\nTRACK AUDIO\n";
         print CDTOC "TWO_CHANNEL_AUDIO\nCD_TEXT {LANGUAGE 0 {\n\t\t";
         print CDTOC "TITLE \"$cdtoctitle\"\n\t\t";
         print CDTOC "PERFORMER \"$cdtocartis\"";
         print CDTOC "\n\t\tSONGWRITER \"$cdtoctrckartis\"" if($vatag > 0);
         print CDTOC "\n\t}\n}\n";
         print CDTOC "FILE \"$rip_wavnam.wav\" $points\n";
         print CDTOC "ISRC " . $isrcs[$_-1] . "\n"
            if($isrc == 1 and $isrcs[$_-1] ne "");
         close(CDTOC);
      }

      print "\nRipper skips track $_ merged into previous one.\n"
         if($verbose >=1 && $skipflag == 1);
      next if($skipflag == 1);

      # Check for tracks already done if option --resume is on.
      $checknextflag = 0;
      if($resumerip) {
         if($normalize == 0 and $cdcue == 0) {
            # Start the encoder in the background, but only once.
            # We do it already here, because:
            # i)  if all wavs are done, the encoding process at the end
            #     of this subroutine will not be started at all!
            # ii) why should we wait for the first missing wav, if
            #     other wavs are already here and encoding could start
            #     (continue) right away?
            if($startenc == 0 && $encode == 1) {
               $startenc = 1;
               open(ENCLOG, ">$wavdir/enc.log");
               close(ENCLOG);
               unless(fork) {
                  enc_cd();
               }
            }
         }

         if(-r "$wavdir/$riptrackname.rip") {
            unlink("$wavdir/$riptrackname.rip");
            print "Found $riptrackname.rip.\n" if($verbose >= 1);
         }
         elsif(-r "$wavdir/$riptrackname\_rip.wav" && $ripper == 2) {
            unlink("$wavdir/$riptrackname\_rip.wav");
            print "Found $riptrackname\_rip.wav.\n" if($verbose >= 1);
         }
         elsif(-r "$wavdir/$riptrackname.wav") {
            $checknextflag = 1;
            print "Found $riptrackname.wav.\n" if($verbose >= 1);
            if($md5sum == 1 && $wav == 1) {
               md5_sum("$wavdir", "$riptrackname.wav", 0);
            }
         }
         elsif($wav == 0) {
            for(my $c = 0; $c <= $#coder; $c++) {
               if(-r "$sepdir[$c]/$riptrackname.$suffix[$c]") {
                  $checknextflag = 1;
                  print "Found file $riptrackname.$suffix[$c].\n"
                     if($verbose >= 1);
               }
               else {
                  $checknextflag = 2;
               }
               last if($checknextflag == 2);
            }
         }
         # Cdda2wav is somehow unpleasant. It dies not quick enough with
         # ^+c. I. e. even if a track has not been ripped to the end,
         # the *.rip file will become a *.wav. So we have to check for
         # completely encoded files and assume, that for not encoded
         # files, there is no fully ripped file. OK, perhaps it would be
         # better to check for the last *.wav file and re-rip only that
         # one. But on a modern machine, the encoder won't be far from
         # catching up the ripper, so deleting all *.wavs for missing
         # encoded files won't hurt, because cdda2wav is quite fast,
         # ripping those tracks again doesn't cost a lot of time.
         if($ripper == 2 && $checknextflag == 1) {
            for(my $c = 0; $c <= $#coder; $c++) {
               if(-r "$sepdir[$c]/$riptrackname.$suffix[$c]") {
                  $checknextflag = 1;
               }
               else {
                  $checknextflag = 2;
               }
               last if($checknextflag == 2);
            }
         }
      }
      # Skip that track, i.e. restart the foreach-loop of tracks if a
      # wav file or other (mp3, ogg, flac, m4a) was found.
      next if($checknextflag == 1);
      # Don't resume anymore if we came until here.
      $resumerip = 0;

      # Now do the job of ripping:
      printf "\n%02d:%02d:%02d: ", sub {$_[2], $_[1], $_[0]}->(localtime)
         if($verbose >= 1 && $rip == 1);
      print "Ripping \"$riptrackname\"...\n"
         if($verbose >= 1 && $rip == 1);
      # Choose the cdaudio ripper to use.
      #
      # TODO: Check behaviour of all rippers on data tracks.
      # Choose to use print instead of die if ripper stops itself!
      # Dagrab fails @ data-track, so don't die and create an error.log,
      # cdparanoia fails @ data-track, so don't die and create an
      # error.log.
      # cdda2wav prints errors @ data-track, therefore die!
      if($ripper == 0 && $rip == 1) {
         if($trackcn == 1) {
            $ripopt .= " -r 3" if($parano == 0 && $ripopt !~ /\s-r\s3/);
            $ripopt .= " -v" if($verbose >= 2 && $ripopt !~ /\s-v/);
         }
         $ripcom = "(dagrab $ripopt -d $cddev \\
                    -f \"$rip_wavdir/$riptrackname.rip\" \\
                    $riptrackno 3>&1 1>&2 2>&3 \\
                    | tee -a \"$wavdir/error.log\") 3>&1 1>&2 2>&3 ";
         $ripcom =~ s/\$/\\\$/g;
         $ripcom = "nice -n $nicerip " . $ripcom if($nicerip != 0);
         unless(log_system("$ripcom")) {
            print "Dagrab detected some read errors on ",
                  "$tracklist[$_ - 1]\n\n";
            # Create error message in CD-directory for encoder: don't
            # wait.
            open(ERO,">>$wavdir/error.log")
               or print "Can not append to file ",
                        "\"$wavdir/error.log\"!\n";
            print ERO "Dagrab detected some read errors at $riptrackno";
            print ERO " on CD $artist - $album, do not worry!\n";
            close(ERO);
         }
         print "\n";
      }
      elsif($ripper == 1 && $rip == 1) {
         if($trackcn == 1) {
            $ripopt .= " -Z" if($parano == 0 && $ripopt !~ /\s-Z/);
            $ripopt .= " -q" if($verbose < 2 && $ripopt !~ /\s-q/);
            $ripopt .= " -O $offset"
               if($ripopt !~ /\s-O/ && ($offset < 0 || $offset > 0));
         }
         # Introduce the span argument into the track number, adjust the
         # track number suffix according to cdparanoia and recalculate
         # the track length (used in the playlist file).
         if($span) {
            my @bea = split(/-/, $span);
            my $offset = 0;
            my $chunk = 0;
            $offset = span_length($bea[0]) if($bea[0]);
            $chunk = span_length($bea[1]) if($bea[1]);
            $bea[0] = "0.0" unless($bea[0]);
            $bea[1] = " " unless($bea[1]);
            $bea[0] = "[" . $bea[0] . "]" if($bea[0] =~ /\d+/);
            $bea[1] = "[" . $bea[1] . "]" if($bea[1] =~ /\d+/);
            if($riptrackno =~ /-/) {
               my($i, $j) = split(/-/, $riptrackno);
               # Special case: if the chunk of sound is larger than the
               # (last) track, use the true track length instead of chunk
               # size.
               if($hiddenflag == 0 && $secondlist[$j - 1] < $chunk) {
                  $chunk = 0;
                  $bea[1] = " ";
               }
               elsif($hiddenflag == 1 && $secondlist[$j] < $chunk) {
                  $chunk = 0;
                  $bea[1] = " ";
               }
               if($chunk <= 0) {
                  $chunk = $secondlist[$j - 1] if($hiddenflag == 0);
                  $chunk = $secondlist[$j] if($hiddenflag == 1);
               }
               $secondlist[$_ - 1] = $secondlist[$_ - 1] - $secondlist[$j - 1] + $chunk - $offset if($hiddenflag == 0);
               $secondlist[$_] = $secondlist[$_] - $secondlist[$j] + $chunk - $offset if($hiddenflag == 1);
               $riptrackno = $i . $bea[0] . "-" . $j . $bea[1];
            }
            else {
               # Special case: if the chunk of sound is larger than the
               # (last) track, use the true track length instead of chunk
               # size.
               if($hiddenflag == 0 && $secondlist[$_ - 1] < $chunk) {
                  $chunk = 0;
                  $bea[1] = " ";
               }
               elsif($hiddenflag == 1 && $secondlist[$_] < $chunk) {
                  $chunk = 0;
                  $bea[1] = " ";
               }
               $riptrackno = $riptrackno . $bea[0] . "-" . $riptrackno . $bea[1];
               # Variable $chunk is zero if span reaches the end of the
               # track.
               if($chunk <= 0) {
                  $chunk = $secondlist[$_ - 1] if($hiddenflag == 0);
                  $chunk = $secondlist[$_] if($hiddenflag == 1);
               }
               $chunk -= $offset;
               $secondlist[$_ - 1] = $chunk if($hiddenflag == 0);
               $secondlist[$_] = $chunk if($hiddenflag == 1);
            }
         }
         if($multi == 0) {
            # Handle special paranoia mode for single failed tracks.
            my $save_ripopt = $ripopt;
            my $save_failflag = $failflag;
            if($parano == 2 && $failflag == 1) {
               $ripopt = $ripopt . " -Z" if($parano == 2);
               print "\n\nTrying again without paranoia.\n"
                  if($verbose > 1);
            }
            # Make sure $failflag is set to 0 if success.
            $failflag = 0;
            $ripcom = "cdparanoia -d $cddev $riptrackno $ripopt \\
               \"$rip_wavdir/$riptrackname.rip\"";
            $ripcom =~ s/\$/\\\$/g;
            $ripcom = "nice -n $nicerip " . $ripcom if($nicerip != 0);
            # Loop for $verify number of times or until identical rips
            # are detected.
            my $xcnter = 1;
            my @md5 = ();
            while($xcnter <= $verify) {
               unless(log_system("$ripcom")) {
                  print "cdparanoia failed on track ", $_,
                        " $tracklist[$_ - 1]\n\n" if($hiddenflag == 0);
                  print "cdparanoia failed on track ", $_,
                        " $tracklist[$_]\n\n" if($hiddenflag == 1);
                  # Create error message in CD-directory for encoder:
                  # don't wait.
                  if($parano == 2 && $save_failflag == 1 || $parano < 2 ) {
                     open(ERO,">>$wavdir/error.log")
                        or print "Can not append to file ",
                                 "\"$wavdir/error.log\"!\n";
                     print ERO "Track $saveriptrackno on CD $artist ";
                     print ERO "- $album failed!\n";
                     close(ERO);
                  }
                  # Leave loop as we do not want continue with
                  # paranoia mode.
                  $xcnter = $verify;
                  $failflag = $save_failflag + 1;
               }
               if($verify > 1) {
                  open(SND, "< $rip_wavdir/$riptrackname.rip") or
                  print "Can not open $rip_wavdir/$riptrackname.rip: ",
                        "$!\n";
                  binmode(SND);
                  my $md5 = Digest::MD5->new->addfile(*SND)->hexdigest;
                  close(SND);
                  print "\nThe MD5-sum for $rip_wavdir/$riptrackname",
                        ".rip is: $md5.\n" if($verbose > 3);
                  my $lastflag = 0;
                  foreach (@md5) {
                     if($md5 eq $_) {
                        print "Rip no. $xcnter resulted in identical ",
                              "rip and will be kept.\n";
                        $lastflag = 1;
                        last;
                     }
                     else {
                        print "Rip no. $xcnter gave different result, ",
                              "will rip again.\n";
                     }
                  }
                  last if($lastflag == 1);
                  rename("$rip_wavdir/$riptrackname.rip",
                         "$rip_wavdir/$riptrackname\_$xcnter.rip")
                     if($verify > 1 && $xcnter < $verify);
                  print "Rip file $rip_wavdir/$riptrackname.rip ",
                        "renamed using counter $xcnter.\n"
                     if($verify > 1 && $xcnter < $verify && $verbose > 3);
                  push(@md5, $md5);
               }
               $xcnter++;
            }
            for(my $c = 1; $c < $xcnter; $c++) {
               print "Rip file $rip_wavdir/$riptrackname\_$c.rip will ",
                     "be deleted.\n" if($verbose > 3);
               unlink("$rip_wavdir/$riptrackname\_$c.rip");
            }
            $ripopt = $save_ripopt;
         }
         elsif($multi == 1) {
            my $save_ripopt = $ripopt;
            my $save_failflag = $failflag;
            if($parano == 2 && $failflag == 1) {
               $ripopt .= " -Z" if($parano == 2);
               print "\n\nTrying again without paranoia.\n"
                  if($verbose > 1);
            }
            $ripcom = "cdparanoia -d $cddev $riptrackno $ripopt \\
               \"$rip_wavdir/$riptrackname.rip\"";
            # Log the ripping output only when using paranoia!
            $ripcom .= " 2>> \"$logfile.$saveriptrackno.txt\""
               if($parano == 2 && $failflag == 1 || $parano < 2 );
            $ripcom =~ s/\$/\\\$/g;
            $ripcom = "nice -n $nicerip " . $ripcom if($nicerip != 0);
            $failflag = 0;
            unless(log_system("$ripcom")) {
               if($parano == 2 && $save_failflag == 1 || $parano < 2 ) {
                  # Append error message to file srXY for rip2m to start
                  # checktrack.
                  open(SRXY,">>$logfile")
                     or print "Can not append to file \"$logfile\"!\n";
                  print SRXY "\ncdparanoia failed on $tracklist[$_ - 1] "
                     if($hiddenflag == 0);
                  print SRXY "\ncdparanoia failed on $tracklist[$_] "
                     if($hiddenflag == 1);
                  print SRXY "in device $logfile";
                  close(SRXY);
                  # Create error message in CD-directory for encoder:
                  # don't wait.
                  open(ERO,">>$wavdir/error.log")
                     or print "Can not append to file ",
                              "\"$wavdir/error.log\"!\n";
                  print ERO "Track $saveriptrackno on CD $artist - $album ";
                  print ERO "failed!\n";
                  close(ERO);
                  # Kill failed CD only if it is not the last track. Last
                  # track may be data/video track.
                  # I.e. print error message to file srXY.Z.txt, checktrack
                  # will grep for string
                  # "cdparanoia failed" and kill the CD immediately!
                  if($riptrackno != $tracksel[$#tracksel]) {
                     open(SRTF,">>$logfile.$saveriptrackno.txt")
                        or print "Can not append to file ",
                                 "\"$logfile.$saveriptrackno.txt\"!\n";
                     print SRTF "cdparanoia failed on $tracklist[$_ - 1]"
                        if($hiddenflag == 0);
                     print SRTF "cdparanoia failed on $tracklist[$_ - 1]"
                        if($hiddenflag == 1);
                     print SRTF "\nin device $logfile, error !";
                     close(SRTF);
                     # Create on the fly error message in log-directory.
                     my $devnam = $cddev;
                     $devnam =~ s/.*dev.//;
                     open(ERO,">>$outputdir/failed.log")
                        or print "Can not append to file ",
                                 "\"$outputdir/failed.log\"!\n";
                     print ERO "$artist;$album;$genre;$categ;$cddbid;";
                     print ERO "$devnam;$hostnam; Cdparanoia failure!\n";
                     close(ERO);
                     # Now wait to be terminated by checktrack.
                     sleep 360;
                     exit;
                  }
               }
               $failflag = $save_failflag + 1;
            }
            $ripopt = $save_ripopt;
         }
         # This is an awkward workaround introduced because of the
         # enhanced --paranoia option. Failures on data tracks are not
         # captured anymore. Force update of error.log for encoder.
         # Remember, because of option --span $riptrackno can be a
         # string. Use $saveriptrackno instead.
         if(! -f "$rip_wavdir/$riptrackname.rip") {
            if($saveriptrackno == $tracksel[$#tracksel] &&
               $riptrackname =~ /data|video/i) {
               open(ERO,">>$wavdir/error.log")
                  or print "Can not append to file ",
                           "\"$wavdir/error.log\"!\n";
               print ERO "Track $saveriptrackno on CD $artist - $album ";
               print ERO "failed!\n";
               close(ERO);
               if($multi == 1) {
                  # Append error message to file srXY for rip2m to start
                  # checktrack.
                  open(SRXY,">>$logfile")
                     or print "Can not append to file \"$logfile\"!\n";
                  print SRXY "\ncdparanoia failed on $tracklist[$_ - 1] "
                     if($hiddenflag == 0);
                  print SRXY "\ncdparanoia failed on $tracklist[$_] "
                     if($hiddenflag == 1);
                  print SRXY "in device $logfile";
                  close(SRXY);
               }
               # Misuse of variable failflag, we don't care, it's the
               # last track!
               $failflag = 3;
            }
            else {
               print "\nRip file $riptrackname.rip not found...\n"
               if($verbose > 2);
            }
         }
      }
      elsif($ripper == 2 && $rip == 1) {
         if($trackcn == 1) {
            $ripopt .= " -q" if($verbose <= 1 && $ripopt !~ /\s-q/);
#            Cdda2wav has no sample offset, do not use it here and
#            therefore exclude ripper from checking accuracy.
         }
         $ripcom = "cdda2wav -D $cddev -H $ripopt ";
         # Introduce the span argument into the track number and
         # recalculate the track length (used in the playlist file).
         # We use $duration instead of $chunk in the cdparanoia part
         # above.
         if($span) {
            my @bea = split(/-/, $span);
            my $offset = 0;
            my $duration = 0;
            $offset = span_length($bea[0]) if($bea[0]);
            $duration = span_length($bea[1]) if($bea[1]);
            if($riptrackno =~ /\+/) {
               my($i, $j) = split(/\+/, $riptrackno);
               if($hiddenflag == 0) {
                  if($secondlist[$j - 1] < $duration) {
                     $duration = 0;
                  }
                  else {
                     $duration = $secondlist[$_ - 1] =
                        $secondlist[$_ - 1] - $secondlist[$j - 1] +
                        $duration - $offset;
                  }
               }
               elsif($hiddenflag == 1) {
                  # TODO: Oops, why is the counter reduced?
                  if($secondlist[$j - 1] < $duration) {
                     $duration = 0;
                  }
                  else {
                     $duration = $secondlist[$_] = $secondlist[$_] -
                                 $secondlist[$j] + $duration - $offset;
                  }
               }
            }
            else {
               if($hiddenflag == 0 && $secondlist[$_ - 1] < $duration) {
                  $duration = 0;
               }
               elsif($hiddenflag == 1 && $secondlist[$_] < $duration) {
                  $duration = 0;
               }
               else {
                  $duration -= int($offset);
                  $secondlist[$_ - 1] = $duration if($hiddenflag == 0);
                  $secondlist[$_] = $duration if($hiddenflag == 1);
               }
            }
            $duration = 0 if($duration < 0);
            $offset *= 75;
            $ripcom .= "-o $offset ";
            $ripcom .= "-d $duration " if($duration > 0);
         }
         if($multi == 0) {
            $ripcom .= "-t $riptrackno \"$rip_wavdir/$riptrackname\"";
            $ripcom .= "_rip";
            $ripcom = "nice -n $nicerip " . $ripcom if($nicerip != 0);
            $ripcom =~ s/\$/\\\$/g;
            # Loop for $verify number of times or until identical rips
            # are detected.
            my $xcnter = 1;
            my @md5 = ();
            while($xcnter <= $verify) {
               unless(log_system("$ripcom")) {
                  print "cdda2wav failed on <$tracklist[$_ - 1]>.\n"
                        if($hiddenflag == 0);
                  print "cdda2wav failed on <$tracklist[$_]>.\n"
                        if($hiddenflag == 1);
                  open(ERO,">>$wavdir/error.log")
                     or print "Can not append to file ",
                              "\"$wavdir/error.log\"!\n";
                  print ERO "Track $saveriptrackno on CD $artist - ";
                  print ERO "$album failed!\n";
                  close(ERO);
                  # Leave loop as we do not want continue with
                  # paranoia mode.
                  $xcnter = $verify;
                  $failflag++;
               }
               if($verify > 1) {
                  open(SND, "< $rip_wavdir/$riptrackname\_rip.wav") or
                  print "Can not open $rip_wavdir/$riptrackname\_rip",
                        ".wav: $!\n";
                  binmode(SND);
                  my $md5 = Digest::MD5->new->addfile(*SND)->hexdigest;
                  close(SND);
                  print "\nThe MD5-sum for $rip_wavdir/$riptrackname",
                        "\_rip.wav is: $md5.\n" if($verbose > 3);
                  my $lastflag = 0;
                  foreach (@md5) {
                     if($md5 eq $_) {
                        print "Rip no. $xcnter resulted in identical ",
                              "rip and will be kept.\n";
                        $lastflag = 1;
                        last;
                     }
                     else {
                        print "Rip no. $xcnter gave different result, ",
                              "will rip again.\n";
                     }
                  }
                  last if($lastflag == 1);
                  rename("$rip_wavdir/$riptrackname\_rip.wav",
                         "$rip_wavdir/$riptrackname\_$xcnter.rip")
                     if($verify > 1 && $xcnter < $verify);
                  print "Rip file $rip_wavdir/$riptrackname\_rip.wav ",
                        "renamed using counter $xcnter.\n"
                     if($verify > 1 && $xcnter < $verify && $verbose > 3);
                  push(@md5, $md5);
               }
               $xcnter++;
            }
            for(my $c = 1; $c < $xcnter; $c++) {
               print "Rip file $rip_wavdir/$riptrackname\_$c.rip will ",
                     "be deleted.\n" if($verbose > 3);
               unlink("$rip_wavdir/$riptrackname\_$c.rip");
            }
         }
         elsif($multi == 1) {
            $ripcom .= "-t $riptrackno \"$rip_wavdir/$riptrackname\_rip\" \\
               2>> \"$logfile.$saveriptrackno.txt\"";
            $ripcom = "nice -n $nicerip " . $ripcom if($nicerip != 0);
            $ripcom =~ s/\$/\\\$/g;
            unless(log_system("$ripcom")) {
               # Append error message to file srXY for rip2m to start
               # checktrack.
               open(SRXY,">>$logfile")
                  or print "Can not append to file \"$logfile\"!\n";
               print SRXY "\ncdda2wav failed on $tracklist[$_ - 1] in "
                  if($hiddenflag == 0);
               print SRXY "\ncdda2wav failed on $tracklist[$_] in "
                  if($hiddenflag == 1);
               print SRXY "device $logfile";
               close(SRXY);
               # Create error message in CD-directory for encoder:
               # don't wait.
               open(ERO,">>$wavdir/error.log")
                  or print "Can not append to file ",
                           "\"$wavdir/error.log\"!\n";
               print ERO "Track $saveriptrackno on CD $artist - $album ";
               print ERO "failed!\n";
               close(ERO);
               # Kill failed CD only if it is not the last track.
               # Last track may be data/video track.
               # I.e. print error message to file srXY.Z.txt, checktrack
               # will grep for string
               # "cdparanoia failed" and kill the CD immediately!
               if($riptrackno != $tracksel[$#tracksel]) {
                  open(SRTF,">>$logfile.$saveriptrackno.txt")
                     or print "Can not append to file ",
                              "\"$logfile.$saveriptrackno.txt\"!\n";
                  print SRTF "cdda2wav failed on $tracklist[$_ - 1]\n"
                     if($hiddenflag == 0);
                  print SRTF "cdda2wav failed on $tracklist[$_]\n"
                     if($hiddenflag == 1);
                  print SRTF "in device $logfile, error !";
                  close(SRTF);
                  # Create on the fly error message in log-directory.
                  my $devnam = $cddev;
                  $devnam =~ s/.*dev.//;
                  open(ERO,">>$outputdir/failed.log")
                     or print "Can not append to file ",
                              "\"$outputdir/failed.log\"!\n";
                  print ERO "$artist;$album;$genre;$categ;$cddbid;";
                  print ERO "$devnam;$hostnam; Cdda2wav failure!\n";
                  close(ERO);
                  # Now wait to be terminated by checktrack.
                  sleep 360;
                  exit;
               }
            }
         }
         print "\n" if($verbose > 1);
      }
      elsif($ripper == 3 && $rip == 1) {
         # Start renaming the files to the ripper format to be treated.
         my $riptracknoF = sprintf("%02d", $saveriptrackno);
         # Test presence of file in case ripper failed on a data track.
         if(-f "$wavdir/$riptracknoF\_Morituri-Rip.wav") {
            log_system(
               "cp \"$wavdir/$riptracknoF\_Morituri-Rip.wav\" \\
                   \"$wavdir/$riptrackname.rip\"")
               or print "Can not copy $riptracknoF\_Morituri-Rip.wav ",
                  "to \"$wavdir/$riptrackname.rip\": $!\n";
         }
         elsif(-f "$wavdir/$mori_dirs/$riptracknoF\_Morituri-Rip.wav") {
            log_system(
               "mv \"$wavdir/$mori_dirs/$riptracknoF\_Morituri-Rip.wav\" \\
                   \"$wavdir/$riptracknoF\_Morituri-Rip.wav\"")
               or print "Can not move $riptracknoF\_Morituri-Rip.wav ",
                  "to \"$wavdir/$riptrackname.rip\": $!\n";
            log_system(
               "cp \"$wavdir/$riptracknoF\_Morituri-Rip.wav\" \\
                   \"$wavdir/$riptrackname.rip\"")
               or print "Can not copy $riptracknoF\_Morituri-Rip.wav ",
                  "to \"$wavdir/$riptrackname.rip\": $!\n";
         }
         else {
            open(ERO,">>$wavdir/error.log")
               or print "Can not append to file ",
                        "\"$wavdir/error.log\"!\n";
            print ERO "Track $saveriptrackno on CD $artist ";
            print ERO "- $album failed!\n";
            close(ERO);
            # Prevent creating inf file.
            # Misuse of variable failflag, we don't care as with ripper
            # rip (Morituri) we do not verify the same track several
            # times and do not want to spoil option inf in case loop
            # is used.
            $failflag = 3 if($inf == 1);
         }
      }
      elsif($ripper == 4 && $rip == 1) {
         my $cdd_dev = $cddev;
         $cdd_dev =~ s/^\/dev\/r//;
         $cdd_dev =~ s/c$//;
         $ripcom = "cdd -t $riptrackno -q -f $cdd_dev - 2> /dev/null \\
                   | sox -t cdr -x - \"$rip_wavdir/$riptrackname.wav\"";
         $ripcom = "nice -n $nicerip " . $ripcom if($nicerip != 0);
         unless(log_system("$ripcom")) {
            die "cdd failed on $tracklist[$_ - 1]";
         }
      }
      elsif($rip == 1) {
         print "No CD Ripper defined.\n";
      }

      redo if($ripper == 1 && $failflag == 1 && $parano == 2);

      # If we had problems in case total path is too long (note: the
      # riptrackname is still the short one):
      if(length($riptrackname) + length($wavdir) > 250) {
         log_system("cd \"$wavdir\" && mv \"/tmp/$riptrackname.rip\" \"$riptrackname.rip\"");
      }
      if($ripper == 2 && $wavdir =~ /\./) {
         if($riptrackname =~ /\./) {
            # See below for comments on this.
            my $cddatrackname = $riptrackname . "end";
            my @riptrackname = split(/\./, $cddatrackname);
            delete($riptrackname[$#riptrackname]);
            $cddatrackname = join('.', @riptrackname);
            log_system("cd \"$wavdir\" && mv \"/tmp/$cddatrackname.wav\" \"$cddatrackname.wav\"");
         }
         else {
            log_system("cd \"$wavdir\" && mv \"/tmp/$riptrackname\_rip.wav\" \"$riptrackname\_rip.wav\"");
         }
      }

      # Cdda2wav output is not easy to handle. Everything beyond a last
      # period . has been erased. Example: riptrackname is something
      # like "never ending...", then we assign cdda2wav in the above
      # section to rip a file called: "never ending..._rip", but
      # cdda2wav misbehaves and the file is called "never ending...".
      # Therefore rename the ripped file to the standard name
      # riptrackname.rip first (if cdda2wav was used).
      if($ripper == 2) {
         if($riptrackname =~ /\./) {
            # But split is too clever! If a track name ends with "bla..."
            # all points get lost, so we've to add a word at the end!
            my $cddatrackname = $riptrackname . "end";
            my @riptrackname = split(/\./, $cddatrackname);
            delete($riptrackname[$#riptrackname]);
            $cddatrackname = join('.', @riptrackname);
            rename("$wavdir/$cddatrackname.wav",
                   "$wavdir/$riptrackname.rip");
         }
         else {
            rename("$wavdir/$riptrackname\_rip.wav",
                   "$wavdir/$riptrackname.rip");
         }
      }
      # Before checking for gaps and silence in wavs make sure to save
      # an original copy of the rip rile in case accuracy check should
      # be done once all tracks are ripped.
      # Note that we're not going to check accuracy if option merge has
      # been used, so we can assume that $riptrackno is a single number,
      # nevertheless we use $saveriptrackno.
      if($accuracy == 1 and $ripper != 3) {
         my $riptracknoF = sprintf("%02d", $saveriptrackno);
         # Test presence of file in case ripper failed on a data track.
         if(-f "$wavdir/$riptrackname.rip") {
            log_system(
               "cp \"$wavdir/$riptrackname.rip\" \\
                   \"$wavdir/$riptracknoF\_Morituri-Rip.wav\"")
               or print "Can not copy $riptrackname to ",
                  "\"$wavdir/$riptracknoF\_Morituri-Rip.rip\": $!\n";
         }
      }
      # Check for gaps and silence in tracks.
      my @times = (0);
      my $save_cdtocn = $cdtocn;
      if(-r "$wavdir/$riptrackname.rip") {
         # Remember: $saveriptrackno is the single track number, whereas
         # $riptrackno may hold an interval if option merge is used.
         if($ghost == 1 && $failflag == 0) {
            @times = get_chunks($saveriptrackno, $riptrackname);
            unless($times[0] eq "blank") {
               (my $shorten, @times) =
                  split_chunks($saveriptrackno, "$riptrackname",
                               $cdtocn, @times);
               ($cdtocn, $cue_point) =
                  rename_chunks($saveriptrackno, "$riptrackname",
                                "$rip_wavnam",
                                $cdtocn, $cue_point, $shorten,
                                $artistag, $riptracktag, @times);
               }
         }
      }
      # A blank track has been deleted.
      $cdtocn-- if(($cdtoc == 1 || $cdcue > 0) && $times[0] eq "blank");
      next if($times[0] eq "blank");
      #
      # Final stuff.
      # Rename rip file to a wav for encoder so that it will be picked
      # up by the encoder background process.
      # If the track has been splitted into chunks, check if the file
      # name holds information about the ghost song. If so, don't use it
      # in the file name! Change in 4.0
      if(defined $times[1] && $times[1] =~ /\d\s\d/) {
         if($riptracktag =~ /\// and (
            $vatag == 0 or ($vatag == 1 and $delim and $delim !~ /\//))) {
            my ($wavname, $dummy) = split(/\//, $riptracktag);
            $wavname =~ s/^\s+|\s+$//;
            # The new riptracktag is needed for inf files.
            $riptracktag = $wavname;
            $wavname = clean_all($wavname);
            $wavname = clean_name($wavname);
            $wavname = clean_chars($wavname) if($chars);
            $wavname = change_case($wavname, "t");
            $wavname =~ s/ /_/g if($underscore == 1);
            $wavname = get_trackname($saveriptrackno, $wavname, 0 , $trackartist, $wavname);
            rename("$wavdir/$riptrackname.rip", "$wavdir/$wavname.wav");
            $riptrackname = $wavname;
         }
         else {
            log_info("perl rename \"$wavdir/$riptrackname.rip\", \"$wavdir/$riptrackname.wav\"");
            rename("$wavdir/$riptrackname.rip", "$wavdir/$riptrackname.wav");
         }
      }
      else {
         log_info("perl rename \"$wavdir/$riptrackname.rip\", \"$wavdir/$riptrackname.wav\"");
         rename("$wavdir/$riptrackname.rip", "$wavdir/$riptrackname.wav");
      }

      # Update cue file if span is used with the true track length.
      if($cdcue > 0 && $span) {
         my $duration = 0;
         $duration = $secondlist[$_ - 1] if($hiddenflag == 0);
         $duration = $secondlist[$_] if($hiddenflag == 1);
         $duration = $duration * 75 + $framelist_orig[$_];
         my $points = track_length($duration, 2);
         open(CDCUE, "<$wavdir/cd.cue")
         or print "Can not read file cd.cue!\n";
         my @cuelines = <CDCUE>;
         close(CDCUE);
         open(CDCUE, ">$wavdir/cd.cue")
         or print "Can not write to file \"$wavdir/cd.cue\"!\n";
         foreach (@cuelines) {
            s/INDEX 01 cue-span-seconds/INDEX 01 $points/;
            print CDCUE $_;
         }
         close(CDCUE);
      }
      # Delete the "single-track" wav if cdcue is used. The track is
      # already merged, no need to keep it.
      log_info("perl unlink $wavdir/$riptrackname.wav")
         if($sshflag == 0 && $cdcue > 0);
      unlink("$wavdir/$riptrackname.wav")
         if($sshflag == 0 && $cdcue > 0);
      md5_sum("$wavdir", "$riptrackname.wav", 0)
         if($md5sum == 1 && $normalize == 0 &&
            $wav == 1 && $failflag == 0);
      # Writing inf files for cdburning.
      # We use the $save_cdtocn counter as track counter instead of the
      # $riptrackno because $riptrackno might hold a span argument and
      # does not reflect the exact number of tracks created.
      # Use failflag == 3 to prevent writing inf file for failed data
      # track.
      # Use $artist instead of $trackartist for get_trackname used on
      # ghost songs (only).
      if($inf >= 1 && $failflag < 3) {
         # If the file name was too long for ripper, $riptrackname holds
         # the short name, use the original copy instead.
         $trackstart = write_inf($wavdir, $riptrackname, $artistag,
            $albumtag, $riptracktag, $save_cdtocn, $cdtocn, $trackstart,
            $artist, $tracktitle, $rip_wavnam);
      }
      chmod oct($fpermission), "$wavdir/$riptrackname.wav"
         if($fpermission);
      unlink("$logfile.$riptrackno.txt") if($multi == 1);
      $failflag = 0;

      if($normalize == 0 and $cdcue == 0) {
         # Start the encoder in the background, but only once.
         if($startenc == 0 && $encode == 1) {
            my $encstart = sprintf("%02d:%02d",
               sub {$_[2], $_[1]}->(localtime));
            chomp $encstart;
            if($multi == 1) {
               open(SRXY,">>$logfile")
                  or print "Can not append to file \"$logfile\"!\n";
               print SRXY "\nEncoding started: $encstart";
               close(SRXY);
            }
            $startenc = 1;
            open(ENCLOG,">$wavdir/enc.log");
            close(ENCLOG);
            unless(fork) {
               enc_cd();
            }
         }
      }

      # Print encoder messages saved in enc.log not to spoil the
      # ripper output. Maybe it would be better to test existence of the
      # file instead of testing all these conditions.
      if($encode == 1 && $normalize == 0 && $cdcue == 0) {
         $encline = enc_report($encline, $trackcn);
      }
   }

   # Check for accuracy, let encoder fill enc.log not to spoil
   # output, operator needs to know if Morituri starts re-ripping.
   # Question: should the offset be added via option $ripopt, but
   # what if other arguments are passed for ripper of first
   # instance?
   if($accuracy == 1 && $ripper != 3) {
      print "Checking accuracy of wavs in \"$wavdir\" using rip:\n"
         if($verbose > 3);
      $ripcom = "rip cd -d $cddev rip --profile=wav -U \\
      --track-template=\"%t\_Morituri-Rip\" \\
      --disc-template=\"\" -O \"$wavdir\"";
      $ripcom .= " -o $offset" if($offset < 0 || $offset > 0);
# TODO      $ripcom .= " $ripopt" if($ripopt ne "");
      $ripcom = "nice -n $nicerip " . $ripcom if($nicerip != 0);

      unless(log_system("$ripcom")) {
         print "Morituri (rip) failed checking accuracy of wavs.";
      }
      print "\nChecking accuracy finished.\n\n" if($verbose > 3);
      if($encode == 1 && $normalize == 0 && $cdcue == 0) {
         $encline = enc_report($encline, $trackcn);
      }
   }

   # If morituri had to rip into an existing dir, delete the dummy
   # direcotry in case it is empty.
   if($ripper == 3 && $rip == 1 && -d "$wavdir/$mori_dirs") {
      # I don't like the -p option.
      log_system("rmdir -p \"$wavdir/$mori_dirs\" 2> /dev/null");
   }

   unlink("$wavdir/enc.log") if(-r "$wavdir/enc.log");

   # Hack to tell the child process that we are waiting for it to
   # finish.
   my $ripend = sprintf("%02d:%02d", sub {$_[2], $_[1]}->(localtime));
   open(ERR, ">>$wavdir/error.log")
      or print "Can not append to file error.log!\n";
   print ERR "The audio CD ripper reports: all done!\n";
   print ERR "Ripping ended: $ripend\n";
   close(ERR);
   if($multi == 1) {
      open(SRXY,">>$logfile")
         or print "Can not append to file \"$logfile\"!\n";
      print SRXY "\nRipping complete: $ripend";
      close(SRXY);
   }
}
########################################################################
#
# Normalize the wav.
# Using normalize will disable parallel ripping & encoding.
#
sub norm_cd {

   print "Normalizing the wav-files...\n" if($verbose >= 1);
   my($escdir, $norm, $normtrackname);
   $escdir = $wavdir;
   $escdir = esc_char($escdir, 0);

   my $album = clean_all($album_utf8);
   $album = clean_name($album);
   $album = clean_chars($album) if($chars);
   $album =~ s/ /_/g if($underscore == 1);
   $album = esc_char($album, 0);
   # New parameters for tracktemplate used for file names only, i.e.
   # less verbose than the corresponding tags $artistag and tracktag.
   my $trackartist;
   my $tracktitle;

   my ($delim, $dummy) = check_va(0) if($vatag > 0);
   $delim = quotemeta($delim) if(defined $delim);

   # Generate file list to be processed:
   if($book == 1 or $cdcue > 0) {
      $normtrackname = "$escdir/$album.wav";
   }
   else {
      foreach (@seltrack) {
         my $riptracktag = $tracktags[$_ - 1];
         $riptracktag = $tracktags[$_] if($hiddenflag == 1);

         # Split the tracktag into its artist part and track part if
         # VA style is used, no messages to be printed.
         if($va_flag > 0 && $riptracktag =~ /$delim/) {
            ($trackartist, $tracktitle) = split_tags($riptracktag, $delim);
         }
         # Actually, we do not need the "full" tags, only names for files.
         $trackartist = clean_all($trackartist);
         $trackartist = clean_name($trackartist);
         $trackartist = clean_chars($trackartist);
         $tracktitle = clean_all($tracktitle);
         $tracktitle = clean_name($tracktitle);
         $tracktitle = clean_chars($tracktitle);
         $trackartist =~ s/ /_/g if($underscore == 1);
         $tracktitle =~ s/ /_/g if($underscore == 1);

         my $riptrackname = get_trackname($_, $tracklist[$_ - 1], 0, $trackartist, $tracktitle);
         $riptrackname = get_trackname($_, $tracklist[$_], 0, $trackartist, $tracktitle)
            if($hiddenflag == 1);

         # If the file name was too long for ripper, look for special
         # name.
         my $wavname = $riptrackname;
         if(length($riptrackname) + length($wavdir) > 190) {
            $wavname = get_trackname($_, $_ . "short", "short", $trackartist, $tracktitle);
         }
         # Normalize is picky about certain characters - get them
         # escaped!
         $wavname = esc_char($wavname, 0);
         $normtrackname .= "$escdir/$wavname.wav" . " \\\n          ";
      }
   }
   $normtrackname =~ s/\s*$//;
   $normtrackname =~ s/\$/\\\$/g;

   # Add verbosity:
   $normopt .= "q" if($verbose == 0);
   $normopt .= "v" if($verbose >= 2 && $normopt !~ /q/);
   $normopt .= "vv" if($verbose >= 4 && $normopt !~ /q/);

   $norm = "$normcmd $normopt -- $normtrackname";

   if(log_system("$norm")) {
      log_info("\nNormalizing complete.\n");
      print "\nNormalizing complete.\n" if($verbose >= 1);
   }
   else {
      print "\nWarning: normalizing failed.\n";
   }
}
########################################################################
#
# Encode the wav.
# This runs as a separate process from the main program which
# allows it to continuously encode as the ripping is being done.
# The encoder will also wait for the ripped wav in-case the encoder
# is faster than the CDROM. In fact it will be waited 3 times the length
# of the track to be encoded.
#
sub enc_cd {
   my ($enc, $riptrackno, $riptrackname, $riptracktag, $suffix, $tagtrackno);
   my ($albumlametag, $albumartistlametag, $artislametag, $commentlametag, $tracklametag);
   my ($ripcomplete, $trackcn, $totalencs) = (0, 0, 0);
   my $lastskip = $tracksel[0];
   my $resumenc = $resume;
   my $encodername = "";
   my @md5tracks = ();  # List of tracks to be re-taged (coverart etc.).

   # Cleaning.
   my $albumtag = clean_all($album_utf8);
   my $artistag = clean_all($artist_utf8);
   my $album = $albumtag;
   my $artist = $artistag;
   my $albumartistag = $artistag;
   $album = clean_name($album);
   $artist = clean_name($artist);
   $album = clean_chars($album) if($chars);
   $artist = clean_chars($artist) if($chars);
   $album =~ s/ /_/g if($underscore == 1);
   $artist =~ s/ /_/g if($underscore == 1);

   # New parameters for tracktemplate used for file names only, i.e.
   # less verbose than the corresponding tags $artistag and tracktag.
   my $trackartist;
   my $tracktitle;

   # Create special variables for Lame-tags because of UTF8 problem.
   if($utftag == 0) {
      $albumartistlametag = back_encoding($albumartistag);
      $albumlametag = back_encoding($albumtag);
      $commentlametag = back_encoding($commentag);
   }
   else{
      $albumlametag = $albumtag;
      $commentlametag = $commentag;
   }
   # Strange timeout to prevent warnings on ghost.logs when using rip
   # (Morituri) But this might not solve the weird behaviour.
   sleep 6 if($ghost == 1 && $ripper == 3);

   # Write header of playlist file. Prevent overwriting of playlist file
   # if operator re-encodes into same directory. Furthermore we do not
   # have any clue about what effects have been applied to the existing
   # sound files. Probably better to copy existing playlist files in
   # case of re-encoding. Wrong: In case tags have been updated the
   # the playlist should be rewritten and existing playlist should not
   # be overwritten...
   my $playfile;
   if($playlist >= 1 or $cue > 0) {
      $playfile = "$artist" . " - " . "$album" . ".m3u";
      $playfile =~ s/\.m3u$/.rec/ if($rip == 0);
      $playfile =~ s/ /_/g if($underscore == 1);
      if($limit_flag == 255) {
         $playfile = substr($playfile, 0, 250);
      }
      # Do not overwrite existing playlist files from re-encoding.
      # Rename existing playlist file.
      if(-f "$wavdir/$playfile" and
            ($rip == 0 or $addtrackoffset == 1 or $trackoffset > 0)) {
         my $nplayfile = $playfile;
         $nplayfile =~ s/\.rec$/_rec.bkp/;
         # Warn if the backup file exists.
         if(-r "$wavdir/$nplayfile") {
            print "Existing playlist backup file $nplayfile will be ",
                  "orverwritten, too many checks failed.\n"
                  if($verbose >= 3);
         }
         rename("$wavdir/$playfile", "$wavdir/$nplayfile");
         print "Existing $playfile renamed to $nplayfile.\n"
            if($verbose >= 3);
      }
      my $time = sprintf("%02d:%02d:%02d",
                         sub {$_[2], $_[1], $_[0]}->(localtime));
      my $date = sprintf("%04d-%02d-%02d",
                         sub {$_[5]+1900, $_[4]+1, $_[3]}->(localtime));
      open(PLST, ">$wavdir/$playfile") or
         print "Can't open $wavdir/$playfile! $!\n";
         print PLST "#EXTM3U\n";
         print PLST "#CREATION=$date $time Ripit verion $version\n";
         print PLST "#CDDBID=$cddbid\n" if($cddbid ne "");
         print PLST "#DISCID=$discid\n"
            if(defined $discid && $discid ne ""); # New 4.0
         print PLST "#MBREID=", $cd{mbreid}, "\n"
            if(defined $cd{mbreid} && $cd{mbreid} ne ""); # New 4.0
   }

   # Read the cdcue file (once) to be copied to the encoder directories.
   my @cuelines = ();
   if($cdcue > 0) {
      open(CDCUE, "<$wavdir/cd.cue")
         or print "Can not read file cue sheet!\n";
      @cuelines = <CDCUE>;
      close(CDCUE);
   }

   # If using book-option define a chapter file.
   my $chapterfile;
   if($book >= 1) {
      $chapterfile = "$artist" . " - " . "$album" . ".chapters.txt";
      $chapterfile =~ s/ /_/g if($underscore == 1);
      if($limit_flag == 255) {
         $chapterfile = substr($chapterfile, 0, 235);
         $chapterfile .= ".chapters.txt";
      }
   }

   my $ghostflag = 0;
   my $ghostcn = 0;

   if($commentag =~ /^discid|cddbid$/) {
      if($commentag =~ /^discid$/) {
         $commentag = $cd{discid}
      }
      elsif($commentag =~ /^cddbid$/) {
         $commentag = $cd{id};
      }
      elsif($commentag =~ /^mbreid$/) {
         $commentag = $cd{mbreid};
      }
      $commentag = "" unless($commentag);
      $commentlametag = $commentag;
   }

   # Prevent using genre "other" if genre is not lame compliant but
   # other encoders than Lame are used:
   my $genre_tag = $genre;
   $genre_tag = $cd{genre}
      if($genre =~ /Other/ && $cd{genre} !~ /Other/ && $cd{genre} ne "");

   # Create a coverart array supposing its exactly in the same order as
   # encoder array.
   my @coverart = ();
   if($coverart) {
      @coverart = split(/,/, $coverart);
   }

   # Loop all track names for a last VA style detection needed for
   # tagging the files. Note that nothing is known about ghost songs.
   my ($delim, $dummy) = check_va(0) if($vatag > 0);
   $delim = quotemeta($delim) if(defined $delim);
   $vatag = 0 if(!defined $delim or $delim eq "");

   my $lamever = 0;
   if($lameflag == 1) {
      open(LAME, "lame --version 2>&1|");
      my @response = <LAME>;
      close(LAME);
      $lamever = $response[0] if(@response);
      $lamever =~ s/^.*\sversion\s(\d\.\d+).*/$1/;
   }

   # Start encoding each track.
   $riptrackno = $tracksel[0] - 1; # Prevent warnings
   foreach(@tracksel) {
      # A lot of hacking for ghost songs. Remember, array @tracksel is
      # the original one, without ghost songs as long as we did not get
      # to the end. Once all tracks are done, this array will be
      # updated if ghost songs were found by the ripper.
      # Now: if only one track in the middle of the album has been
      # selected, problems occur if this track has ghost songs. Why?
      # Because the updated array @tracksel will be e.g. 4 4 4 4 if the
      # track 4 has 3 ghost songs. But the track-list and tag-list
      # arrays have all track names of the whole CD, so after track
      # number 4 will come track number 5! Therefor no track
      # "04 name of track 5" will be found and the encoder fails!
      # To prevent this: Once all (selected) tracks are done, we have to
      # set the $ghostcn to the total number of tracks of the CD to
      # access names of ghost songs added to the end of the list by the
      # ripper process.

      if($ghostflag == 1 && $riptrackno >= $_) {
         $ghostflag = 2
      }
      $ghostcn = $#{$cd{track}} + 1 if($ghostflag == 0);
      # Prevent subroutine check_wav to give up because of missing lock
      # files in case ssh or threads is used.
      if($sshflag > 0 and $ghostflag > 0) {
         open(LOCK, ">$wavdir/ghost.lock");
         print LOCK "Wait for ghost songs added to array tracksel.\n";
         close(LOCK);
      }
      $riptrackno = $_;
      $tagtrackno = $_ + $trackoffset;
      $trackcn++;
      my $tracktag = "";
      if($rip == 1) {
         $tracktag = $tracktags[$_ - 1];
         $tracktag = $tracktags[$_] if($hiddenflag == 1);
         if($ghostflag >= 1) {
            $ghostcn++;
            $tracktag = $tracktags[$ghostcn - 1];
            $tracktag = $tracktags[$ghostcn] if($hiddenflag == 1);
         }
      }
      else {
         # See above for explanation. Keep the same scheme, even if
         # ridicoulus.
         $tracktag = $tracktags[$trackcn - 1];
         # Hiddenflag is set to 1 if a track number 0 has been detected
         # in the track tag of flac file in sub get_cdid.
         $tracktag = $tracktags[$trackcn - 1] if($hiddenflag == 1);
      }

      # Split the tracktag into its artist part and track part if
      # VA style is used.
      if(defined $delim && $delim ne "" && $va_flag > 0 && $tracktag =~ /$delim/) {
         ($artistag, $tracktag) = split_tags($tracktag, $delim);
      }
      $artistag = clean_all($artist_utf8) unless(defined $artistag);
      $trackartist = clean_all($artistag);
      $trackartist = clean_name($trackartist);
      $trackartist = clean_chars($trackartist);
      $tracktitle = clean_all($tracktag);
      $tracktitle = clean_name($tracktitle);
      $tracktitle = clean_chars($tracktitle);
      $trackartist =~ s/ /_/g if($underscore == 1);
      $tracktitle =~ s/ /_/g if($underscore == 1);

      # A new problem arises if the track names of ghost (and original)
      # songs are changed (if the track name with ghost song has a slash
      # in) or operator changed wording while re-encoding.
      # In this case, the resume option and the part that waits for
      # the ripped files to appear will fail.
      # Why? Because the encoder process we're in takes the tag info to
      # deduce the track names. Stupid method from the old days.
      # To prevent failure in case ghost is used:
      # ghost.log needs to be checked. But the ghost.log might not yet
      # be present if ripper is still ripping that file (the resume
      # function in the ripper process failed for the same reason). So
      # don't care here and let the resume function fail again. An
      # additional test will be done in the waiting part below.
      # But no matter what arguments option ghost has, while reencoding
      # the @tracklist is a hole mess.
      if($rip == 1) {
         $riptrackname = get_trackname($_, $tracklist[$_ - 1], 0, $trackartist, $tracktitle);
         $riptrackname = get_trackname($_, $tracklist[$_], 0, $trackartist, $tracktitle)
         if($hiddenflag == 1);

         if($ghostflag >= 1) {
            $riptrackname = get_trackname($_, $tracklist[$ghostcn - 1], 0, $trackartist, $tracktitle);
            $riptrackname = get_trackname($_, $tracklist[$ghostcn], 0, $trackartist, $tracktitle)
            if($hiddenflag == 1);
         }
      }
      else {
         # Use $trackcn instead of $_ as index number as it might be
         # possible that in the inputdir some tracks are missing, giving
         # a tracksel e.g. like this: (1 13) but tracklist only has two
         # entries, entry number 13 would be empty...
         # But why on earth is this so complex? Why do we do a
         # look-up if we still use the old filenames? OK, filenames
         # don't bother if at least the tags are updated, but with
         # option trackoffset we're gonna totally mess it up. And how
         # do I know that for the above mentioned problem tags get
         # not totally messed up too, i.e. the 2nd track number 13
         # will get tags of track 2? Gosh, this code sucks.
         my $dectrackname = $tracklist[$trackcn - 1];
         $dectrackname = $tracklist[$trackcn - 1] if($hiddenflag == 1);
         #
         # More problems: this will disable the trackoffset info, if
         # retrieved while re-checking for DB-data...
         my $tracktitle_modif = $tracklist_modif[$trackcn - 1];
         $tracktitle_modif = $tracklist_modif[$trackcn - 1] if($hiddenflag == 1);
         $riptrackname = get_trackname($_, $tracktitle_modif, 0, $trackartist, $tracktitle);
         # Hiddenflag is set to 1 if a track number 0 has been detected
         # in the track tag of flac file in sub get_cdid.
         $riptrackname = get_trackname($_, $tracktitle_modif, 0, $trackartist, $tracktitle) if($hiddenflag == 1);
         if(-f "$wavdir/$dectrackname.wav" && $dectrackname ne $riptrackname) {
            print "\nWarning\n",
                  "the detected trackname $dectrackname.wav is not",
                  "the expected trackname $riptrackname.wav\n"
                  if($verbose > 6);
            log_system("mv \"$wavdir/$dectrackname.wav\" \\
                           \"$wavdir/$riptrackname.wav\"");
         }
      }
      # Once the file is ripped and merged, it is called $album, no
      # matter if $cdcue == 1 or 2.
      $riptrackname = $album if($book == 1 or $cdcue > 0);
      # If we want to merge, skip a previously merged track:
      my $skipflag = 0;
      if($pmerge) {
         @skip = skip_tracks(0);
         foreach my $skip (@skip) {
            $skipflag = 1 if($_ == $skip);
         }
         if($skipflag == 1 && $_ == $tracksel[$#tracksel] && $ghost == 1 && $ghostflag < 2) {
            # We need to check if merged tracks have ghost songs.
            # This is rather weird, but one never knows... imagine!
            $ghostflag = 1;
            $riptrackno++;
            $skipflag = 2;
            # The $ghostcn will be increased during the following redo
            # loop.
            $ghostcn--;
         }
         elsif($skipflag == 1 && $_ == $tracksel[$#tracksel] && $ghost == 1 && $ghostflag == 2) {
            $skipflag = 3 if(-r "$wavdir/ghost.log");
            $_++;
         }
         if($book == 1) {
            # Search the index number of encoder faac.
            my $index = 0;
            for(my $c = 0; $c <= $#coder; $c++) {
               $index = $c if($coder[$c] == 3);
            }
            # Write the *.chapter.txt file.
            open(CHAP, ">>$sepdir[$index]/$chapterfile") or
               print "Can't open $sepdir[$index]/$chapterfile! $!\n";
            # Use timestamps, not the true track lengths. Where are the
            # specifications, please?
            # Note: array framelist has been hacked and holds the total
            # duration in the second entry.
            my $points = track_length($framelist_orig[$_ - 1] - $framelist_orig[0], 1);
            my $chapname = $tracktags[$_ - 1];
            # Remember: merge writes all merged track names into the
            # first track of an interval.
            $chapname =~ s/\s\+\s.*$// if($_ == 1);
            print CHAP "$points $chapname\n";
            close(CHAP);
         }
      }
      next if($skipflag == 1);
      redo if($skipflag == 2);
      $lastskip = $_;

      # LCDproc
      if($lcd == 1) {
         my $_lcdtracks = scalar(@tracksel);
         my $_lcdenctrack = $trackcn;
         my $lcdperc;
         if($_lcdtracks eq $_lcdenctrack) {
            $lcdperc = "*100";
         }
         else {
            $lcdperc = sprintf("%04.1f", $_lcdenctrack / $_lcdtracks * 100);
         }
         $lcdline3 =~ s/\|\d\d.\d/\|$lcdperc/;
         my $_lcdenctrackF = sprintf("%02d", $_lcdenctrack);
         # orig, gives warnings: $lcdline3 =~ s/\E\d\d/\E$_lcdenctrackF/;
         $lcdline3 =~ s/\d\d/$_lcdenctrackF/;
         substr($lcdline3, 10, 10) = substr($riptrackname, 3, 13);
         ulcd();
      }

      # Adjust encoding of tracktag for Lame.
      if($utftag == 0) {
         $tracklametag = back_encoding($tracktag);
         $artislametag = back_encoding($artistag);
      }
      else{
         $tracklametag = $tracktag;
         $artislametag = $artistag;
      }
      $artistag = clean_all($artist_utf8) if($artistag eq "");
      $tracktag = $album if($cdcue > 0);

      # If the file name was too long for ripper, look for special name.
      # Remember: this is a ripper problem, don't do that in case of
      # re-encoding.
      my $wavname = $riptrackname;
      if((length($riptrackname) + length($wavdir) > 190) && $rip > 0) {
         $wavname = get_trackname($_, $_ . "short", "short");
      }

      # Check for tracks already done.
      my $checknextflag = 1;
      if($resumenc) {
         for(my $c=0; $c<=$#coder; $c++) {
            if(! -r "$sepdir[$c]/$riptrackname.$suffix[$c]") {
               $checknextflag = 0;
            }
            else{
               print "Found $riptrackname.$suffix[$c]:\n"
                  if($verbose >= 1);
               print "Will calculate and write md5sum for:\n"
                  if($verbose >= 4 && $md5sum == 1);
               print "$sepdir[$c], $riptrackname.$suffix[$c]\n"
                  if($verbose >= 4 && $md5sum == 1);
            }
            last if($checknextflag == 0);
         }
         if($checknextflag == 1 and ($playlist >= 1 or $cue > 0)) {
            print PLST "#EXTINF:$secondlist[$_ - 1],$tracktag\n"
               if($hiddenflag == 0);
            print PLST "#EXTINF:$secondlist[$_],$tracktag\n"
               if($hiddenflag == 1);
            print PLST "Sepdir/$riptrackname.suffix\n"
               if($playlist == 1);
            print PLST "$riptrackname.suffix\n" if($playlist == 2);
            print PLST "Add Ghost Song $_ Here.\n" if($ghost == 1);
         }
         unlink("$wavdir/$riptrackname.wav")
            if($wav == 0 && $sshflag == 0 && $checknextflag == 1);
      }
      # Skip that track, i. e. restart the foreach-loop of tracks if a
      # compressed file (mp3, ogg, ma4, flac) was found.
      next if($resumenc && $checknextflag == 1);
      # Don't resume anymore, if we came until here.
      $resumenc = 0;

      # Keep looping until the wav file appears, i.e. wait for
      # ripper timeout. Timeout is 3 times the length of track
      # to rip/encode. Then leave that one and finish the job!
      my $slength = $secondlist[$_ - 1];
      my $mlength = (int($slength / 60) + 1) * 3;
      my $tlength = (int($slength / 10) + 6) * 3;
      print "\nWarning, got negative timeout: $tlength.\nThis should ",
         "not happen and may lead to problems.\nMaybe the track ",
         "lengths are corrupt and need to be fixed.\n"
         if($verbose > 0 and $tlength < 0);

      # We could believe not needing this for ghost songs, as they are
      # fully ripped when the (original) last track was successfully
      # ripped. But be aware, the last track might have changed name...
      my $dataflag = 0;
      my $xtime = 0;
      my $ripsize = 0;
      while(! -r "$wavdir/$wavname.wav" && $ghostflag == 0) {
         $xtime++;
         last if($xtime > $tlength);
         print "\nWaiting for \"$wavdir/$wavname.wav\" to appear.\n"
            if($verbose > 3);
         # There might be a ghost song with an other name. If ripping
         # is done, ghost.log would help, but the ghost.log file
         # might not be present yet! Change in 4.0
         if($ghost == 1) {
            next unless(defined $tracktag);
            my ($ghost_rtn, $dummy) = split(/\//, $tracktag)
               if($vatag == 0 or $vatag == 1 and $delim and $delim !~ /\//);
            if($ghost_rtn) {
               $ghost_rtn =~ s/^\s+|\s+$//;
               my $ghost_trt = $ghost_rtn;
               $ghost_rtn = clean_all($ghost_rtn);
               $ghost_rtn = clean_name($ghost_rtn);
               $ghost_rtn = clean_chars($ghost_rtn) if($chars);
               $ghost_rtn = change_case($ghost_rtn, "t");
               $ghost_rtn =~ s/ /_/g if($underscore == 1);
               $ghost_rtn = get_trackname($riptrackno, $ghost_rtn, 0, $artist, $ghost_rtn);
               # Rename the riptrackname to wavname to exit the
               # while-loop. Do it only when the wav appeared and the
               # rip file disappeared in case it's the last track and
               # the following check of ghost.log is mandatory. Else
               # we would leave this loop and possibly read an old
               # ghost.log not yet updated, because ripper is still
               # ripping.
               if(!-r "$wavdir/$wavname.rip" and
                  !-r "$wavdir/$ghost_rtn.rip" and
                  -r "$wavdir/$ghost_rtn.wav") {
                     $wavname = $riptrackname = $ghost_rtn;
                     $tracktag = $ghost_trt;
                     if($utftag == 0) {
                        $tracklametag = back_encoding($tracktag);
                        # TODO: maybe a copy has to be done here too.             -> UTF-8
                     }
                     else{
                        $tracklametag = $tracktag;
                     }
               }
           }
         }
         # Condition 1: Too long waiting for the track!
         if($xtime >= $tlength) {
            # If the rip file has been found, give a chance to
            # continue if the rip-file increases in size.
            my $old_ripsize = $ripsize;
            #
            if(-r "$wavdir/$wavname.rip") {
               $ripsize = -s "$wavdir/$wavname.rip";
            }
            if($multi != 1) {
               if($ripsize > $old_ripsize * 1.2) {
                  $tlength = $tlength * 1.5;
               }
               else {
                  print "Encoder waited $mlength minutes for file\n";
                  print "$riptrackname.wav to appear, now giving up!\n";
                  print "with $artist - $album in device $cddev\n";
                  log_info("Encoder waited $mlength minutes for file");
                  log_info("$riptrackname.wav to appear, now giving up!");
                  log_info("with $artist - $album in device $cddev");
               }
            }
            else {
               print "Encoder waited $mlength minutes for file\n";
               print "$riptrackname.wav to appear\n";
               print "with $artist - $album in device $cddev.\n";
               # If the rip file has been found, give a chance to
               # continue if the rip-file increases in size.
               if(-r "$wavdir/$wavname.rip") {
                  if($ripsize > $old_ripsize * 1.2) {
                     $tlength = $tlength * 1.5;
                  }
                  else {
                     $xtime = 0 unless($riptrackname =~ /00 Hidden Track/);
                     open(ERR, ">>$wavdir/error.log");
                     print ERR "Ripping ended: 00:00!\n";
                     close(ERR);
                  }
               }
               else {
                  $xtime = 0 unless($riptrackname =~ /00 Hidden Track/);
                  open(ERR, ">>$wavdir/error.log");
                  print ERR "Ripping ended: 00:00!\n";
                  close(ERR);
               }
            }
         }
         sleep 10;
         # Condition 2: Check the error log!
         # If at this moment the ripper did not start with
         # the riptrackname.rip, assume it was a data track!
         # If cdparanoia failed on a data track, there will
         # be an entry in the error.log.
         # If dagrab gave error messages, but the wav file
         # was created, we won't get to this point, so don't
         # worry.
         if(-r "$wavdir/error.log") {
             open(ERR, "$wavdir/error.log")
               or print "Encoder can't read $wavdir/error.log!\n";
            my @errlines = <ERR>;
            close(ERR);
            # Note that the ripper wrote the $savetrackno into the
            # errorlog, we check for $riptrackno not $tagtrackno.
            chomp(my $errtrack = join(' ', grep(/^Track $riptrackno /, @errlines)));
            if($errtrack) {
               $xtime = $tlength + 1;
               $dataflag = 1;
               if($verbose >= 2) {
                  if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
                     open(ENCLOG, ">>$wavdir/enc.log");
                     print ENCLOG "\nDid not detect track $errtrack ",
                                  "($riptrackname.rip),\n assume ",
                                  "ripper failure!\n";
                     close(ENCLOG);
                  }
                  elsif($rip == 0) {
                     print "\nDid not detect track $errtrack ",
                           "($riptrackname.rip), assume decoder ",
                           "failure!\n";
                  }
                  else {
                     print "\nDid not detect track $errtrack ",
                           "($riptrackname.rip), assume ripper ",
                           "failure!\n";
                  }
               }
               if($verbose >= 2 && $sshflag == 0) {
                  if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
                     open(ENCLOG, ">>$wavdir/enc.log");
                     print ENCLOG "\nRipIT will finish the job! ",
                                  "Check the error.log!\n";
                     close(ENCLOG);
                  }
                  else {
                     print "RipIT will finish the job! ",
                           "Check the error.log!\n";
                  }
               }
            }
            chomp(my $rip_ended = join(' ', grep(/^Ripping\sended:\s\d\d:\d\d/, @errlines)));
            if($rip_ended and $xtime == 0 and $multi == 1) {
               print "Ripper reported having ripped all wavs.\n";
               print "There is a problem with $riptrackname.wav.\n";
               print "with $artist - $album in device $cddev.\n";
               open(SRTF,">>$logfile.$riptrackno.txt")
                  or print "Can not append to file ",
                           "\"$logfile.$riptrackno.txt\"!\n";
               print SRTF "cdparanoia failed on $tracklist[$_ - 1]"
                  if($hiddenflag == 0);
               print SRTF "cdparanoia failed on $tracklist[$_ - 1]"
                  if($hiddenflag == 1);
               print SRTF "\nin device $logfile, error !";
               close(SRTF);
               # Create on the fly error message in log-directory.
               my $devnam = $cddev;
               $devnam =~ s/.*dev.//;
               open(ERO,">>$outputdir/failed.log")
                  or print "Can not append to file ",
                           "\"$outputdir/failed.log\"!\n";
               print ERO "$artist;$album;$genre;$categ;$cddbid;";
               print ERO "$devnam;$hostnam; Cdparanoia failure!\n";
               close(ERO);
               # Now wait to be terminated by checktrack.
               sleep 360;
               exit;
            }
         }
      }

      # This is an other hack to update the track-arrays modified by the
      # ripper if ghost songs were found. Is there another way to
      # communicate with the parent process?
      # This loop was supposed to be at the end of this sub-routine,
      # but we need it here in case of data tracks. The encoder would
      # stop here after a data track and fail to encode previously found
      # ghost songs because @tracksel has not yet been updated.
      if($ghost == 1 && $_ == $tracksel[$#tracksel]
                     && -r "$wavdir/ghost.log") {
         open(GHOST, "<$wavdir/ghost.log")
            or print "Can not read file ghost.log!\n";
         my @errlines = <GHOST>;
         close(GHOST);
         my @selines = grep(s/^Array seltrack: //, @errlines);
         @tracksel = split(/ /, $selines[$#selines]);
         chomp($_) foreach(@tracksel);
         my @seclines = grep(s/^Array secondlist: //, @errlines);
         @secondlist = split(/ /, $seclines[$#seclines]);
         chomp($_) foreach(@secondlist);
         @tracklist = grep(s/^Array tracklist: //, @errlines);
         chomp($_) foreach(@tracklist);
         @tracktags = grep(s/^Array tracktags: //, @errlines);
         chomp($_) foreach(@tracktags);
         # Do not delete ghost.log here because as it contains info
         # about trimmed tracks. But the problem is, that it will be
         # checked in md5sum calculation below expecting it only, if
         # ghost songs have been found and exist. Else md5sum
         # calculation will screw-up.
#         unlink("$wavdir/ghost.log"); # Commented in 4.0.0 XXX
         $ghost = 0;
         $ghostflag = 1;
         $resumenc = $resume; # Continue to resume ghost songs.
      }
      # If we come from merge hack, then the actual track $_ does not
      # exist, continue to loop to the first ghost track.
      next if($skipflag == 3);

      # Jump to the next track if wav wasn't found. Note that the
      # $tlength does not exist for additional ghost songs, so don't
      # test this condition when encoding ghost songs, furthermore we
      # assume that ghost songs are present as soon as one was found.
      next if($ghostflag == 0 && $xtime >= $tlength || $dataflag == 1);

      # It seems that long filenames need to berenamed in a subshell,
      # because the rename function does not work if the full path is
      # even longer. NOTE: There is a problem with UTF8, when special
      # characters are true wide characters... Too many of them, and
      # it will fail again. Maybe one should check the length with the
      # unpack function.
      if(length($riptrackname) + length($wavdir) > 190) {
         # Is there a reason why all files should have no file name
         # longer than 190 character? Removed in version 4.0
         # $riptrackname = substr($riptrackname, 0, 190);
         # $riptrackname =~ s/\s*$//;
         log_system("cd \"$wavdir\" && mv \"$wavname.wav\" \"$riptrackname.wav\"");
      }

      my $delwav = 0;
      my $starts = sprintf("%3d", sub {$_[1]*60+$_[0]}->(localtime));
      if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
         open(ENCLOG, ">>$wavdir/enc.log");
         printf ENCLOG "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
         print ENCLOG "Encoding \"$riptrackname\"...\n"
            if($verbose >= 3);
         close(ENCLOG);
      }
      else {
         printf "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
         print "Encoding \"$riptrackname\"...\n" if($verbose >= 3);
      }

      my $covertag;
      my $failflag = 0;
      my $shortname = "";
      my $shortstring = "short-$$";
      # Set the encoder(s) we are going to use.
      for(my $c = 0; $c <= $#coder; $c++) {
         # Initialization of coverart variables.
         $covertag = " ";
         $coverart[$c] = 0 unless($coverart[$c]);
         # Get the command for the encoder to use!
         $genre = "" unless($genre);
         if($coder[$c] == 0) {
            $encodername = "Lame";
            $lameopt = $globopt[$c];

            push(@mp3tags, "TPOS=$discno") if($discno > 0 && $c == 0);

            # Coverart tagging will be done below because MP3::TAG
            # module will be used. Don't handle the whole picture-data
            # in this command.
            # Starting with Lame 3.99 it is said to be possible (Lame
            # should support APIC-frames > 128kb), but we keep it the
            # way it is implemented.

            # Look at that:
            # 11:55:11: Lame -b 128 encoding track 1 of 2
            # Writing of ID3v2.4 is not fully supported (prohibited now via `write_v24').
            # http://www.perlmonks.org/?node_id=844582
            # use MP3::Tag;
            # MP3::Tag->config(write_v24 => 1);

            if($utftag == 0) {
               # Change file names for Lame when tagging with Latin-1
               # to prevent breaking options ssh / threads because
               # the whole string becomes Latin-1 flagged and non ASCII
               # chars in the path will be corrupted...
               $shortname = get_trackname($_, $_ . $shortstring, "short");
               # Copy the file to a non UTF-8 path. The file should
               # be available as all checks have been done above.
               # Don't do it more than once if Lame is used several
               # times, because else the first Lame process would
               # suddenly get a new partially copied wav and quit
               # abruptly if option sshlist or threads is used.
               if(-f "$wavdir/$wavname.wav") {
                  log_system("cp \"$wavdir/$wavname.wav\" \"/tmp/$shortname.wav\"")
                     unless(-f "/tmp/$shortname.wav");
               }
               else {
                  # This is dangerous... assume $riptrackname exists
                  # instead of $wavname and copy without further
                  # testing.
                  log_system("cp \"$wavdir/$riptrackname.wav\" \"/tmp/$shortname.wav\"")
                     unless(-f "/tmp/$shortname.wav");
               }
               my $id3v2_cmd = "--id3v2-latin1";
               if($lamever < 3.99) {
                  $id3v2_cmd = "";
               }
               $enc = "lame $lameopt --quiet $id3v2_cmd \\
             --tt \"$tracklametag\" \\
             --ta \"$artislametag\" --tl \"$albumlametag\" \\
             --ty \"$year\" --tg \"$genre\" --tn $tagtrackno \\
             --tc \"$commentlametag\" --add-id3v2 \\
             \"/tmp/$shortname.wav\" \\
             \"/tmp/$shortname-$c.$suffix[$c]\"";
               if($lamever >= 3.99) {
               # Decode lame string to Latin-1 if encoder supports it.
                  $enc .= "_done";
                  $enc = decode("latin1", $enc);
               }
            }
            else {
               $enc = "lame $lameopt --quiet --tt \"$tracklametag\" \\
             --ta \"$artislametag\" --tl \"$albumlametag\" \\
             --ty \"$year\" --tg \"$genre\" --tn $tagtrackno \\
             --tc \"$commentlametag\" --add-id3v2 \\
             \"$wavdir/$riptrackname.wav\" \\
             \"$sepdir[$c]/$riptrackname.$suffix[$c]_enc\"";
            }
            if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
               open(ENCLOG, ">>$wavdir/enc.log");
               printf ENCLOG "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print ENCLOG "Lame $lameopt encoding track $trackcn" .
                     " of " . ($#tracksel + 1) . "\n" if($verbose >= 3);
               close(ENCLOG);
            }
            else {
               printf "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print "Lame $lameopt encoding track $trackcn of " .
                     ($#tracksel + 1) if($verbose >= 3);
               print " merged tracks." if($verbose >= 3 && $cdcue > 0);
               print "\n" if($verbose >= 3);
            }
            log_info("new-mediafile: $sepdir[$c]/${riptrackname}.$suffix[$c]");
            if($va_flag > 0) {
               # Note, this does not work if option sshflag or threads
               # is used.
               push(@mp3tags, "TPE2=$albumartistlametag")
                  unless("@mp3tags" =~ /TPE2/);
            }
         }
         elsif($coder[$c] == 1) {
            $encodername = "Oggenc";
            $oggencopt = $globopt[$c];
            # Don't know if the COMPILATION-tag is supported but it
            # should not harm at all.
            $oggencopt .= " -c \"DISCNUMBER=$discno\"" if($discno > 0);
            $oggencopt .= " -c \"COMPILATION=1\"" if($va_flag > 0);
            $oggencopt .= " -c \"ALBUMARTIST=$albumartistag\""
               if($va_flag > 0);

            # Some info about coverart tagging.
            # This will happen below, after encoding, because we use
            # vorbiscomment. Don't handle the whole picture-data
            # in this command.

            # http://www.hydrogenaudio.org/forums/lofiversion/index.php/t48386.html

            # CLI solutions:
            # first: base64 encoding of the image:
            #
            # perl -MMIME::Base64 -0777 -ne 'print encode_base64($_, "")' < thumb.png > temp
            #
            # note the double quotes to prevent the newlines.
            # Redirect this output to a file.
            #
            # second: use vorbiscomment to tag the file: (http://darcs.tonywhitmore.co.uk/repos/podcoder/podcoder)
            #
            # vorbiscomment -a 01.ogg -t "COVERARTMIME=image/png" -t "COVERART=`cat temp`"
            #
            # and you're done.

            # My personal solution:
            # me@ripstation:~/Mo/ogg> echo -n COVERART= > temp && perl -MMIME::Base64 -0777 -ne 'print encode_base64($_, "")' < cover.jpg >> temp
            # me@ripstation:~/Mo/ogg> vorbiscomment -a 05_Mo.ogg < temp


            # Use of METADATA_BLOCK_PICTURE
            # http://wiki.xiph.org/index.php/VorbisComment
            # http://lists.xiph.org/pipermail/vorbis-dev/2009-April/019853.html

            # Proposals for extending Ogg Vorbis comments
            # http://reallylongword.org/vorbiscomment/

            $enc = "oggenc $oggencopt -Q -t \"$tracktag\" \\
             -a \"$artistag\" -l \"$albumtag\" \\
             -d \"$year\" -G \"$genre_tag\" \\
             -N $tagtrackno -c \"DESCRIPTION=$commentag\" \\
             -o \"$sepdir[$c]/$riptrackname.$suffix[$c]_enc\" \\
             \"$wavdir/$riptrackname.wav\"";
            if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
               open(ENCLOG, ">>$wavdir/enc.log");
               printf ENCLOG "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print ENCLOG "Oggenc $globopt[$c] encoding track" .
                     " $trackcn of " . ($#tracksel + 1) . "\n"
                     if($verbose >= 3);
               close(ENCLOG);
            }
            else {
               printf "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print "Oggenc $globopt[$c] encoding track $trackcn of " .
                      ($#tracksel + 1) if($verbose >= 3);
               print " merged tracks" if($verbose >= 3 && $cdcue > 0);
               print ".\n" if($verbose >= 3);
            }
            log_info("new-mediafile: $sepdir[$c]/${riptrackname}.$suffix[$c]");
         }
         elsif($coder[$c] == 2) {
            $encodername = "Flac";
            $flacopt = $globopt[$c];
            my $save_flacopt = $flacopt;
            my $flactags = "";
            $flacopt .= " -f" if($resume);
            # Don't know if the COMPILATION-tag is supported but it
            # should not harm at all.
            $flacopt .= " --tag=DISCNUMBER=$discno" if($discno > 0);
            $flacopt .= " --tag=COMPILATION=1" if($va_flag > 0);
            $flacopt .= " --tag=ALBUMARTIST=\"$albumartistag\""
               if($va_flag > 0);
            $flacopt .= " --tag=CATEGORY=\"$categ\""
               if(defined $categ and $categ ne "");
            $flacopt .= " --tag=GENRE=\"$genre_tag\""
               if(defined $genre_tag && "Unknown" ne $genre_tag);
#             $flacopt .= " --tag=MUSICBRAINZ_ALBUMID=\"$cd{mbreid}\""
#                if(defined $cd{mbreid});
#             $flacopt .= " --tag=MUSICBRAINZ_DISCID=\"$cd{discid}\""
#                if(defined $cd{discid});
#             $flacopt .= " --tag=CATALOGNUMBER=\"$cd{catalog}\""
#                if(defined $cd{catalog});
            if($coverart[$c] == 1 && -f "$coverpath" && -s "$coverpath") {
               if($coverpath =~ /[|\\\\:*?\$]/) {
                  $covertag = "--picture=/tmp/ripit-flac-cov-$$.jpg";
                  log_system("cp \"$coverpath\" /tmp/ripit-flac-cov-$$.jpg");
               }
               else {
                  $covertag = "--picture=\"$coverpath\"";
               }
            }
            if(@flactags) {
               foreach (@flactags) {
                  my ($frame, $content) = split(/=/, $_);
                  $content = tag_eval($frame, $content);
                  $flactags .= " --tag=$frame=\"$content\""
                     if(defined $content && $content ne "");
               }
               $flactags =~ s/^\s+//;
            }
            $enc = "flac $flacopt \\
             --totally-silent \\
             --tag=TITLE=\"$tracktag\" \\
             --tag=ARTIST=\"$artistag\" --tag=ALBUM=\"$albumtag\" \\
             --tag=DATE=\"$year\" --tag=TRACKNUMBER=\"$tagtrackno\" \\
             --tag=DESCRIPTION=\"$commentag\" --tag=CDID=\"$cddbid\" \\
             $covertag \\
             $flactags \\
             -o \"$sepdir[$c]/$riptrackname.$suffix[$c]_enc\" \\
             \"$wavdir/$riptrackname.wav\"";
            if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
               open(ENCLOG, ">>$wavdir/enc.log");
               printf ENCLOG "%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print ENCLOG "Flac $globopt[$c] encoding track $trackcn" .
                     " of " . ($#tracksel + 1) . "\n" if($verbose >= 3);
               close(ENCLOG);
            }
            else {
               printf "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print "Flac $globopt[$c] encoding track $trackcn of " .
                     ($#tracksel + 1) if($verbose >= 3);
               print " merged tracks." if($verbose >= 3 && $cdcue > 0);
               print "\n" if($verbose >= 3);
            }
            log_info("new-mediafile: $sepdir[$c]/${riptrackname}.$suffix[$c]");
            my $flacopt = $save_flacopt if($resume);
         }
         elsif($coder[$c] == 3) {
            $encodername = "Faac";
            $faacopt = $globopt[$c];
            if($coverart[$c] == 1 && -f "$coverpath" && -s "$coverpath") {
               $covertag = "--cover-art \"$coverpath\"";
            }
            $faacopt .= " --compilation" if($va_flag > 0);
            $faacopt .= " --disc $discno" if($discno > 0);
            $enc = "faac $faacopt -w --title \"$tracktag\" \\
             --artist \"$artistag\" --album \"$albumtag\" \\
             --year \"$year\" --genre \"$genre_tag\" --track $tagtrackno \\
             --comment \"$commentag\" \\
             $covertag \\
             -o \"$sepdir[$c]/$riptrackname.$suffix[$c]_enc\" \\
             \"$wavdir/$riptrackname.wav\" \\
             > /dev/null 2>&1";
            if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
               open(ENCLOG, ">>$wavdir/enc.log");
               printf ENCLOG "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print ENCLOG "Faac $globopt[$c] encoding track $trackcn" .
                     " of " . ($#tracksel + 1) . "\n" if($verbose >= 3);
               close(ENCLOG);
            }
            else {
               printf "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print "Faac $globopt[$c] encoding track $trackcn of " .
                     ($#tracksel + 1) if($verbose >= 3);
               print " merged tracks."
                  if($verbose >= 3 && ($book > 0 || $cdcue > 0));
               print "\n" if($verbose >= 3);
            }
            log_info("new-mediafile: $sepdir[$c]/${riptrackname}.$suffix[$c]");
         }
         elsif($coder[$c] == 4) {
            $encodername = "mp4als";
            $mp4alsopt = $globopt[$c];
            $enc = "mp4als $mp4alsopt \\
             \"$wavdir/$riptrackname.wav\" \\
             \"$sepdir[$c]/$riptrackname.$suffix[$c]_enc\" \\
             > /dev/null 2>&1 \\
             ";
            # Only add tags if MP4 container is set up, use artwork for
            # coverart.
            my $mp4suffix = $suffix[$c];
            if($mp4alsopt =~ /MP4/) {
               $mp4suffix = "mp4";
               if($coverart[$c] == 1 && -f "$coverpath" && -s "$coverpath") {
                  $covertag = "-P \"$coverpath\"";
               }
               $enc .= " && mp4tags -s \"$tracktag\" -a \"$artistag\" \\
                -A \"$albumtag\" -y \"$year\" -g \"$genre_tag\" \\
                -t $tagtrackno -c \"$commentag\" -e Ripit -E mp4als \\
                $covertag \\
                \"$sepdir[$c]/$riptrackname.$suffix[$c]_enc\"";
            }
            if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
               open(ENCLOG, ">>$wavdir/enc.log");
               printf ENCLOG "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print ENCLOG "Mp4als $globopt[$c] encoding track $trackcn" .
                     " of " . ($#tracksel + 1) . "\n" if($verbose >= 3);
               close(ENCLOG);
            }
            else {
               printf "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print "Mp4als $globopt[$c] encoding track $trackcn of " .
                     ($#tracksel + 1) if($verbose >= 3);
               print " merged tracks." if($verbose >= 3 && $cdcue > 0);
               print "\n" if($verbose >= 3);
            }
            log_info("new-mediafile: $sepdir[$c]/${riptrackname}.$suffix[$c]");
         }
         elsif($coder[$c] == 5) {
            $encodername = "Musepack";
            $museopt = $globopt[$c];
            # TODO: check availability
            # Discnumber is not yet supported
#             $museopt .= " --discnumber=$discno" if($discno > 0);
#             $museopt .= " --compilation=1" if($va_flag > 0);
#             $museopt .= " --albumartist=\"$albumartistag\""
#                if($va_flag > 0);
            # Musepack seems not to support coverart, the developers
            # probably assume that coverart has nothing to do with a
            # track... i.e. with sound.
            $enc = "$musenc --silent $museopt --title \"$tracktag\" \\
             --artist \"$artistag\" --album \"$albumtag\" \\
             --year \"$year\" --genre \"$genre_tag\" --track $tagtrackno --comment \"$commentag\" \\
             \"$wavdir/$riptrackname.wav\" \\
             \"$sepdir[$c]/$riptrackname\_enc.$suffix[$c]\"";
            if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
               open(ENCLOG, ">>$wavdir/enc.log");
               printf ENCLOG "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print ENCLOG "Mppenc $globopt[$c] encoding track $trackcn" .
                     " of " . ($#tracksel + 1) . "\n" if($verbose >= 3);
               close(ENCLOG);
            }
            else {
               printf "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print "Mppenc $globopt[$c] encoding track $trackcn of " .
                     ($#tracksel + 1) if($verbose >= 3);
               print " merged tracks." if($verbose >= 3 && $cdcue > 0);
               print "\n" if($verbose >= 3);
            }
            log_info("new-mediafile: $sepdir[$c]/${riptrackname}.$suffix[$c]");
         }
         elsif($coder[$c] == 6) {
            $encodername = "wavpack";
            $wavpacopt = $globopt[$c];
            $wavpacopt .= " -w \"Part=$discno\"" if($discno > 0);
            $wavpacopt .= " -w \"Compilation=1\"" if($va_flag > 0);
            $wavpacopt .= " -w \"Albumartist=$albumartistag\""
               if($va_flag > 0);
            $wavpacopt .= " -w \"MUSICBRAINZ_ALBUMID=$cd{mbreid}\""
               if(defined $cd{mbreid});
            $wavpacopt .= " -w \"MUSICBRAINZ_DISCID=$cd{discid}\""
               if(defined $cd{discid});
            $wavpacopt .= " -w \"CATALOGNUMBER=$cd{catalog}\""
               if(defined $cd{catalog});
            # Use command wvunpack -ss filename.wv to check if the cover
            # art is present or not. See:
            # www.hydrogenaudio.org/forums/index.php?showtopic=74828
            if($coverart[$c] == 1 && -f "$coverpath" && -s "$coverpath") {
               $covertag = "--write-binary-tag \"Cover Art (Front)=\@$coverpath\"";
            }
            $enc = "wavpack $wavpacopt -q \\
             -w \"Title=$tracktag\" \\
             -w \"Artist=$artistag\" -w \"Album=$albumtag\" \\
             -w \"Year=$year\" -w \"Genre=$genre_tag\" \\
             -w \"Track=$tagtrackno\" -w \"Comment=$commentag\" \\
             $covertag \\
             \"$wavdir/$riptrackname.wav\" \\
             -o \"$sepdir[$c]/$riptrackname\_enc\"";
            if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
               open(ENCLOG, ">>$wavdir/enc.log");
               printf ENCLOG "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print ENCLOG "Wavpack $globopt[$c] encoding track $trackcn" .
                     " of " . ($#tracksel + 1) . "\n" if($verbose >= 3);
               close(ENCLOG);
            }
            else {
               printf "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print "Wavpack $globopt[$c] encoding track $trackcn of " .
                     ($#tracksel + 1) if($verbose >= 3);
               print " merged tracks." if($verbose >= 3 && $cdcue > 0);
               print "\n" if($verbose >= 3);
            }
            log_info("new-mediafile: $sepdir[$c]/${riptrackname}.$suffix[$c]");
         }
         elsif($coder[$c] == 7) {
            $encodername = "ffmpeg";
            # Trying to solve the tag problem of tagging with ffmpeg in
            # general and within alac files in special:
            # First, I tried to use ffmpeg and the -map_meta_tag option:
            # ffmpeg -i 05\ I\ Beg\ For\ You.flac -acodec alac \\
            # 05\ I\ Beg\ For\ You.m4a -map_meta_data outfile:infile
            # Note: do not replace outfile:infile by the file names, use
            # the command as stated!
            #
            # OK, this works and we see, that the four character code
            # used in the m4a tags are "ART" and "wrt". So, what we need
            # is author to access these tags!
            #
            # http://archives.free.net.ph/message/20090925.222527.f3078d30.en.html
            # http://atomicparsley.sourceforge.net/mpeg-4files.html
            # http://code.google.com/p/mp4v2/wiki/iTunesMetadata
            #
            $ffmpegopt = $globopt[$c];
            $ffmpegopt .= " -y" if($overwrite eq "y");
            $ffmpegopt .= " -metadata compilation=1 " if($va_flag > 0 and $ffmpegopt =~ /alac/i);
            $ffmpegopt .= " -metadata discnumber=$discno" if($discno > 0);
#            Not yet supported... at least I don't know how to use the
#            -atag fourcc/tag option.
#            if($coverart[$c] == 1 && -f "$coverpath" && -s "$coverpath") {
#               $covertag = "-metadata artwork=\'$coverpath\'";
#            }
            $enc = "ffmpeg -i \"$wavdir/$riptrackname.wav\" \\
             $ffmpegopt \\
             -metadata author=\"$artistag\" -metadata album=\"$albumtag\" \\
             -metadata title=\"$tracktag\" -metadata genre=\"$genre_tag\" \\
             -metadata day=\"$year\" -metadata comment=\"$commentag\" \\
             -metadata track=\"$tagtrackno\" \\
             $covertag \\
             \"$sepdir[$c]/$riptrackname.$suffix[$c]\" > /dev/null 2>&1";
            # Only add artwork for coverart if alac is present.
            if($coverart[$c] == 1 && -f "$coverpath" && -s "$coverpath") {
               if($ffmpegopt =~ /alac/) {
                  $enc .= " && mp4art -q --add \"$coverpath\" \\
                  \"$sepdir[$c]/$riptrackname.$suffix[$c]\"";
               }
            }
            if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
               open(ENCLOG, ">>$wavdir/enc.log");
               printf ENCLOG "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print ENCLOG "ffmpeg $ffmpegopt encoding track $trackcn" .
                     " of " . ($#tracksel + 1) . "\n" if($verbose >= 3);
               close(ENCLOG);
            }
            else {
               printf "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime)
                  if($verbose >= 3);
               print "ffmpeg $ffmpegopt encoding track $trackcn of " .
                     ($#tracksel + 1) if($verbose >= 3);
               print " merged tracks." if($verbose >= 3 && $cdcue > 0);
               print "\n" if($verbose >= 3);
            }
            log_info("new-mediafile: $sepdir[$c]/${riptrackname}.$suffix[$c]");
         }
         # Set "last encoding of track" - flag.
         $delwav = 1 if($wav == 0 && $c == $#coder);
         # Set nice if wished.
         $enc = "nice -n $nice " . $enc if($nice != 0);
         # Make the output look nice, don't mess the messages!
         my $ripmsg = "The audio CD ripper reports: all done!";
         if($ripcomplete == 0 ) {
            if(-r "$wavdir/error.log") {
               open(ERR, "$wavdir/error.log")
                  or print "Can not open file error.log!\n";
               my @errlines = <ERR>;
               close(ERR);
               my @ripcomplete = grep(/^$ripmsg/, @errlines);
               $ripcomplete = 1 if(@ripcomplete);
            }
         }

         $enc =~ s/\$/\\\$/g;
         # Finally, do the job of encoding.
         if($sshflag == 1) {
            if(-f "$sepdir[$c]/$riptrackname.$suffix[$c]" && ((-f "$coverpath" && -s "$coverpath") || @mp3tags)) {
               printf "\n%02d:%02d:%02d: ",
               sub {$_[2], $_[1], $_[0]}->(localtime)
               if($verbose > 0);
               print "Warning, file ",
                     "$sepdir[$c]/$riptrackname.$suffix[$c]\n",
                     "          already exists and post processing ",
                     "would be done before new file appears...\n",
                     "          File will be deleted now!\n"
                     if($verbose > 0);
               unlink("$sepdir[$c]/$riptrackname.$suffix[$c]");
            }
            enc_ssh($delwav,$enc,$riptrackname,$sepdir[$c],$suffix[$c],$shortname,$c);
            # Calculation of md5sum has been moved to the end, we still
            # use the process to check the files already done to add
            # coverart. Files not yet encoded will need to be post-
            # processed in del_erlog subroutine.
            push(@md5tracks,
                 "$sepdir[$c];#;$riptrackname.$suffix[$c]");
            my @waitracks;
            foreach my $md5tr (@md5tracks) {
               my ($sepdir, $donetrack) = split(/;#;/, $md5tr);
               # Proceed only if file appeared.
               if(-f "$sepdir/$donetrack") {
                  # Add additional mp3 tags.
                  if(@mp3tags && $donetrack =~ /mp3$/) {
                     mp3_tags("$sepdir/$donetrack")
                        if(defined $mp3tags[0] && $mp3tags[0] !~ /^\s*$/);
                  }
                  # Add special tags to ogg with strings to be evaluated
                  elsif(@oggtags && $donetrack =~ /ogg$/) {
                     ogg_tags("$sepdir/$donetrack") if($oggtags[0] ne "");
                  }
                  # Add coverart if it is a mp3 or ogg.
                  if($donetrack =~ /mp3$/ && -f "$coverpath" && -s "$coverpath") {
                     mp3_cover("$sepdir/$donetrack", "$coverpath");
                  }
                  elsif($donetrack =~ /ogg$/ && -f "$coverpath" && -s "$coverpath") {
                     ogg_cover("$sepdir/$donetrack", "$coverpath");
                  }
               }
               # Only keep files in array @md5tracks if not yet
               # processed.
               else {
                  push(@waitracks, "$sepdir;#;$donetrack");
               }
            }
            # TODO: Check if array md5tracks gets cleared as expected.
            # No md5sums can be calculated...
            @md5tracks = @waitracks;
         }
         else {
            if(log_system("$enc")) {
               if($ripcomplete == 0) {
                  if(-r "$wavdir/error.log") {
                     open(ERR, "$wavdir/error.log")
                        or print "Can open file error.log!\n";
                     my @errlines = <ERR>;
                     close(ERR);
                     my @ripcomplete = grep(/^$ripmsg/, @errlines);
                     $ripcomplete = 1 if(@ripcomplete);
                  }
               }
               if($coder[$c] == 4 && $mp4alsopt =~ /MP4/) {
                  rename("$sepdir[$c]/$riptrackname.$suffix[$c]_enc",
                         "$sepdir[$c]/$riptrackname.mp4");
               }
               elsif($coder[$c] == 5) {
                  rename("$sepdir[$c]/$riptrackname\_enc.$suffix[$c]",
                         "$sepdir[$c]/$riptrackname.$suffix[$c]");
               }
               elsif($coder[$c] == 6) {
                  rename("$sepdir[$c]/$riptrackname\_enc.$suffix[$c]",
                         "$sepdir[$c]/$riptrackname.$suffix[$c]");
                  if(-r "$sepdir[$c]/$riptrackname\_enc.wvc") {
                     rename("$sepdir[$c]/$riptrackname\_enc.wvc",
                            "$sepdir[$c]/$riptrackname.wvc");
                  }
               }
               elsif($coder[$c] == 0 and $utftag == 0) {
                  log_system("mv \"/tmp/$shortname-$c.mp3_done\" \\
                                 \"$sepdir[$c]/$riptrackname.mp3\"");
               }
               else {
                  rename("$sepdir[$c]/$riptrackname.$suffix[$c]_enc",
                         "$sepdir[$c]/$riptrackname.$suffix[$c]");
               }
               # Add special mp3 tags.
               if(@mp3tags && $coder[$c] == 0) {
                  mp3_tags("$sepdir[$c]/$riptrackname.$suffix[$c]")
                     if(defined $mp3tags[0] && $mp3tags[0] !~ /^\s*$/);
               }
               # Add special tags to ogg with strings to be evaluated
               elsif(@oggtags && $coder[$c] == 1) {
                  ogg_tags("$sepdir[$c]/$riptrackname.$suffix[$c]")
                     if($oggtags[0] ne "");
               }
               # Add coverart if it is a mp3 or ogg.
               if($coder[$c] == 0 && $coverart[$c] == 1 &&
                  -f "$coverpath" && -s "$coverpath") {
                  mp3_cover("$sepdir[$c]/$riptrackname.$suffix[$c]", "$coverpath");
               }
               elsif($coder[$c] == 1 && $coverart[$c] == 1 &&
                     -f "$coverpath" && -s "$coverpath") {
                  ogg_cover("$sepdir[$c]/$riptrackname.$suffix[$c]", "$coverpath");
               }
               else {
                  print "Failed adding coverart to $suffix[$c].\n"
                  if($coverart[$c] == 1 && $verbose > 2 && $coder[$c] < 2);
               }
               if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
                  open(ENCLOG, ">>$wavdir/enc.log");
                  print ENCLOG "Encoding of " .
                               "\"$riptrackname.$suffix[$c]\" " .
                               "complete.\n" if($verbose >= 1);
                  close(ENCLOG);
               }
               else {
                  print "Encoding of \"$riptrackname.$suffix[$c]\" " .
                        "complete.\n" if($verbose >= 1);
               }
            }
            else {
               print "Encoder $encodername failed on $tracklist[$_ - 1]\n",
                     "of disc in device $cddev.\n",
                     "Error message says: $?\n";
               $failflag = 1;
               if($multi == 1) {
                  # Print error message to file srXY.Z.txt, checktrack
                  # will grep for string "encoder failed" and kill the
                  # CD immediately!
                  open(SRTF,">>$logfile.$riptrackno.txt")
                     or print "Can not append to file ",
                              "\"$logfile.$riptrackno.txt\"!\n";
                  print SRTF "\nencoder failed on $tracklist[$_ - 1] ";
                  print SRTF "in device $cddev, error $? !";
                  close(SRTF);
                  # Create on the fly error message in log-directory.
                  my $devnam = $cddev;
                  $devnam =~ s/.*dev.//;
                  open(ERO, ">>$outputdir/failed.log")
                     or print "Can not append to file ",
                              "\"$outputdir/failed.log\"!\n";
                  print ERO "$artist;$album;$genre;$categ;$cddbid;";
                  print ERO "$devnam;$hostnam; Encoder failure!\n";
                  close(ERO);
                  # Wait to be terminated by checktrack.
                  sleep 360;
               }
            }
            sleep 1;
         }
         # Copy the CDCUE file (once) to the directory of the encoded
         # files.
         if($cdcue > 0) {
            my $cue_suffix = $suffix[$c];
            $cue_suffix =~ tr/a-z/A-Z/;
            open(CDCUE, ">$sepdir[$c]/$album.cue")
               or print "Can not write to file ",
                        "\"$sepdir[$c]/$album.cue\"!\n";
            foreach (@cuelines) {
               chomp;
               s/\.wav/.$suffix[$c]/;
               s/\sWAVE/ $cue_suffix/;
               print CDCUE "$_\n";
            }
            close(CDCUE);
         }
      }
      # Calculate time in seconds when encoding ended and total time
      # encoder needed.
      my $endsec = sprintf("%3d", sub {$_[1]*60+$_[0]}->(localtime));
      $endsec += 60 while($endsec <= $starts);
      $totalencs = $totalencs + $endsec - $starts;
      # Delete the wav if not wanted.
      unlink("$wavdir/$riptrackname.wav")
         if($delwav == 1 && $sshflag == 0 && $accuracy == 0);
      unlink("/tmp/$shortname.wav")
         if($lameflag == 1 && $utftag == 0);

      # Write the playlist file. This is somehow tricky, if ghost songs
      # may appear. To ensure the files in the right order, introduce
      # placeholders for possible ghost songs.
      # The problem is that the secondlist with the true track lengths
      # will only be updated when the last track has been encoded (the
      # last track except ghost songs). But we need the true length
      # right now. So, if $ghost == 1, check for the ghost.log file at
      # any track.
      # TODO:
      # An other buggy behaviour: if the last encoder of a list fails,
      # failflag will prevent writing playlist files, although encoding
      # was successful for all other encoders (but the last one).
      # Would it be better to write the playlist file in any case?
      if($failflag == 0 and ($playlist >= 1 or $cue > 0 )) {
         # Ghost songs follow after the last track, but $ghostflag was
         # set to 1 just before last track is encoded. Therefore set
         # $ghostflag to 2 after the last track has been done and
         # inserted in the playlist file as a regular file (below),
         # and insert sound files as ghost songs only when $ghostflag is
         # 2. If only the last song has been split into chunks and
         # the counter increased, continue to insert as regular file.
         if($ghostflag == 2) {
            print PLST "GS$_:#EXTINF:$secondlist[$ghostcn - 1],",
                        "$tracktag\n"
               if($hiddenflag == 0);
            print PLST "GS$_:#EXTINF:$secondlist[$ghostcn],$tracktag\n"
               if($hiddenflag == 1);
            print PLST "GS$_:Sepdir/$riptrackname.suffix\n"
               if($playlist == 1);
            print PLST "GS$_:$riptrackname.suffix\n" if($playlist == 2);
         }
         else {
            if($ghost == 1 && -r "$wavdir/ghost.log") {
               open(GHOST, "<$wavdir/ghost.log")
                  or print "Can not read file ghost.log!\n";
               my @errlines = <GHOST>;
               close(GHOST);
               my @seclines = grep(s/^Array secondlist: //, @errlines);
               @secondlist = split(/ /, $seclines[$#seclines]);
               chomp($_) foreach(@secondlist);
            }
            print PLST "#EXTINF:$secondlist[$_ - 1],$tracktag\n"
               if($hiddenflag == 0);
            print PLST "#EXTINF:$secondlist[$_],$tracktag\n"
               if($hiddenflag == 1);
            print PLST "Sepdir/$riptrackname.suffix\n"
               if($playlist == 1);
            print PLST "$riptrackname.suffix\n" if($playlist == 2);
            print PLST "Add Ghost Song $_ Here.\n"
               if($ghost == 1 || $ghostflag == 1);
         }
      }
      last if($cdcue > 0);
   }

   print "\n" if($verbose > 2);
   # Only add albumgain and md5sum calculation if all tracks are done,
   # this might not be the case when running with more than one thread
   # or using remote process. In the later case, we need to add coverart
   # and album gain before calculating md5sums, so: move all this stuff
   # to del_erlog!

   # Tell the mother process the encoding time.
   open(ERR, ">>$wavdir/error.log")
      or print "Can not append to file error.log!\n";
   print ERR "Encoding needed $totalencs seconds!\n";
   print ERR "md5: $_\n" foreach(@md5tracks);
   print ERR "mp3tags: $_\n" foreach(@mp3tags);
   print ERR "flac-cover: /tmp/ripit-flac-cov-$$.jpg\n"
      if(defined $coverpath and -f "/tmp/ripit-flac-cov-$$.jpg");
   close(ERR);
   close(PLST);
   exit unless($normalize == 1 or $cdcue > 0 or $rip == 0);
}
########################################################################
#
# Finish the M3U file used by players such as Amarok, Noatun, X11Amp...
# Use this subroutine to create a cue file.
#
sub create_m3u {
   my $playfile;
   my @mp3s = ();

   my $albumtag = clean_all($album_utf8);
   my $artistag = clean_all($artist_utf8);
   my $album = $albumtag;
   my $artist = $artistag;
   $album = clean_name($album);
   $artist = clean_name($artist);
   $album = clean_chars($album) if($chars);
   $artist = clean_chars($artist) if($chars);

   $playfile = "$artist" . " - " . "$album" . ".m3u";
   $playfile =~ s/\.m3u$/.rec/ if($rip == 0);
   $playfile =~ s/ /_/g if($underscore == 1);
   if($limit_flag == 255) {
      $playfile = substr($playfile, 0, 240);
   }

   # Prevent warnings in some rare cases if no tracks have been ripped.
   return unless(-r "$wavdir/$playfile");

   open(PLST, "<$wavdir/$playfile")
      or print "Can not open file $wavdir/$playfile!\n";
   my @playlines = <PLST>;
   close(PLST);
   my @ghosts = grep(/^GS\d+:/, @playlines);

   unlink("$wavdir/$playfile");
   # Once the safe playlist-file from re-encoding is purged, use the
   # common suffix.
   $playfile =~ s/\.rec$/.m3u/ if($rip == 0);

   # Do not overwrite existing playlist-files.
   # Rename existing playlist file.
   if(-f "$wavdir/$playfile" and $rip == 0) {
      my $nplayfile = $playfile;
      my $counter = 1;
      $nplayfile =~ s/\.m3u$/ orig.m3u/;
      # Warn if the backup file exists.
      while(-r "$wavdir/$nplayfile") {
         $nplayfile =~ s/.orig\.m3u/.m3u/;
         $nplayfile =~ s/.orig.\d+\.m3u/.m3u/;
         $nplayfile =~ s/\.m3u$/ orig $counter.m3u/;
         $nplayfile =~ s/ /_/g if($underscore == 1);
         $counter++;
         if($counter > 10) {
            print "Existing playlist backup file $nplayfile will be ",
                  "orverwritten, too many checks failed.\n"
                  if($verbose >= 3);
         }
         last if($counter > 10);
      }
      rename("$wavdir/$playfile", "$wavdir/$nplayfile");
      print "Existing file $playfile renamed to $nplayfile.\n"
         if($verbose >= 3);
   }

   # Modify placeholders for ghostsongs
   my @playlist = ();
   foreach (@playlines) {
      # All lines with GS have been extracted from the @playlines into
      # array @ghosts, so skip them if encountered within @playlines.
      next if($_ =~ /^GS\d+:/ || $_ =~ /^$/);
      $_ =~ s/^Add Ghost Song (\d+) Here.$/$1/;
      chomp $_;
      if($_ =~ /^\d+$/) {
         # Now keep track of remaining ghost songs:
         my @ghosts_remain = ();
         foreach my $ghostsong (@ghosts) {
            if($ghostsong =~ s/^GS$_\://) { # Why not as a 1-liner?
               $ghostsong =~ s/^GS$_\://;
               chomp $ghostsong;
               push(@playlist, $ghostsong);
            }
            else {
               push(@ghosts_remain, $ghostsong);
            }
         }
         @ghosts = @ghosts_remain;
      }
      else {
         push @playlist, $_;
      }
   }
   # Add trailing ghost songs
   if(defined $ghosts[0]) {
      foreach my $ghostsong (@ghosts) {
         chomp $ghostsong;
         $ghostsong =~ s/^GS\d+\://;
         push(@playlist, $ghostsong);
      }
   }

   my $cplayfile;
   my $nplayfile;
   my @cuelist = @playlist;
   for(my $c = 0; $c <= $#coder; $c++) {
      my $trackoffsetflag = 0;
      my @mp3s = @playlist;
      $_ =~ s/\.suffix$/.$suffix[$c]/i foreach (@mp3s);
      $_ =~ s/^Sepdir/$sepdir[$c]/ foreach (@mp3s);
      # Extension of playlist-file only needed when more than one
      # encoder selected. Using separate dirs, this would not be
      # necessary, but who says we use them? We keep the extension.
      # Side note for the $rip == 0 case (re-encoding and recreation of
      # a playlist file): Cleanup of paths for comparison.
      $inputdir =~ s/\/$//;
      if($#coder != 0 or ($rip == 0 and $inputdir eq $sepdir[$c])) {
         $nplayfile = $playfile;
         $nplayfile = change_case($nplayfile, "t");
         $nplayfile =~ s/\.m3u$/ - $suffix[$c].m3u/
            if($underscore == 0);
         $nplayfile =~ s/\.m3u$/_-_$suffix[$c].m3u/
            if($underscore == 1);
         $cplayfile = $nplayfile;
         $cplayfile =~ s/m3u$/cue/;
         # If file exists from previous run with --addtrackoffset or
         # --trackoffset, do not overwrite it; read content first and
         # append it afterwards. If this happens repeated times, this
         # will screw up the playlist file.
         if(-f "$sepdir[$c]/$nplayfile" and ($addtrackoffset == 1 and
            $trackoffset > 0 )) {
            open(PLST, "<$sepdir[$c]/$nplayfile") or
               print "Can't open $sepdir[$c]/$nplayfile! $!\n";
            @playlines = <PLST>;
            close PLST;
            $trackoffsetflag = 1;
         }
         open(PLST, ">$sepdir[$c]/$nplayfile") or
            print "Can't open $sepdir[$c]/$nplayfile! $!\n";
         # Not so sure what users want (what a cue sheet is needed for).
         # Rather create a second file.
         if(-f "$sepdir[$c]/$cplayfile" and ($addtrackoffset == 1 and
            $trackoffset > 0 and $cue > 0)) {
            $cplayfile =~ s/\.cue$/ $discno.cue/ if($underscore == 0);
            $cplayfile =~ s/\.cue$/_$discno.cue/ if($underscore == 1);
         }
         if($cue > 0) {
            open(CLST, ">$sepdir[$c]/$cplayfile") or
               print "Can't open $sepdir[$c]/$cplayfile! $!\n";
         }
      }
      else {
         $nplayfile = $playfile;
         $cplayfile = $nplayfile;
         $cplayfile =~ s/m3u$/cue/;
         open(PLST, ">$sepdir[$c]/$nplayfile") or
            print "Can't open $sepdir[$c]/$nplayfile! $!\n";
         if($cue > 0) {
            open(CLST, ">$sepdir[$c]/$cplayfile") or
               print "Can't open $sepdir[$c]/$cplayfile! $!\n";
         }
      }
      # Add original playlist-files to the playlist.
      if($trackoffsetflag == 1) {
         print "\nAdding playlist info from previous run, please check",
               " the new playlist file\n$sepdir[$c]/$nplayfile",
               "\nfor consistency.\n"
            if($verbose > 2);
         foreach(@playlines) {
            chomp;
            print PLST "$_\n";
            # Actually, do not add infos from previous runs, rather
            # create a new file.
            # print CLST "$_\n" if($cue > 0);
         }
         # Remove header line of new playlist file.
         shift(@mp3s);
      }
      print PLST "$_\n" foreach(@mp3s);
      close(PLST);
      if($cue > 0) {
         my $cn = 0;
         my $pos = 0;
         my $tn = "";
         @cuelist = @playlist;
         foreach(@cuelist) {
            s/^#\s*/REM /;
            s/^Sepdir\///;
            s/\.suffix$/.$suffix[$c]/i;
            if($pos == 1) {
               my $dcn = sprintf("%02d", $cn);
               my $suf = uc($suffix[$c]);
               print CLST "FILE \"$_\" $suf\n";
               print CLST "  TRACK $dcn AUDIO\n    TITLE \"$tn\"\n",
                 "    PERFORMER \"$artistag\"\n    INDEX 01 00:00:00\n";
               $pos = 0;
            }
            elsif(/^REM EXTINF/) {
               $tn = $_;
               $tn =~ s/^REM EXTINF:\d*,\s*//;
               $pos = 1;
               print CLST "TITLE \"$albumtag\"\n",
                          "PERFORMER \"$artistag\"\n" if($cn == 0);
               $cn++;
            }
            else {
               print CLST "$_\n" unless(/REM EXTM3U/);
            }
         }
         close(CLST);
      }

      chmod oct($fpermission), "$sepdir[$c]/$nplayfile"
         if($fpermission);
      chmod oct($fpermission), "$sepdir[$c]/$cplayfile"
         if($fpermission && $cue > 0);
      $trackoffsetflag = 0;

      if($cue > 0 and $c == $#coder and $wav == 1) {
         open(CLST, "$sepdir[$c]/$cplayfile") or
            print "Can't open $sepdir[$c]/$cplayfile! $!\n";
         @cuelist = <CLST>;
         close(CLST);
         foreach(@cuelist) {
            s/\s$suffix[$c]$/ WAVE/i;
            s/\.$suffix[$c]/.wav/;
         }
      }
   }
   # Recreate the wav-playlist if wavs aren't deleted.
   if($wav == 1) {
      my @mp3s = @playlist;
      $_ =~ s/\.suffix$/\.wav/i foreach (@mp3s);
      $_ =~ s/^Sepdir/$wavdir/ foreach (@mp3s);
      $nplayfile = $playfile;
      $nplayfile = change_case($nplayfile, "t");
      $nplayfile =~ s/\.m3u$/ - wav\.m3u/
         if($underscore == 0);
      $nplayfile =~ s/\.m3u$/_-_wav\.m3u/
         if($underscore == 1);
      open(PLST, ">$wavdir/$nplayfile") or
         print "Can't open $wavdir/$nplayfile! $!\n";
      print PLST "$_\n" foreach(@mp3s);
      close(PLST);
      if($cue > 0) {
         $cplayfile = $nplayfile;
         $cplayfile =~ s/m3u$/cue/;
         open(CLST, ">$wavdir/$cplayfile") or
         print "Can't open $wavdir/$cplayfile! $!\n";
         foreach(@cuelist) {
            print CLST "$_";
         }
         close(CLST);
      }
      chmod oct($fpermission), "$wavdir/$nplayfile"
         if($fpermission);
      chmod oct($fpermission), "$wavdir/$cplayfile"
         if($fpermission and $cue > 0);
   }
}
########################################################################
#
# Create a default or manual track list.
#
sub create_deftrack {
# Let operator chose to use default names or enter them manually.
# Do not ask if we come form CDDB submission, i.e. index == 0,
# or if $interaction == 0, then $index == 1.
   my ($i, $j, $index) = (0,1,@_);
   my ($album, $artist);

   my $tracks = substr($cddbid, 6);
   $tracks = hex($tracks);

   $album = clean_all($album_utf8) if(defined $cd{title});
   $artist = clean_all($artist_utf8) if(defined $cd{artist});

   # Preselect answer if no interaction requested.
   $index = 1 if($interaction == 0);

   while($index !~ /^[0-1]$/ ) {
      print "\nThis CD shall be labeled with:\n\n";
      print "1: Default album, artist and track names\n\n";
      print "0: Manual input\n\nChoose [0-1]: (0) ";
      $index = <STDIN>;
      chomp $index;
      $index = 0 unless($index);
      print "\n";
   }
   # Create default tracklist and cd-hash.
   # NOTE: here we define an additional key: revision, which does not
   # exist if %cd is filled by CDDB_get. If this key exists we know
   # that it is a new entry.
   if($index == 1) {
      $artist = "Unknown Artist";
      $album = "Unknown Album";
      %cd = (
         artist => $artist,
         title => $album,
         cat => $categ,
         genre => $genre,
         id => $cddbid,
         revision => 0,
         year => $year,
      );
      while($i < $tracks) {
         $j = $i + 1;
         $j = "0" . $j if($j < 10);
         $cd{track}[$i] = "Track " . "$j";
         ++$i;
      }
      $cddbsubmission = 0;
   }
   # Create manual tracklist.
   elsif($index == 0) {
      # In case of CDDB resubmission
      if(defined $cd{artist}) {
         print "\n   Artist ($artist): ";
      }
      # In case of manual CDDB entry.
      else {
         print "\n   Artist : ";
      }
      $artist = <STDIN>;
      chomp $artist;
      # If CDDB entry confirmed, take it.
      if(defined $cd{artist} && $artist eq "") {
         $artist = $artist_utf8;
      }
      # If CDDB entry CHANGED, submission OK.
      elsif(defined $cd{artist} && $artist ne "") {
         $cddbsubmission = 1;
         $cd{artist} = $artist;
         $artist_utf8 = $artist;
      }
      if($artist eq "") {
         $artist = "Unknown Artist";
         $cddbsubmission = 0;
      }
      if(defined $cd{title}) {
         print "\n   Album ($album): ";
      }
      else {
         print "\n   Album : ";
      }
      $album = <STDIN>;
      chomp $album;
      while($year !~ /^\d{4}$/) {
         if(defined $cd{year}) {
            print "\n   Year ($year): ";
         }
         else {
            print "\n   year : ";
         }
         $year = <STDIN>;
         chomp $year;
         last if($year eq "");
      }
      # If CDDB entry confirmed, take it.
      if(defined $cd{title} && $album eq "") {
         $album = $album_utf8;
      }
      # If CDDB entry CHANGED, submission OK.
      elsif(defined $cd{title} && $album ne "") {
         $cddbsubmission = 1;
         $cd{title} = $album;
         $album_utf8 = $album;
      }
      if($album eq "") {
         $album = "Unknown Album";
         $cddbsubmission = 0;
      }
      %cd = (
         artist => $artist,
         title => $album,
         cat => $categ,
         genre => $genre,
         id => $cddbid,
         revision => 0,
         year => $year,
      ) unless(defined $cd{title});
      print "\n";
      $i = 1;
      while($i <= $tracks) {
         if(defined $cd{track}[$i-1]) {
            printf("   Track %02d (%s): ", $i + $trackoffset, $tracktags[$i-1]);
         }
         else {
            printf("   Track %02d: ", $i + $trackoffset);
         }
         my $tracktag = <STDIN>;
         chomp $tracktag;
         $tracktag = clean_all($tracktag);
         my $track = $tracktag;
         $track = clean_name($track);
         $track = clean_chars($track) if($chars);
         $track = change_case($track, "t");
         $track =~ s/ /_/g if($underscore == 1);
         # If CDDB entry confirmed, take and replace it in tracklist.
         if(defined $cd{track}[$i-1] && $track ne "") {
            splice @tracklist, $i-1, 1, $track;
            splice @tracktags, $i-1, 1, $tracktag;
            $cddbsubmission = 1;
         }
         elsif(!$cd{track}[$i-1] && $track eq "") {
            $track = "Track " . sprintf("%02d", $i);
            $cddbsubmission = 0;
         }
         # Fill the "empty" array @{$cd{track}}.
         push(@{$cd{track}}, "$track");
         $i++;
      }
      print "\n";
   }
   else {
      # I don't like die, but I don't like if-loops without else.
      # This should not happen because of previous while-loop!
      die "Choose 0 or 1!\n\n";
   }
   return;
}
########################################################################
#
# Read the CD and generate a TOC with DiscID, track frames and total
# length. Then prepare CDDB-submission with entries from @tracklist.
#
sub pre_subm {
   my($check,$i,$ans,$genreno,$line,$oldcat,$subject) = (0,0);

   my $tracks = $#framelist;
   my $totals = int($framelist[$#framelist] / 75);

   my $album = clean_all($album_utf8);
   my $artist = clean_all($artist_utf8);

   my $revision = get_rev() unless($cd{discid});
   if($revision) {
      # TODO: if submission fails, set revision back.
      $revision++;
      print "Revision is set to $revision.\n" if($verbose > 4);
   }
   elsif(defined $cd{revsision}) {
      $revision = $cd{revision};
   }
   else {
      $revision = 0;
   }

   # Check for CDDB ID vs CD ID problems.
   if($cddbid ne $cd{id} && defined $cd{id}) {
      print "\nObsolet warning: CDID ($cddbid) is not identical to ";
      print "CDDB entry ($cd{id})!";
      print "\nYou might get a collision error. Try anyway!\n";
      $revision = 0;
   }
   # Questioning to change CDDB entries and ask to fill missing fields.
   if(defined $cd{year} && $year ne "") {
      $year = get_answ("year",$year);
   }
   if(!$year) {
      while($year !~ /^\d{4}$| / || !$year ) {
      print "\nPlease enter the year (or none): ";
      $year = <STDIN>;
      chomp $year;
      $cd{year} = $year;
      last if(!$year);
      $cddbsubmission = 1;
      }
   }
   if($cd{year}) {
      $cddbsubmission = 1 unless($year eq $cd{year});
   }
   else {
      $cddbsubmission = 1;
   }
   # Ask if CDDB category shall be changed and check if done;
   # $categ will be an empty string if user wants to change it.
   $oldcat = $categ;
   if($cd{cat} && $categ) {
      $categ = get_answ("CDDB category",$categ);
   }

   my @categ = ();
   my @categories = (
      "blues",  "classical", "country", "data",
      "folk",   "jazz",      "misc",    "newage",
      "reggae", "rock",      "soundtrack"
   );

   # If data is from musicbrainz, don't ask to check category and simply
   # prepare a CD-DB file with category musicbrainz. User will have to
   # find an unused category and submit the entry manually.
   if(!$categ && !$cd{discid} && $submission != 0) {
      print "Shall Ripit check for available categories?",
               " [y/n] (y) ";
      $ans = <STDIN>;
      chomp $ans;
      if($ans eq "") {
         $ans = "y";
      }
      if($ans =~ /^y/) {
         print "\n\nAvailable categories:\n";
         foreach (@categories) {
            my $templines = "";
            my $source = "http://www.freedb.org/freedb/" .
                          $_ . "/" . $cddbid;
            $templines = LWP::Simple::get($source);
            # Question: what is wrong that I need to put a \n in the print
            # command to force perl to print right away, and not to print
            # the whole bunch only when the foreach-loop is done???
            if($templines) {
               push @categ, $_;
            }
            else {
               print "   $_\n"
            }
         }
         if($categ[10]) {
            print "\nAll 11 categories are used, bad luck!";
            print "\nSave the file locally with --archive!\n";
            print "\nUse one of the following categories:";
            print "\nblues, classical, country, data, folk";
            print "\njazz, misc, newage, reggae, rock, soundtrack\n";
            $cddbsubmission = 0;
         }

         # Check if the $categ variable is correct.
         while($categ !~ m/^blues$|^classical$|^country$|^data$|^folk$|
                          |^jazz$|^newage$|^reggae$|^rock$|^soundtrack$|
                          |^misc$/ ) {
            print "\nPlease choose one of the available CDDB categories: "
               if($categ[10]);
            print "\nPlease choose one of the categories: "
               unless($categ[10]);
            $categ = <STDIN>;
            chomp $categ;
         }
         $cddbsubmission = 1 unless($categ eq $cd{cat});
      }
   }
   elsif($cd{discid}) {
      # Are we sure to use this condition to prevent further submission?
      $categ = "musicbrainz";
      $cddbsubmission = 0;
   }
   # If one changes category for a new submission, set Revision to 0.
   if($oldcat ne $categ && defined $cd{cat}) {
      $revision = 0;
   }
   # Remind the user if genre is not ID3v2 compliant even if Lame is
   # not used! Reason: There should be no garbage genres in the DB.
   # If Lame is used, genre has already been checked!
   if($lameflag != 1 && defined $genre) {
      ($genre,$genreno) = check_genre($genre);
      $cddbsubmission = 1 unless($genre eq $cd{genre});
   }
   # Do not to ask if genre has been passed from command line, except if
   # looping and one migt want to change the genre.
   if($loop > 0) {
      # Ask
      $genre = get_answ("genre", $genre);
   }
   else {
      unless($pgenre) {
         $genre = get_answ("genre", $genre);
      }
   }
   unless($genre) {
      print "\nPlease enter a valid CDDB genre (or none): ";
      $genre = <STDIN>;
      chomp $genre;
      $cd{genre} = $genre;
      # Allow to submit no genre! Else check it!
      if($genre) {
         $genre =~ s/[\015]//g;
         ($genre, $genreno) = check_genre($genre);
      }
   }
   $cddbsubmission = 1 unless($genre eq $cd{'genre'});
   my $dtitle = $artist . " / " . $album;
   substr($dtitle, 230, 0, "\nDTITLE=") if(length($dtitle) > 250);
   substr($dtitle, 460, 0, "\nDTITLE=") if(length($dtitle) > 500);

   # Start writing the CDDB submission.
   open(TOC, ">$homedir/cddb.toc")
      or print "Can not write to cddb.toc $!\n";
   print TOC "# xmcd CD database generated by RipIT\n#\n",
             "# Track frame offsets:\n";
   $i = 0;
   foreach (@framelist) {
      print TOC "# $_\n" if($i < $#framelist);
      $i++;
   }
   print TOC "#\n# Disc length: $totals seconds\n#\n";
   if(!$cd{discid} && $archive == 1 && $categ ne "musicbrainz") {
      my $source = "http://www.freedb.org/freedb/" . $categ . "/" . $cddbid;
      print "Will try to get <$source>.\n";
      my $templines = LWP::Simple::get($source);
      my @templines = split(/\n/, $templines);
      chomp($revision = join('', grep(s/^\s*#\sRevision:\s(\d+)/$1/, @templines)));
      $revision++ if($revision =~ /^\d+/);
      $revision = 0 unless($revision =~ /^\d+/);
      print "\nRevision number set to $revision.\n" if($verbose >= 4);
   }
   print TOC "# Revision: $revision\n";
   my $time = sprintf("%02d:%02d", sub {$_[2], $_[1]}->(localtime));
   my $date = sprintf("%04d-%02d-%02d",
      sub {$_[5]+1900, $_[4]+1, $_[3]}->(localtime));
   $date = $date . " at " . $time;
   print TOC "# Submitted via: RipIT $version ";
   print TOC "www.suwald.com/ripit/ripit.html on $date\n";
   print TOC "#\n";
   print TOC "DISCID=$cddbid\n";
   print TOC "DTITLE=$dtitle\n";
   print TOC "DYEAR=$year\n";
   if(defined $genre) {
      print TOC "DGENRE=$genre\n";
   }
   elsif($genre eq "" && defined $categ) {
      print TOC "DGENRE=$categ\n";
   }
   $i = 0;
   foreach (@tracktags) {
      # Don't alter the real track tags!
      my $line = $_;
      my $limit = 230;
      my $j = $i;
      $j += $trackoffset if($trackoffset > 0);
      while(length($line) > $limit) {
         substr($line, $limit, 0, "\nTTITLE$j=");
         $limit += 230;
      }
      print TOC "TTITLE$j=$line\n";
      ++$i;
   }

   my @comment = extract_comm;
   my $commentest = "@comment";
   if($commentest) {
      $ans = "x";
      $check = 0;
      print "Confirm (Enter), delete or edit each comment line ";
      print "(c/d/e)!\n";
      foreach (@comment) {
         chomp($_);
         s/\n//g;
         next if($_ eq "");
         while($ans !~ /^c|^d|^e/) {
            print "$_ (c/d/e): ";
            $ans = <STDIN>;
            chomp $ans;
            if($ans eq "") {
               $ans = "c";
            }
         }
         if($ans =~ /^c/ || $ans eq "") {
            print TOC "EXTD=$_\\n\n";
            $check = 1;
         }
         elsif($ans =~ /^e/) {
            print "Enter a different line: \n";
            my $ans = <STDIN>;
            chomp $ans;
            substr($ans, 230, 0, "\nEXTD=") if(length($ans) > 250);
            substr($ans, 460, 0, "\nEXTD=") if(length($ans) > 500);
            print TOC "EXTD=$ans\\n\n";
            $cddbsubmission = 1;
            $check = 1;
         }
         else {
            # Don't print the line.
            $cddbsubmission = 1;
         }
         $ans = "x";
      }
      $line = "a";
      while(defined $line) {
         print "Do you want to add a line? (Enter for none or type!): ";
         $line = <STDIN>;
         chomp $line;
         $cddbsubmission = 1 if($line ne "");
         last if(!$line);
         substr($line, 230, 0, "\nEXTD=") if(length($line) > 250);
         substr($line, 460, 0, "\nEXTD=") if(length($line) > 500);
         print TOC "EXTD=$line\\n\n";
         $check = 1;
      }
      # If all lines have been deleted, add an empty EXTD line!
      if($check == 0) {
         print TOC "EXTD=\n";
      }
   }
   # If there are no comments, ask to add some.
   elsif(!$comment[0]) {
      $line = "a";
      my $linecn = 0;
      while(defined $line) {
         print "Please enter a comment line (or none): ";
         $line = <STDIN>;
         chomp $line;
         $cddbsubmission = 1 if($line ne "");
         substr($line, 230, 0, "\nEXTD=") if(length($line) > 250);
         substr($line, 460, 0, "\nEXTD=") if(length($line) > 500);
         print TOC "EXTD=$line\n" if($linecn == 0);
         print TOC "EXTD=\\n$line\n" if($linecn != 0);
         $linecn++;
         # This line has to be written, so break the
         # while loop here and not before, as above.
         last if(!$line);
      }
   }
   else {
      print TOC "EXTD=\n";
   }

   # Extract the track comment lines EXTT.
   my @trackcom = grep(/^EXTT\d+=/, @{$cd{raw}});
   @trackcom = grep(s/^EXTT\d+=//, @trackcom);
   foreach (@trackcom) {
      chomp($_);
      s/\n//g;
      s/[\015]//g;
   }
   $ans = get_answ('Track comment','existing ones');
   if($ans eq "") {
      $i = 0;
      while($i < $tracks) {
         my $track;
         if($trackcom[$i]) {
            printf("   Track comment %02d (%s):", $i+1, $trackcom[$i]);
         }
         else {
            printf("   Track comment %02d: ", $i+1);
         }
         $track = <STDIN>;
         chomp $track;
         my $j = $i;
         $j += $trackoffset if($trackoffset > 0);
         substr($track, 230, 0, "\nEXTT$j=") if(length($track) > 250);
         substr($track, 460, 0, "\nEXTT$j=") if(length($track) > 500);

         # If CDDB entry confirmed, take and replace it in tracklist.
         if(defined $trackcom[$i] && $track eq "") {
            print TOC "EXTT$j=$trackcom[$i]\n";
         }
         elsif(defined $trackcom[$i] && $track ne "") {
            print TOC "EXTT$j=$track\n";
            $cddbsubmission = 1;
         }
         elsif($track ne "") {
            print TOC "EXTT$j=$track\n";
            $cddbsubmission = 1;
         }
         else {
            print TOC "EXTT$j=\n";
         }
         $i++;
      }
   }
   elsif(@trackcom) {
      $i = 0;
      my $j = $i;
      $j += $trackoffset if($trackoffset > 0);
      foreach (@tracklist) {
         print TOC "EXTT$j=$trackcom[$i]\n";
         ++$i;
      }
   }
   else {
      $i = 0;
      my $j = $i;
      $j += $trackoffset if($trackoffset > 0);
      foreach (@tracklist) {
         print TOC "EXTT$j=\n";
         ++$i;
      }
   }

   # Extract the playorder line.
   my @playorder = grep(/^PLAYORDER=/, @{$cd{raw}});
   @playorder = grep(s/^PLAYORDER=//, @playorder);
   if(@playorder) {
      my $playorder = $playorder[0];
      chomp $playorder;
      print TOC "PLAYORDER=$playorder\n";
   }
   else {
      print TOC "PLAYORDER=\n";
   }

   # If no connection to the internet do not submit.
   if($submission == 0) {
      $cddbsubmission = 0;
   }
   # If we came from MB do not submit.
   elsif($cd{discid}) {
      $cddbsubmission = 0;
   }

   # Only print non regular info to the toc if no submission will happen.
   if($cddbsubmission == 0) {
      print TOC "CDINDEX=", $cd{discid}, "\n" if($cd{discid});
      print TOC "MBREID=", $cd{mbreid}, "\n" if($cd{mbreid});
      print TOC "ASIN=", $cd{asin}, "\n" if($cd{asin});
      print TOC "DGID=", $cd{dgid}, "\n" if($cd{dgid});
      print TOC "BARCODE=", $cd{barcode}, "\n" if($cd{barcode});
      print TOC "CATALOG=", $cd{catalog}, "\n" if($cd{catalog});
      print TOC "RELDAT=", $cd{reldate}, "\n" if($cd{reldate});
      print TOC "LANG=", $cd{language}, "\n" if($cd{language});
      print TOC "DISCNO=", $cd{discno}, "\n" if($cd{discno});
   }
   close(TOC);

   # Copy the *edited* CDDB file if variable set to the ~/.cddb/
   # directory.
   if($archive == 1 && $cddbsubmission != 2) {
      log_system("mkdir -m 0755 -p \"$homedir/.cddb/$categ\"")
         or print
         "Can not create directory \"$homedir/.cddb/$categ\": $!\n";
      log_system(
         "cp \"$homedir/cddb.toc\" \"$homedir/.cddb/$categ/$cddbid\""
         )
         or print
         "Can not copy cddb.toc to directory ",
         "\"$homedir/.cddb/$categ/$cddbid\": $!\n";
      print "Saved file $cddbid in \"$homedir/.cddb/$categ/\"";
   }
   print "\n";

   if($cddbsubmission == 1) {
      my $ans = "x";
      while($ans !~ /^y$|^n$/) {
         print "Do you really want to submit your data to freeDB.org?",
               " [y/n] (y) ";
         $ans = <STDIN>;
         chomp $ans;
         if($ans eq "") {
            $ans = "y";
         }
      }
      if($ans =~ /^y/) {
         $cddbsubmission = 1;
      }
      else{
         $cddbsubmission = 0;
      }
   }
   if($cddbsubmission == 1) {
      while($mailad !~ /.@.+[.]./) {
         print "\nReady for submission, enter a valid return ";
         print "e-mail address: ";
         $mailad = <STDIN>;
         chomp $mailad;
      }

      open TOC, "cat \"$homedir/cddb.toc\" |"
         or die "Can not open file $homedir/cddb.toc $!\n";
      my @lines = <TOC>;
      close(TOC);

      $subject = "cddb " . $categ . " " . $cddbid;
      open(MAIL, "|/usr/sbin/sendmail $mailopt -r $mailad")
         or print "/usr/sbin/sendmail not installed? $!\n";

      # Generate the mail-header and add the toc-lines.
      print MAIL "From: $mailad\n";
      print MAIL "To: freedb-submit\@freedb.org\n";
#      print MAIL "To: test-submit\@freedb.org\n";
      print MAIL "Subject: $subject\n";
      print MAIL "MIME-Version: 1.0\n";
      print MAIL "Content-Type: text/plain; charset=$charset\n";
      foreach (@lines) {
         print MAIL $_;
      }
      close(MAIL);
      print "Mail exit status not zero: $?" if($?);
      print "CDDB entry submitted.\n\n" unless($?);
      unlink("$homedir/cddb.toc");
   }
   elsif($cddbsubmission == 2) {
      print "\n CDDB entry created and saved in \$HOME, but not send, ";
      print "because no changes";
      print "\n were made! Please edit and send it manually to ";
      print "freedb-submit\@freedb.org";
      print "\n with subject: cddb ";
      my $pcateg = $categ;
      $pcateg = "category" if($categ =~ /musicbrainz/);
      print "$pcateg $cddbid\n";
      print " where category is one of the 11 valid freedb categories.\n"
         if($categ =~ /musicbrainz/);
      print "\n";
      sleep (4);
   }
   else {
      print "\n CDDB entry saved in your home directory, but not send,";
      print "\n please edit it and send it manually to:";
      print "\n freedb-submit\@freedb.org with subject:";
      print "\n cddb ";
      my $pcateg = $categ;
      $pcateg = "category" if($categ =~ /musicbrainz/);
      print "$pcateg $cddbid\n";
      print " where category is one of the 11 valid freedb categories.\n"
         if($categ =~ /musicbrainz/);
      print "\n";
   }
}
########################################################################
#
# Check if genre is correct.
#
sub check_genre {
   my $genre = $_[0];
   my $genreno = "";
   my $genrenoflag = 1;

   $genre = "  " if($genre eq "");

   # If Lame is not used, don't die if ID3v2-tag is not compliant.
   if($lameflag == 0) {
      unless(log_system(
         "lame --genre-list 2>&1 | grep -i \" $genre\$\" > /dev/null ")) {
         print "Genre $genre is not ID3v2 compliant!\n"
            if($verbose >= 1);
         print "Continuing anyway!\n\n" if($verbose >= 1);
         chomp($genreno = "not ID3v2 compliant!\n");
      }
      return ($genre,$genreno);
   }

   # If Lame is not installed, don't loop for ever.
   if($lameflag == -1) {
      chomp($genreno = "Unknown.\n");
      return ($genre,$genreno);
   }

   # Check if (similar) genre exists. Enter a new one with interaction,
   # or take the default one.
   while(!log_system(
      "lame --genre-list 2>&1 | grep -i \"$genre\" > /dev/null ")) {
      print "Genre $genre is not ID3v2 compliant!\n" if($verbose >= 1);
      if($interaction == 1) {
         print "Use \"lame --genre-list\" to get a list!\n";
         print "\nPlease enter a valid CDDB genre (or none): ";
         $genre = <STDIN>;
         chomp $genre;
         $cd{genre} = $genre;
      }
      else {
         print "Genre \"Other\" will be used instead!\n"
            if($verbose >= 1);
         $genre = "12 Other";
      }
   }

   if($genre eq "") {
      return;
   }
   elsif($genre =~ /^\d+$/) {
      chomp($genre = `lame --genre-list 2>&1 | grep -i \' $genre \'`);
   }
   else {
      # First we want to be sure that the genre from the DB, which might
      # be "wrong", e.g. wave (instead of Darkwave or New Wave) or synth
      # instead of Synthpop, will be correct. Put the DB genre to ogenre
      # and get a new right-spelled genre... Note, we might get several
      # possibilities, e.g. genre is Pop, then we get a bunch of
      # "pop-like" genres!
      # There will be a line break, if multiple possibilities found.
      my $ogenre = $genre;
      chomp($genre = `lame --genre-list 2>&1 | grep -i \'$genre\'`);
      # Second we want THE original genre, if it precisely exists.
      chomp(my $testgenre = `lame --genre-list 2>&1 | grep -i \'\^... $ogenre\$\'`);
      $genre = $testgenre if($testgenre);
      # If we still have several genres:
      # Either let the operator choose, or if no interaction, take
      # default genre: "12 Other".
      if($genre =~ /\n/ && $interaction == 1) {
         print "More than one genre possibility found:\n";
         my @list = split(/\n/, $genre);
         my ($i, $j) = (0,1);
         while($i > $#list+1 || $i == 0) {
            # TODO: Here we should add the possibility to choose none!
            # Or perhaps to go back and choose something completely
            # different.
            foreach (@list) {
               printf(" %2d: $_ \n", $j);
               $j++;
            }
            $j--;
            print "\nChoose [1-$j]: ";
            $i = <STDIN>;
            chomp $i;
            $j = 1;
         }
         chomp($genre = $list[$i-1]);
      }
      # No interaction! Take the first or default genre!
      elsif($genre =~ /\n/ && $interaction != 1 && $lameflag == 1) {
         $genre = "12 Other" if($genre eq "");
         $genre =~ s/\n.*//;
      }
      # The genre is not Lame compliant, and we do not care about,
      # because Lame is not used. Set the genre-number-flag to 0 to
      # prevent genre-number-extracting at the end of the subroutine.
      elsif($lameflag != 1) {
         $genre = $ogenre;
         $genrenoflag = 0;
      }
      chomp $genre;
   }

   # Extract genre number.
   if($genre ne "" && $genrenoflag == 1) {
      $genre =~ s/^\s*//;
      my @genre = split(/ /, $genre);
      $genreno = shift(@genre);
      $genre = "@genre";
   }
   return ($genre,$genreno);
}
########################################################################
#
# Check mirrors. Need to be tested from time to time, which ones are up.
#
#  http://at.freedb.org:80/~cddb/cddb.cgi working
#  http://au.freedb.org:80/~cddb/cddb.cgi not working
#  http://ca.freedb.org:80/~cddb/cddb.cgi working
#  http://ca2.freedb.org:80/~cddb/cddb.cgi working
#  http://de.freedb.org:80/~cddb/cddb.cgi working
#  http://es.freedb.org:80/~cddb/cddb.cgi working
#  http://fi.freedb.org:80/~cddb/cddb.cgi working
#  http://freedb.freedb.org:80/~cddb/cddb.cgi not working
#  http://ru.freedb.org:80/~cddb/cddb.cgi working
#  http://uk.freedb.org:80/~cddb/cddb.cgi working
#  http://us.freedb.org:80/~cddb/cddb.cgi not working
#
#
sub check_host {
#   while($mirror !~ m/^freedb$|^at$|^au$|^ca$|^es$|^fi$|
#                     |^fr$|^jp$|^jp2$|^ru$|^uk$|^uk2$|^us$/) {
   while($mirror !~ m/^freedb$|^at$|^au$|^bg$|^ca$|^es$|^fi$|
                     |^lu$|^no$|^uk$|^us$/) {
      print "host mirror ($mirror) not valid!\nenter freedb, ",
            "at, au, ca, es, fi, fr, jp, jp2, ru, uk, uk2 or us: ";
      $mirror = <STDIN>;
      chomp $mirror;
   }
}
########################################################################
#
# Answer to question.
#
sub get_answ {
   my $ans = "x";
   while($ans !~ /^y|^n/) {
      print "Do you want to enter a different ".$_[0]." than ".$_[1];
      print "? [y/n], (n): ";
      $ans = <STDIN>;
      chomp $ans;
      if($ans eq "") {
         $ans = "n";
      }
   }
   if($ans =~ /^y/) {
      return "";
   }
   return $_[1];
}
########################################################################
#
# Check quality passed from command line for lame, oggenc, flac, faac.
#
sub check_quality {
   #
   # Prevent warnings.
   @pquality = defined unless(@pquality);
   #
   # Remember, if the quality is defined via -q/--quality switch
   # on the command line, the array consists of a comma separated
   # string in the first entry only!
   #
   if($pquality[0] =~ /\d/ or "@pquality" =~ "off") {  # new in 4.0
      # Why this joining and splitting? Because the whole string is in
      # $quality[0]! But why joining? Because we can come from CLI! In
      # this case we need to make it identical to the way it comes from
      # config file, i.e. as comma separated string in the first entry.
      @quality = split(/,/, join(',', @pquality));
   }
   else {
      my @clean_q = ();
      foreach (@quality) {
         next unless(defined $_);
         push(@clean_q, $_);
      }
      if("@clean_q" eq "5 3 5 100 0 5") {
         return;
      }
   }
   # If no coder-array has been passed, we do not know to which encoder
   # each quality-entry belongs to. NOTE, we've not yet read the config.
   # So we need to read the config file to check if there is an unusual
   # order of encoders. In this way, this subroutine will ask the
   # correct questions and not mess up the encoders if qualities are
   # wrong, supposing the operator is aware about an unusual order!
   if(!@pcoder && -r "$ripdir") {
      open(CONF, "$ripdir");
      my @conflines = <CONF>;
      close(CONF);
      @pcoder = grep(s/^coder=//, @conflines) unless(@pcoder);
      chomp @pcoder;
      if($pcoder[0] =~ /^\d/) {
         @coder = split(/,/, join(',',@pcoder));
      }
   }
   # Actually check only those qualities needed, i.e. for chosen
   # encoders.
   # NOTE again: the $qualame etc. variables hold the string needed for
   # the config, it might be a comma separated string. When passing
   # commands, we should not use them, but things like "$quality[$c]"
   # instead!
   my $corrflag = 0;
   $qualame = "";
   $qualoggenc = "";
   $quaflac = "";
   $quafaac = "";
   $quamp4als = "";
   $quamuse = "";
   for(my $c=0; $c<=$#coder; $c++) {
      if($coder[$c] == 0 && !defined($quality[$c])) {
         $quality[$c] = 5; # prevent warnings.
      }
      elsif($coder[$c] == 0 && $quality[$c] ne "off") {
         $quality[$c] = 5 unless($quality[$c] =~ /\d/);
         while($quality[$c] > 9) {
            print "\nThe quality $quality[$c] is not valid for Lame!",
                  "\nPlease enter a different quality (0 = best),",
                  " [0-9]: ";
            $quality[$c] = <STDIN>;
            chomp $quality[$c];
         }
         $qualame .= ";" . $quality[$c];
      }
      elsif($coder[$c] == 0 && $quality[$c] eq "off") {
         $qualame .= ";" . $quality[$c];
      }
      # Done with lame, do the other encoders.
      if($coder[$c] == 1 && !defined($quality[$c])) {
         $quality[$c] = 3; # prevent warnings.
      }
      elsif($coder[$c] == 1 && $quality[$c] ne "off") {
         $quality[$c] = 3 unless($quality[$c] =~ /\d/);
         while($quality[$c] > 10 || $quality[$c] == 0) {
            print "\nThe quality $quality[$c] is not valid for Oggenc!",
                  "\nPlease enter a different quality (10 = best),",
                  " [1-10]: ";
            $quality[$c] = <STDIN>;
            chomp $quality[$c];
         }
         $qualoggenc .= "," . $quality[$c];
      }
      elsif($coder[$c] == 1 && $quality[$c] eq "off") {
         $qualoggenc .= "," . $quality[$c];
      }
      if($coder[$c] == 2 && !defined($quality[$c])) {
         $quality[$c] = 5; # prevent warnings.
      }
      elsif($coder[$c] == 2 && $quality[$c] ne "off") {
         $quality[$c] = 5 unless($quality[$c] =~ /\d/);
         while($quality[$c] > 8) {
            print "\nThe compression level $quality[$c] is not valid ",
                  "for Flac!",
                  "\nPlease enter a different compression level ",
                  "(0 = lowest), [0-8]: ";
            $quality[$c] = <STDIN>;
            chomp $quality[$c];
         }
         $quaflac = $quaflac . "," . $quality[$c];
      }
      elsif($coder[$c] == 2 && $quality[$c] eq "off") {
         $quaflac .= "," . $quality[$c];
      }
      if($coder[$c] == 3 && !defined($quality[$c])) {
         $quality[$c] = 100; # prevent warnings.
      }
      elsif($coder[$c] == 3 && $quality[$c] ne "off") {
         $quality[$c] = 100 unless($quality[$c] =~ /\d/);
         while($quality[$c] > 500 || $quality[$c] < 10) {
            print "\nThe quality $quality[$c] is not valid for Faac!",
                  "\nPlease enter a different quality (500 = max), ",
                  "[10-500]: ";
            $quality[$c] = <STDIN>;
            chomp $quality[$c];
         }
         $quafaac .= "," . $quality[$c];
      }
      elsif($coder[$c] == 3 && $quality[$c] eq "off") {
         $quafaac .= "," . $quality[$c];
      }
      if($coder[$c] == 4 && !defined($quality[$c])) {
         $quality[$c] = 0; # prevent warnings.
      }
      elsif($coder[$c] == 4 && $quality[$c] ne "off") {
         $quality[$c] = 0 unless($quality[$c] =~ /\d/);
         # Any info about mp4als "qualities", i. e. compression levels?
         $quamp4als .= "," . $quality[$c];
      }
      elsif($coder[$c] == 4 && $quality[$c] eq "off") {
         $quamp4als .= "," . $quality[$c];
      }
      if($coder[$c] == 5 && !defined($quality[$c])) {
         $quality[$c] = 5; # prevent warnings.
      }
      elsif($coder[$c] == 5 && $quality[$c] ne "off") {
         $quality[$c] = 5 unless($quality[$c] =~ /\d/);
         while($quality[$c] > 10 || $quality[$c] < 0) {
            print "\nThe quality $quality[$c] is not valid for $musenc!",
                  "\nPlease enter a different quality (10 = max), ",
                  "[0-10]: ";
            $quality[$c] = <STDIN>;
            chomp $quality[$c];
         }
         $quamuse .= "," . $quality[$c];
      }
      elsif($coder[$c] == 5 && $quality[$c] eq "off") {
         $quamuse .= "," . $quality[$c];
      }
      if($coder[$c] == 6 && !defined($quality[$c])) {
         $quality[$c] = " "; # prevent warnings.
      }
      if($coder[$c] == 7 && !defined($quality[$c])) {
         $quality[$c] = " "; # prevent warnings.
      }
   }
   $qualame =~ s/^,//;
   $qualoggenc =~ s/^,//;
   $quaflac =~ s/^,//;
   $quafaac =~ s/^,//;
   $quamuse =~ s/^,//;
   # Small problem if only option --savenew is used, with no other
   # option at all. Then, qualame has default value (because Lame is
   # default encoder), but all other qualities are empty!
   $qualoggenc = 3 unless($qualoggenc);
   $quaflac = 5 unless($quaflac);
   $quafaac = 100 unless($quafaac);
   $quamp4als = 0 unless($quamp4als);
   $quamuse = 5 unless($quamuse);
   # NOTE: corrections have been done on quality array, not pquality.
   # If pquality was passed, we need to apply corrections and save it
   # the same way as if it had been passed on command line.
   if($pquality[0]) {
      my $pquality = join(',', @quality);
      $pquality =~ s/(,\s)*$//;
      @pquality = ();
      $pquality[0] = $pquality;
   }
}
########################################################################
#
# Check bitrate for Lame only if vbr is wanted.
#
sub check_vbrmode {
   while($vbrmode ne "new" && $vbrmode ne "old") {
      print "\nFor vbr using Lame choose *new* or *old*! (new): ";
      $vbrmode = <STDIN>;
      chomp $vbrmode;
      $vbrmode = "new" if($vbrmode eq "");
   }
}
########################################################################
#
# Check preset for Lame only.
#
sub lame_preset {
   if($vbrmode eq "new") {
      $preset = "fast " . $preset;
   }
}
########################################################################
#
# Check if there is an other than $cddev which has a CD if no --device
# option was given.
#
sub check_cddev {
   # Try to get a list of possible CD devices.
   open(DEV, "/etc/fstab");
   my @dev = <DEV>;
   close(DEV);
   @dev = grep(/^\s*\/dev/, @dev);
   @dev = grep(!/^\s*\/dev\/[f|h]d/, @dev);
   @dev = grep(!/sd/, @dev);
   my @devlist = ();
   foreach (@dev) {
      my @line = split(/\s/, $_);
      chomp $line[0];
      push(@devlist, $line[0]) unless($line[0] =~ /by-id/);
   }
   # First check some default addresses.
   if(open(CD, "$cddev")) {
      $cddev = $cddev;
      close(CD);
   }
   elsif(open(CD, "/dev/cdrecorder")) {
      $cddev = "/dev/cdrecorder";
      close(CD);
   }
   elsif(open(CD, "/dev/dvd")) {
      $cddev = "/dev/dvd";
      close(CD);
   }
   elsif(open(CD, "/dev/sr0")) {
      $cddev = "/dev/sr0";
      close(CD);
   }
   elsif(open(CD, "/dev/sr1")) {
      $cddev = "/dev/sr1";
      close(CD);
   }
   else {
      foreach (@devlist) {
         if(open(CD, "$_")) {
            $cddev = $_;
            chomp $cddev;
            close(CD);
         }
         else {
            # Condition added in 4.0, why should the $cddev be cleared
            # unconditionally?
            $cddev = "" unless($cddev =~ /\/dev\/.*/);
         }
      }
   }
   # On a notebook, the tray can't be closed automatically!
   # Print error message and retry detection.
   if($cddev eq "" && $rip > 0) {
      print "Is there a CD and the tray of the device closed?\n";
      print "Pausing 12 seconds.\n";
      sleep(12);
      foreach (@devlist) {
         if(open(CD, "$_")) {
            $cddev = $_;
            chomp $cddev;
            close(CD);
         }
      }
   }
   if($cddev eq "" && $rip > 0) {
      print "Could not detect CD device! The default /dev/cdrom ";
      print "device will be used.\n";
      $cddev = "/dev/cdrom";
   }
   return;
}
########################################################################
#
# Check bitrate if bitrate is not zero.
#
sub check_bitrate {
   while($bitrate !~ m/^32$|^40$|^48$|^56$|^64$|^80$|^96$|^112$|^128$|
                     |^160$|^192$|^224$|^256$|^320$|^off$/) {
      print "\nBitrate should be one of the following numbers or ";
      print "\"off\"! Please Enter";
      print "\n32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, ";
      print "256 or 320: (128) \n";
      $bitrate = <STDIN>;
      chomp $bitrate;
      if($bitrate eq "") {
         $bitrate = 128;
      }
   }
}
########################################################################
#
# Check protocol level for CDDB query.
#
sub check_proto {
   while($proto > 6) {
      print "Protocol level for CDDB query should be less-equal 6!\n";
      print "Enter an other value for protocol level (6): ";
      $proto =  <STDIN>;
      chomp $proto;
      $proto = 6 if($proto eq "");
   }
}
########################################################################
#
# Check and clean the coder array.
#
sub check_coder {

   # Reset $lameflag set by past invocation of check_coder() except if
   # lame is not installed ($lameflag == -1).
   $lameflag = 0 if($lameflag > 0);

   # Create encoder array if passed or read from config file.
   # Remember, if we come from reading the config file, the array
   # consists of a comma separated string in the first entry only!
   if(@pcoder) {
      @coder = split(/,/, join(',', @pcoder));
   }
   else {
      # This can happen because this subroutine is called before config
      # file is read! So @pcoder can be empty and @coder will be filled
      # with default value for Lame. Do we need this?
      @coder = split(/,/, join(',', @coder));
   }

   my @ffmpegsuf = ();
   if($ffmpegsuffix) {
      @ffmpegsuf = split(/,/, $ffmpegsuffix);
   }

   # Check if there is an entry > 7.
   for(my $c = 0; $c <= $#coder; $c++) {
      if($coder[$c] > 7) {
         die "Encoder number $coder[$c] does not yet exist, ",
             "please enter\n0 for Lame, 1 for Oggenc, 2 for Flac ",
             "3 for Faac,\n 4 for mp4als, 5 for Musepack, ",
             "6 for Wavpack or 7 for ffmpeg!\n\n";
         # TODO: splice that entry out, don't die!
      }
      $lameflag = 1 if($coder[$c] == 0);
      $oggflag = 1 if($coder[$c] == 1);
      $wvpflag = 1 if($coder[$c] == 6);
      $suffix[$c] = "mp3" if($coder[$c] == 0);
      $suffix[$c] = "ogg" if($coder[$c] == 1);
      $suffix[$c] = "flac" if($coder[$c] == 2);
      $suffix[$c] = "m4a" if($coder[$c] == 3);
      $suffix[$c] = "m4b" if($coder[$c] == 3 && $book == 1);
      $suffix[$c] = "als" if($coder[$c] == 4);
      $suffix[$c] = "mpc" if($coder[$c] == 5);
      $suffix[$c] = "wv" if($coder[$c] == 6);
      if($coder[$c] == 7) {
         $suffix[$c] = shift @ffmpegsuf;
      }
   }
   # Use comma separated string to write the encoder array to the
   # config file!
   $wcoder = join(',', @coder);
}
########################################################################
#
# Over or re-write the config file (depends on option savenew or save).
#
# New options step 10: Add description of new option to config file.
#
sub save_config {
   $confdir = "$homedir/.ripit" if($confdir eq "");
   log_system("mkdir -m 0755 -p $confdir")
      or die "Can not create directory $confdir: $!\n";
   # Remember: $ripdir is the full path including config file name.
   rename("$confdir/$confname","$confdir/$confname.old")
      if(-r "$confdir/$confname");
   open(CONF, "> $confdir/$confname")
      or die "Can not write to $confdir/$confname: $!\n";
   print CONF "
#####
#
# RipIT $version configuration file.
#
# For further information on ripit configuration / parameters
# and examples see the manpage or the README provided with ripit
# or type ripit --help .


#####
#
# Ripping device, permissions & path.
#

# cddevice: Define ripping device if other than /dev/cdrom.
# Default: /dev/cdrom

cddevice=$cddev

# scsidevice: Device name for special devices if the non ripping
# commands should be executed on a different device node. This might
# be useful for some old SCSI devices. If not set the cddevice will
# be used.
# Example: /dev/sr18
# Default: not set

scsidevice=$scsi_cddev

# output: Path for audio files. If not set, \$HOME will be used.
# Default: not set

output=$outputdir

# directory permissions: Permissions for directories.
# Default: 0755

dpermission=$dpermission

# file permissions: Permissions for sound and log files.
# If not set, uses the default system settings.
# Default: not set

fpermission=$fpermission


#####
#
# Ripping options.
#

# ripper: select CD ripper
# 0 - dagrab
# 1 - cdparanoia
# 2 - cdda2wav
# 3 - rip (Morituri)
# 4 - cdd (support not ensured)
# Default: cdparanoia

ripper=$ripper

# ripopt: User definable options for the CD ripper.
# Example: when using cdda2wav: -v summary
# Default: not set

ripopt=$ripopt

# offset: User definable sample offset for the CD ripper. This will
# trigger option -O when using cdparanoia and option -o when using rip.
# Icedax (cdda2wav) seems not to provide a sample offset.
# Possible values: integers
# Example: 48
# Default: 0

offset=$offset

# span: Rip only part of a single track or the merged track-interval.
# Possible values: any in the format hh:mm:ss.ff-hh:mm:ss.ff
# Example: rip first 30s of each track: 0-30
# Default: not set

span=$span

# paranoia: Turn \"paranoia\" on or off for dagrab and cdparanoia.
# Possible values: 0 - no paranoia, 1 - use paranoia
#                  2 - switch paranoia off if ripping fails on one
#                      track and retry this track without paranoia
# Default: 1 - use paranoia

paranoia=$parano

# ghost: Analyze the wavs for possible gaps, split the wav into
# chunks of sound and delete blank tracks.
# Possible values: 0 - off, 1 - on
# Default: off

ghost=$ghost

# prepend: Enlarge the chunk of sound by a number of
# seconds at the beginning (if possible).
# Possible values: any positive number and zero; precision in
# tenths of seconds. Be aware of low numbers, especially when
# using option cdcue.
# Default: 2.0

prepend=$prepend

# extend: Enlarge the chunk of sound by a number of
# seconds at the end (if possible).
# Possible values: any positive number and zero; precision in
# tenths of seconds. Be aware of low numbers.
# Default: 2.0

extend=$extend

# resume: Resume a previously started session.
# Possible values: 0 - off, 1 - on
# Default: off

resume=$resume

# overwrite: Default behaviour of Ripit is not to overwrite existing
# directories, a suffix will be added if directory name exists.
# Use option overwrite to prevent this and either overwrite a previous
# rip or force Ripit to quit or even eject the disc. If ejection is
# chosen, the disc will be ejected even if option eject has not been
# switched on.
# Possible values: n - off, y - on,
#                  q - quit, e - quit and force ejection
# Default: off

overwrite=$overwrite

# accuracy: Check ripped tracks using rip (Morituri) for accuracy with
# AccurateRip DB in case tracks have been ripped without rip (Morituri).
# Note: Option is defunct, rip (Morituri) will re-rip the whole disc.
# Possible values: 0 - off, 1 - on
# Default: off

accuracy=$accuracy

# verify: Rip each track \$verify times (or less) until at least 2 rips
# give the same md5sum.
# Possible: any integer
# Example: 3
# Default: 1

verify=$verify


#####
#
# Encoding options
#

# encode: Encode the wavs.
# Possible values: 0 - off, 1 - on
# Default: on

encode=$encode

# coder: Select encoders for audio files:
# 0 - Lame (mp3)
# 1 - Oggenc (ogg)
# 2 - Flac (flac)
# 3 - Faac (m4a)
# 4 - mp4als (als or mp4)
# 5 - Musepack (mpc)
# 6 - Wavpack (wv)
# 7 - ffmpeg
# Multiple encoders can be selected by giving a comma separated list
# Example: coder=0,0,1,2 encodes CD twice to mp3, ogg and flac files
# Default: Lame

coder=$wcoder

###
#
# lame (mp3) encoder options
#

# qualame: Sets audio quality for lame encoder in cbr (lame-option -q)
# and vbr (lame-option -V) mode, comma separated list if encoder is
# used several times.
# Possible values: 0...9, off
# 0: highest quality
# 9: lowest quality
# Can be set to \"off\" if all options are passed to --lameopt.
# Example: qualame=off,off
# Note: default value is the same for cbr and vbr,
# although vbr-default should be 4.
# Default: 5

qualame=$qualame

# lameopt: Additional options for lame encoder,
# use a comma separated list if encoder is used several times.
# Example: lameopt=-b 128,--preset extreme
# Default: not set

lameopt=$lameopt

# vbrmode: Enable variable bitrate for lame encoder.
# Possible values: \"old\" or \"new\"
# Default: not set

vbrmode=$vbrmode

# bitrate: Sets bitrate for lame encoder.
# Possible values: 32...320, off
# Should be set to \"off\" if vbr is used
# Default: 128

bitrate=$bitrate

# maxrate: Sets maximum bitrate for lame (when using vbr) and oggenc.
# Possible values: 0 - off, 32...320
# Default: 0

maxrate=$maxrate

# preset: Use lame presets. To set the \"fast\" switch, use --vbrmode new.
# Possible values: medium, standard, extreme, insane
#
# medium: 160kbps
# standard: 192kbps
# extreme: 256kbps
# insane: 320kbps
#
# Default: not set

preset=$wpreset

###
#
# oggenc (ogg) encoder options
#

# qualoggenc: Sets audio quality for oggenc.
# Possible values: 1..10, off
# 1: lowest quality
# 10: highest quality
# Can be set to \"off\"
# Default: 3

qualoggenc=$qualoggenc

# oggencopt: Additional options for oggenc,
# use a comma separated list if encoder is used several times.
# Default: not set

oggencopt=$oggencopt

###
#
# flac (lossless) encoder options
#

# quaflac: Sets audio compression for flac encoder
# Possible values: 0...8, off
# 0: lowest compression
# 8: highest compression
# Can be set to \"off\"
# Default: 5

quaflac=$quaflac

# flacopt: Additional options for flac encoder,
# use a comma separated list if encoder is used several times.
# Example of single encoder:
# flacopt=--padding=8212 --replay-gain
# Example of multiple encoder:
# flacopt=--padding=8212 --replay-gain,--padding=8212
# Note: If using the --replay-gain option the padding option
# is recommended, otherwise all padding might be lost.
# Default: not set

flacopt=$flacopt

# flacdecopt: Additional options for flac when used to decode flacs.
# Might be needed to force (over) writing existing wav files
# Example: flacdecopt=\"--totally-silent -f\"
# Default: -s (silent)

flacdecopt=$flacdecopt

###
#
# faac (m4a) encoder options
#

# quafaac: Sets audio quality for faac encoder
# Possible values: 10...500, off
# 10: lowest quality
# 500: highest quality
# Can be set to \"off\"
# Default: 100

quafaac=$quafaac

# faacopt: Additional options for faac encoder,
# comma separated list if encoder is used several times.
# Default: not set

faacopt=$faacopt

###
#
# mp4als (als or mp4) encoder options
#

# quamp4als: Set audio compression level for mp4als.
# Note: Options that influence compression and speed
# should be used in the mp4als options below.
# Default: 0

quamp4als=$quamp4als

# mp4alsopt: Additional options for mp4als encoder,
# comma separated list if encoder is used several times.
# Example: -MP4 to allow tagging, mandatory.
# Example: -a -o30 for faster speed.
# Default: not set

mp4alsopt=$mp4alsopt

###
#
# Musepack (mpc) encoder options
#

# musenc: The encoder name on the command line
# Possible values: any
# Example: musenc=mppenc for older versions
# Default: mpcenc

musenc=$musenc

# quamuse: Sets audio quality for Musepack encoder
# Possible values: 0...10, off
# 0: lowest quality
# 10: highest quality
# Can be set to \"off\"
# Default: 5

quamuse=$quamuse

# museopt: Additional options for Musepack encoder,
# use a comma separated list if encoder is used several times.
# Default: not set

museopt=$museopt

###
#
# Wavpack (wv) encoder options
#

# wavpacopt: Additional options for Wavpack encoder,
# use a comma separated list if encoder is used several times.
# Example: -b320chy
# Default: -y

wavpacopt=$wavpacopt

###
#
#ffmpeg encoder options
#

# ffmpegopt: Additional options for ffmpeg,
# use a comma separated list if encoder is used several times.
# Example if ffmpeg is used twice: -acodec alac,-acodec wmav2
# Default: off

ffmpegopt=$ffmpegopt

# ffmpegsuffix: Suffix to be used for ffmpeg,
# use a comma separated list if encoder is used several times.
# Example if ffmpeg is used twice: m4a,wma
# Default: off

ffmpegsuffix=$ffmpegsuffix


#####
#
# Track name and directory template
#

# dirtemplate: Template for directory structure
# The template can be created using any legal
# character, including slashes (/) for multi-level
# directory-trees, and the following variables:
# \$album
# \$artist
# \$iletter
# \$genre
# \$quality
# \$suffix
# \$trackname
# \$tracknum
# \$year
# \$trackno
#
# The variable \$iletter is the initial letter of
# the artist variable, the \$quality is the quality
# according to the encoding format defined by \$suffix.
# The variable \$quality reflects the encoder options,
# not the arguments of option --quality which may be set
# to off. The variable \$trackno is the total number of tracks
# of the release.
#
# dirtemplate is an array, for each encoder a different
# dirtemplate may be defined (i. e. for each encoder state
# a line starting with dirtemplate=...).
#
# Example:
# dirtemplate=\"\$suffix/hard_path/\$iletter/\$artist/\$year - \$album\"
#
# The double quotes (\") are mandatory!
# Default: \"\$artist - \$album\"
\n";
   print CONF "dirtemplate=$_\n" foreach(@dirtemplate);
   print CONF "
# tracktemplate: Template for track names
# \"tracktemplate\" is used similarly to \"dirtemplate\" but allows two
# more variables helpful in case VA-style is detected:
# \$trackartist
# \$tracktitle
# Note: \$trackartist will be filled with the value of \$artist in case
# no track artist has been found to respect the templates settings.
# Example:
# tracktemplate=\"\$tracknum: \$tracktitle performed by \$trackartist\"
# Default:  \"\$tracknum \$trackname\"

tracktemplate=$tracktemplate

# trackoffset: Add an offset to the track counter (\$tracknum)
# Possible values: any integer
# Default: 0

trackoffset=$trackoffset

# addtrackoffset: When using MusicBrainz automatically add an offset
# to the track counter (\$tracknum) in case a multi disc release has
# been detected.
# Possible values: 0 - off, 1 - on
# Default: off

addtrackoffset=$addtrackoffset

# discno: Set a counter for the disc when using a multi disc release.
# Possible values: 0 - off, any integer, when using MB set to 1 and
# MB might detect and set the discnumber.
# Default: 0

discno=$discno

# infolog: Log certain operations to file
# (e.g. system calls, creation of dirs/files)
# Possible values: filename (full path, no ~ here!)
# Default: not set

infolog=$infolog

# lowercase: Convert filenames and or directory names to lowercase
# Possible values: 0 - off, 1 - on (for both file and direcotry names)
#                  2 - on (only file names), 3 - on (only directory
#                  names)
# Default: off

lowercase=$lowercase

# uppercasefirst: Convert filenames and tags to uppercase first,
# not recommended. To be used on the command line only if CDDB entry
# is in uppercase.
# Possible values: 0 - off, 1 - on
# Default: off

uppercasefirst=$uppercasefirst

# underscore: Replace blanks in filenames with underscores
# Possible values: 0 - off, 1 - on
# Default: off

underscore=$underscore

# chars: Exclude special characters in file names and path.
# Note: following characters will always be purged:
#  ; > < \" and \\015 .
# Side note: if calling this option on the command line without
# argument, following characters will be purged:  |\\:*?\$  plus
# blanks and periods at beginning and end of file names and directories.
# This is identical to the word NTFS passed as argument to the command
# line or stated here in the config file. The word HFS will purge colons
# only plus blanks and periods at beginning of file names and
# directories.
#
# No need to escape the special characters here in the config file.
# Possible values: HFS, NTFS, none, any (?)
# Default: not set

chars=$chars


#####
#
# Audio file tagging
#

# year-tag: State a year (mp3, m4a) or a date (ogg, flac) tag.
# Possible values: integer
# Default: not set

year=$year

# comment-tag: State a comment (mp3, m4a, mpc) or a
# description (ogg, flac) tag. To write the cddbid used for freedb
# or the MusicBrainz discid into the comment, use the word \"cddbid\"
# or \"discid\".
# Possible values: discid, cddbid or any string
# Default: not set

comment=$commentag

# flactags: Additional tags for flac not passed by the encoder to ensure
# evaluation of special strings similar to mp3tags. Use option
# --flacopt \"--tag=FRAME=foo\" for additional hard coded tags instead.
# When using MB providing additional meta data can be added using the
# string FRAME=frame.
# Examples:
# Add asin:
# flactags=ASIN=asin
# Add musicbrainz release id and disid to be recodnized by Picard:
# flactags=MUSICBRAINZ_ALBUMID=mbreid
# flactags=MUSICBRAINZ_DISCID=discid
# flactags=CATALOGNUMBER=catalog
# Note: option is an array, for each additional frame/tag to be added
# state the option once.
# Possible values: none, any (?)
# Default: not set
\n";
   if(@flactags) {
      foreach(@flactags) {
         print CONF "flactags=$_\n";
      }
   }
   else {
      print CONF "flactags=\n";
   }
   print CONF "
# oggtags: Same as flactags.
\n";
   if(@oggtags) {
      foreach(@oggtags) {
         print CONF "oggtags=$_\n";
      }
   }
   else {
      print CONF "oggtags=\n";
   }
   print CONF "
# mp3tags: Additional tags for mp3 not passed by the encoder.
# Example: Add url tag:
# mp3tags=WUOF=www.id3v2.org
# Add a special track annotation:
# mp3tags=TXXX=[ASIN]B00654321
# Force an unofficial compilation frame when using a certain player:
# mp3tags=TCMP=1
# Special tags will be evaluated in case the meta data is provided
# mp3tags=TXXX=[ASIN]asin
# mp3tags=TXXX=[CATALOGNUMBER]catalog
# mp3tags=TXXX=[DISCID]discid
# mp3tags=TXXX=[MusicBrainz Disc Id]discid
# mp3tags=TXXX=[MusicBrainz Album Id]mbreid
# Note: option is an array, for each additional frame/tag to be added
# state the option once.
# Possible values: none, any (?)
# Default: not set
\n";
   if(@mp3tags) {
      foreach(@mp3tags) {
         print CONF "mp3tags=$_\n";
      }
   }
   else {
      print CONF "mp3tags=\n";
   }
   print CONF "
# utftag: Use Lame-tags in UTF-8 or convert them
# (but not the filenames) from Unicode to ISO8859-1.
# Use when your mp3-audio player doesn't support Unicode tags.
# May be useful with Lame. Experimental use in combination with option
# --threads or --sshlist.
# Possible values: 0 - off, 1 - on
# Default: on

utftag=$utftag

# coverart: Add cover image to meta data of encoded file if possible.
# Note: The cover must be available when encoding starts and specified
# with option --coverpath (below). One might want to use option
# --precmd to execute a script for downloading and preparing a cover.
# Argument is a list in same order as encoders with
# values 0 (no coverart) or 1 (add coverart) for each encoder.
# Example: 1,0,0,1
# Possible values: 0 - off, 1 - on
# Default: off

coverart=$coverart

# coverorg: If set coverart will be retrieved from coverartarchive.org.
# Possible values: 0 - off, 1 - on
# Default: off

coverorg=$coverorg

# coverpath: Path where the cover can be found, mandatory with option
# --coverart. Note that the full path is required unless you know what
# you do. The same variables as in option --dirtemplate may be
# used and need to be quoted.
# Example: \"\$wavdir/../thumb.png\"
# Possible values: string, none
# Default: none

coverpath=$coverpath

# coversize: Alter size of provided cover to be added to tags and rename
# the original cover making use of the ImageMagick package.
# Example: 640x640 or simply in the format 640
# Possible values: any valid format treated by ImageMagick
# Default: none

coversize=$coversize

# copycover: Copy a cover (or any other file) with full path to all
# directories containing encoded files. The same variables as in option
# --dirtemplate may be used and need to be quoted.
# Example: /media/snd/covers/cover.png
# Possible values: none - off, absolute path to image
# Default: off

copycover=$copycover

# mbrels: MusicBrainz relationships will be retrieved for each track to
# add vocal performer names in the form \"(featuring PERFORMER)\" or
# (covering WORK) if found.
# Possible values: 0 - off, 1 - on
# Default: off

mbrels=$mbrels

# vatag: Analyze track names for \"various artists\" style and split
# the meta data in case one of the delimiters (colon, hyphen, slash or
# parenthesis) are found. Use unpair numbers for the scheme
# \"artist ? tracktitle\" and pair numbers in the opposite case.
# The artist will be compared to the argument of option --vastring
# (see below). If the artist must be like vastring and each track have a
# delimiter, use 1 (2), if the artist must be like vastring while only
# some tracks contain the delimiter, use 3 (4), if no restrictions
# apply for the artist but all track names must have a delimiter, use
# 5 (6) and finally, if only a few tracks contain a delimiter to be
# used as splitting point, set vatag to 7 (8).
# Example: 5
# Possible values: 0 - off, 1, 2, 3, 4, 5, 6, 7, 8
# Default: off

vatag=$vatag

# vastring: the string (regular expression) that defines the
# \"various artists\" style
# Example: Varios|VA
# Possible values: string, none
# Default: \\bVA\\b|Variou*s|Various\\sArtists|Soundtrack|OST

vastring=$vastring

# mp3gain: Add album gain tags to mp3 files using the appropriate
# command with options and arguments but without in-files.
# Example: mp3gain -a -c -q -s i
# Default: not set

mp3gain=$mp3gain

# vorbgain: Add album gain tags to ogg files using the appropriate
# command with options and arguments but without in-files.
# Example: vorbisgain -a -q
# Default: not set

vorbgain=$vorbgain

# flacgain: Add album gain tags to flac files using the appropriate
# command with options and arguments but without in-files.
# Example: metaflac --add-replay-gain
# Default: not set

flacgain=$flacgain

# aacgain: Add album gain tags to mp4 or m4a files using the appropriate
# command with options and arguments but without in-files.
# Example: aacgain -a -c -q
# Default: not set

aacgain=$aacgain

# mpcgain: Add album gain tags to mpc files using the appropriate
# command with options and arguments but without in-files.
# Example: mpcgain
# Default: not set

mpcgain=$mpcgain

# wvgain: Add album gain tags to wv files using the appropriate
# command with options and arguments but without in-files.
# Example: wvgain -a -q
# Default: not set

wvgain=$wvgain


#####
#
# CDDB options
#

# mb: Access MusicBrainz DB via WebService::MusicBrainz module instead
# of the http protocol (see below).
# Possible values: 0 - off, 1 - on
# Default: off

mb=$mb

# CDDBHOST: Specifies the CDDB server
# Possible values: freedb.org, freedb2.org or musicbrainz.org
# Note: Full name of the server used is \$mirror.\$CDDBHOST, except for
# freedb2.org (no mirror) and musicbrainz.org has freedb as default
# mirror.
# E.g. default server is freedb.freedb.org
# Default: freedb.org

CDDBHOST=$CDDB_HOST

# mirror: Selects freedb mirror
# Possible values: \"freedb\" or any freedb mirrors
# See www.freedb.org for mirror list
# Note: Full name of the server used is \$mirror.\$CDDBHOST
# E.g., default server is freedb.freedb.org
# Default: freedb

mirror=$mirror

# transfer: Set transfer mode for cddb queries
# Possible values: cddb, http
# Note: CDDB servers freedb2.org and musicbrainz.org may need transfer
# mode http.
# Default: cddb

transfer=$transfer

# proto: Set CDDP protocol level
# Possible values: 5, 6
# Protocol level 6 supports Unicode (UTF-8)
# Default: 6

proto=$proto

# proxy: Address of http-proxy, if needed.
# Default: not set

proxy=$proxy

# mailad: Mail address for cddb submissions.
# Possible values: Valid user email address for submitting cddb entries
# Default: not set

mailad=$mailad

# mailopt: Additional options for sendmail.
# Possible values: Any sendmail options.
# Default: -t

mailopt=$mailopt

# archive: Read and save cddb data on local machine.
# Possible values: 0 - off, 1 - on
# Default: off

archive=$archive

# submission: Submit new or edited cddb entries to freeCDDB.
# Possible values: 0 - off, 1 - on
# Default: on

submission=$submission

# interaction: Turns on or off user interaction in cddb dialog and
# everywhere else.
# Possible values: 0 - off, 1 - on
# Default: on

interaction=$interaction

# isrc: detect track ISRCs using icedax and submit them to Musicbrainz
# if login info is provided. Please check if the device in use is
# able to read correct ISRCs and submit them if found.
# Possible values: 0 - off, 1 - on
# Default: off

isrc=$isrc

# mbname: login name to Musicbrainz.org
# Possible values: string
# Default: not set

mbname=$mbname

# mbpass: password to Musicbrainz.org
# Possible values: string
# Default: not set

mbpass=$mbpass

# cdtext: check if CD text is present and use it if no DB entry found.
# Possible values: 0 - off, 1 - on
# Default: off

cdtext=$cdtext


#####
#
# LCD options
#

# lcd: Use lcdproc to display status on LCD
# Possible values: 0 - off, 1 - on
# Default: off

lcd=$lcd

# lcdhost: Specify the lcdproc host
# Default: localhost

lcdhost=$lcdhost

# lcdport: Specify port number for $lcdhost
# Default: 13666

lcdport=$lcdport


#####
#
# Distributed ripping options
#

# sshlist: Comma separated list of remote machines ripit shall use
# for encoding. The output path must be the same for all machines.
# Specify the login (login\@machine) only if not the
# same for the remote machine. Else just state the
# machine names.
# Default: not set

sshlist=$wsshlist

# scp: Copy files to encode to the remote machine.
# Use if the fs can not be accessed on the remote machines
# Possible values: 0 - off, 1 - on
# Default: off

scp=$scp

# local: Turn off encoding on local machine, e.g. use only remote
# machines.
# Possible values: 0 - off, 1 - on
# Example: local=0 (off) turns off encoding on the
# local machine
# Default: on

local=$local


#####
#
# Misc. options
#

# verbosity: Run silent (do not output comments, status etc.) (0), with
# minimal (1), normal without encoder msgs (2), normal (3), verbose (4)
# or extremely verbose (5).
# Possible values: 0...5
# Default: 3 - normal

verbose=$verbose

# eject: Eject cd after finishing encoding.
# Possible values: 0 - off, 1 - on
# Default: off

eject=$eject

# ejectcmd: Command used to eject and close CD tray.
# Possible values: string
# Example: /usr/sbin/cdcontrol for FreeBSD
# Default: eject

ejectcmd=$ejectcmd

# ejectopt: Options to command used to eject or close CD.
# Possible values: string or \"{cddev}\" to design the CD
# device.
# Note: Don't use options -t / close or eject,
#       RipIT knows when to eject or load the tray
# Default: {cddev}

ejectopt=$ejectopt

# quitnodb: Give up CD if no CDDB entry found.
# Useful if option --loop or --nointeraction are on.
# Default behaviour is to let operator enter data or to use default
# artist, album and track names.
# Possible values: 0 - off, 1 - on
# Default: off

quitnodb=$quitnodb

# execmd: Execute a command when done with ripping. Quote the command
# if needed.
# Note: The same variables as in the dirtemplate can be used. When
# using MusicBrainz one might want to use \$cd{asin} to get the ASIN
# if available.
# Possible values: none - off, string - on
# Example: execmd=\"add_db -a \\\"\$artist\\\" -r \\\"\$album\\\"\"
# Default: off

execmd=$execmd

# precmd: Execute a command before starting to rip. Quote the command
# if needed.
# Note: The same variables as in the dirtemplate can be used. When
# using MusicBrainz one might want to use \$cd{asin} to get the ASIN
# if available.
# Possible values: none - off, string - on
# Example: precmd=\"get_cover -a \\\"\$artist\\\" -r \\\"\$album\\\" -o \\\"\$wavdir\\\" -t \\\"\$trackno\\\"\"
# Default: off

precmd=$precmd

# book: Create an audiobook, i. e. merge all tracks into one single
# file, option --ghost will be switched off and file suffix will be
# m4b. Make sure to use encoder faac, ripit will not check that.
# A chapter file will be written for chapter marks.
# Possible values: 0 - off, 1 - on
# Default: off

book=$book

# loop: Continue with a new CD when the previous one is done.
# Option --eject will be forced. To start ripping process immediately
# after ejection of previous disc, use experimental argument 2. Ripit
# will restart as child process, one might see the prompt and it will
# be necessary to manually terminate the process! Use with caution!
# Possible values: 0 - off, 1 - on, 2 - immediate restart, experimental
# Default: off

loop=$loop

# halt: Powers off machine after finishing encoding.
# Possible values: 0 - off, 1 - on
# Default: off

halt=$halt

# nice: Sets \"nice\" value for the encoding process.
# Possible values: 0..19 for normal users,
#                  -20..19 for user \"root\"
# Default: 0

nice=$nice

# nicerip: Sets \"nice\" value for the ripping process.
# Possible values: 0..19 for normal users,
#                  -20..19 for user \"root\"
# Default: 0

nicerip=$nicerip

# threads: Comma separated list of numbers giving maximum
# of allowed encoder processes to run at the same time
# (on each machine when using sshlist).
# Possible values: comma separated integers
# Default: 1

threads=$wthreads

# md5sum: Create file with md5sums for each type of sound files.
# Possible values: 0 - off, 1 - on
# Default: off

md5sum=$md5sum

# wav: Don't delete wave-files after encoding.
# Possible values: 0 - off, 1 - on
# Default: off

wav=$wav

# normalize: Normalizes the wave-files to a given dB-value
# (default: -12dB)
# See http://normalize.nongnu.org for details.
# Possible values: 0 - off, 1 - on
# Default: off

normalize=$normalize

# normcmd: Command to be used to normalize.
# Possible values: string
# Example: normalize-audio (when using Debian)
# Default: normalize

normcmd=$normcmd

# normopt: Options to pass to normalize
# Possible values: -a -nndB   : Normalize to -nn dB, default is -12dB,
#                  Value range: All values <= 0dB
#                  Example    : normalize -a -20dB *.wav
#                  -b         : Batch mode - loudness differences
#                               between individual tracks of a CD are
#                               maintained
#                  -m         : Mix mode - all track are normalized to
#                               the same loudness
#                  -v         : Verbose operation
#                  -q         : Quiet operation
# For further options see normalize documentation.
# Default: -b
# The -v option will be added by default according to RipITs verbosity

normopt=$normopt

# playlist: Create m3u playlist with or without the full path
# in the filename.
# Possible values: 0 - off,
#                  1 - on with full path
#                  2 - on with no path (filename only)
# Default: on (with full path)

playlist=$playlist

# cue: Create a cue file with all tracks to play or burn them with
# cd-text.
# Possible values: 0 - off, 1 - on
# Default: off

cue=$cue

# cdtoc: Create a toc file to burn the wavs with
# cd-text using cdrdao or cdrecord (in dao mode).
# Possible values: 0 - off, 1 - on
# Default: off

cdtoc=$cdtoc

# inf: Create inf files to burn the wavs with
# cd-text using wodim or cdrecord (in dao mode).
# Possible values: 0 - off, 1 - on
# Default: off

inf=$inf

# cdcue: Create a cue file to burn the merged wav with cd-text.
# Note that all tracks will be merged and normalized.
# Possible values: 0 - off, 1 - on, 2 - on (experimental fallback)
# Note: Use value 2 only if for whatever reason value 1 should fail.
# Default: off

cdcue=$cdcue
\n";
   close(CONF);
}
########################################################################
#
# Read the config file, take the parameters only if NOT yet defined!
#
# New options step 11: Read the new options from config file. Replicate
# one of the 2-liners starting with chomp.
#
sub read_config {
   if($confdir ne "") {
      $ripdir = $confdir . "/" . $confname;
   }
   elsif($confname ne "config") {
      $ripdir = $homedir . "/.ripit/" . $confname;
   }
   # Fallback:
   $ripdir = $homedir . "/.ripit/config" unless(-r "$ripdir");
   $ripdir = "/etc/ripit/config" unless(-r "$ripdir");
   print "Reading config file in $ripdir.\n" if($verbose > 4);
   if(-r "$ripdir") {
      open(CONF, "$ripdir") or
      print "Can not read config file in $ripdir: $!\n";
      my @conflines = <CONF>;
      close(CONF);
      my @confver = grep(s/^# RipIT //, @conflines);
      @confver = split(/ /, $confver[0]) if($confver[0] =~ /^\d/);
      my $confver = $confver[0] if($confver[0] =~ /^\d/);
      $confver = 0 unless($confver);
      chomp $confver;
      if($version ne $confver && $savepara == 0) {
         $verbose = 3 if($verbose <= 1);
         print "\nPlease update your config-file with option --save";
         print "\nto ensure correct settings! Pausing 3 seconds!\n\n";
         sleep(3);
      }
      elsif($version ne $confver) {
         grep(s/^chars=[01]\s*$/chars=/, @conflines);
      }
      chomp($accuracy = join(' ', grep(s/^accuracy=//, @conflines)))
         unless defined $paccuracy;
      chomp($archive = join(' ', grep(s/^archive=//, @conflines)))
         unless defined $parchive;
      chomp($bitrate = join(' ', grep(s/^bitrate=//, @conflines)))
         unless($pbitrate);
      chomp($book = join(' ', grep(s/^book=//, @conflines)))
         unless($pbook);
      chomp($maxrate = join(' ', grep(s/^maxrate=//, @conflines)))
         unless($pmaxrate);
      chomp($cddev = join(' ', grep(s/^cddevice=//, @conflines)))
         unless($pcddev);
      chomp($scsi_cddev = join(' ', grep(s/^scsidevice=//, @conflines)))
         unless($pscsi_cddev);
      chomp($cdtext = join('', grep(s/^cdtext=//, @conflines)))
         unless defined $pcdtext; # Remember, $cdtext might be zero.
      chomp($cdtoc = join('', grep(s/^cdtoc=//, @conflines)))
         unless defined $pcdtoc; # Remember, $cdtoc might be zero.
      chomp($cdcue = join('', grep(s/^cdcue=//, @conflines)))
         unless($pcdcue);
      chomp($cue = join('', grep(s/^cue=//, @conflines)))
         unless($pcue);
      chomp($chars = join('', grep(s/^chars=//, @conflines)))
         if($chars eq "XX");
      chomp($commentag = join('', grep(s/^comment=//, @conflines)))
         unless($pcommentag);
      chomp($CDDB_HOST = join('', grep(s/^CDDBHOST=//, @conflines)))
         unless($PCDDB_HOST);
      @pcoder = grep(s/^coder=//, @conflines) unless(@pcoder);
      # NOTE: all coders are in array entry $pcoder[0]!
      # NOTE: we have to fill the wcoder (w=write) variable!
      $wcoder = $pcoder[0] if(@pcoder);
      chomp $wcoder;
      @dirtemplate = grep(s/^dirtemplate=//, @conflines)
         unless($pdirtemplate[0]);
      chomp $_ foreach(@dirtemplate);
      chomp($dpermission = join('', grep(s/^dpermission=//, @conflines)))
         unless($pdpermission);
      chomp($eject = join('', grep(s/^eject=//, @conflines)))
         unless defined $peject;
      chomp($ejectcmd = join('', grep(s/^ejectcmd=//, @conflines)))
         unless defined $pejectcmd;
      chomp($ejectopt = join('', grep(s/^ejectopt=//, @conflines)))
         unless defined $pejectopt;
      chomp($encode = join('', grep(s/^encode=//, @conflines)))
         unless defined $pencode;
      chomp($extend = join('', grep(s/^extend=//, @conflines)))
         unless defined $pextend;
      chomp($execmd = join('', grep(s/^execmd=//, @conflines)))
         unless defined $pexecmd;
      chomp($precmd = join('', grep(s/^precmd=//, @conflines)))
         unless defined $pprecmd;
      chomp($fpermission = join('', grep(s/^fpermission=//, @conflines)))
         unless($pfpermission);
      chomp($ghost = join('', grep(s/^ghost=//, @conflines)))
         unless defined $pghost;
      chomp($halt = join('', grep(s/^halt=//, @conflines)))
         unless($phalt);
      chomp($inf = join('', grep(s/^inf=//, @conflines)))
         unless($pinf);
      chomp($infolog = join('', grep(s/^infolog=//, @conflines)))
         unless(defined $pinfolog);
      chomp($interaction = join('', grep(s/^interaction=//, @conflines)))
         unless defined $pinteraction;
      chomp($isrc = join('', grep(s/^isrc=//, @conflines)))
         unless defined $pisrc;
      chomp($lcd = join('', grep(s/^lcd=//, @conflines)))
         unless defined $plcd;
      chomp($lcdhost = join('', grep(s/^lcdhost=//, @conflines)))
         unless($plcdhost);
      chomp($lcdport = join('', grep(s/^lcdport=//, @conflines)))
         unless($plcdport);
      chomp($local = join('', grep(s/^local=//, @conflines)))
         unless defined $plocal;
      chomp($loop = join('', grep(s/^loop=//, @conflines)))
         unless defined $ploop;
      chomp($lowercase = join('', grep(s/^lowercase=//, @conflines)))
         unless defined $plowercase;
      chomp($uppercasefirst = join('', grep(s/^uppercasefirst=//, @conflines)))
         unless defined $puppercasefirst;
      chomp($mailad = join('', grep(s/^mailad=//, @conflines)))
         unless($pmailad);
      chomp($mailopt = join('', grep(s/^mailopt=//, @conflines)))
         unless($pmailopt);
      chomp($mb = join('', grep(s/^mb=//, @conflines)))
         unless defined $pmb;
      chomp($mbrels = join('', grep(s/^mbrels=//, @conflines)))
         unless defined $pmbrels;
      chomp($mbname = join('', grep(s/^mbname=//, @conflines)))
         unless defined $pmbname;
      chomp($mbpass = join('', grep(s/^mbpass=//, @conflines)))
         unless defined $pmbpass;
      chomp($md5sum = join('', grep(s/^md5sum=//, @conflines)))
         unless($pmd5sum);
      chomp($mirror = join('', grep(s/^mirror=//, @conflines)))
         unless($pmirror);
      @flactags = grep(s/^flactags=//, @conflines)
         unless($pflactags[0]);
      chomp $_ foreach(@flactags);
      @oggtags = grep(s/^oggtags=//, @conflines)
         unless($poggtags[0]);
      chomp $_ foreach(@oggtags);
      @mp3tags = grep(s/^mp3tags=//, @conflines)
         unless($pmp3tags[0]);
      chomp $_ foreach(@mp3tags);
      chomp($musenc = join('', grep(s/^musenc=//, @conflines)))
         unless($pmusenc);
      chomp($normalize = join('', grep(s/^normalize=//, @conflines)))
         unless defined $pnormalize;
      chomp($normcmd = join('', grep(s/^normcmd=//, @conflines)))
         unless($pnormcmd);
      chomp($normopt = join('', grep(s/^normopt=//, @conflines)))
         unless($pnormopt);
      chomp($nice = join('', grep(s/^nice=//, @conflines)))
         unless defined $pnice;
      chomp($nicerip = join('', grep(s/^nicerip=//, @conflines)))
         unless defined $pnicerip;
      chomp($offset = join('', grep(s/^offset=//, @conflines)))
         unless($poffset);
      chomp($outputdir = join('', grep(s/^output=//, @conflines)))
         unless($poutputdir);
      chomp($overwrite = join('', grep(s/^overwrite=//, @conflines)))
         unless($poverwrite);
      chomp($parano = join('', grep(s/^paranoia=//, @conflines)))
         unless defined $pparano;
      chomp($playlist = join('', grep(s/^playlist=//, @conflines)))
         unless defined $pplaylist;
      chomp($prepend = join('', grep(s/^prepend=//, @conflines)))
         unless defined $pprepend;
      chomp($preset = join('', grep(s/^preset=//, @conflines)))
         unless($ppreset);
      # NOTE: we have to fill the w_RITE_preset variable!
      $wpreset = $preset unless($ppreset);
      chomp $preset;
      chomp $wpreset;
      chomp($proto = join('', grep(s/^proto=//, @conflines)))
         unless($pproto);
      chomp($proxy = join('', grep(s/^proxy=//, @conflines)))
         unless($pproxy);
      my @quafaac = grep(s/^quafaac=//, @conflines) unless($pquality[0]);
      chomp($quafaac = $quafaac[0]) unless($pquality[0]);
      my @quaflac = grep(s/^quaflac=//, @conflines) unless($pquality[0]);
      chomp($quaflac = $quaflac[0]) unless($pquality[0]);
      my @qualame = grep(s/^qualame=//, @conflines) unless($pquality[0]);
      chomp($qualame = $qualame[0]) unless($pquality[0]);
      my @qualoggenc = grep(s/^qualoggenc=//, @conflines)
         unless($pquality[0]);
      chomp($qualoggenc = $qualoggenc[0]) unless($pquality[0]);
      my @quamp4als = grep(s/^quamp4als=//, @conflines)
         unless($pquality[0]);
      chomp($quamp4als = $quamp4als[0]) unless($pquality[0]);
      my @quamuse = grep(s/^quamuse=//, @conflines)
         unless($pquality[0]);
      chomp($quamuse = $quamuse[0]) unless($pquality[0]);
      # I don't really like this. I don't like the variables qualame etc
      # too and wanted to get rid of them. Not possible anymore. We need
      # them because they hold a comma separated string necessary to
      # write to the config file...
      unless($pquality[0]) {
         @qualame = split(/,/, $qualame);
         @qualoggenc = split(/,/, $qualoggenc);
         @quaflac = split(/,/, $quaflac);
         @quafaac = split(/,/, $quafaac);
         @quamp4als = split(/,/, $quamp4als);
         @quamuse = split(/,/, $quamuse);
         @coder = split(/,/, join(',',@pcoder));
         for(my $c=0; $c<=$#coder; $c++) {
            if($coder[$c] == 0) {
               print "\nWarning: Config file has less Lame qualties than stated coders!\nPlease fix your config file.\n" if(!defined $qualame[0]);
               $quality[$c] = $qualame[0];
               shift(@qualame);
            }
            if($coder[$c] == 1) {
               print "\nWarning: Config file has less Oggenc qualties than stated coders!\nPlease fix your config file.\n" if(!defined $qualoggenc[0]);
               $quality[$c] = $qualoggenc[0];
               shift(@qualoggenc);
            }
            if($coder[$c] == 2) {
               print "\nWarning: Config file has less Flac qualties than stated coders!\nPlease fix your config file.\n" if(!defined $quaflac[0]);
               $quality[$c] = $quaflac[0];
               shift(@quaflac);
            }
            if($coder[$c] == 3) {
               print "\nWarning: Config file has less Faac qualties than stated coders!\nPlease fix your config file.\n" if(!defined $quafaac[0]);
               $quality[$c] = $quafaac[0];
               shift(@quafaac);
            }
            if($coder[$c] == 4) {
               print "\nWarning: Config file has less mp4als qualties than stated coders!\nPlease fix your config file.\n" if(!defined $quamp4als[0]);
               $quality[$c] = $quamp4als[0];
               shift(@quamp4als);
            }
            if($coder[$c] == 5) {
               print "\nWarning: Config file has less Musepack qualties than stated coders!\nPlease fix your config file.\n" if(!defined $quamuse[0]);
               $quality[$c] = $quamuse[0];
               shift(@quamuse);
            }
         }
      }
      chomp($faacopt = join('', grep(s/^faacopt=//, @conflines)))
         unless($pfaacopt);
      chomp($flacopt = join('', grep(s/^flacopt=//, @conflines)))
         unless($pflacopt);
      chomp($flacdecopt = join('', grep(s/^flacdecopt=//, @conflines)))
         unless($pflacdecopt);
      chomp($lameopt = join('', grep(s/^lameopt=//, @conflines)))
         unless($plameopt);
      chomp($mp4alsopt = join('', grep(s/^mp4alsopt=//, @conflines)))
         unless($pmp4alsopt);
      chomp($museopt = join('', grep(s/^museopt=//, @conflines)))
         unless($pmuseopt);
      chomp($oggencopt = join('', grep(s/^oggencopt=//, @conflines)))
         unless($poggencopt);
      chomp($wavpacopt = join('', grep(s/^wavpacopt=//, @conflines)))
         unless($pwavpacopt);
      chomp($aacgain = join('', grep(s/^aacgain=//, @conflines)))
         unless($paacgain);
      chomp($flacgain = join('', grep(s/^flacgain=//, @conflines)))
         unless($pflacgain);
      chomp($mp3gain = join('', grep(s/^mp3gain=//, @conflines)))
         unless($pmp3gain);
      chomp($mpcgain = join('', grep(s/^mpcgain=//, @conflines)))
         unless($pmpcgain);
      chomp($vorbgain = join('', grep(s/^vorbgain=//, @conflines)))
         unless($pvorbgain);
      chomp($wvgain = join('', grep(s/^wvgain=//, @conflines)))
         unless($pwvgain);
      chomp($ffmpegopt = join('', grep(s/^ffmpegopt=//, @conflines)))
         unless($pffmpegopt);
      chomp($ffmpegsuffix = join('', grep(s/^ffmpegsuffix=//, @conflines)))
         unless($pffmpegsuffix);
      chomp($coverart = join('', grep(s/^coverart=//, @conflines)))
         unless($pcoverart);
      chomp($coverorg = join('', grep(s/^coverorg=//, @conflines)))
         unless defined $pcoverorg;
      chomp($coverpath = join('', grep(s/^coverpath=//, @conflines)))
         unless($pcoverpath);
      chomp($coversize = join('', grep(s/^coversize=//, @conflines)))
         unless($pcoversize);
      chomp($copycover = join('', grep(s/^copycover=//, @conflines)))
         unless($pcopycover);
      chomp($quitnodb = join('', grep(s/^quitnodb=//, @conflines)))
         unless defined $pquitnodb;
      chomp($ripper = join('', grep(s/^ripper=//, @conflines)))
         unless defined $pripper;
      chomp($resume = join('', grep(s/^resume=//, @conflines)))
         unless defined $presume;
      chomp($ripopt = join('', grep(s/^ripopt=//, @conflines)))
         unless defined $pripopt;
      my @clist = grep(s/^threads=//, @conflines) unless($pthreads[0]);
      chomp @clist;
      # NOTE: all threads numbers are in array entry $clist[0]!
      @threads = split(/,/, join(',',@clist));
      my @rlist = grep(s/^sshlist=//, @conflines) unless($psshlist[0]);
      chomp @rlist;
      # NOTE: all machine names are in array entry $rlist[0]!
      @sshlist = split(/,/, join(',',@rlist));
      chomp($scp = join('', grep(s/^scp=//, @conflines)))
         unless defined $pscp;
      chomp($span = join('', grep(s/^span=//, @conflines)))
         unless defined $pspan;
      chomp($submission = join('', grep(s/^submission=//, @conflines)))
         unless defined $psubmission;
      chomp($transfer = join('', grep(s/^transfer=//, @conflines)))
         unless($ptransfer);
      chomp($tracktemplate = join('', grep(s/^tracktemplate=//, @conflines)))
         unless($ptracktemplate);
      chomp($trackoffset = join('', grep(s/^trackoffset=//, @conflines)))
         unless($ptrackoffset);
      chomp($addtrackoffset = join('', grep(s/^addtrackoffset=//, @conflines)))
         unless($paddtrackoffset);
      chomp($discno = join('', grep(s/^discno=//, @conflines)))
         unless($pdiscno);
      chomp($underscore = join('', grep(s/^underscore=//, @conflines)))
         unless defined $punderscore;
      chomp($utftag = join('', grep(s/^utftag=//, @conflines)))
         unless defined $putftag;
      chomp($vatag = join('', grep(s/^vatag=//, @conflines)))
         unless defined $pvatag;
      chomp($vastring = join('', grep(s/^vastring=//, @conflines)))
         unless defined $pvastring;
      chomp($vbrmode = join('', grep(s/^vbrmode=//, @conflines)))
         unless($pvbrmode);
      chomp($verify = join('', grep(s/^verify=//, @conflines)))
         unless defined $pverify;
      chomp($year = join('', grep(s/^year=//, @conflines)))
         unless($pyear);
      chomp($wav = join('', grep(s/^wav=//, @conflines)))
         unless defined $pwav;
   }
   else {
      print "\nNo config file found! Use option --save to create one.\n"
         if($verbose >= 2);
   }
}
#
#
########################################################################
#
# Change encoding of tags back to iso-8859-1. Again: this is only needed
# when using lame to create mp3s. Tagging works for all other
# encoders and encodings.
#
# Test CDs where option --noutf should work:
# Bang Bang:  Je t'aime...     10: Sacré cœur
# Distain!:   [Li:quíd]:        3: Summer 84
# Enya:       The Celts:       10: Triad: St. Patrick Cú Chulainn Oisin
# Enya:       The Celts:       14: Dan y Dŵr
# Röyksopp:   Junior:           5: Röyksopp Forever
# Žofka:      Bad Girls:        1: Woho
#
sub back_encoding {
   my $string = shift;
   my $latin1 = encode("latin1", $string);
   my $utf_string = $string;
   if(utf8::is_utf8($string)) {
      print "The \$string is already in utf8, do nothing!\n"
         if($verbose > 5);
   }
   else {
      print "The \$string is *not* in utf8, encode->decode!\n"
         if($verbose > 5);
      $utf_string = Encode::decode('UTF-8', $utf_string, Encode::FB_QUIET);
   }
   my @utf_points = unpack("U0U*", "$utf_string"); # Perl 5.10
   my $latinflag = 0;
   my $wideflag = 0;
   foreach (@utf_points) {
      $wideflag = 1 if($_ > 255);
      $latinflag++ if($_ > 128 && $_ < 256);
   }

   # It works with Röyksopp archive and freeCDDB entry.
   my @char_points = unpack("U0U*", "$string");
   @char_points = @utf_points if($wideflag == 1);

   return $string if($string eq "");
   my $decoded = "";
   foreach (@char_points) {
      if($_ > 255) {
         print "\"Wide\" char detected: $_.\n" if($verbose > 5);
         use Unicode::UCD 'charinfo';
         my $charinfo = charinfo(sprintf("0x%X", $_));
         my $letter = $charinfo->{name};
         print "The charinfo is <$letter>.\n" if($verbose > 5);
         my $smallflag = 0;
         $smallflag = 1 if($letter =~ /SMALL\sLETTER/);
         $smallflag = 1 if($letter =~ /SMALL\sLIGATURE/);
         $letter =~ s/^.*LETTER\s(\w+)\s.*/$1/;
         $letter =~ s/^.*LIGATURE\s(\w+)(\.|\s)*.*/$1/;
         $letter = "\L$letter" if($smallflag == 1);
         # Rather do nothing than print rubbish (string with words):
         $letter = $_ if($letter =~ /\s/);
         print "New letter will be: $letter.\n" if($verbose > 5);
         $decoded .= $letter;
      }
      else {
         $decoded .= chr($_);
      }
   }

   if($cd{discid}) {
      # Special condition for MB data. Please do not ask why.
      if($wideflag == 0 && $latinflag == 0) {
      # Original.
      Encode::from_to($decoded, 'UTF8', 'iso-8859-1');
      # But we come here in every case because we want the discid to be
      # present (in comment tags), but come from archive, not from MB.
      }
      elsif($wideflag == 0) {
         Encode::from_to($decoded, 'UTF8', 'ISO-8859-1');
      }
   }
   elsif($wideflag == 0) {
      Encode::from_to($decoded, 'UTF8', 'ISO-8859-1');
   }
   return($decoded);
}
########################################################################
#
# Check the preset options.
#
sub check_preset {
   if($preset !~ /^\d/) {
      while($preset !~ /^insane$|^extreme$|^standard$|^medium$/) {
         print "\nPreset should be one of the following words! Please";
         print " Enter \ninsane (320\@CBR), extreme (256), standard";
         print " (192) or medium (160), (standard): ";
         $preset = <STDIN>;
         chomp $preset;
         if($preset eq "") {
            $preset = "standard";
         }
      }
   }
   else {
      while($preset !~ m/^32$|^40$|^48$|^56$|^64$|^80$|^96$|^112$|^128$|
                        |^160$|^192$|^224$|^256$|^320$/) {
         print "\nPreset should be one of the following numbers!",
               " Please Enter \n32, 40, 48, 56, 64, 80, 96, 112, 128,",
               " 160, 192, 224, 256 or 320, (128):\n";
         $preset = <STDIN>;
         chomp $preset;
         if($preset eq "") {
            $preset = 128;
         }
      }
   }
   $preset = "medium" if($preset =~ /\d+/ && $preset == 160);
   $preset = "standard" if($preset =~ /\d+/ && $preset == 192);
   $preset = "extreme" if($preset =~ /\d+/ && $preset == 256);
   $preset = "insane" if($preset =~ /\d+/ && $preset == 320);
   $wpreset = $preset;
}
########################################################################
#
# Check sshlist of remote machines and create a hash.
#
sub check_sshlist {
   if(@psshlist) {
      @sshlist = split(/,/, join(',', @psshlist));
   }
   if(@pthreads) {
      @threads = split(/,/, join(',', @pthreads));
   }
   $wthreads = join(',', @threads);
   if(@sshlist || $threads[0] > 1) {
      $sshflag = 1;
      $wsshlist = join(',', @sshlist);
      # Create a hash with all machines and the number of encoding
      # processes each machine is able to handle.
      $sshlist{'local'} = $threads[0] if($local == 1);
      my $threadscn = 1;
      foreach (@sshlist) {
         $threads[$threadscn] = 1 unless($threads[$threadscn]);
         $sshlist{$_} = $threads[$threadscn];
         $threadscn++;
      }
   }
   else {
      $sshflag = 0;
   }
}
########################################################################
#
# Dispatcher for encoding on remote machines. If there are no .lock
# files, a ssh command will be passed, else the dispatcher waits until
# an already passed ssh command terminates and removes the lock file.
# The dispatcher checks all machines all 6 seconds until a machine is
# available. If option --scp is used, the dispatcher will not start an
# other job while copying. In this situation, it looks like nothing
# would happen, but it's only during scp.
#
sub enc_ssh {
   my $machine;
   my @codwav = ();
   my $delwav = $_[0];
   my $enccom = $_[1];
   my $ripnam = $_[2];
   my $sepdir = $_[3];
   my $suffix = $_[4];
   my $shortnam = $_[5];
   my $enc_no = $_[6];
   my $old_wavdir = $wavdir;
   my $old_sepdir = $sepdir;
   my $old_ripnam = $ripnam;
   my $esc_name;
   my $esc_dir;
   my $threadscn;

   $sshflag = 2;
   while($sshflag == 2) {
      # Start on the local machine first.
      $threadscn = 1;
      for($threadscn = 1; $threadscn <= $threads[0]; $threadscn++) {
         if(! -r "$wavdir/local.lock_$threadscn") {
            if($local == 1) {
               $sshflag = 1;
               $machine = "local";
               push @codwav, "$ripnam";
            }
         }
         else {
            $sshflag = del_lock("$wavdir", "local.lock_$threadscn")
               if($utftag == 0);
            $sshflag = 1 if($sshflag == 0);
         }
         last if($sshflag == 1);
      }
      last if($sshflag == 1);
      $threadscn = 1;

      foreach $_ (keys %sshlist) {
         # Variable $machine will be needed below... and must be set.
         $machine = $_;
         next if(!defined $machine or $machine eq "");
         for($threadscn = 1; $threadscn <= $sshlist{$_}; $threadscn++) {
            if(! -r "$wavdir/$_.lock_$threadscn") {
               $sshflag = 1;
            }
            # Prepare array @codwav with all track names in, which are
            # still in progress, i. e. either being ripped or encoded.
            else {
               open(LOCK, "$wavdir/$_.lock_$threadscn");
               my @locklines = <LOCK>;
               close(LOCK);
               if($utftag == 0) {
                  $sshflag = del_lock("$wavdir", "$_.lock_$threadscn");
               }
               if($locklines[0]) {
                  chomp(my $locklines = $locklines[0]);
                  # Push track name into array only if not yet present.
                  my @presence = grep(/$locklines/, @codwav);
                  my $presence = $presence[0];
                  push @codwav, "$locklines" if(!$presence);
               }
            }
            last if($sshflag == 1);
         }
         $sshflag = 1 if($sshflag == 0);
         last if($sshflag == 1);
      }
      last if($sshflag == 1);
      sleep 3 if($sshflag != 1);
   }

   $machine = "local" if(!defined $machine or $machine eq "");
   if(-r "$wavdir/enc.log" && $verbose >= 3) {
      open(ENCLOG, ">>$wavdir/enc.log");
      print ENCLOG "...on machine $machine.\n"
         if($#threads > 1 || $machine !~ /^local$/);
      print ENCLOG "Executing scp command to $machine.\n"
         if($scp && $machine !~ /^local$/);
      close(ENCLOG);
   }
   elsif($verbose >= 3) {
      print "...on machine $machine.\n"
         if($#threads > 1 || $machine !~ /^local$/);
      print ENCLOG "Executing scp command to $machine.\n"
         if($scp && $machine !~ /^local$/);
   }

   open(LOCKF, ">$wavdir/$machine.lock_$threadscn");
   print LOCKF "$sepdir/$ripnam.$suffix\n";
   close(LOCKF);

   # We need more quotes for the commands (faac,flac,lame,ogg)
   # passed to the remote machine. NOTE: But now pay attention
   # to single quotes in tags. Quote them outside of single quotes.
   # TODO: Please tell me how to quote leading periods within ssh, thx.
   if($machine !~ /^local$/) {
      $enccom =~ s/'/'\\''/g;
      $enccom = "ssh " . $machine . " '" . $enccom . "'";
      if($scp) {
         # *Create* the directory:
         # Quote the double quotes with a backslash when using ssh!
         $sepdir = esc_char($sepdir, 0);
         $wavdir = esc_char($wavdir, 0);
         log_info("new-outputdir: $sepdir on $machine created.");
         log_system("ssh $machine mkdir -p \\\"$sepdir\\\"");
         log_info("new-outputdir: $wavdir on $machine created.");
         log_system("ssh $machine mkdir -p \\\"$wavdir\\\"");
         # *Copy* the File:
         # Don't overwrite destination file, it will confuse running
         # encoders! Do it the hard way! First get all lock-file-names
         # of that machine. There will be at least one, created above!
         opendir(LOCK, "$old_wavdir") or
            print "Can not read in $old_wavdir: $!\n";
         my @boxes = grep {/^$machine/i} readdir(LOCK);
         close(LOCK);
         my $wavflag = 0;
         # Open each lock-file, read the content, increase counter if
         # the same wavname is found. Again: it will be found at least
         # once.
         foreach(@boxes) {
            open(LOCKF, "$old_wavdir/$_") or
               print "Can't open $old_wavdir/$_: $!\n";
            my @content = <LOCKF>;
            close(LOCKF);
            $wavflag++ if("@content" =~ /$ripnam/);
         }
         $ripnam = esc_char($ripnam, 0);
         log_system("scp $wavdir/$ripnam.wav \\
           $machine:\"$wavdir/$ripnam.wav\" > /dev/null 2>&1")
           if($wavflag <= 1);
      }
   }
   else {
      # On the local machine escape at least the dollar sign.
      $ripnam =~ s/\$/\\\$/g;
      $sepdir =~ s/\$/\\\$/g;
   }
   $enccom = $enccom . " > /dev/null"
      unless($enc_no == 3 || $enc_no == 4);
   # Because Lame comes with the "Can't get "TERM" environment string"
   # error message, I decided to switch off all error output. This is
   # not good, if ssh errors appear, then RipIT may hang with a message
   # "Checking for lock files". If this happens, switch to verbosity 4
   # or higher and look what's going on.
   $enccom = $enccom . " 2> /dev/null"
      if($verbose <= 3 && ($enc_no != 3 || $enc_no != 4));
   if($machine !~ /^local$/ && $scp) {
      if($suffix eq "mpc") {
         $enccom = $enccom . " && \\
            scp $machine:\"$sepdir/$ripnam\_enc.$suffix\" \\
            $sepdir/$ripnam.$suffix > /dev/null 2>&1 && \\
            ssh $machine rm \"$sepdir/$ripnam\_enc.$suffix\" ";
      }
      elsif($suffix eq "wv") {
         $enccom = $enccom . " && \\
            scp $machine:\"$sepdir/$ripnam\_enc.$suffix\" \\
            $sepdir/$ripnam.$suffix > /dev/null 2>&1 && \\
            ssh $machine rm \"$sepdir/$ripnam\_enc.$suffix\" ";
            # TODO:
            # Copy correction file! Not yet supported.
      }
      else {
         $enccom = $enccom . " && \\
            scp $machine:\"$sepdir/$ripnam.$suffix\_enc\" \\
            $sepdir/$ripnam.$suffix > /dev/null 2>&1 && \\
            ssh $machine rm \"$sepdir/$ripnam.$suffix\_enc\" ";
      }
   }
   #
   if($suffix eq "mpc") {
      $enccom = $enccom . " && \\
             mv \"$sepdir/$ripnam\_enc.$suffix\" \\
             \"$sepdir/$ripnam.$suffix\""
         if($machine eq "local" || ($machine !~ /^local$/ && !$scp));
   }
   elsif($suffix eq "wv") {
      $enccom = $enccom . " && \\
             mv \"$sepdir/$ripnam\_enc.$suffix\" \\
             \"$sepdir/$ripnam.$suffix\""
         if($machine eq "local" || ($machine !~ /^local$/ && !$scp));
         # TODO:
         # Copy correction file! Not yet supported.
   }
   # This should not be used:
   elsif($suffix eq "mp3" and $utftag == 0) {
      # The command starts in Latin-1 and can not be enlarged with
      # a string in local encoding probably different from Latin-1.
      # The file name will never be found.
      open(LOCKF, ">>$wavdir/$machine.lock_$threadscn");
      print LOCKF "short-in: /tmp/$shortnam-$enc_no.mp3\n";
      print LOCKF "full-out: $sepdir/$ripnam.$suffix\n";
      close(LOCKF);
      $enccom = $enccom . " && \\
             mv \"/tmp/$shortnam-$enc_no.mp3_done\" \\
             \"/tmp/$shortnam-$enc_no.mp3\" &"
         if($machine eq "local" || ($machine !~ /^local$/ && !$scp));
   }
   else {
      $enccom = $enccom . " && \\
             mv \"$sepdir/$ripnam.$suffix\_enc\" \\
             \"$sepdir/$ripnam.$suffix\""
         if($machine eq "local" || ($machine !~ /^local$/ && !$scp));
   }
   $enccom = $enccom . " && \\
             rm \"$old_wavdir/$machine.lock_$threadscn\" &"
             unless($suffix eq "mp3" and $utftag == 0);

   # A huge hack only not to interfere with the ripper output.
   if($verbose >= 4) {
      my $ripmsg = "The audio CD ripper reports: all done!";
      my $ripcomplete = 0;
      if(-r "$wavdir/error.log") {
         open(ERR, "$wavdir/error.log")
            or print "Can not open file error.log!\n";
         my @errlines = <ERR>;
         close(ERR);
         my @ripcomplete = grep(/^$ripmsg/, @errlines);
         $ripcomplete = 1 if(@ripcomplete);
         if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
            open(ENCLOG, ">>$wavdir/enc.log");
            print ENCLOG "\n\nExecuting command on machine $machine",
                         " and trying to encode \n$ripnam.$suffix\_enc.\n";
            close(ENCLOG);
         }
         else {
            print "\nExecuting command on machine $machine and tring",
                  " to encode \n$ripnam.$suffix\_enc.\n";
         }
      }
      else {
         print "\nExecuting command on machine $machine and tring",
               " to encode \n$ripnam.$suffix\_enc.\n";
      }
   }
   log_system("$enccom");
   sleep 2; # Don't mess up with possible error-msgs from remote hosts.

   $wavdir = $old_wavdir;
   $sepdir = $old_sepdir;
   $ripnam = $old_ripnam;
   # Delete the wav only if all encodings of this track are done!
   # When the (last) encoding of a track started, its name is pushed
   # into the array @delname. Then the first (oldest) entry of the same
   # array (@delname) will be compared to the @codwav array. If this
   # entry is still present in the codewav-array, nothing happens, else
   # the wav file will be deleted and the track name shifted out of the
   # @delname.
   if($delwav == 1) {
      push @delname, "$ripnam";
      my $delflag = 0;
      while($delflag == 0) {
         my $delname = $delname[0];
         my $deln = quotemeta($delname);
         my @delwav = grep(/$deln/, @codwav);
         if(!$delwav[0] && $#delname > 1) {
            unlink("$wavdir/$delname.wav");
            log_info("File $wavdir/$delname.wav deleted.");
            shift(@delname);
            # Prevent endless loop if array is empty.
            $delflag = 1 if(!$delwav[0]);
         }
         else {
            $delflag = 1;
         }
      }
   }
}
########################################################################
#
# Delete wavs if sshlist was used. DONE: Improve code for following
# situation: if no .lock files are found, but the encoder did not yet
# finish, don't delete the wavs (i.e. wait for more lock files to
# appear). Do it only after a certain timeout with no .lock file.
# Furthermore if encoder subroutine checks again for
# ghost songs (in an extra loop), add an artificial ghost.lock file to
# ensure an additional timeout. Actually, this should not be necessary,
# as ghost songs are already present when last track has been ripped,
# but it may happen that check_wav quits before encoding of ghost
# songs started.
#
# We come here from sub finish_process.
#
sub check_wav {
   my $waitflag = 0;
   my $waitsecs = 3;
   sleep $waitsecs;
   my $time = sprintf "%02d:%02d:%02d:",
      sub {$_[2], $_[1], $_[0]}->(localtime);
   print "\n$time Checking for remaining lock files in $wavdir.\n"
      if($verbose > 1);
   my @timeout = split(/:/, $time);
   my $timeout = $timeout[1];
   while($waitflag < 4) {
      sleep $waitsecs;
      opendir(DIR, "$wavdir");
      my @locks = readdir(DIR);
      closedir(DIR);
      @locks = grep { /\.lock_\d+$/ } @locks;
      foreach (@locks) {
         $waitflag = del_lock("$wavdir", "$_")
            if($utftag == 0);
      }
      $waitflag++ if(! @locks);
      $waitsecs = $waitflag = 1 if(@locks);
      $waitsecs += 1 if(defined $pmerge and $pmerge ne "");
      $waitsecs += 1 if(defined $ghost and $ghost > 0);
      $waitsecs += $#coder if($waitflag  > 1);
      if(-r "$wavdir/ghost.lock") {
         sleep $waitsecs;
         unlink("$wavdir/ghost.lock");
         $waitsecs = $waitflag = 1;
      }
      my $time = sprintf "%02d:%02d:%02d:",
         sub {$_[2], $_[1], $_[0]}->(localtime);
      my @timeout = split(/:/, $time);
      my $timecnt = $timeout[1];
      $timecnt += 60 if($timecnt < $timeout);
      if($timecnt - $timeout > $#tracklist + 6) {
         print "\n$time Something went wrong with encoder, lock files ",
               "are locked for more than an hour.\nGiving up and ",
               "deleting all lock files.\n" if($verbose > 0);
         open(ERO,">>$wavdir/error.log")
            or print "Can not append to file ",
                     "\"$wavdir/error.log\"!\n";
         foreach (@locks) {
            open(LOCK, "$wavdir/$_");
            my @locklines = <LOCK>;
            close(LOCK);
            print ERO "Track on CD $cd{artist} - $cd{title} ",
                      "failed!\n";
            print ERO "@locklines\n";
            unlink("$wavdir/$_");
         }
         close(ERO);
      }
   }
   del_wav if($wav == 0);
   if($scp) {
      foreach my $machine (keys %sshlist) {
         next if($machine =~ /local/);
         foreach my $deldir (@sepdir, $wavdir) {
            my $dd = $deldir;
            $dd = esc_char($dd, 0);
            log_system("ssh $machine rm \"$dd/*.wav\" 2> /dev/null");
            log_system("ssh $machine rmdir -p \"$dd\" 2> /dev/null");
         }
      }
   }
}
########################################################################
#
# Delete wavs if sshlist was used.
#
sub del_wav {
   printf "\n%02d:%02d:%02d: ",
      sub {$_[2], $_[1], $_[0]}->(localtime)
      if(-d "$wavdir" && $verbose > 1);
   print "Searching existing wav files to be deleted.\n"
      if(-d "$wavdir" && $verbose > 1);
   if(-d "$wavdir") {
      opendir(DIR, "$wavdir");
      my @wavs = readdir(DIR);
      closedir(DIR);
      @wavs = grep { /\.wav$/ } @wavs;
      foreach (@wavs) {
         unlink("$wavdir/$_");
         log_info("File $wavdir/$_ deleted.");
      }
   }
}
########################################################################
#
# LCDproc subroutines, all credits to Max Kaesbauer. For comments and
# questions contact max [dot] kaesbauer [at] gmail [dot] com.
#

# print

sub plcd {
   my ($data) = @_;
   print $lcdproc $data."\n";
   my $res = <$lcdproc>;
}

# update

sub ulcd {
   if($lcdoline1 ne $lcdline1) {
      $lcdoline1 = $lcdline1;
      plcd("widget_set ripitlcd line1 1 2 {$lcdline1}");
       }
   if($lcdoline2 ne $lcdline2) {
      $lcdoline2 = $lcdline2;
      plcd("widget_set ripitlcd line2 1 3 {$lcdline2}");
   }
   if($lcdoline3 ne $lcdline3) {
      $lcdoline3 = $lcdline3;
      plcd("widget_set ripitlcd line3 1 4 {$lcdline3}");
   }
}

# init

sub init_lcd {
   $lcdproc = IO::Socket::INET->new(
      Proto     => "tcp",
      PeerAddr  => $lcdhost,
      PeerPort  => $lcdport,
   ) || die "Can not connect to LCDproc port\n";
   $lcdproc->autoflush(1);
   sleep 1;

   print $lcdproc "Hello\n";
   my @lcd_specs = split(/ /,<$lcdproc>);
   my %screen;

   $screen{wid} = $lcd_specs[7];
   $screen{hgt} = $lcd_specs[9];
   $screen{cellwid} = $lcd_specs[11];
   $screen{cellhgt} = $lcd_specs[13];

   $screen{pixwid} = $screen{wid}*$screen{cellwid};
   $screen{pixhgt} = $screen{hgt}*$screen{cellhgt};

   fcntl($lcdproc, F_SETFL, O_NONBLOCK);

   plcd("client_set name {ripit.pl}");
   plcd("screen_add ripitlcd");
   plcd("screen_set ripitlcd name {ripitlcd}");

   plcd("widget_add ripitlcd title title");
   plcd("widget_set ripitlcd title {RipIT $version}");

   plcd("widget_add ripitlcd line1 string");
   plcd("widget_add ripitlcd line2 string");
   plcd("widget_add ripitlcd line3 string");
}
########################################################################
#
# Read the CDDB on the local machine.
#
sub read_entry {
   my ($album, $artist, $totals, $trackno, $asin, $asinurl, $barcode,
       $catalog, $dgid, $language, $reldate, $mbreid);
   my @rawlines = ();
   my $logfile = $_[0];
   open(LOG, "<$logfile") || print "Can't open $logfile\n";
   my @cddblines = <LOG>;
   close(LOG);
   %cd = ();
   # Note that long lines may be split into several lines
   # all starting with the same keyword, e.g. DTITLE.
   # Note, discno is not yet reseted anymore. There will be some
   # interference.
   if($_[1] eq "musicbrainz" or $multi == 1) {
      chomp($artist = join('', grep(s/^artist:\s//i, @cddblines)));
      chomp($album = join('', grep(s/^album:\s//i, @cddblines)));
      chomp($categ = join('', grep(s/^category:\s//i, @cddblines)));
      chomp($genre = join('', grep(s/^genre:\s//i, @cddblines)));
      chomp($year = join('', grep(s/^year:\s//i, @cddblines)));
      chomp($cddbid = join('', grep(s/^cddbid:\s//i, @cddblines)));
      chomp($discid = join('', grep(s/^discid:\s//i, @cddblines)));
      chomp($mbreid = join('', grep(s/^mbreid:\s//i, @cddblines)));
      chomp($asin = join('', grep(s/^asin:\s//i, @cddblines)));
      chomp($asinurl = join('', grep(s/^asinurl:\s//i, @cddblines)));
      chomp($dgid = join('', grep(s/^discogs:\s//i, @cddblines)));
      chomp($barcode = join('', grep(s/^barcode:\s//i, @cddblines)));
      chomp($catalog = join('', grep(s/^catalog:\s//i, @cddblines)));
      chomp($language = join('', grep(s/^language:\s//i, @cddblines)));
      chomp($reldate = join('', grep(s/^reldate:\s//i, @cddblines)));
      chomp($trackno = join('', grep(s/^trackno:\s//i, @cddblines)));
      chomp($totals = join('', grep(s/^totaltime:\s//i, @cddblines)));
      chomp($discno = join('', grep(s/^disc-number:\s//i, @cddblines)));
      chomp($trackoffset = join('', grep(s/^trackoff:\s//i, @cddblines)));
      $trackoffset = 0 unless($trackoffset =~ /^\d+$/);
      $trackno = $_[2] unless($trackno);

      push(@rawlines, "# xmcd CD database generated by RipIT\n#\n",
                      "# Track frame offsets:\n");
      my $i = 0;
      foreach(@framelist) {
         push(@rawlines, "#\t$_\n") if($i < $#framelist);
         $i++;
      }
      # In case $rip == 0 disc length is given in seconds only, could
      # be changed there, but for now do it this way when regular
      # disc length is in minutes:seconds format.
      if(defined $totals && $totals =~ /:/) {
         my @totals = split(/:/, $totals);
         $totals = $totals[0] * 60 + $totals[1];
      }
      push(@rawlines, "#\n# Disc length: $totals seconds\n");
      push(@rawlines, "# Revision: 0\n");
      push(@rawlines, "# Submitted via: RipIT $version\n#\n");
      push(@rawlines, "DISCID=$cddbid\n");
      push(@rawlines, "DTITLE=$artist / $album\n");
      push(@rawlines, "DYEAR=$year\n");
      push(@rawlines, "DGENRE=$genre\n");
   }
   else {
      $cd{raw} = \@cddblines;
      # In case we want to know the toc read it out here:
      foreach (@cddblines) {
         chomp;
         my $tocnumber = $_;
         $tocnumber =~ s/#\s*Disc\slength:\s*/# /;
         next unless($tocnumber =~ /^#\s*\d+/);
         $tocnumber =~ s/#\s*//g;
         $tocnumber =~ s/\s*seconds.*$//;
         push(@framelist, $tocnumber);
      }
      # Sometimes the archive entry might be corrupted (ripits fault?);
      # do not fail in this case.
      $framelist[$#framelist] *= 75 if($framelist[0]);
      chomp($artist = join(' x/x ', grep(s/^DTITLE=//g, @cddblines)));
      $artist =~ s/[\015]//g;
      $artist =~ s/\n\sx\/x\s//g;
      $artist =~ s/\sx\/x\s//g;
      # Artist is just the first part before first occurrence of
      # the slash (/), album gets all the rest!
      my @disctitle = split(/\s\/\s/, $artist);
      $artist = shift(@disctitle);
      $album = join(' / ', @disctitle);
      chomp $artist;
      chomp $album;
      $categ = $_[1];
      unless($genre) {
         chomp($genre = join('', grep(s/^DGENRE=//, @cddblines)));
         $genre =~ s/[\015]//g;
      }
      unless($year) {
         chomp($year = join('', grep(s/^DYEAR=//, @cddblines)));
         $year =~ s/[\015]//g;
      }
      unless($discid) {
         chomp($discid = join('', grep(s/^DISCID=//, @cddblines)));
         $discid =~ s/[\015]//g;
         $discid = "" unless($discid =~ /\-$/ && length($discid) == 28);
      }
      if(defined $discno and $discno < 2) {
         chomp($discno = join('', grep(s/^DISCNO=//, @cddblines)));
         $discno =~ s/[\015]//g;
      }
      unless($dgid) {
         chomp($dgid = join('', grep(s/^DGID=//, @cddblines)));
         $dgid =~ s/[\015]//g;
         $dgid = "" if($dgid =~ /\D/);
      }
      unless($mbreid) {
         chomp($mbreid = join('', grep(s/^MBREID=//, @cddblines)));
         $mbreid =~ s/[\015]//g;
         $mbreid = "" if($mbreid =~ /\-$/ or length($mbreid) <= 28);
      }
      $trackno = $_[2];
   }
   $cd{artist} = $artist;
   $cd{title} = $album;
   $cd{cat} = $categ;
   $cd{genre} = $genre;
   $cd{id} = $cddbid;
   $cd{discid} = $discid;
   $cd{mbreid} = $mbreid;
   $cd{asin} = $asin;
   $cd{asinurl} = $asinurl;
   $cd{dgid} = $dgid;
   $cd{year} = $year;
   $cd{barcode} = $barcode;
   $cd{catalog} = $catalog;
   $cd{language} = $language;
   $cd{reldate} = $reldate;
   $cd{discno} = $discno if(defined $discno and $discno > 0);

   my $h = 0; # Array counter
   my $i = $trackoffset + 1; # Track counter for display
   my $j = $trackoffset; # Track name counter
   # Problem: if the local file has been saved with a trackoffset,
   # counter $i will work. But in case it has been saved without and
   # operator wants to rip with a trackoffset, $j must be reset to 0.
   # Hm... shall we test tracknumbers in case trackoffset is larger than
   # 0 if tracknumbers start at TTITLE0= or not? If not suppose local
   # CDDB file is actual. Let's test and alter the track name counter.
   if($trackoffset > 0 or $discno > 0) {
      my @trackcn = grep(/^TTITLE\d+=/, @cddblines);
      @trackcn = grep(s/^TTITLE//, @trackcn);
      @trackcn = grep(s/=.*//, @trackcn);
      if(defined $trackcn[0] and $trackcn[0] == 0) {
         $j = 0;
      }
      elsif(defined $trackcn[0] and $trackcn[0] > 0) {
         $j = $trackcn[0];
         $i += $j;
         $trackoffset = $j if($trackoffset == 0);
      }
   }

   while($i <= $trackno + $trackoffset) {
      my @track = ();
      @track = grep(s/^TTITLE$j=//, @cddblines) if($multi == 0);
      @track = grep(s/^track\s$i:\s//i, @cddblines)
         if($_[1] eq "musicbrainz" or $multi == 1);
      my $track = join(' ', @track);
      $track =~ s/[\015]//g;
      $track =~ s/\n\s\/\s//g;
      chomp $track;
      $cd{track}[$h] = $track;
      push(@rawlines, "TTITLE$j=$track\n")
         if($_[1] eq "musicbrainz" or $multi == 1);
      $h++;
      $i++;
      $j++;
   }

   if($_[1] eq "musicbrainz" or $multi == 1) {
      push(@rawlines, "EXTD=\n");
      $i = 1;
      $j = 0;
      $j += $trackoffset if($trackoffset > 0);
      while($i <= $trackno) {
         push(@rawlines, "EXTT$j=\n");
         $i++;
         $j++;
      }
      push(@rawlines, "PLAYORDER=\n");
      push(@rawlines, "CDINDEX=" . $cd{discid} . "\n") if($cd{discid});
      push(@rawlines, "MBREID=" . $cd{mbreid} . "\n") if($cd{mbreid});
      push(@rawlines, "ASIN=" . $cd{asin} . "\n") if($cd{asin});
      push(@rawlines, "ASINURL=" . $cd{asinurl} . "\n") if($cd{asinurl});
      push(@rawlines, "DGID=" . $cd{dgid} . "\n") if($cd{dgid});
      push(@rawlines, "BARCODE=" . $cd{barcode} . "\n") if($cd{barcode});
      push(@rawlines, "CATALOG=" . $cd{catalog} . "\n") if($cd{catalog});
      push(@rawlines, "RELDAT=" . $cd{reldate} . "\n") if($cd{reldate});
      push(@rawlines, "LANG=" . $cd{language} . "\n") if($cd{language});
      push(@rawlines, "DISCNO=" . $cd{discno} . "\n") if($cd{discno});

      $cd{raw} = \@rawlines;
   }
   return;
}
########################################################################
#
# Delete error.log if there is no track-comment in!
#
sub del_erlog {
   open(ERR, "$wavdir/error.log")
     or print "Fatal: $wavdir/error.log disappeared!\n";
   my @errlines = <ERR>;
   close(ERR);

   my @covs = grep(s/^flac-cover: //, @errlines) if(defined $coverpath);
   chomp($_) foreach(@covs);
   # Add missing coverart and tags to files previously not done because
   # of option thread or sshlist.
   my @md5tracks = grep(s/^md5: //, @errlines) if($md5sum == 1);
   @mp3tags = grep(s/^mp3tags: //, @errlines);
   if(@md5tracks) {
      foreach (@md5tracks) {
         my ($sepdir, $donetrack) = split(/;#;/, $_);
         chomp $donetrack;
         # Add special mp3 tags.
         if(@mp3tags && $donetrack =~ /mp3$/) {
            mp3_tags("$sepdir/$donetrack")
               if(defined $mp3tags[0] && $mp3tags[0] !~ /^\s*$/);
         }
         # Add coverart if it is a mp3 or ogg.
         if($donetrack =~ /mp3$/ && -f "$coverpath" && -s "$coverpath") {
            mp3_cover("$sepdir/$donetrack", "$coverpath");
         }
         elsif($donetrack =~ /ogg$/ && -f "$coverpath" && -s "$coverpath") {
            ogg_cover("$sepdir/$donetrack", "$coverpath");
         }
      }
   }
   # Add album-gain once all files are present.
   for(my $c = 0; $c <= $#coder; $c++) {
      if($verbose > 2 && ($mp3gain || $vorbgain || $flacgain || $aacgain || $mpcgain || $wvgain)) {
         printf "\n%02d:%02d:%02d: ",
            sub {$_[2], $_[1], $_[0]}->(localtime) if($verbose > 2);
         print "Starting with album gain detection for $suffix[$c]-files.\n";
      }
      if($mp3gain && $suffix[$c] =~ /mp3/) {
         log_system("$mp3gain \"$sepdir[$c]/\"*.$suffix[$c]");
      }
      elsif($vorbgain && $suffix[$c] =~ /ogg/) {
         log_system("$vorbgain \"$sepdir[$c]/\"*.$suffix[$c]");
      }
      elsif($flacgain && $suffix[$c] =~ /flac/) {
         log_system("$flacgain \"$sepdir[$c]/\"*.$suffix[$c]");
      }
      elsif($aacgain && $suffix[$c] =~ /m4a|mp4/) {
         log_system("$aacgain \"$sepdir[$c]/\"*.$suffix[$c]");
      }
      elsif($mpcgain && $suffix[$c] =~ /mpc/) {
         log_system("$mpcgain \"$sepdir[$c]/\"*.$suffix[$c]");
      }
      elsif($wvgain && $suffix[$c] =~ /wv/) {
         log_system("$wvgain \"$sepdir[$c]/\"*.$suffix[$c]");
      }
      else {
         print "\nNo album gain command found for $suffix[$c].\n"
         if($verbose > 5 && ($mp3gain || $vorbgain || $flacgain || $aacgain || $mpcgain || $wvgain));
      }
   }
   # Once all tagging is done, continue with md5sum calculation.
   printf "\n\n%02d:%02d:%02d: ",
      sub {$_[2], $_[1], $_[0]}->(localtime)
      if($verbose > 2 && $md5sum == 1);
   print "Starting with md5sum calculation.\n"
      if($verbose > 2 && $md5sum == 1);
   # Final sound file stuff
   my $album = clean_all($album_utf8);
   my $riptrackname;

   # New parameters for tracktemplate used for file names only, i.e.
   # less verbose than the corresponding tags $artistag and tracktag.
   my $trackartist;
   my $artistag;
   my $tracktitle;

   my ($delimiter, $dummy) = check_va(0) if($vatag > 0);
   my $delim = "";
   if(defined $delimiter) {
      my $delim = quotemeta($delimiter);
      $vatag = 0 if($delim eq "");
   }

   # Array @tracksel has not yet been updated in case ghost songs are
   # found.
   my $orig_size = $#tracksel + 1; # Is this a bug? Version 4.0.0 fails
   # if only on track with ghost song is to be ripped...
   # The above line does not work if a track selection has been used...
   foreach(@tracksel) {
      # Don't alter array @tracksel, rather the original not the
      # modified one.
      my $tn = $_;
      # Update array @tracksel if ghost songs have been detected, but
      # only once.
      if($ghost == 1 && $tn == $tracksel[$#tracksel]
                     && -r "$wavdir/ghost.log") {
         open(GHOST, "<$wavdir/ghost.log")
            or print "Can not read file ghost.log!\n";
         my @errlines = <GHOST>;
         close(GHOST);
         my @selines = grep(s/^Array seltrack: //, @errlines);
         @tracksel = split(/ /, $selines[$#selines]);
         chomp($_) foreach(@tracksel);
         $ghost = 2;
      }
# Did I need this with tracks split into several parts?
#       if($ghost == 2) {
#          $tn = $orig_size++;
#       }
      my $riptracktag = $tracktags[$tn - 1];
      $riptracktag = $tracktags[$tn] if($hiddenflag == 1);
      # Split the tracktag into its artist part and track part if
      # VA style is used, no messages to be printed.
      if($va_flag > 0 && $riptracktag =~ /$delim/) {
         ($artistag, $riptracktag) = split_tags($riptracktag, $delim);
      }
      # Actually, we do not need the "full" tags, only names for files.
      $artistag = clean_all($artist_utf8) unless(defined $artistag);
      $trackartist = clean_all($artistag);
      $trackartist = clean_name($trackartist);
      $trackartist = clean_chars($trackartist);
      $tracktitle = clean_all($riptracktag);
      $tracktitle = clean_name($tracktitle);
      $tracktitle = clean_chars($tracktitle);
      $trackartist =~ s/ /_/g if($underscore == 1);
      $tracktitle =~ s/ /_/g if($underscore == 1);

      # Note, here we work on the track number coming from @tracksel.
      if($rip == 1) {
         $riptrackname = get_trackname($_, $tracklist[$tn - 1], 0, $trackartist, $tracktitle);
         $riptrackname = get_trackname($_, $tracklist[$tn], 0, $trackartist, $tracktitle)
            if($hiddenflag == 1);
      }
      # Tracklist already has a track counter as prefix in case we
      # re-encode... this will break trackoffset...
      #
      else {
#          $riptrackname = $tracklist[$_ - 1];
#          $riptrackname = $tracklist[$_] if($hiddenflag == 1);
         $riptrackname = get_trackname($tn, $tracktitle, 0, $trackartist, $tracktitle);
         # Just to make things clear.
         $riptrackname = get_trackname($tn, $tracktitle, 0, $trackartist, $tracktitle) if($hiddenflag == 1);
      }
      $riptrackname = $album if($book == 1 or $cdcue > 0);
      for(my $c = 0; $c <= $#coder; $c++) {
         chmod oct($fpermission),
            "$sepdir[$c]/$riptrackname.$suffix[$c]"
            if($fpermission);
         # Generate md5sum of files.
         if($md5sum == 1) {
            if(-r "$sepdir[$c]/$riptrackname.$suffix[$c]") {
               md5_sum("$sepdir[$c]",
                  "$riptrackname.$suffix[$c]", 1);
            }
            else {
               print "Error, no file \"$sepdir[$c]/$riptrackname.$suffix[$c]\" found.\n" if($verbose > 0);
            }
         }
      }
      last if($book > 0 || $cdcue > 0);
   }

   # Change file permissions for md5 files.
   if($fpermission && $md5sum == 1){
      foreach(@sepdir, $wavdir) {
         opendir(MD5, "$_") or print "Can not read in $_: $!\n";
         my @md5files = grep {/\.md5$/i} readdir(MD5);
         close(MD5);
         # Security check: if encoder not installed, but directory
         # created, then no md5sum-file will be found and the
         # directory instead of the file gets the permissions.
         next unless($md5files[0]);
         if($_ eq $wavdir) {
            chmod oct($fpermission), "$_/$md5files[0]" if($wav == 1);
         }
         else {
            chmod oct($fpermission), "$_/$md5files[0]";
         }
      }
   }
   chmod oct($fpermission), "$wavdir/cd.toc" if($fpermission);
   my @ulink = grep(/^Track /, @errlines);
   if(!@ulink && $multi == 0) {
      unlink("$wavdir/error.log");
   }
   elsif($fpermission) {
      chmod oct($fpermission), "$wavdir/error.log";
   }
   if($ghost > 0 && -r "$wavdir/ghost.log") {
      unlink("$wavdir/ghost.log");
   }
   if(defined $coverpath && defined $covs[0] && -f "$covs[0]") {
      unlink("$covs[0]");
   }
   if($wav == 0 && $wavdir ne $homedir) {
      # I don't like the -p option.
      log_system("rmdir -p \"$wavdir\" 2> /dev/null");
   }
}
########################################################################
#
# Escape special characters when using scp.
#
sub esc_char {
   $_[0] =~ s,\\,x,g if($_[1] == 0);
   $_[0] =~ s/\(/\\\(/g;
   $_[0] =~ s/\)/\\\)/g;
   $_[0] =~ s/\[/\\\[/g;
   $_[0] =~ s/\]/\\\]/g;
   $_[0] =~ s/\&/\\\&/g;
   $_[0] =~ s/\!/\\\!/g;
   $_[0] =~ s/\?/\\\?/g;
   $_[0] =~ s/\'/\\\'/g;
   $_[0] =~ s/\$/\\\$/g;
   $_[0] =~ s/ /\\ /g if($_[1] == 0);
   return $_[0];
}
########################################################################
#
# Calculate how much time ripping and encoding needed.
#
sub cal_times {
   my $encend = `date \'+%R\'`;
   chomp $encend;
   # Read times from the file $wavdir/error.log.
   open(ERR, "$wavdir/error.log")
      or print "Can't calculate time, $wavdir/error.log disappeared!\n";
   my @errlines = <ERR>;
   close(ERR);
   my @enctime = grep(s/^Encoding needed //, @errlines);
   my @ripstart = grep(s/^Ripping started: //, @errlines);
   my @ripend = grep(s/^Ripping ended: //, @errlines);
   # Read info about trimmed tracks in file $wavdir/ghost.log.
   if(-r "$wavdir/ghost.log") {
      open(ERR, "$wavdir/ghost.log")
      or print "Can't read $wavdir/ghost.log.\n";
      @errlines = <ERR>;
      close(ERR);
   }
   chomp(my $blanktrks = join(', ', grep(s/^Blankflag = //, @errlines)));
   chomp(my $ghostrks = join(', ', grep(s/^Ghostflag = //, @errlines)));
   chomp(my $splitrks = join(', ', grep(s/^Splitflag = //, @errlines)));
   $blanktrks =~ s/\n//g;
   $ghostrks =~ s/\n//g;
   $splitrks =~ s/\n//g;
   $blanktrks =~ s/,\s(\d+)$/ and $1/g;
   $ghostrks =~ s/,\s(\d+)$/ and $1/g;
   $splitrks =~ s/,\s(\d+)$/ and $1/g;

   my $riptime = 0;
   if($rip == 1) {
      @ripstart = split(/:/, $ripstart[0]);
      @ripend = split(/:/, $ripend[0]);
      $ripend[0] += 24 if($ripend[0] < $ripstart[0]);
      $riptime = ($ripend[0] * 60 + $ripend[1]) -
                    ($ripstart[0] * 60 + $ripstart[1]);
   }

   my $enctime = "@enctime";
   chomp $enctime;
   if($encode == 1) {
      @enctime = split(/ /, $enctime);
      $enctime[0] = 0 unless(@enctime);
      $enctime = int($enctime[0]/60);
   }
   else {
      $enctime = 0;
   }

   # Return to sub finish_process.
   return ($riptime,$enctime,$encend,$blanktrks,$ghostrks,$splitrks);
}
########################################################################
#
# Thanks to mjb: log info to file.
#
sub log_info {
   if(!defined($infolog)) { return; }
   elsif($infolog eq "") { return; }
   open(SYSLOG, ">>$infolog") or
   print "Can't open info log file <$infolog>.\n";
   print SYSLOG "@_\n";
   close(SYSLOG);
}
########################################################################
#
# Thanks to mjb and Stefan Wartens improvements:
# log_system used throughout in place of system() calls.
#
sub log_system {
   my $P_command = shift;
   if($verbose > 3) {
      # A huge hack only not to interfere with the ripper output.
      if($P_command =~ /faac|flac|lame|machine|mpc|mp4als|oggenc|vorbiscomment/ &&
         $P_command !~ /cdparanoia|cdda2wav|dagrab|icedax|vorbiscomment.*COVERART/) {
         enc_print("$P_command", 3);
      }
      elsif($P_command =~ /mkdir|COVERART/) {
         my $prcmd = $P_command;
         $prcmd =~ s/COVERART=.*$/COVERART=binary-data-removed/;
         print "system: $prcmd\n\n" if($verbose > 4);
      }
      else {
         print "system: $P_command\n\n";
      }
   }

   # Log the system command to logfile unless it's the coverart command
   # for vorbiscomment with the whole binary picture data.
   log_info("system: $P_command") unless($P_command =~ /vorbiscomment/);

   # Start a watch process to check progress of ripped tracks.
   if($parano == 2 && $P_command =~ /^cdparano/
                   && $P_command !~ /-Z/
                   && $P_command !~ /-V/) {
      my $pid = 0;
      # This is probably dangerous, very dangerous because of zombies...
      $SIG{CHLD} = 'IGNORE';
      unless($pid = fork) {
         exec($P_command);
         exit;
      }
      # ... but we check and wait for $pid to finish in subroutine.
      my $result = check_ripper($P_command, $pid);
      waitpid($pid, 0);
      $SIG{CHLD} = 'DEFAULT';
      return $result;
   }
   else {
      system($P_command);
   }

   # system() returns several pieces of information about the launched
   # subprocess squeezed into a 16-bit integer:
   #
   #     7  6  5  4  3  2  1  0  7  6  5  4  3  2  1  0
   #   +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
   #   |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  [ $? ]
   #   +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
   #    \_____________________/ \/ \__________________/
   #          exit code        core    signal number
   #
   # To get the exit code, use        ($? >> 8)
   # To get the signal number, use    ($? & 127)
   # To get the dumped core flag, use ($? & 128)

   # Subprocess has been executed successfully.
   return 1 if $? == 0;

   # Subprocess was killed by SIGINT (CTRL-C). Exit RipIT.
   die "\n\nRipit caught a SIGINT.\n" if(( $? & 127) == 2);

   # Subprocess could not be executed or failed.
   return 0;
}
########################################################################
#
# Special characters in cd.toc file won't be written correctly by
# cdrdao, so map them to octal.
#
# Thanks to pancho horrillo:
# http://perldoc.perl.org/perluniintro.html#Displaying-Unicode-As-Text
#
sub oct_char {
   $_[0] = join '',
               map { $_ > 191
                     ? sprintf '\%o', $_
                     : chr $_
               } unpack("C0U*", "$_[0]");
}
########################################################################
#
# Check if there is a CD in the CD device. If a CD is present, start
# process. If not, wait until operator inserts a CD, i.e. come back!
# Problem: when used with option loop, the CD already done should not
# be reread again. In this case, don't close the tray automatically.
#
sub cd_present {
   print "\nExecuting sysopen(CD, $scsi_cddev, O_RDONLY | O_NONBLOCK) ",
         "or return;\n" if($verbose > 5);
   sysopen(CD, $scsi_cddev, O_RDONLY | O_NONBLOCK) or return;
   my $os = `uname -s`;
   my $CDROMREADTOCHDR = 0x5305;            # Linux
   if($os eq "SunOS") {
      $CDROMREADTOCHDR = 0x49b;
   }
   elsif($os =~ /BSD/i) {
      $CDROMREADTOCHDR = 0x40046304;
   }
   my $tochdr = "";
   my $err = ioctl(CD, $CDROMREADTOCHDR, $tochdr);
   close(CD);
   return $err;
}
########################################################################
#
# A hack to reinitialize global variables before starting a new loop.
#
sub init_var {
   # We lost and tweaked too many things, start from scratch:
   read_config() if($config == 1);
   # But all arguments passed on CL should remain...
   $categ            = "";
   $cddbid           = 0;
   $cdid             = "";
   $discid           = "";
   @audio            = ();
   @isrcs            = ();
   @idata            = ();
   @framelist        = ();
   @secondlist       = ();
   @tracklist        = ();
   @tracktags        = ();
   @seltrack         = ();
   @tracksel         = ();
   %cd               = ();
   $cddbsubmission   = 2;
   $hiddenflag       = 0;
   $wavdir           = "";
   @sepdir           = ();
   $year             = "";
   $genre            = "";
   $album_utf8       = "";
   $artist_utf8      = "";
   if(defined $pscsi_cddev) {
      $scsi_cddev = $pscsi_cddev;
   }
   else {
      $scsi_cddev = $pcddev if($pcddev);
   }
   if($scsi_cddev eq "") {
      $scsi_cddev = $cddev;
   }
}
########################################################################
#
# Get the revision number of the CDDB entry.
#
sub get_rev {
   my @revision = grep(/^\#\sRevision:\s/, @{$cd{raw}});
   my $revision = join('', grep(s/^\#\sRevision:\s//, @revision));
   chomp $revision if($revision);
   return $revision;
}
########################################################################
#
# Change case to lowercase and uppercase first if wanted. Test command:
# perl -e '$string="gLabber (live/mix:radio edit [perl re-mix])"; $string=~s/(\w+)/\u\L$1/g; print "\nString is: $string\n"'
#
sub change_case {
# We want to differentiate if coming from a track or directory string to
# be lowercased (or put to ucfirst). Second argument gives that hint:
# "t" for track, "d" for directory.
#   use encoding "utf8"; # This will break every single non ascii char!
if($lowercase == 1 or ($lowercase == 2 and $_[1] eq "t")
                   or ($lowercase == 3 and $_[1] eq "d")
                   or $uppercasefirst == 1) {
      $_[0] = lc($_[0]);
      $_[0] =~ tr/[ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏ]/[àáâãäåæçèéêëìíîï]/;
      $_[0] =~ tr/[ÐÑÒÓÔÕÖØÙÚÛÜÝÞ]/[ðñòóôõöøùúûüýþ]/;
   }
   if($uppercasefirst == 1) {
      # s/(\w+)/\u\L$1/g; # Does not work with non ascii chars...
      my @words = split(/ /, $_[0]);
      foreach (@words) {
         s/(\w+)/\u\L$1/g; # Ensure ucfirst within brackets etc.
         $_ = "\u$_";
         $_ =~ tr/^[àáâãäåæçèéêëìíîï]/[ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏ]/;
         $_ =~ tr/^[ðñòóôõöøùúûüýþ]/[ÐÑÒÓÔÕÖØÙÚÛÜÝÞ]/;
      }
      $_[0] = join(' ', @words);
   }
   return $_[0];
}
########################################################################
#
# Strip dodgey chars I. This will be done for file names and tags.
#
# TODO: Do we really have to erase all of them? Maybe we should keep
# some for the tags...
#
sub clean_all {
   return unless(defined $_[0]);
   $_[0] =~ s/[;><"\015]//g;
   $_[0] =~ s/\`/\'/g;
   $_[0] =~ s/´/\'/g;
   $_[0] =~ s/\s+/ /g;
   return $_[0];
}
########################################################################
#
# Strip dodgey chars II. This will only be done for file names.
#
sub clean_name {
   return unless(defined $_[0]);
   $_[0] =~ s/[*]//g;
   $_[0] =~ s/\// - /g;
   $_[0] =~ s/\s+/ /g;
   return $_[0];
}
########################################################################
#
# Strip dodgey chars III. This will optionally be done for file names
# and paths. Remember the default chars to be erased are:   |\:*?$  plus
# blanks and periods at begin and end of file names and directories.
# But the ending periods problem is not done here, because
# it should only affect directories, not files which have a suffix
# anyway! See subroutine create_dirs!
#
sub clean_chars {
   return unless(defined $_[0]);
   # Delete beginning blanks in directory names.
   $_[0] =~ s,/\s+,/,g if($chars =~ /NTFS/);
   # Delete beginning blanks in file names.
   $_[0] =~ s/^\s+//g if($chars =~ /NTFS/);
   # Delete beginning periods in directory names.
   $_[0] =~ s,/\.+,/,g if($chars =~ /HFS|NTFS/);
   # Delete beginning periods in file names.
   $_[0] =~ s/^\.+//g if($chars =~ /HFS|NTFS/);
   my $purged_chars = $chars;
   $purged_chars = ":" if($chars =~ /HFS/);
   $purged_chars = "[|\\\\:*?\$]" if($chars =~ /NTFS/);
   $_[0] =~ s/$purged_chars//g if($purged_chars ne "");
   $_[0] =~ s/\s+/ /g;
   $_[0] =~ s/\s$//;
   return $_[0];
}
########################################################################
#
# Put all chars in brackets and escape some.
#
sub check_chars {
   $chars =~ s/\\/\\\\/;
   $chars =~ s/-/\\-/;
   $chars =~ s/]/\\]/;
   $chars =~ s/\s/\\s/;
   $chars = "[" . $chars . "]" unless($chars =~ /HFS|NTFS|off/);
}
########################################################################
#
# Extract the CDDB comment lines starting with EXTD=.
# NOTE: Each EXTD line my have \n's, but two EXTD lines do NOT
# mean that there's a line break in between! So, what we have to do
# is, put all comment lines into a string and split the string
# according to the explicitly \n's (i.e. use \\n).and add a \n at the
# end of each line!
#
sub extract_comm {
   my @comment = grep(/^EXTD=/, @{$cd{raw}});
   @comment = grep(s/^EXTD=//, @comment);
   my $line = "@comment";
   $line =~ s/[\015]//g;
   @comment = split(/\\n/, $line);
   foreach (@comment) {
      chomp $_;
      $_ =~ s/^\s+//g;
   }
   return (@comment);
}
########################################################################
#
# Display a help page and exit.
#
# New options step 12: Add a short explanation for option --help and do
# not forget to update the manpage ripit.1 to be checked with option -l.
#
sub print_help {
   print <<END

SYNOPSIS:
   ripit [options]

OPTIONS:
 [track_selection]
              If not specified, all tracks will be ripped. Type a number
              or a selection of tracks using numbers separated by commas
              or hyphens. Use 1-a to rip all consecutive audio tracks
              and prevent trying to rip data tracks. Default: not set.
 -I, --span number-number
              Give a span or interval to rip only a part of the track.
              The cdparanoia notation is used in the format hh:mm:ss.ff
              without brackets. The hyphen is mandatory.
 --merge ordered list of comma separated intervals
              Place a hyphen or a + between first and last track number
              to be merged, default: not set.
 -o, --outputdir directory
              Where the sound should go. If not set, \$HOME will be used.
              Default: not set.
 --dpermission number
              Define directory permissions, default: 0755.
 --fpermission number
              Define permissions of sound and log files, default: not
              set, i.e. depending on the system settings.
 -d, --device cddevice
              Path of audio CD device, default: /dev/cdrom.
 --scsidevice cddevice
              Devicename for a different device node of cddevice
              where non ripping commands shall be executed.
 -r, --ripper number
              0 dagrab, 1 cdparanoia, 2 cdda2wav, 3 tosha, 4 cdd,
              default: 1.
 --ripopt options
              Additional options for specific ripper. Default: not set.
 --offset number
              Give a sample offset for the ripper. Optiononly supported
              by cdparanoia and rip (Morituri). Default: not set.
 -Q, --accuracy number
              Check rips at AccurateRip using Morituri (rip) which must
              be installed. Default: off (0).
 -Y, --verify number
              Rip track until md5sum for 2 rips match, maximum tries
              is number given as argument, default: 1, i.e. no checks
              will be done.
 --nicerip value
              Set niceness of ripping process, default: 0.
 -Z, --disable-paranoia [number]
              When using dagrab, the number of retries will be set to 3,
              with cdparanoia this option is equal to the -Z option of
              cdparanoia. Usefull for faster ripping but not recommended.
              Use no argument or 1 to swith paranoia off or 2 if failed
              tracks should be done again without paranoia (only one
              retry). Default: off (i.e. paranoia on).
 -G, --ghost  Analyze wav and split into possible chunks of sound or try
              to trim lead-in/out. This may override option merge!
              Delete blank tracks if only silence ("zero bytes") are
              found. Experimental! Default: off.
 --extend seconds
              Enlarge splitted chunk by number of seconds if possible,
              or track may be trimmed if value is small (e.g. 0.2), use
              with caution! default: 2.0.
 --prepend seconds
              Enlarge splitted chunk by number of seconds if possible,
              or track may be trimmed if value is small (e.g. 0.2), use
              with caution! Default: 2.0.
 -c, --coder encoder
              0 Lame, 1 Oggenc, 2 Flac,  3 Faac, 4 mp4als, 5 Musepack,
              6 Wavpack, 7 ffmpge, a comma separated list or use -c for
              each encoder.
              The same encoder may be stated more than once. Adapt
              --dirtemplate in this case, see below. Default: 0.
 --musenc name
              Pass the command line name of Musepack encoder, e. g.
              mppenc. Default: mpcenc.
 --faacopt Faac-options
              Pass other options to the encoder,  quote them with double
              quotes if needed; comma separated list if same enocder
              is used more than once. Default: not set.
 --flacopt    Flac-options
              Same as above.
 --lameopt    Lame-options
              Same as above.
 --museopt    Musepack-options
              Same as above.
 --mp4alsopt  mp4als-options
              Same as above.
 --oggencopt  Oggenc-options
              Same as above.
 --wavpacopt  Wavpack-options
              Same as above.
 --ffmpegopt  ffmpeg-options
              Same as above.
 --ffmpegsuffix suffix
              Suffix of the choosen encoder in ffmpeg, a comma sparated
              list; default: not set.
 -q, --quality quality
              A comma separated list of values or the word \"off\", passed
              in the same order as the list of encoders! If no encoders
              passed, follow the order of the config file! No quality
              for wavpack and ffmpeg, use options instead. Default
              5,3,5,100,0,5.
 -v, --vbrmode mode
              Variable bitrate, only used with Lame, mode is new or old,
              see Lame manpage.  The Lame-option quality will be changed
              to -V instead of -q if vbr-mode is used; default: not set.
 -b, --bitrate rate
              Encode \"mp3\" at this bitrate for Lame. If option --vbrmode
              used, bitrate is equal to the -b option, so one might want
              to set it \"off\", default: 128.
 -B, --maxrate rate
              maxrate (Bitrate) for Lame using --vbrmode is equal to the
              -B option for Lame or the -M option for Oggenc,
              default: 0.
 -S, --preset mode
              Use the preset switch when encoding with Lame. With option
              --vbrmode new --preset fast will be used. Default: off.
 -W, --chars [list]
              Exclude special characters and  (ending!)  periods in file
              names and path. The argument is optional. Following
              characters will be erased, if no argument is stated:
              |\\:*?\$  else only ending periods and all passed ones.
              Default: off.
 --comment comment
              Specify a comment tag (mp3, m4a), or a description tag for
              (ogg, flac). To write the cddbid used for freedb
              or the MusicBrainz discid into the comment, use the word
              \"cddbid\" or \"discid\". Default: not set.
 -g, --genre genre
              Specify (and  override CDDB)  genre,  must be a valid ID3-
              genre name  if using Lame, can (but shouldn't) be anything
              if using other encoders, default: not set.
 -y, --year year
              Specify (and override CDDB) year tag (mp3, m4a), or a date
              tag (ogg, flac), default: not set.
 -D, --dirtemplate '\" foo \$parameters \"'
              Use single and double quotes to pass the parameters of the
              templates. More than one --dirtemplate may be stated, or
              use variables \$quality and \$suffix. See manpage for more
              info. Default: '\"\$artist - \$album\"'
 -T, --tracktemplate '\"foo \$parameters\"'
              See above. Only one tracktemplate can be stated. Default:
              '"\$tracknum \$trackname"'.
 --trackoffset number
              Use an offset to be added to \$tracknum, default 0.
 --addtrackoffset
              With MusicBrainz check for multi disc release and use
              offset if found. Overwrite mode will be switched on for
              those runs where the first track of the disc is not found
              in an existing direcotry. Default off.
 --discno number
              Set a discnumber in the tags if encoder supports the tag.
              Set manually a value above 0 or when using MB let it set
              automatically (discno=1). Default 0 (off).
 --coverart list
              Add coverart to the sound files. Comma separated list
              according to option coder with values 0 (no) or 1 (yes),
              default 0.
 --coverpath path
              Path to the coverart picture to be included in the
              meta data of the sound files, default: not set.
 -F, --coversize format
              Resize coverart pictures to be included in the meta data
              of the sound files to a XXXxYYY format. To ensure aspect
              ratio, only the width can be stated, default: not set.
 --copycover path
              Copy an image (may also be any other file) to all
              directories containing encoded files.
              Value: absolute path to file. Default: not set.
 --coverorg number
              Search for coverart at coverartarchive.org.
              Value: 0 (no) or 1 (yes), default 0.
 --flactags FRAME=tag
              Special frames to be added to the flac file with meta
              data provided e.g. when using MB. Use option --flacopt
              for regular hard coded tags to be added. Use this option
              to add following predefined frames: ASIN, BARCODE,
              CATALOG, CDDBID, DISCID and MBREID
              (musicbrainz release ID), tag names in lower case.
              Default: not set.
 --mp3tags FRAME=tag or FRAME=[description]tag
              Additional frames to be added to the mp3 file if encoder
              does not support the frame or if some unofficial FRAMEs
              shall be used. More than one --mp3tags can be used if
              several tags shall be added. Special tags to TXXX or
              WXXX frame need a description. If stated with a special
              description the tag names are evaluated.
              Special descriptions are ASIN, BARCODE, CATALOG, CDDBID,
              DISCID and MBREID (musicbrainz release ID), tag names in
              lower case.
              Default: not set.
 --oggtags FRAME=tag
              Same as flactags, default: not set.
 --vatag number
              Analyze track names for "various artists" style and split
              the meta data in case one of the delimiters (colon, hyphen,
              slash or parenthesis) are found. Use unpair numbers for
              the scheme "artist ? tracktitle" and pair numbers in the
              opposite case. Default: not set.
 --vastring string
              A string (regular expression) that defines the "various
              artists" style, default: \bVA\b|Variou*s|Various\\sArtists|Soundtrack|OST
 --flacgain   Flacgain command with options but no filenames, e.g.
              metflac.
 --mp3gain    mp3gain command with options but no filenames.
 --mpcgain    mpdgain command with options but no filenames.
 --aacgain    aacgain command with options but no filenames.
 --vorbgain   vorbisgain command with options but no filenames.
 --wvgain     wvgain command with options but no filenames.
 --sshlist list
              Comma separated list of remote machines where RipIT should
              encode. Default: not set.
 --scp        If the filesystem can not be accessed on the remote
              machines, copy the wavs to the remote machines,
              default: off.
 --local      Only used with option --sshlist; if all encodings shall be
              done on remote machines, use --nolocal, default: on.
 --mb         Use musicbrainz instead of freedb, default: off.
 --mbrels number Retrieve relationships for each track and add vocal
              performer to track title if found, default: off.
 --mbname login
              Give MB login name to submitt ISRCs to the database. Saved
              in plain when using a config, default not set.
 --mbpass password
              Give MB password to submitt ISRCs to the database. Saved
              in plain when using a config, default not set.
 --isrc number
              Enable ISRC detection and submission to MB (1 yes, 0 no);
              default: 0
 --cdtext number
              Check for CD text if no DB entry found, default: 0 - off.
 -C, --cddbserver server
              CDDB server, default freedb.org. Note, the full address is
              \"mirror\".freedb.org, i. e. default is freedb.freedb.org.
 -m, --mirror mirror
              Choose \"freedb\" or one of the possible freedb
              mirrors, default: freedb.
 -L, --protocol level
              CDDB protocol level for CDDB query. Level 6 supports UTF-8
              and level 5 not. Default: 6
 -P, --proxy address
              The http proxy to use when accessing the cddb server.  The
              CDDB protocol must be http! Default: not set.
 -t, --transfer mode
              Transfer mode, cddb or http, will set default port to 8880
              or 80 (for http), default: cddb.
 -n, --nice value
              Set niceness of encoding process, default: not set.
 -a, --archive
              Read and save CDDB files in  \$HOME/.cddb/\"category\"
              directory. Default: off.
 -e, --eject  Ejects the CD when finished, default off.
 --ejectcmd cmd
              Command to use for ejecting CD (see --eject), default:
              eject.
 --ejectopt options
              Arguments to the ejecting CD command (see --ejectcmd),
              default: path of CD device.
 --halt       Powers off  the machine when finished if the configuration
              supports it, default: off.
 -s, --submission
              Specify --nosubmission if the computer is  offline and the
              created file cddb.toc shall be saved in the home directory
              instead of being submitted. With option  --archive it will
              also be saved in the \$HOME/.cddb directory. Default: on.
 -M, --mail address
              Users return email address, needed for submitting an entry
              to freedb.org. Default: not set.
 --mailopt options
              Special options to sendmail program, default: -t
 -p, --playlist number
              Create a m3u playlist file with full paths in filenames.
              For filenames without paths use --playlist 2. To prevent
              playlist creation, use: --playlist 0. Default: 1 - on.
 -i, --interaction
              Specify --nointeraction if ripit shall take the first CDDB
              entry found and rip without any questioning. Default: on.
 --lcd        Use lcdproc to display status, default: on.
 --lcdhost    Specify the lcdproc host, default: localhost.
 --lcdport    Specify the lcdport, default: 13666.
 --infolog file
              Log operations (system calls,  file/directory creation) to
              file, given with full path; default: not set.
 -l, --lowercase number
              Lowercase file and / or directory names, default: off.
              0 off; 1 on; 2 on only for file names; 3 on only for
              directory names.
 -u, --underscore
              Use underscores _ instead of spaces in filenames, default:
              off.
 --uppercasefirst
              Uppercase first characters of each word in filenames and
              tags, default: off.
 -U, --utftag If negated decodes Lame-tags to ISO8859-1. Default: off.
 --rip        Rip the CD, to be used as --norip if wavs of flacs are
              present in --inputdir.
              Default: on.
--inputdir directory
              Full path to the directory with wav or flac files to be
              re-encoded using option --norip. Default: not set.
--cdid id     Give a freedb.ord CDDBID or a musicbrainz discid in case
              look-up shall be done when re-encoding wav or flac files
              using --norip. Default: not set.
 --encode     Prevent encoding (generate only wavs) with --noencode.
              Default: on.
 -w, --wav    Keep the wav files after encoding instead of deleting them
              default: off.
 -N, --normalize
              Normalizes the wav-files to a given dB-value (default:
              -12dB). Default: off.
 --normcmd    Command to use for normalizing, default: normalize.
 -z, --normopt
              Options to pass to normalize. For further options see
              normalize documentation (http://normalize.nongnu.org).
              Keeping the default value of -12dB is recommended.
              Default: -b. Option v will be set according to verbosity.
 --cdtoc n
              n=1: Create a toc file to burn the wavs with cd-text using
              cdrdao or cdrecord (in dao mode), default: 0 - off.
 --cdcue n
              n=1: Create a cue file to burn the merged wavs with
              cd-text, default: 0 - off.
 --cue n
              n=1: Create a cue file to play or burn the wavs with
              cd-text, default: 0 - off.
 --inf n
              n=1: Creat inf files for each track to burn the wavs with
              cd-text using wodim or cdrecord (in dao mode),
              default: 0 - off.
 -h, --help   Print this and exit.
 -V, --version
              Print version and exit.
 -x, --verbose number
              Run silent (0), with minimal (1), normal without encoder
              messages (2), normal (3), verbose (4) or extremely verbose
              (5). Default 3
 --config     Read parameters from config file or specify  --noconfig to
              prevent reading it; default: on.
 --save       Add parameters passed on command line to config file. This
              options does not  overwrite other  settings.  An  existing
              config file will be saved as config.old. Default: off.
 --savenew    Save all parameters passed on command line to a new config
              file, backup an existing file to config.old. Default: off.
 -A, --book number
              Create an audiobook, i. e. merge all tracks into one sinlge
              file, option --ghost will be switched off and file suffix
              will be m4b in case faac is used. A chapter file
              will be written for chapter marks. Default: off
 --loop number
              Continue to ripp and encode as soon as the previous CD has
              finished. This option forces ejection of the CD. Set
              number to 2 for immediate restart of ripping process,
              experimental. Default off.
 --quitnodb value
              Give up CD if no CDDB entry found.
              Possible values: 0 - off, 1 - on, default: off
 --resume     Resume a previously started session. Default: not set.
 - O, --overwrite argument
              Overwrite existing rip (y), quit if directory exists (q)
              or force ejection of disc if directory exists (e). Default
              off (n), do not overwrite existing directories, use a
              directory name with a suffix instead.
 --md5sum     Create a MD5-sum file for each type of sound files.
              Default: not set.
 --threads number
              Comma separated list of numbers giving maximum of allowed
              encoders to run at the same time, default: 1.
 --execmd command
              State a command to be executed when ripit finished. Make
              sure to escape the command if needed. Default: not set.
 --precmd command
              State a command to be executed when ripping starts. Make
              sure to escape the command if needed. Default: not set.


SEE ALSO
       ripit(1), cdparanoia(1), lame(1), oggenc(1), flac(1),
       normalize(1), cdda2wav(1), vorbgain(1).

AUTHORS
       RipIT is now maintained by Felix Suwald, please send bugs, wishes
       comments to ripit _[at]_ suwald _[dot]_ com. For bugs, wishes and
       comments about lcdproc, contact max.kaesbauer [at] gmail[dot]com.
       Former maintainer:  Mads Martin Joergensen;  RipIT was originally
       developed by Simon Quinn.

DATE
       April 4th, 2014

END
}
########################################################################
#
# Display available options and exit!
#
# New options step 13: Add the new options to the short help/error msg.
#
sub print_usage {
   print <<END

Usage:
ripit [--device|d cd-device] [--scsidevice path] [--outputdir|o path]
      [--dirtemplate '\"\$parameters\"'] [--chars|W [list]]
      [--tracktemplate '\"\$parameters\"'] [--trackoffset number]
      [--addtrackoffset] [--dpermission number] [--fpermission number]
      [--overwrite|O argument] [--resume|R] [--inputdir path] [--rip]
      [--ripper|r cdripper] [--ripopt ripper-options] [--offset number]
      [--nicerip number] [--disable-paranoia|Z] [--wav|w]
      [--verify|Y number] [--accuracy|Q number] [--flacdecopt options]
      [--ghost|G] [--extend seconds] [--prepend seconds] [--cdid id]
      [--quitnodb value] [--encode] [--coder|c encoders] [--musenc cmd]
      [--faacopt options] [--flacopt options] [--oggencopt options]
      [--lameopt options] [--mp4alsopt options] [--museopt options]
      [--wavpacopt options] [--ffmpegopt options] [--ffmpegsuffix suffix]
      [--quality qualities-list] [--bitrate|b rate]
      [--maxrate|B rate] [--vbrmode|v old or new] [--preset|S mode]
      [--vatag number] [--vastring string or regular expression]
      [--comment id3-comment] [--genre|g genre-tag] [--year|y year-tag]
      [--mp3gain| cmd options] [--vorbgain| cmd options]
      [--flacgain| cmd options] [--aacgain| cmd options]
      [--mpcgain| cmd options] [--wvgain| cmd options]
      [--lowercase|l number] [--underscore|u] [--uppercasefirst]
      [--utftag|U] [--mb] [--mbrels| number] [coverorg| number]
      [--coverart list] [--coverpath path] [--coversize|F format]
      [--copycover path] [--mp3tags FRAME=tag or FRAME=[desciption]tag]
      [--falctags FRAME=tag] [--oggtags FRAME=tag] [--discno number]
      [--mbname MB-login] [--mbpass MB-password] [--isrc number]
      [--cddbserver|C server] [--mirror|m mirror] [--protocol|L level]
      [--transfer|t cddb or http] [--submission|s] [--cdtext|number]
      [--proxy|P path] [--mail|M address] [--mailopt options]
      [--eject|e] [--ejectcmd command] [--ejectopt options for command]
      [--lcd] [--lcdhost host] [--lcdport port]
      [--config] [--confdir] [--confname] [--save] [--savenew]
      [--sshlist remote hosts] [--local] [--scp] [--threads numbers]
      [--archive|a] [--playlist|p number] [--infolog path] [--md5sum]
      [--cdtoc number] [--inf number] [--cdcue number] [--cue number]
      [--loop number] [--verbose|x number]
      [--normalize|N] [--normcmd] [--normopt|z options]
      [--interaction|i] [--nice|n adjustment] [--halt]
      [--help|h] [--version|V] [--precmd cmd] [--execmd|X cmd]
      [--book|A number] [--merge list] [--span|I span] [track_selection]


For general usage information see the manpage or type:
       ripit --help | less
or try to run
       ripit
without any options.

END
}
########################################################################
#
# Define the tracks to be skipped, change the passed values of the form
# 2+3,5-7 to an array @skip with 3,6,7. Note that we use the untouched
# variable $pmerge to determine the tracks to be skipped.
# In the same time, the intervals have to be tested if valid.
#
sub skip_tracks {
   my $fill_array_flag = shift;
   my @merge = split(/,/, $pmerge);
   foreach (@merge) {
      # Split each interval into a BeginEndArray.
      my @bea = split(/-|\+/, $_);
      my $i = $bea[0] + 1;
      # Missing separator in command line argument?
      if($#bea > 1) {
         print "\nStrange interval in argument of option merge ($_)!",
               "\nIs there a comma missing?\n\n";
         exit;
      }
      # Operator forgot to give last track or wanted the whole CD to be
      # merged. But don't add zeros if we come here from the initial
      # argument check when the CD-data is still unknown.
      if($#tracklist >= 0) {
         $pmerge .= $#tracklist + 1 unless($bea[1]);
         $bea[1] = $#tracklist + 1 unless($bea[1]);
      }
      # Track number larger than number of tracks on CD?
      if($#tracklist > 0) {
         if($bea[0] > $#tracklist + 1 || $bea[1] > $#tracklist + 1) {
            print "\nWrong interval in argument of option merge ($_)!",
                  "\nHigher track number than tracks on CD?\n\n";
            exit;
         }
      }
      while($i <= $bea[$#bea]) {
         push(@skip, $i) if($fill_array_flag == 1);
         $i++;
      }
   }
   return(@skip);
}
########################################################################
#
# Read the header of the wav file yet still called $trn.rip and use a
# flag $prn if info shall be printed.
#
sub get_wavhead {
   my $trn = shift;
   my $prn = shift;
   open(IN, "< $wavdir/$trn") or print "Can't open $wavdir/$trn: $!\n";
   binmode(IN);
   my $H = {};
   $H->{header_size} = 44;
   my $wavheader;
   print "Can not read full WAV header!\n"
      if($H->{header_size} != read(IN, $wavheader, $H->{header_size}));
   close(IN);

   # Unpack the wav header and fill all values into a hashref.
   ($H->{RIFF_header},     $H->{file_size_8},      $H->{WAV_header},
    $H->{FMT_header},      $H->{WAV_chunk_size},   $H->{WAV_type},
    $H->{channels},        $H->{sample_rate},      $H->{byte_per_sec},
    $H->{block_align},     $H->{bit_per_sample},   $H->{data_header},
    $H->{data_size}
   ) = unpack("a4Va4a4VvvVVvva4V", $wavheader);

   $H->{sample_size} = ($H->{channels} * $H->{bit_per_sample})>>3;
   if($verbose >= 4 && $prn == 1) {
      print "\nThe wav header has following entries:\n";
      print "$_ \t -> $H->{$_} \n" foreach (keys %$H);
      print "\n";
   }
   return($wavheader, $H);
}
########################################################################
#
# Analyze the wav for chunks and gaps. Fill an array @times with two
# blank separated numbers in each entry. These two numbers are the
# time in seconds of the starting point of sound and the duration of
# that chunk. This is important because this number will be used to seek
# to that point of sound from the beginning of the file, not form the
# end point of the previous cycle. For each chunk we start to seek from
# zero; this is not a large time loss, seeking is fast.
#
# There were weeks of testing to manage Audio::FindChunks-0.03, gave up!
# The behaviour seems inconsistent. For example: ripping all tracks of
# the CD: Lamb - What Sound gave *no* gaps. When ripping only the last
# track, gaps were immediately detected.
# First, changing the sec_per_chunk value gave better results, but
# suddenly no gaps at all were found. The threshold stayed at zero.
# So then I introduced a loop where the sec_per_chunk increases from
# 0.1 - 0.8 in steps of 0.1, and in the same time, the threshold from
# 0.1 in steps of 0.2 only if the resulting threshold is less than 100.
# You say that this is ugly? No, it is extremely ugly. And all this
# because there might be a caching problem in Audio::FindChunks-0.03?
# Then, testing on a 64bit machine was a drawback, no gaps at all.
#
# So I gave up this sophisticated and "fully documented" PM, and coded a
# few lines to solve the problem. This code might not be useful to
# split manually recorded vinyl, but the results for ripped CDs are
# much more precise than with the PM. Of course, I can test only on a
# limited range of CDs, and I have no classical or Death-Metal to test.
# But for the following CDs (and hundreds of CDs with no gaps -->
# thousands of tracks and not one was erroneously split) this
# snippet works. (See below for explanation!)
#
#
# Testreport (CDs with correctly split ghost songs):
#
# OK: 2raumwohnung: in wirklich: 11
# OK: A Camp: Colonia: 12
# OK: Archive: Londonium: 13
# OK: Archive: Take My Head: 10
# OK: Aromabar: 1!: 15 (2 ghost songs!)
# OK: Autour de Lucie: L'échappée belle: 11
# OK: Camille: Sac des filles: 11
# OK: Camille: Le fil: 15 (Ghost song without zero-gap... not splitted!)
# OK: Cibelle: Cibelle: 11
# OK: Dining Rooms: Experiments In Ambient Soul: 13
# OK: Distain!: [li:quíd]: 11
# OK: Falco: Out of the Dark: 9+1 renamed
# OK: Fiji: Fijical: 11+1 renamed
# OK: Helena: Née dans la nature: 11
# OK: Imogen Heap: Ellipse (disc 2): Half Life (instr.):13+1 renamed
# OK: Jay-Jay Johanson: Antenna: 10
# OK: Laika: Sound Of The Satellites: 12
# OK: Lamb: Debut: 10
# OK: Lamb: Fear Of Fours: 00 Hidden Track
# OK: Lamb: What Sound: 10
# OK: Little Boots: Hands: 12+1 renamed
# OK: Lunik: Preparing To Leave: 11
# OK: Lunik: Weather: 11
# OK: Mãozinha: Aerosferas: 11
# OK: Massive Attack: 100th Window: 09
# OK: Moby: Last Night: 14
# OK: Moloko: Do You Like My Tight Sweater?: 17+1
# OK: Olive: Trickle: 12
# OK: Ott: Blumenkraft: 00 Hidden Track
# OK: Rightous Men: Disconnected: 11
# OK: Samia Farah: Samia Farah: 12
# OK: Saint Etienne: Heart Failed [In The Back Of A Taxi] (CD1): 03
# OK: Stereo Total: Musique Automatique 15
# OK: Yoshinori Sunahara: Pan Am: 09
#
# Deleted blank tracks:
#
# OK: 22 Pistepirkko: Ralley of Love: 0 (hidden track - copy protection)
# OK: NPG: New Power Soul: all blank tracks
# OK: Dave Matthews Band: Under the Table and Dreaming: all blank tracks
#
#
sub get_chunks {
   my ($tcn, $trn) = @_;
   my @times = ();
   $trn = $trn . ".rip";
   my ($wavheader, $H) = get_wavhead("$trn", 0);

# How do I analyze the chunks? I calculate a threshold value called
# $thresh of the actual chunk by summing up its binary values - perl is
# so cool! Then this value is used to calculate a kind of mean value
# with the previous one --> $deltathre, but only at every 5th value, to
# cancel short fluctuations. If the actual $thresh value lies
# within a small range compared to the deltathre, a weight (counter)
# will be increased and deltathre will be raised to cancel (not so)
# short peak changes (not only) at the end of a track (gap).
# Silence is defined as (not so) significant drop of the $thresh value
# compared to the $deltathre one. Use an upper cut-off value $maxthresh
# (70% of maximum value) to allow deltathre to grow (quickly) in the
# beginning but prevent to bailing out immediately. During the track, a
# weight will help to prevent the same. If the silence lasts more than
# 4 seconds, the detected startsound and duration values will be pushed
# into the @times array. In version 3.7.0 additionally a $trimcn is
# introduced, to enable RipIT to trim tracks at beginning and end. This
# can now be done, if the --extend and --prepend options are set to 0,
# not recommended. If the lead-in/out and gaps are really zero, the
# $trimcn will correct the values pushed into @times which correspond to
# the time points where volume is below the thresh value, but not yet
# zero. With these values a --prepend or --extend of 0 would cut off a
# few fractions of seconds. This may still happen, if the lead-in/out
# and/or gap is not really zero. How should RipIT know about silence?
# If lead-in/out and gaps are zero, $trimcn will slightly enlarge the
# chunks of sound and trimming should not cut away sound, hopefully.
# As far as I understand, the unpack function returns the number of bits
# set -- in a bit vector.  Using this value, I stress that we deal with
# bits and not bytes for the variables $thresh and $maxthresh. Therefore
# $maxthresh is multiplied by 8!

   my $bindata;
   my $bytecn = 0;
   my $silencecn = 0;
   my $chunkcn = 0;
   my $chunksize = 0.1; # Chunk size in seconds.
   my $chunkbyte = $H->{byte_per_sec} * $chunksize;
   my $chunklen = 0;
   my $leadinflag = 0;
   my $startsnd = 0;
   my $soundflag = 0;
   my $deltathre = $H->{byte_per_sec} * $chunksize;
   my $totalthre = 0;
   my $trimcn = 0;
   my $weight = 1;
   my $maxthresh = $deltathre * 8 * 0.7;

   open(IN, "< $wavdir/$trn") or print "Can't open $trn: $!\n";
   binmode(IN);
   seek(IN, 44, 0);
   while(read(IN, $bindata, $chunkbyte)) {
      $chunkcn++;
      my $thresh = unpack('%32b*', $bindata);
      $totalthre += $thresh / 1000 if($thresh < $maxthresh * 1.1 );
      $weight++
         if($thresh > 0.8 * $deltathre && $thresh < 1.1 * $deltathre);
      $deltathre = ($deltathre * $weight + $thresh) / (1 + $weight)
         if($thresh > 0.8 * $deltathre && $thresh < $maxthresh &&
            $chunkcn =~ /[05]$/);
      # According to the $thresh value, decide whether it is sound or
      # not.
      # The if-condition itself is a little more tricky. We have to
      # force this condition at beginning, even if there is no silence!
      # Why this? If there is a lead-in with immediate sound but very
      # short interruptions, the switch of $soundflag = 1 will be the
      # reason that the startsnd will increase, although it shouldn't,
      # it should stay at 0.0, but will become 0.1 or similar in this
      # case! In this way, if the interruptions are short (< 4s) nothing
      # will happen, and the fact that $startsnd will not set back to
      # zero until a true gap will be found, $startsnd will not be
      # recalculated in the else-part.
      if($thresh < 0.8 * $deltathre || $bytecn == 0) {
         $silencecn += $chunkbyte;
         # If thresh is zero, use an other counter to calculate more
         # precise values.
         $trimcn += $chunkbyte if($thresh == 0);
         $leadinflag = 1 if($thresh == 0 && $bytecn == 0);
         # If the gap is 4 seconds long, save values in array @times, or
         # to detect lead-ins shorter than 4s, set the $soundflag to 1.
         if($silencecn == $H->{byte_per_sec} * 4 ||
            $bytecn < $H->{byte_per_sec} * 4) {
            $chunklen = ($bytecn - $silencecn) / $H->{byte_per_sec};
            # Otherwise:
            $chunklen = ($bytecn - $trimcn) / $H->{byte_per_sec}
               if($trimcn < $silencecn && $trimcn > 0);
            $chunklen -= $startsnd;
            # The chunk of sound must be longer than 4.0 seconds!
            if($chunklen < 4) {
               $chunklen = 0;
            }
            else {
               push(@times, "$startsnd $chunklen");
               # Prevent re-entering a duplicate last entry outside of
               # the loop.
               $startsnd = 0;
            }
            # Chunk of sound has been detected. Doing this here and not
            # just above where $starsnd is set to zero, will enable
            # detection of short lead-ins!
            $soundflag = 1;
            # From now on we are in silence!
            # Set $trimcn to $silencecn to detect another difference
            # at the end of the gap, if the gap consists of zeros.
            $trimcn = $silencecn if($bytecn > $H->{byte_per_sec} * 4);
         }
         # We will stay in this condition, until...
      }
      else {
         # ... sound is detected (again)!
         # If we get here the first time, save the $startsound time.
         if($soundflag == 1 && $startsnd == 0) {
            if($trimcn < $silencecn &&
               $trimcn > (0.8 * $silencecn)) {
               $startsnd = ($bytecn - $silencecn + $trimcn) /
                            $H->{byte_per_sec};
            }
            elsif($startsnd == 0) {
               $startsnd = $bytecn / $H->{byte_per_sec};
            }
            $soundflag = 0;
         }
         $trimcn = 0;
         $silencecn = 0;
      }
      $bytecn += $chunkbyte;
   }
   # Calculations for the last (only) chunk of sound.
   $chunklen = ($bytecn - $silencecn) / $H->{byte_per_sec};
   # Otherwise (slightly different condition than above):
   $chunklen = ($bytecn - $trimcn) / $H->{byte_per_sec}
      if($trimcn < $silencecn);
   $chunklen -= $startsnd;
   push(@times, "$startsnd $chunklen") unless($startsnd == 0);
   push(@times, "$startsnd $chunklen") unless(@times);
   $times[0] =~ s/^0.1/0/ if($startsnd == 0.1 && $leadinflag == 0);

   my $tracklen = int(($framelist[$tcn] - $framelist[$tcn - 1]) / 7.5);
   $tracklen = int($framelist[$tcn] / 7.5) if($tcn == 0);
   $tracklen /= 10;

   # I don't like it, but it might be OK to delete very short tracks
   # if their content is blank.
   if(-s "$wavdir/$trn" < 200000 && $totalthre >= 200) {
      $chunkcn = 0;
      $totalthre = 0;
      open(IN, "< $wavdir/$trn") or print "Can't open $trn: $!\n";
      binmode(IN);
      seek(IN, 44, 0);
      while(read(IN, $bindata, 2)) {
         $chunkcn++;
         my $thresh = unpack('%32b*', $bindata);
         $thresh = 0 if($thresh >= 14);
         $totalthre += $thresh;
      }
      $totalthre = $totalthre * 4 / $chunkcn;
   }

   if($totalthre < 200) {
      unlink("$wavdir/$trn") or print "Can't delete $trn: $!\n";
      if($verbose >= 1) {
         print "\n\nRipIT found blank track $trn\n",
               "and decided to delete it.\n\n";
      }
      if($inf > 0) {
         my $infile = $trn;
         $infile =~ s/.wav$/.inf/i;
         if(-f "$wavdir/$infile") {
            unlink("$wavdir/$infile") or
            print "Can't delete $infile: $!\n";
         }
      }
      open(ERO,">>$wavdir/error.log")
         or print "Can not append to file $wavdir/error.log\"!\n";
      print ERO "Blankflag = $tcn\nTrack $tcn on CD failed!\n";
      close(ERO);
      log_info("blank track deleted: $wavdir/$trn");
      $times[0] = "blank";
      return(@times);
   }

   if($verbose >= 2) {
      printf "\n%02d:%02d:%02d: ",
         sub {$_[2], $_[1], $_[0]}->(localtime);
      print "RipIT found following chunks for track\n",
            "$trn (${tracklen}s long):\nstart duration (in seconds)\n";
      log_info("\nRipIT found following chunks for track:");
      log_info("$trn (${tracklen}s long):\nstart duration (in seconds)");
      foreach(@times) {
         my @interval = split(/ /, $_);
         printf("%5.1f %9.1f\n", $interval[0], $interval[1]);
         log_info("@interval");
      }
   }
   return(@times);
}
########################################################################
#
# Split the wav into chunks of sound and rename all of them to
# "Ghost Song $counter.wav".
#
sub split_chunks {
   my ($tcn, $trn, $cdtocn, @times) = @_;
   my $album = clean_all($album_utf8);
   $album = clean_name($album);
   $album = clean_chars($album) if($chars);
   $album =~ s/ /_/g if($underscore == 1);
   my $artist = clean_all($artist_utf8);
   $artist = clean_name($artist);
   $artist = clean_chars($artist) if($chars);
   $artist =~ s/ /_/g if($underscore == 1);
   my $bindata;
   my ($wavheader, $H) = get_wavhead("$trn.rip", 1);
   my $chunksize = 0.1; # Chunk size in seconds.
   my $chunkbyte = $H->{byte_per_sec} * $chunksize;
   my $chunkcn = 0;
   # Save the track length of the original track to be compared with the
   # chunks of sound.
   my $tracklen = int($H->{data_size} / $H->{byte_per_sec} * 10);
   $tracklen /= 10;
   # Let the other processes know, if the track has been shorten or not.
   my $shorten = 0;

   # We may need to delete a single index in array @times:
   my $prn_flag = 0;
   my @times_new = ();
   my $times_cn = 0;
   foreach(@times) {
      # Remember: each entry of @times has the form: "start duration"
      # where start is the beginning of sound in seconds, and duration
      # the time in seconds.
      my @interval = split(/ /, $_);
      if($interval[0] >= $prepend) {
         $interval[0] -= $prepend;
         $interval[1] += $prepend;
      }
      else{
         $interval[1] += $interval[0];
         $interval[0] = 0;
      }
      # Extend the interval, this might result in a too long interval.
      $interval[1] += $extend;
      # Don't allow too long end-times, this can happen with the above
      # extend command.
      if($interval[0] + $interval[1] > $tracklen) {
         $interval[1] = $tracklen - $interval[0];
      }
      # Update the times array.
      $times_new[$times_cn] = "$interval[0] $interval[1]";
      $times_cn++;
      # Modify the @times array.
      $_ = "$interval[0] $interval[1]";

      # Don't split if interval is larger than track length from cdtoc.
      # Use a threshold of $extend + $prepend. Reasonable?
      if(($tracklen - $extend - $prepend) <= $interval[1] ||
          $interval[1] < 3) {
         print "Track $tcn not splitted.\n\n"
            if($verbose >= 1);
         log_info("Track $tcn not splitted.");

         # Merge track into album-track if $cdcue == 1.
         merge_wav($trn, $chunkbyte, $album) if($cdcue == 1);
         # Do not return here, more pairs might exist in @times...
         # return($shorten, @times);
         # And further more the array still holds the additional pair
         # not used.

         # Clean up counters:
         $prn_flag--; # Do not print.
         pop(@times_new) if($times_cn > 1); # Remove pair if no ghost.
         next;
      }

      # Use array @secondlist to save new track lengths to allow the
      # ripper (!) process to write correct playlist files. The array
      # will be printed to ghost.log for encoder process in the "next"
      # subroutine called rename_chunks, see below.
      if($chunkcn == 0) {
         $secondlist[$tcn - 1] = int($interval[1]) if($hiddenflag == 0);
         $secondlist[$tcn] = int($interval[1]) if($hiddenflag == 1);
      }
      else {
         push(@secondlist, int($interval[1]));
      }

      # Print info message about what is going on (only once):
      if($verbose >= 2 && $chunkcn == 0) {
         print "Splitting \"$trn\" into " . ($#times + 1) . " chunk";
         print ".\n" if($#times == 0);
         print "s.\n" unless($#times == 0);
      }
      if($chunkcn == 0) {
         log_info("Splitting \"$trn\" into " . ($#times + 1) . " chunk.")
            if($#times == 0);
         log_info("Splitting \"$trn\" into " . ($#times + 1) . " chunks.")
            unless($#times == 0);
      }
      if($verbose >= 4) {
         print "\n\nUsing these values for chunk $chunkcn:\n";
         printf("%5.1f %5.1f\n", $interval[0], $interval[1]);
      }
      log_info("\nUsing these values for chunk $chunkcn:");
      log_info("@interval");

      # Prepare the filename for output.
      my $outr = "Ghost Song $chunkcn";
      $outr = get_trackname($tcn, $outr, 0, $artist, $outr) . ".rip";

      if($cdcue == 1) {
         my $file_size = -s "$wavdir/$album.wav";
         print "\nAppending $outr to album.wav, yet $file_size B large",
               ".\n" if($verbose > 4);
         log_info("\nAppending $outr to album.wav, yet $file_size B large.\n");
         open(OUT, ">> $wavdir/$album.wav")
            or print "Can not append to file ",
                     "\"$wavdir/$album.wav\"!\n";
      }
      else {
         open(OUT, "> $wavdir/$outr");
      }
      binmode(OUT);

      # From now on count in bytes instead of seconds.
      $interval[0] = $interval[0] * $H->{byte_per_sec} + 44;
      $interval[1] = $interval[1] * $H->{byte_per_sec};

      # Edit header according to size of the chunk.
      $H->{data_size} = $interval[1];
      $H->{file_size_8} = $H->{data_size} + 36;
      substr($wavheader, 4, 4) = pack("V", $H->{file_size_8});
      substr($wavheader, 40, 4) = pack("V", $H->{data_size});

      # This is nuts, don't know why this happens, but the chunk sizes
      # in the RIFF header are sometimes one byte smaller leading to an
      # unpaired number. This causes flac to fail on splitted tracks!
      # So let's do it the ugly way: add 1 byte and rewrite the header.
      # What goes wrong in the above substr command or elsewhere?
      # If someone finds out, please submit code.
      my $loopcn = 0;
      # Initialization:
      ($H->{RIFF_header},  $H->{file_size_8},     $H->{WAV_header},
       $H->{FMT_header},   $H->{WAV_chunk_size},  $H->{WAV_type},
       $H->{channels},     $H->{sample_rate},     $H->{byte_per_sec},
       $H->{block_align},  $H->{bit_per_sample},  $H->{data_header},
       $H->{data_size}
      ) = unpack("a4Va4a4VvvVVvva4V", $wavheader);

      while($loopcn < 10 and $H->{data_size} ne $interval[1]) {
         if($verbose > 5) {
            print "\nFatal error, unpair chunk sizes detected\n",
                  "in new header of ghost track part $chunkcn:\n",
                  "\$H->{data_size} is $H->{data_size} ",
                  "instead of chunk length = $interval[1]!\n",
                  "The new wav header has following entries:\n";
            print "$_ \t -> $H->{$_} \n" foreach(keys %$H);
            print "\n";
         }
         log_info("\nFatal error, unpair chunk sizes detected\n",
               "in new header of ghost track part $chunkcn:\n",
               "\$H->{data_size} is $H->{data_size} ",
               "instead of chunk length = $interval[1]!\n",
               "The new wav header has following entries:");
         log_info("$_ \t -> $H->{$_}") foreach(keys %$H);
         log_info("\n");

         $H->{data_size} = 2 * $interval[1] - $H->{data_size};
#         $H->{data_size} = $interval[1] + 1;
         $H->{file_size_8} = $H->{data_size} + 36;

         substr($wavheader, 4, 4) = pack("V", $H->{file_size_8});
         substr($wavheader, 40, 4) = pack("V", $H->{data_size});

         ($H->{RIFF_header}, $H->{file_size_8},    $H->{WAV_header},
          $H->{FMT_header},  $H->{WAV_chunk_size}, $H->{WAV_type},
          $H->{channels},    $H->{sample_rate},    $H->{byte_per_sec},
          $H->{block_align}, $H->{bit_per_sample}, $H->{data_header},
          $H->{data_size}
         ) = unpack("a4Va4a4VvvVVvva4V", $wavheader);

         $loopcn++;
      }

      if($loopcn >= 9 && $verbose >= 3) {
         print "\nMajor problem writing the wav header.";
         log_info("\nMajor problem writing the wav header.");
         if($wcoder =~ /2/) {
            print "\nWon't split this track because Flac will fail.";
            log_info("\nWon't split this track because Flac will fail.");
            # Reset the @times array.
            @interval = (0, $tracklen);
            @times_new = ("0 $tracklen");
            if($chunkcn == 0) {
               $secondlist[$tcn - 1] = $interval[1] if($hiddenflag == 0);
               $secondlist[$tcn] = $interval[1] if($hiddenflag == 1);
            }
            else {
               pop(@secondlist);
            }
         }
         else {
            print "\nTrying to continue anyway.\n";
            log_info("\nTrying to continue anyway.\n");
         }
      }
      # Return with a default pair number in the @times array in case
      # wav header could not be written.
      return($shorten, @times_new) if($loopcn >= 9 && $wcoder =~ /2/);

      syswrite(OUT, $wavheader, 44) if($cdcue == 0);
      log_info("The length of data is $interval[1].");
      log_info("The final wav header has following entries:");
      log_info("$_ \t -> $H->{$_}") foreach(keys %$H);
      log_info("\n");
      if($verbose > 5) {
         print "The length of data is $interval[1].\nThe final wav",
               "header of chunk $chunkcn has following entries:\n";
         print "$_ \t -> $H->{$_} \n" foreach (keys %$H);
         print "\n";
      }

      # Seek from beginning of file to start of sound of chunk.
      open(IN, "< $wavdir/$trn.rip") or
      print "Can't open $trn.rip: $!\n";
      binmode(IN);
      print "Seeking to: ${interval[0]} B, starting from 0B.\n"
         if($verbose >= 4);
      log_info("Seeking to: ${interval[0]} B, starting from 0 B.");
      seek(IN, $interval[0], 0) or
         print "\nCould not seek in file IN: $!\n";

      # I don't know if it is good to read so many bytes a time, but it
      # is faster than reading byte by byte.
      my $start_snd = $interval[0];
      $interval[1] = $interval[1] + $interval[0];
      while(read(IN, $bindata, $chunkbyte) &&
            $interval[0] < $interval[1] - 1) {
         $interval[0] += $chunkbyte;
         # Before we write the data, check it, because it happens that
         # seek does not seek to a pair number, starting to read an
         # unpair (right-channel) byte. In this case, the wav will sound
         # like pure noise, and adding or deleting a single byte right
         # after the header will heal the wav.
         # The amount of data in the read $bindata seems OK, only the
         # position is wrong.
         my $pos = tell(IN);
         if($pos !~ /[02468]$/) {
            print "After chunkbyte = <$chunkbyte> reached pos <$pos>.\n"
               if($verbose > 5);
            log_info("After chunkbyte = <$chunkbyte> reached pos <$pos>.\n");
            # Move one byte!
            read(IN, my $dummybyte, 1);
            $pos = tell(IN);
            print "After 1 byte read reached pos <$pos>.\n"
               if($verbose > 5);
         }
         print OUT $bindata;
      }
      print "This chunk should be ", $interval[0] - $start_snd,
            "B large.\n" if($verbose > 5);
      log_info("This chunk should be ", $interval[0] - $start_snd,
               "B large.");
      log_info("Remember, steps in the size of $chunkbyte B are used.");
      close(OUT);
      write_wavhead("$wavdir/$album.wav") if($cdcue == 1);
      $chunkcn++;
      $prn_flag++;
   }
   close(IN);
   @times = @times_new;

   open(ERO,">>$wavdir/ghost.log")
      or print "Can not append to file \"$wavdir/error.log\"!\n";
   if($#times == 0) {
      if($prn_flag > 0) {
         print "Track $tcn successfully trimmed.\n\n" if($verbose >= 1);
         log_info("Track $tcn successfully trimmed.\n\n");
         print ERO "Splitflag = $tcn\n";
         $shorten = 1;
      }
   }
   else {
      if($prn_flag > 0) {
         print "Track $tcn successfully splitted.\n\n" if($verbose >= 1);
         log_info("Track $tcn successfully splitted.\n\n");
         print ERO "Ghostflag = $tcn\n";
         $shorten = 1;
      }
   }
   close(ERO);
   return($shorten, @times);
}
########################################################################
#
# Rename the chunks called "XY Ghost Song $chunkcn" to the appropriate
# file name according to the track-template.
#
sub rename_chunks {

   # The ripper uses a copy of the initial @seltrack array, called
   # @tracksel. Ghost songs will be added in @seltrack, but not in array
   # @tracksel. This means: the ripper will behave as usual and not
   # care about additional songs. Note that splitted songs are of course
   # already ripped, so we do not need to notify the ripper process
   # about ghost songs.

   # If there is only one chunk, this chunk gets the true track name.
   # If there is more than one chunk the first chunk gets the true
   # track name. Note that this is not done here but only when back in
   # the ripper process right after this routine.
   # This kind of renaming might be wrong, but who knows?
   # Renaming of all subsequent chunks is done here.
   # If there are only two chunks, the second will get the suffix
   # Ghost Song without a counter. If the track name holds a slash, the
   # track name will be splitted, the first part will be used for the
   # actual track, the second part for the ghost song.
   # If there are more than two chunks, a counter will be added.

   # Another problem is with data tracks. Then the track-counter will
   # not increase for ghost songs, as we expect for ghost songs that
   # appear in the last track, sad (see below).

   my ($tcn, $trn, $rip_wavnam, $cdtocn, $cue_point, $shorten, $artistag, $trt, @times) = @_;

   my $album = clean_all($album_utf8);
   $album = clean_name($album);
   $album = clean_chars($album) if($chars);
   $album =~ s/ /_/g if($underscore == 1);
   my $artist = clean_all($artist_utf8);
   $artist = clean_name($artist);
   $artist = clean_chars($artist) if($chars);
   $artist =~ s/ /_/g if($underscore == 1);

   my $chunkcn = 0;
   my $ghostflag = 0;
   my $outr = "Ghost Song $chunkcn";
   $outr = get_trackname($tcn, $outr, 0, $artist, $outr) . ".rip";
   # The first track must be renamed to the *.rip file because the
   # ripper will rename it to wav!
   log_info("perl rename \"$wavdir/$outr\", \"$wavdir/$trn.rip\"");
   rename("$wavdir/$outr", "$wavdir/$trn.rip");

   # Write the toc file in case $cdtoc == 1.
   # Note that $rip_wavnam is the name the actual snd file will get
   # in the ripping process.
   if($cdtoc == 1) {
         my $cdtocartis = $artistag;
         oct_char($cdtocartis);
         my $cdtoctitle = $trt;
         $cdtoctitle = clean_name($cdtoctitle);
         oct_char($cdtoctitle);
         open(CDTOC, ">>$wavdir/cd.toc")
            or print "Can not append to file \"$wavdir/cd.toc\"!\n";
         print CDTOC "\n//Track $cdtocn:\nTRACK AUDIO\n";
         print CDTOC "TWO_CHANNEL_AUDIO\nCD_TEXT {LANGUAGE 0 {\n\t\t";
         print CDTOC "TITLE \"$cdtoctitle\"\n\t\t";
         print CDTOC "PERFORMER \"$cdtocartis\"\n\t}\n}\n";
         print CDTOC "FILE \"$rip_wavnam.wav\" 0\n";
         print CDTOC "ISRC " . $isrcs[$tcn-1] . "\n"
            if($isrc == 1 and defined $isrcs[$tcn-1] and $isrcs[$tcn-1] ne "");
         close(CDTOC);
   }

   # Writing the cue file in case $cdcue == 1 (forcing option ghost).
   # The value $cue_point has already been calculated and should be
   # correct.
   if($cdcue > 0) {
      my $points = track_length($cue_point, 2);
      my $cuetrackno = sprintf("%02d", $cdtocn);
      open(CDCUE ,">>$wavdir/cd.cue")
         or print "Can not append to file \"$wavdir/cd.cue\"!\n";
      print CDCUE "TRACK $cuetrackno AUDIO\n",
                  "   TITLE \"$trt\"\n",
                  "   PERFORMER \"$artistag\"\n",
                  "   INDEX 01 $points\n";
      close(CDCUE);
   }
   # Extract first entry of array @times. If only one chunk has been
   # trimmed, we are done, array @times is empty now.
   my $interval = shift(@times);
   # Calculate length of this track for next cue point (start point of
   # next track). A similar calculation will be done below in case the
   # @times array has more than one entry i.e. more chunks are found.
   my ($start, $chunk_length) = split(/ /, $interval);
   $chunk_length *= 75;
   if($shorten == 0) {
      if($span) {
         print "Track length detection in sub rename_chunks because ",
               "span > 0 form wav file <$wavdir/$trn>.\n"
            if($verbose > 5);
         my ($wavheader, $H) = get_wavhead("$trn.rip", 0);
         $chunk_length = int($H->{data_size} / $H->{byte_per_sec} * 10);
         $chunk_length *= 7.5;
      }
      else {
         # Note that for the last track [$tcn + 1] is not defined
         # and not needed, so chunk_length must not be calculated.
         $chunk_length = $framelist[$tcn + 1] - $framelist[$tcn]
            if($hiddenflag == 0 && defined $framelist[$tcn + 1]);
         $chunk_length = $framelist[$tcn] - $framelist[$tcn - 1]
            if($hiddenflag == 1);
      }
   }
   $cue_point += $chunk_length;

   # If there are two or more chunks then array @times is not empty and
   # has more entries. Proceed and hack all necessary arrays needed for
   # the encoder process. They will be written in the ghost.log file.
   # Note that with only one ghost song no counter is needed in the
   # filename. The suffix can now be wav instead of rip.
   # TODO: check if final track name already exists.
   # So, the track name of a new ghost song shall have the same leading
   # track number to identify its origin, except if it comes from
   # the last track, then the leading number may increase! Define a new
   # ghost counter $gcn.
   my $gcn = $tcn;
   $ghostflag = 1 if($tcn == $#framelist);
   $ghostflag = 1 if($hiddenflag == 1 && $tcn == $#framelist - 1);
   $gcn++ if($ghostflag == 1);
   $chunkcn++;

   my ($delimiter, $dummy) = check_va(0) if($vatag > 0);
   my $delim = "";
   if(defined $delimiter) {
      $delim = quotemeta($delimiter);
      $vatag = 0 if($delim eq "");
   }
   foreach (@times) {
      my $trt = $tracktags[$tcn - 1];
      $trt = $tracktags[$tcn] if($hiddenflag == 1);
      # Some tracks with ghost songs contain the ghost song name after
      # a slash. Prevent splitting in case VA-style is used because
      # tracks might have been splitted already and chunks of snd will
      # mix up with chunks of meta data used differently. New in 4.0
      my @ghostnames = split(/\//, $trt)
         if($vatag == 0 or $vatag == 1 and $delim and $delim !~ /\//);
      if($ghostnames[$chunkcn]) {
         $trt = $ghostnames[$chunkcn];
         $trt =~ s/^\s+|\s+$//;
         # Split the tracktag into its artist part and track part if
         # VA style is used and delimiter is not a slash. Note, here
         # to only aim is to get the track artist, the tracktag trt
         # will not be used as track stuff is handled with @ghostnames.
         my $trackartist = "";
         my $dummy;
         if($va_flag > 0 && $trt =~ /$delim/) {
            ($trackartist, $dummy) = split_tags($trt, $delim);
         }
         # We need to update the track-arrays as the first track will
         # get only its name without the ghost songs name.
         if($chunkcn == 1) {
            my $prev_trt = $ghostnames[0];
            $prev_trt =~ s/^\s+|\s+$//;
            $tracktags[$#tracktags] = $prev_trt;
            my $prev_trn = $prev_trt;
            $prev_trn = clean_all($prev_trn);
            $prev_trn = clean_name($prev_trn);
            $prev_trn = clean_chars($prev_trn) if($chars);
            $prev_trn = change_case($prev_trn, "t");
            $prev_trn =~ s/ /_/g if($underscore == 1);
            $tracklist[$#tracklist] = $prev_trn;
            # The cdtoc needs to be hacked too.
            if($cdtoc == 1) {
               open(CDTOC, "<$wavdir/cd.toc")
                  or print "Can not read file cd.toc!\n";
               my @toclines = <CDTOC>;
               close(CDTOC);
               open(CDTOC, ">$wavdir/cd.toc")
                  or print "Can't append to file \"$wavdir/cd.toc\"!\n";
               foreach (@toclines) {
                  last if(/\/\/Track\s$cdtocn:/);
                  print CDTOC $_;
               }
               my $cdtocartis = $artistag;
               oct_char($cdtocartis);
               my $cdtoctitle = $prev_trt;
               $cdtoctitle = clean_name($cdtoctitle);
               oct_char($cdtoctitle);
               my $cdtoctrckartis = $trackartist;
               oct_char($cdtoctrckartis);
               $prev_trn = get_trackname($tcn, $prev_trn, 0, $artist, $prev_trn);
               print CDTOC "\n//Track $cdtocn:\nTRACK AUDIO\n";
               print CDTOC "TWO_CHANNEL_AUDIO\nCD_TEXT {LANGUAGE 0 {\n\t\t";
               print CDTOC "TITLE \"$cdtoctitle\"\n\t\t";
               print CDTOC "PERFORMER \"$cdtocartis\"";
               print CDTOC "\n\t\tSONGWRITER \"$cdtoctrckartis\""
                  if($vatag > 0 and $cdtoctrckartis ne "");
               print CDTOC "\n\t}\n}\n";
               print CDTOC "FILE \"$prev_trn.wav\" 0\n";
               close(CDTOC);
            }
            # The cdcue needs to be hacked too, because the track length
            # is different if the track has been splitted.
            # Hey, wait a second. No track length update here, only
            # track name is updated...? Confused.
            if($cdcue > 0) {
               open(CDCUE, "<$wavdir/cd.cue")
                  or print "Can not read file cd.cue!\n";
               my @cuelines = <CDCUE>;
               close(CDCUE);
               open(CDCUE, ">$wavdir/cd.cue")
                  or print "Can't write to file \"$wavdir/cd.cue\"!\n";
               my $cuetrackno = sprintf("%02d", $cdtocn);
               my $track_flag = 0;
               foreach (@cuelines) {
                  if($track_flag == 1) {
                     print "   TITLE \"$prev_trt\"\n";
                     print CDCUE "   TITLE \"$prev_trt\"\n";
                     $track_flag = 0;
                  }
                  else {
                     print $_;
                     print CDCUE $_;
                  }
                  $track_flag = 1 if(/^TRACK\s$cuetrackno\sAUDIO/);
               }
               close(CDCUE);
            }
         }
      }
      else {
         # Split the tracktag into its artist part and track part if
         # VA style is used.
         if(defined $delim && $delim ne "" && $va_flag > 0 && $trt =~ /$delim/) {
            ($artist, $trt) = split_tags($trt, $delim);
         }
         # The name for the tags will be with originating track name as
         # prefix.
         $trt = $trt . " - Ghost Song" if($#times == 0);
         $trt = $trt . " - Ghost Song $chunkcn" if($#times > 0);
      }
      # The actual track name will be slightly different.
      $trn = $trt;
      $trn = clean_all($trn);
      $trn = clean_name($trn);
      $trn = clean_chars($trn) if($chars);
      $trn = change_case($trn, "t");
      $trn =~ s/ /_/g if($underscore == 1);
      my $track_delim = $delimiter;
      $track_delim =~ s/\//-/g if(defined $delimiter && $delimiter =~ /\//);
      push(@seltrack, $gcn);
      # Again, when snipping around with VA schemes, we need to
      # mirror the delimiters:
      my $delim_l_close = $delimiter; # for the track List
      my $delim_t_close = $delimiter; # for the track Tags
      $delim_l_close =~ tr/\({\[/)}]/ if(defined $delimiter);
      $delim_t_close =~ tr/\({\[/)}]/ if(defined $delimiter);
      # Brainfood.
      if(defined $delim && $delim ne "" && $vatag > 0 and $vatag % 2 == 0) {
         if($track_delim =~ /[([{]/) {
            push(@tracklist, "$trn $track_delim$artist$delim_l_close");
            push(@tracktags, "$trt $delimiter$artist$delim_t_close");
         }
         else {
            push(@tracklist, "$trn $track_delim $artist");
            push(@tracktags, "$trt $delimiter $artist");
         }
      }
      elsif(defined $delim && $delim ne "" && $vatag > 0 and $vatag % 2 == 1) {
         if($track_delim =~ /[([{]/) {
            push(@tracklist, "$artist $track_delim$trn$delim_l_close");
            push(@tracktags, "$artist $delimiter$trt$delim_t_close");
         }
         else {
            push(@tracklist, "$artist $track_delim $trn");
            push(@tracktags, "$artist $delimiter $trt");
         }
      }
      else {
         push(@tracklist, $trn);
         push(@tracktags, "$trt");
      }
      # Remember: $outr is the output track name of the splitted wav.
      $outr = "Ghost Song $chunkcn";
      if($vatag > 0) {
         $outr = get_trackname($tcn, $outr, 0, "Various", $outr) . ".rip";
      }
      else {
         $outr = get_trackname($tcn, $outr, 0, $artist, $outr) . ".rip";
      }
      $trn = get_trackname($gcn, $tracklist[$#tracklist], 0, $artist, $tracklist[$#tracklist]);
      log_info("perl rename \"$wavdir/$outr\", \"$wavdir/$trn.wav\"");
      rename("$wavdir/$outr", "$wavdir/$trn.wav");
      md5_sum("$wavdir", "$trn.wav", 0) if($md5sum == 1 && $wav == 1);
      if($cdtoc > 0 || $cdcue > 0) {
         $cdtocn++;
      }
      if($cdtoc == 1) {
         my $cdtocartis = $artistag;
         oct_char($cdtocartis);
         my $cdtoctitle = $trt;
         $cdtoctitle = clean_name($cdtoctitle);
         oct_char($cdtoctitle);
         my $cdtoctrckartis = $artist;
         oct_char($cdtoctrckartis);
         open(CDTOC, ">>$wavdir/cd.toc")
            or print "Can not append to file \"$wavdir/cd.toc\"!\n";
         print CDTOC "\n//Track $cdtocn:\nTRACK AUDIO\n";
         print CDTOC "TWO_CHANNEL_AUDIO\nCD_TEXT {LANGUAGE 0 {\n\t\t";
         print CDTOC "TITLE \"$cdtoctitle\"\n\t\t";
         print CDTOC "PERFORMER \"$cdtocartis\"";
         print CDTOC "\n\t\tSONGWRITER \"$cdtoctrckartis\"" if($vatag > 0);
         print CDTOC "\n\t}\n}\n";
         print CDTOC "FILE \"$trn.wav\" 0\n";
         # No writing of ISRC here, as ghost songs won't have any ISRCs
         # provided.
         # print CDTOC "ISRC " . $isrcs[$_-1] . "\n"
         #    if($isrc == 1 and $isrcs[$_-1] ne "");
         close(CDTOC);
      }
      if($cdcue > 0) {
         my $points = track_length($cue_point, 2);
         my $cuetrackno = sprintf("%02d", $cdtocn);
         open(CDCUE ,">>$wavdir/cd.cue")
            or print "Can not append to file \"$wavdir/cd.cue\"!\n";
         print CDCUE "TRACK $cuetrackno AUDIO\n",
                     "   TITLE \"$trt\"\n",
                     "   PERFORMER \"$artistag\"\n",
                     "   INDEX 01 $points\n";
         close(CDCUE);
      }

      # Calculate length of track for next cue point. No problems with
      # option span here as the chunks have been splitted and effective
      # lengths are detected.
      my ($start, $chunk_length) = split(/ /, $_);
      $cue_point += $chunk_length * 75;
      print "\nNext cue_point based on interval: $cue_point.\n",
            "This is: ", track_length($cue_point, 2), ".\n"
         if($verbose > 5);
      $gcn++ if($ghostflag == 1);
      $chunkcn++;
   }
   print "\n\n" if($verbose >= 2);
   log_info("\n");

   # Is there another way to communicate with the encoder process (child
   # process) than writing log files?
   # Oops: As we use ghost.log to collect info about trimmed tracks, we
   # can't overwrite existing ghost.log with updated info about arrays,
   # we need to reed it first.
   my @ghostlines = ();
   if(-r "$wavdir/ghost.log") {
      open(ERR, "$wavdir/ghost.log")
      or print "Can't read $wavdir/ghost.log.\n";
      @ghostlines = <ERR>;
      close(ERR);
   }

   open(GHOST, ">$wavdir/ghost.log")
      or print "Can not append to file ghost.log!\n";
   print GHOST "Array seltrack: @seltrack\n";
   print GHOST "Array secondlist: @secondlist\n";
   print GHOST "Array tracklist: $_\n" foreach(@tracklist);
   print GHOST "Array tracktags: $_\n" foreach(@tracktags);
   foreach(@ghostlines) {
      chomp;
      print GHOST "$_\n" unless(/^Array\s/);
   }
   close(GHOST);
   return($cdtocn, $cue_point);
}
########################################################################
#
# Check if the necessary modules are available.
#
sub init_mod {
   print "\n" if($verbose >= 1);

   # We need to know if coverart is added to mp3 or ogg because those
   # encoders can't handle picture tags. The pictures are added after
   # encoding process using an additional module.
   # Create a coverart array supposing its exactly in the same order as
   # encoder.
   my $mp3art = 0;
   my $oggart = 0;
   my $wvpart = 0;
   if($coverart && ($lameflag == 1 || $oggflag == 1 || $wvpflag == 1)) {
      my @coverart = split(/,/, $coverart);
      for(my $c = 0; $c <= $#coder; $c++) {
         if(defined $coverart[$c]) {
            $mp3art = 1 if($coder[$c] == 0 && $coverart[$c] > 0);
            $oggart = 1 if($coder[$c] == 1 && $coverart[$c] > 0);
            $wvpart = 1 if($coder[$c] == 6 && $coverart[$c] > 0);
         }
      }
   }

   eval { require CDDB_get };
   if($@) {
      print "\nPerl module CDDB_get not found. Needed for",
            "\nchecking the CD-ID and retrieving the CDDB",
            "\nentry from freeDB.org!",
            "\nPlease install CDDB_get from your closest",
            "\nCPAN mirror before trying again.",
            "\nInstall by hand or e.g. type as root:",
            "\nperl -MCPAN -e 'install CDDB_get'\n\n";
      exit 0;
   }
   $@ = ();

   eval { require XML::Simple };
   if($@) {
      print "\nPerl module XML::Simple not found. Needed for",
      "\nchecking trackoffsets with multi disc releases when using",
      "\nMusicbrainz.",
      "\nPlease install XML::Simple and dependencies ",
      "\nfrom your closest CPAN mirror or submission will fail.",
      "\nInstall by hand or e.g. type as root:",
      "\nperl -MCPAN -e 'install XML::Simple'\n\n";
      sleep 2;
   }
   $@ = ();

   eval { require LWP::Simple };
   if($@) {
      print "\nPerl module LWP::Simple not found. Needed for",
            "\nchecking free categories before submitting CDDB",
            "\nentries to freeDB.org!",
            "\nPlease install LWP::Simple and dependencies ",
            "\nfrom your closest CPAN mirror or submission will fail.",
            "\nInstall by hand or e.g. type as root:",
            "\nperl -MCPAN -e 'install LWP::Simple'\n\n";
      sleep 2;
   }
   $@ = ();

   eval { require Digest::MD5 } if($md5sum == 1 or $verify > 1);
   if($@) {
      print "\nPlease install Digest::MD5 and dependencies",
            "\nfrom your closest CPAN mirror before trying again with",
            "\noption --md5sum. Install by hand or e.g. type as root:",
            "\nperl -MCPAN -e 'install Digest::MD5'\n\n";
      exit 0;
   }
   $@ = ();

   eval { require Unicode::UCD } if($utftag == 0);
   if($@) {
      print "\nPlease install Unicode::UCD and dependencies",
            "\nfrom your closest CPAN mirror before trying again with",
            "\noption --noutftag. Install by hand or e.g. type as",
            "root: \nperl -MCPAN -e 'install Unicode::UCD'\n\n";
      exit 0;
   }
   $@ = ();

   eval { require Text::Unidecode } if($utftag == 0);
   if($@) {
      print "\nPlease install Text::Unidecode and dependencies",
            "\nfrom your closest CPAN mirror before trying again with",
            "\noption --noutftag. Install by hand or e.g. type as",
            "root: \nperl -MCPAN -e 'install Text::Unidecode'\n\n";
      exit 0;
   }
   $@ = ();

   eval { use MP3::Tag;
          MP3::Tag->config(write_v24 => 1);
          MP3::Tag->config(id3v23_unsync => 1);
   } if(($mp3art == 1 || $mp3tags[0]) && $lameflag == 1);
   if($@) {
      print "\nPlease install MP3::Tag and dependencies",
            "\nfrom your closest CPAN mirror before trying again with",
            "\noption --coverart. Install by hand or e.g. type as",
            "root: \nperl -MCPAN -e 'install MP3::Tag'\n\n";
      exit 0;
   }
   $@ = ();

   eval { require MIME::Base64 } if($oggart == 1 && $oggflag == 1);
   if($@) {
      print "\nPlease install MIME::Base64 and dependencies",
            "\nfrom your closest CPAN mirror before trying again with",
            "\noption --coverart. Install by hand or e.g. type as",
            "root: \nperl -MCPAN -e 'install MIME::Base64'\n\n";
      exit 0;
   }

   eval { require WebService::MusicBrainz::Release } if($mb == 1);
   if($@) {
      print "\nPlease install WebService::MusicBrainz and dependencies",
            "\nfrom your closest CPAN mirror before trying again with",
            "\noption --mb.",
            "\nInstall by hand or using force because using (as root):",
            "\nperl -MCPAN -e 'install WebService::MusicBrainz'",
            "\nmight fail.\n\n";
      exit 0;
   }

   eval { require MusicBrainz::DiscID } if($mb == 1);
   if($@) {
      print "\nError message is: $@\n" if($verbose > 4);
      print "\nPlease install MusicBrainz::DiscID and dependencies",
            "\nfrom your closest CPAN mirror; e.g. type as root:",
            "\nperl -MCPAN -e 'install MusicBrainz::DiscID'\n\n";
      sleep 2;
#      exit 0;
   }

   if($wvpart == 1) {
      open(WAVPAK, "wavpack 2>&1|");
      my @response = <WAVPAK>;
      close(WAVPAK);
      chomp(my $wvpver = join('', grep(s/.*Linux\sVersion\s//, @response)));
      $wvpver =~ s/(\d+\.\d).*/$1/;
      if($wvpver <= 4.5) {
         print "\n\nWarning:\nThere is a newer version of wavpack ",
               "with coverart support.\nThis version of wavpack does ",
               "not write binary-tags.\n\n" if($verbose > 0);
         sleep 3;
      }
   }

   if($cdtext == 1) {
      my $cdinfo = `which cd-info`;
      unless($cdinfo) {
         print "\n\nWarning:\ncd-info (from cdda2wav or cdio-utils ",
               "package (libcdio-utils)) not installed!\n\n"
            if($verbose > 0);
         sleep 3;
      }
   }

   if(defined $coversize && $coversize =~ /\d+/) {
      my $convert = `which convert`;
      unless($convert) {
         print "\n\nWarning:\nconvert (from ImageMagick package) ",
               "not installed!\n\n"
            if($verbose > 0);
         sleep 3;
      }
      my $identify = `which identify`;
      unless($identify) {
         print "\n\nWarning:\nidentfy (from ImageMagick package) ",
               "not installed!\n\n"
            if($verbose > 0);
         sleep 3;
      }
   }

   if($multi == 1) {
      eval "use Color::Output";
      if($@) {print "\nColor::Output not installed!\n"};
      eval "Color::Output::Init";
   }

   print "\n\n" if($verbose >= 1);
}
########################################################################
#
# Check if lame is installed.
#
sub check_enc {
   my ($enc, $suf) = @_;
   unless(log_system("$enc --version > /dev/null 2>&1")) {
      $enc = "\u$enc";
      if(!@pcoder && "@coder" =~ /0/ || "@pcoder" =~ /0/) {
         print "\n$enc not found (needed to encode $suf)!",
               "\nUse oggenc instead (to generate ogg)?\n";
         my $ans = "x";
         while($ans !~ /^[yn]$/i) {
            print "Do you want to try oggenc? [y/n] (y) ";
            $ans = <STDIN>;
            chomp $ans;
            $ans = "y" if($ans eq "");
         }
         if($ans eq "y") {
            my $coders = "@coder";
            my $pcoders = "@pcoder";
            if($coders !~ /1/) {
               $coders =~ s/0/1/g if($enc =~ /Lame/);
               $coders =~ s/3/1/g if($enc =~ /Faac/);
            }
            else {
               $coders =~ s/0//g if($enc =~ /Lame/);
               $coders =~ s/3//g if($enc =~ /Faac/);
            }
            if($pcoders !~ /1/) {
               $pcoders =~ s/0/1/g if($enc =~ /Lame/);
               $pcoders =~ s/3/1/g if($enc =~ /Faac/);;
            }
            else {
               $pcoders =~ s/0//g if($enc =~ /Lame/);
               $pcoders =~ s/3//g if($enc =~ /Faac/);
            }
            $lameflag = -1;
            @coder = split(/ /, $coders);
            @pcoder = split(/ /, $pcoders);
         }
         else {
            print "\n",
                  "Install $enc or choose another encoder with option",
                  "\n",
                  "-c 1 for oggenc, -c 2 for flac, -c 3 for faac,",
                  "\n",
                  "-c 4 for mp4als, -c 5 for Musepack,",
                  "\n",
                  "-c 6 for Wavpack or -c 7 for ffmpeg.",
                  "\n\n",
                  "Type ripit --help or check the manpage for info.",
                  "\n\n";
            exit;
         }
      }
      else {
         $lameflag = -1;
      }
   }
}
########################################################################
#
# Create MD5sum file of sound files.
#
sub md5_sum {
   my $sepdir = shift;
   my $filename = shift;
   my $ripcomplete = shift;
   my $suffix = $filename;
   $suffix =~ s/^.*\.//;
   chomp($filename);
   chomp($suffix);

   # What name should the md5 file get?
   my @paths = split(/\//, $sepdir);
   my $md5file =  $paths[$#paths] . " - " . $suffix . ".md5";
   $md5file =~ s/ /_/g if($underscore == 1);

   return unless(-r "$sepdir/$filename");

   open(my $SND, '<', "$sepdir/$filename") or
      print "Can not open $sepdir/$filename: $!\n";
   binmode($SND);
   if($verbose > 3) {
      if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
         open(ENCLOG, ">>$wavdir/enc.log");
         print ENCLOG "\n\nCalculating MD5-sum for $filename...";
         close(ENCLOG);
      }
      else {
         print "\nCalculating MD5-sum for $filename...";
      }
   }
   my $md5 = Digest::MD5->new->addfile($SND)->hexdigest;
   close($SND);

   my $time = sprintf "%02d:%02d:%02d:",
      sub {$_[2], $_[1], $_[0]}->(localtime);

   if($verbose > 3) {
      if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
         open(ENCLOG, ">>$wavdir/enc.log");
         print ENCLOG "\n$time The MD5-sum for $filename is: $md5.\n\n";
         close(ENCLOG);
      }
      else {
         print "\n$time The MD5-sum for $filename is: $md5.\n";
      }
   }
   log_info("$time MD5-sum for $filename is: $md5.");
   open(MD5SUM,">>$sepdir/$md5file")
      or print "Can not append to file \"$sepdir/$md5file\"!\n";
   print MD5SUM "$md5 *$filename\n";
   close(MD5SUM);
}
########################################################################
#
# Sort the options and fill the globopt array according to the encoder.
# Remember, the list of options for one encoder stated several times is
# separated by commas. The *opt arrays below will have only one
# entry, if the corresponding encoder has been stated only once. If one
# needs to find globopt in the code, search for "$globopt[" and not for
# @globopt.
#
sub check_options {
   my @flacopt = split(/,/, $flacopt);
   my @lameopt = split(/,/, $lameopt);
   my @oggencopt = split(/,/, $oggencopt);
   my @faacopt = split(/,/, $faacopt);
   my @mp4alsopt = split(/,/, $mp4alsopt);
   my @museopt = split(/,/, $museopt);
   my @wavpacopt = split(/,/, $wavpacopt);
   my @ffmpegopt = split(/,/, $ffmpegopt);
   $faacopt[0] = " " unless($faacopt[0]);
   $flacopt[0] = " " unless($flacopt[0]);
   $lameopt[0] = " " unless($lameopt[0]);
   $mp4alsopt[0] = " " unless($mp4alsopt[0]);
   $museopt[0] = " " unless($museopt[0]);
   $oggencopt[0] = " " unless($oggencopt[0]);
   $wavpacopt[0] = " " unless($wavpacopt[0]);
   $ffmpegopt[0] = " " unless($ffmpegopt[0]);
   for(my $c=0; $c<=$#coder; $c++) {
      if($coder[$c] == 0) {
         if($preset) {
            $lameopt[0] .= " --preset $preset";
         }
         else {
            $lameopt[0] .= " --vbr-$vbrmode" if($vbrmode);
            $lameopt[0] .= " -b $bitrate" if($bitrate ne "off");
            $lameopt[0] .= " -B $maxrate" if($maxrate != 0);
            $lameopt[0] .= " -V $quality[$c]"
               if($qualame ne "off" && $vbrmode);
            $lameopt[0] .= " -q $quality[$c]"
               if($quality[$c] ne "off" && !$vbrmode);
         }
         # Nice output of Lame-encoder messages.
         if($quality[$c] eq "off" && $lameopt[0] =~ /\s*-q\s\d\s*/) {
            $quality[$c] = $lameopt[0];
            $quality[$c] =~ s/^.*-q\s(\d).*$/$1/;
         }
         $lameopt[0] =~ s/^\s*//;
         push(@globopt, $lameopt[0]);
         shift(@lameopt);
      }
      elsif($coder[$c] == 1) {
         $oggencopt[0] .= " -q $quality[$c]" if($quality[$c] ne "off");
         $oggencopt[0] .= " -M $maxrate" if($maxrate != 0);
         $oggencopt[0] =~ s/^\s*//;
         push(@globopt, $oggencopt[0]);
         shift(@oggencopt);
      }
      elsif($coder[$c] == 2) {
         $flacopt[0] .= " -$quality[$c]" if($quality[$c] ne "off");
         $flacopt[0] =~ s/^\s*//;
         push(@globopt, $flacopt[0]);
         shift(@flacopt);
      }
      elsif($coder[$c] == 3) {
         $faacopt[0] .= " -q $quality[$c]" if($quality[$c] ne "off");
         $faacopt[0] =~ s/^\s*//;
         push(@globopt, $faacopt[0]);
         shift(@faacopt);
      }
      elsif($coder[$c] == 4) {
         $mp4alsopt[0] .= " -q $quality[$c]" if($quality[$c] ne "off");
         $mp4alsopt[0] =~ s/^\s*//;
         push(@globopt, $mp4alsopt[0]);
         shift(@mp4alsopt);
      }
      elsif($coder[$c] == 5) {
         $museopt[0] .= " --quality $quality[$c]" if($quality[$c] ne "off");
         $museopt[0] =~ s/^\s*//;
         push(@globopt, $museopt[0]);
         shift(@museopt);
      }
      elsif($coder[$c] == 6) {
         push(@globopt, $wavpacopt[0]);
         shift(@wavpacopt);
      }
      elsif($coder[$c] == 7) {
         push(@globopt, $ffmpegopt[0]);
         shift(@ffmpegopt);
      }
   }
}
########################################################################
#
# Check ripper (cdparanoia) and calculate a timeout according to track
# length.
#
sub check_ripper {
   my $P_command = shift;
   my $pid = shift;
   my @commands = split(/ /, $P_command);
   my $riptrackno = $commands[3];
   # Remember, $riptrackno might hold an span (interval) format.
   $riptrackno =~ s/\[.*$//;
   $riptrackno =~ s/-.*$//;
   # The $P_command is slightly different in case of hidden tracks.
   # Prevent warning when $riptrackno holds the device path instead of
   # the hidden track number.
   $riptrackno = 0 if($hiddenflag == 1 && $riptrackno !~ /^\d+$/);
   my $tlength = $secondlist[$riptrackno - 1];
   $tlength = $secondlist[$riptrackno] if($hiddenflag == 1);
   $tlength = int(exp(- $tlength / 2000) * ($tlength + 20));
   my $cn = 0;
   while(kill 0, $pid) {
      if($cn > $tlength) {
         unless(kill 9, $pid) {
            warn "\nProcess $pid already finished!\n";
         }
         return 0;
      }
      sleep 3;
      $cn += 3;
   }
   return 1;
}
########################################################################
#
# Check distribution.
#
sub check_distro {
   $distro = "debian" if(-f "/etc/debian_version");
}
########################################################################
#
# Get discid and number of tracks of inserted disc.
#
sub get_cddbid {
   CDDB_get->import( qw( get_cddb get_discids ) );
   my $cd = get_discids($scsi_cddev);
   my ($id, $tracks, $toc) = ($cd->[0], $cd->[1], $cd->[2]);
   $cddbid = sprintf("%08x", $id);
   my $totaltime =
      sprintf("%02d:%02d",$toc->[$tracks]->{min},$toc->[$tracks]->{sec});
   return($cddbid, $tracks, $totaltime);
}
########################################################################
#
# Analyze string build from CDDB data for latin and wide chars.
# Simplified code by T. Kukuk
#
sub check_encoding {
   my $char_string = shift;
   # Check if utf-8 or alike
   my $enc = Encode::Guess->guess($char_string);

   # If it is not utf-8 or something similar, check for latin1.
   # Guess_encoding cannot always differentiate between latin1 and utf-8
   # so check utf-8 first alone.
   if(!ref($enc)) {
     $enc = Encode::Guess->guess($char_string, 'latin1');
   }

   # Still nothing found, assume cp1252, works most of the cases.
   if(!ref($enc)) {
     return('cp1252');
   }

   return($enc->name);
}
########################################################################
#
# Transform length of span in seconds. Argument has hh:mm:ss.ff format.
#
sub span_length {
   my $time = shift;
   my @time = split(/:/, $time);
   my $factor = 60;
   $time = pop(@time);
   # Cut off frames (sectors).
   my $frames = 0;
   ($time, $frames) = split(/\./, $time) if($time =~ /\./);
   # Round the value of frames.
   $time++ if($frames > 37);
   while ($time[0]) {
      $time += pop(@time) * $factor;
      # TODO: stop, this is a bug! Multiplication by 60, not sum!
      $factor += 60;
   }
   return($time);
}
########################################################################
#
# Transform length of span from frames to (hh:)mm:ss.ff format. Type $t
# is eq 1 when chapatermarks are wanted (HH:MM:SS:FF format) and eq 2
# when cue-points shall be returned (in MM:SS:FF format without hours).
# Thanks to perlmonks for input.
#
sub track_length {
   my $f = shift;
   my $t = shift;
   my $s = int($f / 75);
   $f = $f % 75;
   return sprintf("%s%02d", "00:00:", $s) if($s < 60 and $t == 1);
   return sprintf("%s%02d:%02d", "00:", $s , $f) if($s < 60 and $t == 2);

   my $m = $s / 60;
   $s = $s % 60;
   return sprintf("%s%02d:%02d", "00:", $m, $s) if($m < 60 and $t == 1);
   return sprintf("%02d:%02d:%02d", $m, $s , $f) if($t == 2);

   my $h = $m / 60;
   $m %= 60;
   return sprintf("%02d:%02d:%02d", $h, $m, $s) if($h < 24);

   my $d = $h / 24;
   $h %= 24;
   return sprintf("%d:%02d:%02d:%02d", $d, $h, $m, $s);
}
########################################################################
#
# Finish process.
#
sub finish_process {
   if($sshflag == 1) {
      check_wav();
   }
   else {
      wait;
   }

   if($playlist >= 1 && $encode == 1) {
      create_m3u();
   }

   my ($riptime, $enctime, $encend, $blanktrks, $ghostrks, $splitrks)
      = cal_times();
   del_erlog() if(-r "$wavdir/error.log");

   if(-r "$wavdir/error.log" && $blanktrks eq "") {
      if($verbose >= 1) {
         print "\nCD may not be complete! Check the error.log \n",
               "in $wavdir!\n";
      }
      elsif($verbose >= 3) {
         print "\nRipping needed $riptime min and encoding needed ",
               "$enctime min.\n\n";
      }
   }
   else {
      if($verbose >= 1) {
         if($ghost == 1) {
            if($blanktrks) {
               print "\nCD may not be complete! Check the error.log \n",
                    "in $wavdir!\n";
               print "Blank track deleted: $blanktrks!\n"
                   if($blanktrks !~ /and/);
               print "Blank tracks deleted: $blanktrks!\n"
                   if($blanktrks =~ /and/);
            }
            else {
               printf "\n%02d:%02d:%02d: ",
                  sub {$_[2], $_[1], $_[0]}->(localtime);
               print "All complete!\n";
            }
            if($ghostrks) {
               print "Ghost song found in track $ghostrks!\n"
                   if($ghostrks !~ /and/);
               print "Ghost songs found in tracks $ghostrks!\n"
                   if($ghostrks =~ /and/);
            }
            else {
               print "No ghost songs found!\n";
            }
            if($splitrks) {
               print "Track $splitrks trimmed!\n"
                  if($splitrks !~ /and/);
               print "Tracks $splitrks trimmed!\n"
                  if($splitrks =~ /and/);
            }
            else {
              print "No tracks trimmed!\n" unless($splitrks);
            }
         }
         else {
            print "\nAll complete!\n";
         }
         print "Ripping needed $riptime min and ";
         print "encoding needed $enctime min.\n\n";
      }
   }

   log_info("\nRipping needed $riptime minutes.");
   log_info("Encoding needed $enctime minutes.");

   if($lcd == 1) {                 # lcdproc
      $lcdline1 = " ";
      $lcdline2 = "   RipIT finished   ";
      $lcdline3 = " ";
      ulcd();
      close($lcdproc) or print "close: $!";
   }

   if($multi == 1) {
      open(SRXY,">>$logfile")
         or print "Can not append to file \"$logfile\"!\n";
      print SRXY "\nEncoding   ended: $encend";
      print SRXY "\nRipping  needed: $riptime min.";
      print SRXY "\nEncoding needed: $enctime min.";
      print SRXY "\nGhost song(s) found in tracks $ghostrks!\n"
         if($ghostrks && $ghost == 1);
      print SRXY "\nTrack(s) $splitrks trimmed!\n"
         if($splitrks && $ghost == 1);
      print SRXY "\nTrack(s) $blanktrks deleted!\n"
         if($blanktrks && $ghost == 1);
      close(SRXY);
      my $cddevno = $cddev;
      $cddevno =~ s/\/dev\///;
      open(SUCC,">>$outputdir/done.log")
         or print "Can not append to file \"$outputdir/succes.log\"!\n";
      print SUCC "$cd{artist};$cd{title};$genre;$categ;$cddbid;";
      print SUCC "$cddevno;$hostnam;$riptime;$enctime\n";
      close(SUCC);
      $cddev =~ s/\/dev\//device /;
      $cddev = $cddev . " " unless($cddev =~ /\d\d$/);
      my $time = sprintf("%02d:%02d", sub {$_[2], $_[1]}->(localtime));
      cprint("\x037Encoding done  $time in $cddev with:\x030");
      cprint("\x037\n$cd{artist} - $cd{title}.\x030");
      cprint("\x033\nGhost song(s) found in tracks $ghostrks!\x030")
         if($ghostrks =~ /1/ && $ghost == 1);
      cprint("\x033\nTrack(s) $splitrks trimmed!\x030")
         if($splitrks =~ /1/ && $ghost == 1);
      cprint("\x033\nTrack(s) $blanktrks deleted!\x030")
         if($blanktrks =~ /1/ && $ghost == 1);
   }

   if($execmd) {
      $execmd =~ s/\$/\\\$/g;
      print "Will execute command \"$execmd\".\n" if($verbose >= 3);
      log_system("$execmd");
   }

   if($halt == 1 && $verbose >= 1) {
      print "\nShutdown...\n";
      log_system("shutdown -h now");
   }

   log_info("*" x 72, "\n");
   print "\n";
   print "Please insert a new CD!\n\n" if($loop == 2);
   return;
}
########################################################################
#
# Write inf file for each track.
#
sub write_inf {
   my $wavdir = shift;
   my $riptrackname = shift;
   my $artistag = shift;
   my $albumtag = shift;
   my $tracktag = shift;
   my $riptrackno = shift;
   my $nofghosts = shift;
   my $trackstart = shift;
   my $artist = shift;
   my $tracktitle = shift;
   my $rip_wavnam = shift;

   print "\nWriting inf file for $riptrackname.wav.\n" if($verbose > 3);
   $nofghosts = $nofghosts - $riptrackno + 1;
   my $ripstart = sprintf("%02d:%02d:%02d",
                          sub {$_[2], $_[1], $_[0]}->(localtime));
   my $date = sprintf("%04d-%02d-%02d",
      sub {$_[5]+1900, $_[4]+1, $_[3]}->(localtime));

   my ($delim, $dummy) = check_va(0) if($vatag > 0);
   $delim = quotemeta($delim) if(defined $delim);

   while($nofghosts > 0) {
      # This is not as ugly as it looks like. Remember that subroutine
      # rename_chunks alters the track name if that track has a slash
      # in.
      if(-r "$wavdir/$riptrackname.wav" and $rip_wavnam ne $riptrackname) {
         $rip_wavnam = $riptrackname unless($riptrackname =~ /short/ and length("$wavdir/$rip_wavnam.wav") > 190);
      }
      open(INF, ">$wavdir/$rip_wavnam.inf");
      print INF "# Wave-info file created by ripit $version on ",
                "$date at $ripstart.\n# To burn the wav files use e.g.",
                " command:\n# wodim dev=/dev/scd0 -v -eject -pad -dao ",
                "-useinfo -text *.wav\n#\n";
      print INF "CDINDEX_DISCID=\t'$cd{discid}'\n" if($cd{discid});
      print INF "CDDB_DISCID=\t$cddbid\n";
      print INF "DISCID=\t$discid\n#\n" if($discid ne ""); # New 4.0
      if($va_flag == 1) {
         print INF "Albumperformer=\t'$artist_utf8'\n";
      }
      else {
         print INF "Albumperformer=\t'$artistag'\n";
      }
      print INF "Performer=\t'$artistag'\n";
      print INF "Albumtitle=\t'$albumtag'\n";
      print INF "Tracktitle=\t'$tracktag'\n";
      print INF "Tracknumber=\t$riptrackno\n";
      print INF "Trackstart=\t$trackstart\n";
      my $length = 0;
      # The wav does not exist if ripper failed.
      if(-f "$wavdir/$riptrackname.wav") {
         $length = -s "$wavdir/$riptrackname.wav";
      }
      $length = int(($length - 44) / 2352) if($length > 0);
      print INF "# track length in sectors (1/75 seconds each), rest samples\n";
      print INF "Tracklength=\t'",  $length, ", 0'\n";
      $trackstart += $length;
      print INF "Pre-emphasis=\tno\n";
      print INF "Channels=\t2\n";
      print INF "Endianess=\tlittle\n";
      print INF "# index list\n";
      print INF "Index=\t0\n";
      print INF "Index0=\t-1\n";
      close(INF);
      $nofghosts--;
      if($nofghosts > 0) {
         my $gcn = $seltrack[$#seltrack - $nofghosts + 1];
         my $trn = $tracklist[$#tracklist - $nofghosts + 1];
         $tracktag = $tracktags[$#tracktags - $nofghosts + 1];
         # Split the tracktag into its artist part and track part if
         # VA style is used.
         if($va_flag > 0 && $trn =~ /$delim/) {
            ($artist, $trn) = split_tags($trn, $delim);
         }
         $riptrackname = get_trackname($gcn, $trn, 0, $artist, $trn);
         $rip_wavnam = $riptrackname;
         $riptrackno++;
      }
   }
   return($trackstart);
}
########################################################################
#
# Write coverart to mp3 files.
#
sub mp3_cover {
   my($snd_file, $coverpath) = @_;
   my $mp3 = MP3::Tag->new($snd_file);
   $mp3->get_tags;
   my $id3v2 = exists $mp3->{'ID3v2'}
         ? $mp3->{'ID3v2'}
         : $mp3->new_tag('ID3v2');
   my $type = $coverpath;
   $type =~ s/.*\.(gif|jpg|jpeg|png)$/$1/;
   $type =~ s/jpg/jpeg/;

   my $msg = "\nAdding a $type to $snd_file.";
   enc_print("$msg", 3);
   log_info("$msg");
   # Read coverart into $data.
   open(PIC, "< $coverpath" )
      or print "Cannot open file $coverpath: $!\n\n";
   binmode(PIC);
   my $data = do { local($/); <PIC> };

# http://id3.org/id3v2.4.0-frames
# -------------------------------
#      <Header for 'Attached picture', ID: "APIC">
#      Text encoding      $xx
#      MIME type          <text string> $00
#      Picture type       $xx
#      Description        <text string according to encoding> $00 (00)
#      Picture data       <binary data>
#
# http://id3.org/id3v2.4.0-structure
# ----------------------------------
#    Frames that allow different types of text encoding contains a text
#    encoding description byte. Possible encodings:
#
#      $00   ISO-8859-1 [ISO-8859-1]. Terminated with $00.
#      $01   UTF-16 [UTF-16] encoded Unicode [UNICODE] with BOM. All
#            strings in the same frame SHALL have the same byteorder.
#            Terminated with $00 00.
#      $02   UTF-16BE [UTF-16] encoded Unicode [UNICODE] without BOM.
#            Terminated with $00 00.
#      $03   UTF-8 [UTF-8] encoded Unicode [UNICODE]. Terminated with $00.


   $id3v2->add_frame('APIC', chr(0x3), "image/$type", chr(0x3), "", $data);
   $id3v2->write_tag;
   close(PIC);
   $mp3->close;
   return;
}
########################################################################
#
# Write special tags to mp3 files.
#
sub mp3_tags {
   my($snd_file) = shift;
   my $mp3 = MP3::Tag->new($snd_file);
   $mp3->get_tags;
   my $id3v2 = exists $mp3->{'ID3v2'}
         ? $mp3->{'ID3v2'}
         : $mp3->new_tag('ID3v2');
   foreach (@mp3tags) {
      my ($frame, $content) = split(/=/, $_);
      if($frame =~ /^\wXXX$/) {
         my($string, @content) = split(/\]/, $content);
         $string =~ s/\[//;
         $content = join(']', @content);
         $content = tag_eval($string, $content);
         if(defined $content && $content ne "") {
            $id3v2->add_frame($frame, $string, $content);
            my $msg = "\nAdding $frame=$string $content to $snd_file.";
            enc_print($msg, 3);
            log_info("$msg");
         }
         else {
            my $msg = "\nFrame $frame with description " .
                      "$string not added as no content given.";
            enc_print($msg, 3);
            log_info("$msg");
         }
      }
      else {
         # TODO: maybe back_encoding is needed for special frames...
         # But for TPE2 it has already been done.
         $id3v2->add_frame($frame, $content);
         my $msg = "\nAdding $frame=$content to $snd_file.";
         enc_print($msg, 3);
         log_info("$msg");
      }
   }
   $id3v2->write_tag;
   $mp3->close;
   return;
}
########################################################################
#
# Write coverart to ogg files.
#
sub ogg_cover {
   use MIME::Base64 qw(encode_base64);
   my($snd_file, $coverpath) = @_;
   my $type = $coverpath;
   $type =~ s/.*\.(gif|jpg|png)$/$1/;

   open(PIC, "$coverpath")
      or print "Cannot open file $coverpath: $!\n\n";
   my $data = do { local($/); encode_base64(<PIC>, '') };
   close(PIC);

   my $temp_cov = "/tmp/ripit-ogg-cov-$$";
   open(TMP, "> $temp_cov") or print "$temp_cov $!";
   print TMP "COVERART=$data";
   close(TMP);

   my $msg = "\nAdding a $type to $snd_file.";
   enc_print($msg, 3);
   log_info("$msg");
   if(-s "$coverpath" < 60000) {
      log_system("vorbiscomment -a \"$snd_file\" -t COVERARTMIME=image/$type -t COVERART=$data");
   }
   else {
      log_system("vorbiscomment -a \"$snd_file\" -t COVERARTMIME=image/$type");
      # This command will never end, the encoder process will stop here.
      # open(OGG, "|vorbiscomment -a \"$snd_file\"");
      # print OGG $temp_cov;
      # close OGG;
      # This command will never end, the encoder process will stop here.
      # exec("vorbiscomment -a \"$snd_file\" < $temp_cov");
      # Why does it work with back ticks?
      log_info("\nExecuting vorbiscomment to add the cover in base64.\n");
      `vorbiscomment -a \"$snd_file\" < $temp_cov`;
   }
   unlink("$temp_cov");
   return;
}
########################################################################
#
# Write special tag frames to ogg files.
#
sub ogg_tags {
   my($snd_file) = @_;

   foreach (@oggtags) {
      my ($frame, $content) = split(/=/, $_);
      $content = tag_eval($frame, $content);
      if(defined $content and $content ne ""
         and $frame =~ /ASIN|BARCODE|CATALOG|CATALOGNUMBER|CDDBID|DGID|DISCID|MBREID|MUSICBRAINZ_ALBUMID|MUSICBRAINZ_DISCID/) {
         my $msg = "\nAdding $frame=$content to $snd_file.";
         enc_print($msg, 3);
         log_info("$msg");
         log_system("vorbiscomment -a \"$snd_file\" -t \'$frame=$content\'");
      }
      elsif(defined $content) {
         my $msg = "\nThe frame=$frame with content=$content has not " .
                   "been added to\n$snd_file";
         enc_print($msg, 3);
      }
      else {
         my $msg = "\nThe frame=$frame has not been added to\n$snd_file";
         enc_print($msg, 3);
      }
   }
   return;
}
########################################################################
#
# Evaluate special tags to be added (check for mp3, vorbis etc.).
#
sub tag_eval {
   my($frame, $content) = @_;
   return unless(defined $frame);
   chomp $content;
   return $cd{asin} if($frame eq "ASIN" and $content eq "asin");
   return $cd{barcode} if($frame eq "BARCODE" and $content eq "barcode");
   return $cd{catalog} if($frame eq "CATALOG" and $content eq "catalog");
   return $cd{catalog} if($frame eq "CATALOGNUMBER" and $content eq "catalog");
   return $cddbid if($frame eq "CDDBID" and $content eq "cddbid");
   return $cd{dgid} if($frame eq "DGID" and $content eq "dgid");
   return $cd{discid} if($frame eq "DISCID" and $content eq "discid");
   return $cd{discid} if($frame eq "MUSICBRAINZ_DISCID" and $content eq "discid");
   return $cd{discid} if($frame eq "MusicBrainz Disc Id" and $content eq "discid");
   return $cd{mbreid} if($frame eq "MBREID" and $content eq "mbreid");
   return $cd{mbreid} if($frame eq "MUSICBRAINZ_ALBUMID" and $content eq "mbreid");
   return $cd{mbreid} if($frame eq "MusicBrainz Album Id" and $content eq "mbreid");
}

########################################################################
#
# Write the CDDB entry to ~/.cddb/category if there is not already
# an entry present.
#
sub write_cddb {
   chomp($categ = $cd{cat});
   log_system("mkdir -m 0755 -p $homedir/.cddb/$categ/")
      or print "Can not create directory $homedir/.cddb/$categ: $!\n";
   $cddbid =~ s/,.*$// if($cddbid =~ /,/);
   if(! -f "$homedir/.cddb/$categ/$cddbid") {
      open(TOC, "> $homedir/.cddb/$categ/$cddbid")
         or print "Can not write to $homedir/.cddb/$categ/$cddbid: $!\n";
      foreach(@{$cd{raw}}) {
         print TOC $_;
      }
   }
   else {
      print "\nA local archive entry exists in $homedir/.cddb/$categ/",
            "$cddbid, nothing over written.\n" if($verbose > 4);
   }
   close TOC;
   $archive = 0;
}
########################################################################
#
# Merge the wav files if $cdcue == 1.
#
sub merge_wav {
   my ($trn, $chunkbyte, $album) = @_;
   open(IN, "< $wavdir/$trn.rip") or
   print "Can't open $trn.rip: $!\n";
   binmode(IN);
   # Only skip the header in case the base file already exists.
   if(-r "$wavdir/$album.wav") {
      seek(IN, 44, 0) or
         print "\nCould not seek beyond header in file IN: $!\n";
   }
   open(OUT, ">> $wavdir/$album.wav");
   binmode(OUT);

   # I don't know if it is good to read so many bytes a time, but it
   # is faster than reading byte by byte.
   while(read(IN, my $bindata, $chunkbyte)) {
      print OUT $bindata;
   }
   close(IN);
   close(OUT);

   # Rewrite the header of the merged file $album.wav.
   write_wavhead("$wavdir/$album.wav");

   return;
}
########################################################################
#
# Rewrite the wav header.
#
sub write_wavhead {
   my $file = shift;
   if(!sysopen(WAV, $file, O_RDWR | O_CREAT, 0755)) {
      print "\nCan not to open $file: $!\n";
      return;
   }
   my $buffer;
   my $nread = sysread(WAV, $buffer, 44);
   if($nread != 44 || length($buffer) != 44) {
      print "\nWAV-header length problem in file $file.\n";
      close(WAV);
      return;
   }

   my $main_template = "a4 V a4 a4 V a16 a4 V";
   my($riff_header, $file_size_8, $wav_header, $fmt_header,
      $fmt_length, $fmt_data,$data_header,$data_size) =
      unpack($main_template, $buffer);
   if($verbose > 5) {
      print "RIFF chunk descriptor is: $riff_header\n",
            "RIFF chunk length is:     $file_size_8\n",
            "WAVE format is:           $wav_header\n",
            "FMT subchunk is:          $fmt_header\n",
            "FMT subchunk length is:   $fmt_length\n";
   }
   my $file_length = -s "$file";
   $file_size_8 = $file_length - 8;
   $data_size = $file_length - 44;
   $buffer = pack($main_template, $riff_header, $file_size_8,
                  $wav_header, $fmt_header, $fmt_length, $fmt_data,
                  $data_header, $data_size);
   sysseek(WAV, 0, 0);
   syswrite(WAV, $buffer, length($buffer));
   close(WAV);
   return;
}
########################################################################
#
# Check all tracks for VA-style.
#
sub check_va {
   my $prt_msg = shift;
   my $delim = "";
   my $delim_colon = 0;
   my $delim_hyphen = 0;
   my $delim_slash = 0;
   my $delim_parenthesis = 0;
   my $n = 0;
   # Don't use @tracktags because operator might not want to rip the
   # whole CD. VA-style detection will fail if number of selected tracks
   # are compared to the total number of tracks!
   # There are problems in case operator wants to re-encode, @seltrack
   # must be available, but remained empty. In this case use array
   # tracklist instead.
   my @tracks = @seltrack;
   @tracks = (1 .. $#tracklist) if($vatag > 0 && !defined $seltrack[0]);
   foreach (@tracks) {
      my $tn = $_ - 1;
      $delim_colon++ if($tracktags[$tn] =~ /:/);
      $delim_hyphen++ if($tracktags[$tn] =~ /-/);
      $delim_slash++ if($tracktags[$tn] =~ /\//);
      $delim_parenthesis++ if($tracktags[$tn] =~ /\(.*\)/);
      $n++;
   }

   $n = -1 if($n == 0 and $rip == 0); # Prevent false msg.

   my $artist = clean_all($cd{artist});

   if($vatag > 0 and $artist =~ /$vastring/i and
     ($delim_colon == $n or $delim_hyphen == $n or
      $delim_slash == $n or $delim_parenthesis == $n)) {
      $va_flag = 1;
      print "\nVarious Artists CDDB detected, track artist will be ",
            "used for each track tag.\n"
            if($verbose > 2 and $prt_msg == 1);
   }
   elsif($vatag > 0 and $artist =~ /$vastring/i and
     ($delim_colon > 0 or $delim_hyphen > 0 or $delim_slash > 0 or
      $delim_parenthesis > 0)) {
      $va_flag = 1;
      print "\nVarious Artists CDDB detected, track artist will be ",
            "used for some track tags.\n"
            if($verbose > 2 and $prt_msg == 1);
   }
   elsif($vatag > 0 and
     ($delim_colon == $n or $delim_hyphen == $n or
      $delim_slash == $n or $delim_parenthesis == $n)) {
      $va_flag = 1;
      print "\nMultiple artists data detected, track artist will be",
            " used for each track tag.\n"
            if($verbose > 2 and $prt_msg == 1);
   }
   elsif($vatag > 0 and
     ($delim_colon > 0 or $delim_hyphen > 0 or $delim_slash > 0 or
      $delim_parenthesis > 0)) {
      $va_flag = 1;
      print "\nMultiple artists data detected, track artist will be",
            " used for some track tags.\n"
            if($verbose > 2 and $prt_msg == 1);
   }
   else {
      $va_flag = 0 unless($va_flag == 2);
      print "\nNo Various Artists DB detected, album artist will be",
            " used for each track tag.\n"
            if($verbose > 2 and $va_flag == 0 and $prt_msg == 1);
   }
   print "\n" if($verbose > 2 and $prt_msg == 1);
   return($delim) if($va_flag == 0);

   my $delim_cn = 0;
   if($va_flag == 2) {
      $va_flag = 1;
      $delim = "/";
      $delim_cn = $delim_slash;
   }
   # Give slashes highest priority and set default to slashes too.
   if($delim_slash >= $delim_colon and
         $delim_slash >= $delim_hyphen and
         $delim_slash >= $delim_parenthesis) {
      $delim = "/";
      $delim_cn = $delim_slash;
   }
   elsif($delim_colon >= $delim_hyphen and
         $delim_colon >= $delim_parenthesis and
         $delim_colon >= $delim_slash) {
      $delim = ":";
      $delim_cn = $delim_colon;
   }
   elsif($delim_hyphen >= $delim_colon and
         $delim_hyphen >= $delim_slash and
         $delim_hyphen >= $delim_parenthesis) {
      $delim = "-";
      $delim_cn = $delim_hyphen;
   }
   elsif($delim_parenthesis >= $delim_colon and
         $delim_parenthesis >= $delim_slash and
         $delim_parenthesis >= $delim_hyphen) {
      $delim = "(";
      $delim_cn = $delim_parenthesis;
   }
   else {
      $delim = "/";
      $delim_cn = $delim_slash;
   }
   return($delim, $delim_cn);
}
########################################################################
#
# Copy image file from destination path to directories of encoded sound
# files. Prevent copying to itself.
#
sub copy_cover {
   for(my $c=0; $c<=$#coder; $c++) {
      my $basepath = $copycover;
      my @basepath = split(/\//, $basepath);
      pop(@basepath);
      $basepath = join('/', @basepath);
      next if("$basepath" eq "$sepdir[$c]");
      log_system("cp \"$copycover\" \"$sepdir[$c]\"")
         or print "Copying file to $sepdir[$c] failed: $!\n";
   }
}
########################################################################
#
# Check album cover in path variable copycover.
#
sub check_copy {
   my $copycover = shift;
   my $msg = shift;
   if($copycover =~ /^".*"$/) {
      print "Operator did quote too many times!\n" if($verbose > 5);
      $copycover =~ s/^"(.*)"$/$1/;
   }
   check_cover($copycover, $msg);
}
########################################################################
#
# Check album cover in path variable copycover or coverpath.
#
sub check_cover {
   my $copycover = shift;
   my $msg = shift;
   my $ans;
   if(-f "$copycover") {
      print "File $copycover found\n" if($verbose > 4);
   }
   else {
      while($copycover !~ /^[yn]$/i) {
         print "$msg\nImage file $copycover is not a valid file. ",
               "Continue? [y/n] (y) ";
         $ans = <STDIN>;
         chomp $ans;
         $ans = "y" if($ans eq "");
         last if($ans =~ /y/i);
         die "Aborting.\n\n" if($ans =~ /n/i);
      }
   }
}
########################################################################
#
# Resize album cover to given format.
#
sub resize_cover {
   my $coverpath = shift;
   my $orig_coverpath = $coverpath;
   my $orig_fmt = "";
   if(-f "$coverpath" && -s "$coverpath") {
      open(FMT, "identify -format \"%[fx:w]x%[fx:h]\" \"$coverpath\" |")
      or print "\nFailed to run ImageMagicks identify command: $!\n";
      while(<FMT>) {
         chomp;
         $orig_fmt = $_ if(/\d+x\d+/);
      }
      close(FMT);
      if($orig_fmt =~ /\d+x\d+/) {
         if($orig_coverpath =~ /\.[A-Za-z]{3,4}$/) {
            $orig_coverpath =~ s/(\.[A-Za-z]+)$/_$orig_fmt$1/;
         }
         else{
            $orig_coverpath .= "_$orig_fmt";
         }
      }
      else{
         print "\nProblem with format detection of $coverpath: ",
               "$orig_fmt\n" if($verbose > 3);
      }
      my ($orig_width, $orig_height) = split(/x/, $orig_fmt);
      my ($width, $height) = split(/x/, $coversize);
      $height = 0 unless(defined $height);
      # Do not alter image if sizes are smaller.
      if($orig_width <= $width || $orig_height <=  $height) {
         print "\nCoversize is equal or larger than sizes of provided ",
               "coverart, no changes will happen.\n" if($verbose > 1);
         return;
      }
      if($coverpath ne $orig_coverpath) {
         log_info("rename(\"$coverpath\", \"$orig_coverpath\")");
         rename("$coverpath", "$orig_coverpath") ;
         log_system("convert -resize $coversize \"$orig_coverpath\" \"$coverpath\"");
         print "Renamed cover to $orig_coverpath and resized the ",
               "$coverpath\n" if($verbose > 4);
      }
      else {
         print "\nProblem while creating a backup of $coverpath ",
               "renamed to $orig_coverpath\n" if($verbose > 3);
      }
   }
   else {
      print "File $coverpath not found\n" if($verbose > 3);
   }
   return;
}
########################################################################
#
# Read in ISRCs using Icedax and submit them if detected using code from
# Nicholas Humfrey <njh@aelius.com>.
#
sub get_isrcs {
   print "\nReading ISRC..." if($verbose > 2);
   my $icedax = `which icedax`;
   chomp($icedax);
   if($mbname ne "" and $mbpass ne "" and $icedax ne "") {
      my $mcn = undef;
      @isrcs = ();
      open(ICEDAX, "icedax -D $scsi_cddev -g -H -J -Q -v trackid 2>&1 |")
      or print "\nFailed to run icedax command: $!\n";
      while(<ICEDAX>) {
         chomp;
         if(/T:\s+(\d+)\s+ISRC:\s+([A-Z]{2}-?\w{3}-?\d{2}-?\d{5})$/) {
            my ($num, $isrc) = ($1-1, uc($2));
            $isrc =~ s/\W//g;
            $isrcs[$num] = $isrc;
         }
         elsif(/Media catalog number: (.+)/i) {
            $mcn = $1;
         }
      }
      close(ICEDAX);

      my $diflag = 1; # Suppose all ISRCs found are different.
      # Now preparing ISRC data array to post to MB server.
      my @isrcdata = ();
      print "MCN: " . $mcn . "\n" if($mcn && $verbose > 3);
      for(my $i = 0; $i < scalar(@isrcs); $i++) {
         my $isrcno = $isrcs[$i];
         my $trackid = $idata[$i];
         next unless($trackid);
         if(defined $isrcno && $isrcno ne '' && $isrcno !~ /^0+$/) {
            printf("\nTrack %2.2d: %s %s", $i + 1, $isrcno || '', $trackid)
            if($verbose >= 3);
            push(@isrcdata, "isrc=" . $trackid . '%20' . $isrcno);
         }
         # Test if subsequent (all) ISRCs are different.
         if($i > 0) {
            $isrcno = $i unless($isrcno);
            $diflag = 0 if($isrcs[$i-1] && $isrcno eq $isrcs[$i-1]);
         }
      }
      print "\n\n" if($verbose > 3);

      # Check that we have something to submit
      if(scalar(@isrcdata) < 1) {
         print "\nNo valid ISRCs to submit." if($verbose > 2);
         sleep 1;
      }
      elsif($diflag == 0) {
         print "\nIdentical ISRCs for different tracks detected.",
               "\nNo submission in this case.\n" if($verbose > 2);
         sleep 1;
      }
      else {
         # Send to Musicbrainz.
         if($mbname ne "" and $mbpass ne "") {
            print "\n@isrcdata" if($verbose > 4);
            my $isrc_sub = -1;
            if($interaction > 0) {
               while($isrc_sub < 0 || $isrc_sub > 1) {
                  print "\n\nSubmission of ISRCs to MB? [y/n] (n) ";
                  $isrc_sub = <STDIN>;
                  chomp $isrc_sub;
                  $isrc_sub = 0 if($isrc_sub eq "" or $isrc_sub eq "n");
                  $isrc_sub = 1 if($isrc_sub eq "y");
                  $isrc_sub = -1 unless($isrc_sub =~ /^0|1$/);
                  print "\n";
               }
            }
            else {
               $isrc_sub = 1;
            }
            if($isrc_sub == 1) {
               my $ua = LWP::UserAgent->new;
               $ua->timeout(10);
               $ua->env_proxy;
               $ua->credentials( 'musicbrainz.org:80',
                                 'musicbrainz.org',
                                 "$mbname", "$mbpass" );

               my $request = HTTP::Request->new(
                  'POST', 'http://musicbrainz.org/ws/1/track/' );
               $request->content(join('&', @isrcdata));
               $request->content_type(
                  'application/x-www-form-urlencoded');

               my $re = $ua->request($request);
               print "\nISRC submission to MB " . $re->status_line. "\n"
                  if($verbose > 2);
            }
            else {
               print "\nNo ISRC submission to MB.\n" if($verbose > 2);
            }
         }
      }
   }
   return;
}
########################################################################
#
# Detect a discID somewhere in log or cue files, or maybe even in the
# comment tag of the sound files.
#
sub get_cdid {
   my ($album, $artist, $trackno, $title, $reldate);

   # Read the inputdir folder.
   opendir (DIR, "$inputdir") or
      print "Can't read inputdir $inputdir $!\n";
   my @dirfiles = readdir(DIR);
   closedir(DIR);
   @dirfiles = sort(@dirfiles);
   my @cntfiles = grep { /\.cue$|\.inf$|\.log$|\.m3u$|\.toc$/ } @dirfiles;
   my @sndfiles = grep { /\.flac$/ } @dirfiles;
   my @wavfiles = grep { /\.wav$/ } @dirfiles;
   if(!$sndfiles[0] && !$wavfiles[0]) {
      die "\nQuitting, inputdir \"$inputdir\" has no flac or wav",
          " files.\n\n";
   }

   # Add one snd file (flac) to the list of files to be checked for ids.
   if($sndfiles[0]) {
      push(@cntfiles, $sndfiles[0])
   }

   # Read the potential files with content:
   foreach my $cntfile (@cntfiles) {
      # Introduced to track down Morituri bug writing hidden cue sheets
      # and playlist files; but actually does not solve the problem.
      next unless(-r "$inputdir/$cntfile");
      open(CONF, "$inputdir/$cntfile") ||
         print "Can not read $cntfile file!\n";
      my @conflines = <CONF>;
      close(CONF);
      if($cntfile =~ /\.m3u$/) {
         print "Analyzing playlist file.\n" if($verbose > 4);
         # First non regular tags in header of m3u file.
         # TODO: what happens if playlist file in an multi disc release
         # contains all discids, i.e. more than one...
         my @cdid = grep(s/^\s*#CDDBID=//, @conflines);
         if(defined $cdid[0] && $#cdid < 1 or $interaction == 0) {
            chomp($cdid = $cdid[0])
               unless($pcdid =~ /[0-9a-f]/ && length($pcdid) == 8);
         }
         elsif(defined $cdid[0]) {
            print "More than one CDDBID found:\n";
            my ($i, $j) = (0, 0);
            while($i > $#cdid+2 || $i == 0) {
               foreach my $id (@cdid) {
                  $j++;
                  chomp($id);
                  my $tno = substr($id, 6);
                  $tno = hex($tno);
                  printf(" %2d: $id for a $tno track CD\n", $j);
               }
               print "\nChoose [1-$j]: ";
               $i = <STDIN>;
               chomp $i;
               $j = 0;
            }
            chomp($cdid = $cdid[$i-1]);
            print "\n";
         }
         my @discid = grep(s:^#DISCID=::, @conflines);
         if(defined $discid[0] && $#discid < 1 or $interaction == 0) {
            chomp($discid = $discid[0])
               unless($pcdid =~ /\-$/ && length($pcdid) == 28);
         }
         elsif(defined $discid[0]) {
            print "More than one discid found:\n";
            my ($i, $j) = (0, 0);
            while($i > $#discid+2 || $i == 0) {
               foreach my $id (@discid) {
                  $j++;
                  chomp($id);
                  printf(" %2d: $id\n", $j);
               }
               print "\nChoose [1-$j]: ";
               $i = <STDIN>;
               chomp $i;
               $i = 0 unless($i =~ /^\d+$/);
               $j = 0;
            }
            chomp($discid = $discid[$i-1]);
         }
      }
      elsif($cntfile =~ /\.cue$/) {
         print "Analyzing cue sheet.\n" if($verbose > 4);
         # First non regular tags in header of toc file.
         chomp($cdid = join('', grep(s:^//CDDBID=|REM\sDISCID\s::, @conflines)))
         unless($pcdid =~ /[0-9a-f]/ && length($pcdid) == 8);
         chomp($discid = join('', grep(s:^//DISCID=::, @conflines)))
         unless($pcdid =~ /\-$/ && length($pcdid) == 28);
         # Regular entry in toc file.
         if($cdid eq "") {
            chomp($cdid = join('', grep(s:DISC_ID\s*"::, @conflines)));
            chop($cdid) if($cdid);
         }
         $cdid =~ s/\s//g;
      }
      elsif($cntfile =~ /\.toc$/) {
         print "Analyzing toc file.\n" if($verbose > 4);
         # First non regular tags in header of toc file.
         chomp($cdid = join('', grep(s:^//CDDBID=::, @conflines)))
         unless($pcdid =~ /[0-9a-f]/ && length($pcdid) == 8);
         chomp($discid = join('', grep(s:^//DISCID=::, @conflines)))
         unless($pcdid =~ /\-$/ && length($pcdid) == 28);
         # Regular entry in toc file.
         if($cdid eq "") {
            chomp($cdid = join('', grep(s:DISC_ID\s*"::, @conflines)));
            chop($cdid) if($cdid);
         }
         $cdid =~ s/\s//g;
      }
      elsif($cntfile =~ /\.inf$/) {
         print "Analyzing inf files.\n" if($verbose > 4);
         # First non regular tags in header of a inf file.
         chomp($discid = join('', grep(s:^DISCID=\t::, @conflines)))
         unless($pcdid =~ /\-$/ && length($pcdid) == 28);
         # Regular entry in inf file.
         if($cdid eq "") {
            chomp($cdid = join('', grep(s:^CDINDEX_DISCID=\t::, @conflines)))
            unless($pcdid =~ /\-$/ && length($pcdid) == 28);
            chomp($cdid = join('', grep(s:^CDDB_DISCID=\t::, @conflines)))
            unless($pcdid =~ /[0-9a-f]/ && length($cdid) == 8);
         }
      }
      elsif($cntfile =~ /\.flac$/) {
         print "Analyzing flac files.\n" if($verbose > 4);
         # Read out the comment-tag.
         my $tagfile = $cntfile;
         $tagfile =~ s/\.flac$//;

         open(DISCID, "metaflac --export-tags-to=- \"$inputdir/$cntfile\"|");
         my @response = <DISCID>;
         close(DISCID);

         chomp($cdid = join("", grep(s/^CDID=\s*//, @response)))
         unless($pcdid =~ /[0-9a-f]/ && length($cdid) == 8);
         chomp($discid = join("", grep(s/^DESCRIPTION=\s*//, @response)))
         unless($discid =~ /\-$/ && length($discid) == 28);
      }
      # Final clean-up of IDs. We should incorporate passed ids here.
      if(defined $cdid && $cdid =~ /[0-9a-f]/ && length($cdid) == 8) {
         $cddbid = $cdid;
         $cd{id} = $cddbid;
      }
      else{
         $cdid = "" unless($pcdid =~ /[0-9a-f]/ && length($cdid) == 8);
      }
      $discid = "" unless($discid =~ /\-$/ && length($discid) == 28);
      $discid = $pcdid if($pcdid =~ /\-$/ && length($pcdid) == 28);
      $cd{discid} = $discid if($discid ne "");
      last if($cdid ne "" and $discid ne "");
   }
   # Read the potential flac files:
   my @vartists = ();
   my $ghostflag = 0;
   @sndfiles = sort(@sndfiles);
   foreach my $sndfile (@sndfiles) {
      log_info("metaflac --export-tags-to=- \"$inputdir/$sndfile\"|");
      open(SND, "metaflac --export-tags-to=- \"$inputdir/$sndfile\"|");
      my @response = <SND>;
      close(SND);
      # Read out the meta data:
      chomp($title = join('', grep(s/^TITLE=//i, @response)));
      chomp($artist = join('', grep(s/^ARTIST=//i, @response)));
      chomp($album = join('', grep(s/^ALBUM=//i, @response)));
      chomp($categ = join('', grep(s/^CATEGORY=//i, @response)));
      chomp($genre = join('', grep(s/^GENRE=//i, @response)));
      chomp($reldate = join('', grep(s/^DATE=//i, @response)));
      chomp($trackno = join('', grep(s/^TRACKNUMBER=//i, @response)));

      $album_utf8 = $album;
      $artist_utf8 = $artist;

      my $year = $reldate;
      $year =~ s/.*(\d{4}).*/$1/;

      # What if meta data is in VA style? First artist might not be the
      # album artist and each artist tag from each track should be
      # merged into the track title with VA option switched on ...
      push(@vartists, $artist);
      $cd{artist} = $artist;
      $cd{title} = $album;
      $cd{cat} = $categ;
      $cd{genre} = $genre;
      $cd{year} = $year;

      my $j = $trackno - 1;
      $j = $trackno if($hiddenflag == 1);
      if($trackno <= 0 or $trackno eq "00") {
         $j = 0;
         $hiddenflag = 1;
      }
      $ghostflag = 1 if($sndfile =~ /Ghost.Song/i);
      # Ghost song in the middle means that more than one track will
      # hold the same tracknumber if it comes from an original rip
      # (done by Ripit). For the moment: increase track counter in each
      # case a track has already been used.
      while(defined $cd{track}[$j]) {
         $j++;
         last if($j > 100);
      }
      $cd{track}[$j] = $title;
      # Fill the tracksel array here... or not?
      # But as we do not use $trackno make sure to count the right way.
      # Do not care about ghost songs anymore, they will be renamed.
      push(@tracksel, $j+1);
   }
   if($vatag > 0) {
      my $j = 0;
      my $vaflag = 0;

      # Check if different artists are given.
      foreach(@vartists) {
         $vaflag = 1 if($_ ne $cd{artist});
         last if($vaflag == 1);
      }
      # In case VA style has been detected, ask for true artist name
      # and recombine the track names with track artist.
      if($vaflag > 0) {
         if($interaction > 0) {
            print "\nEnter album artist (Various Artists): ";
            $cd{artist} = <STDIN>;
            chomp($cd{artist});
            $cd{artist} = "Various Artists" if($cd{artist} eq "");
         }
         else {
            $cd{artist} = "Various Artists";
         }
         $artist_utf8 = $artist;
         foreach(@vartists) {
            $cd{track}[$j] = $cd{track}[$j] . " / " . $_
               if($vatag % 2 == 0);
            $cd{track}[$j] = $_ . " / " . $cd{track}[$j]
               if($vatag % 2 == 1);
            $j++;
         }
      }
   }
}
########################################################################
#
# Decode existing flac and create list of track names to be re-encoded.
#
sub decode_tracks {
   # Check if wav are present in inputdir.
   # Read the inputdir folder.
   opendir (DIR, "$inputdir") or
      print "Can't read inputdir $inputdir $!\n";
   my @dirfiles = readdir(DIR);
   closedir(DIR);
   @dirfiles = sort(@dirfiles);
   my @wavfiles = grep { /\.wav$/ } @dirfiles;
   my @sndfiles = grep { /\.flac$/ } @dirfiles;
   # Decode flac to wav if flac directory has no wav in. We suppose:
   # existing flac means no existing wav. Should operator decide on type
   # of source in case both exist in $inputdir?
   # Other problem: if inputdir does not correspond to the dirtemplate
   # according to a wavdir has been created... While decoding use
   # wavdir for output for encoder to find the file names.
   # More problems: if operator changed wording, ripit still uses the
   # original names here, but encoder expects wav with new wording...
   if(@sndfiles) {
      my $trcn = 0;
      @tracklist_modif = @tracklist;
      @tracklist = ();
      foreach my $sndfile (@sndfiles) {
         $trcn++;
         my $wavfile = $sndfile;
         $wavfile =~ s/\.flac$/.wav/;
         if($verbose > 2) {
            if(-f "$wavdir/$wavfile") {
               print "No decoding of flac, WAV $wavfile exists under\n$wavdir\n";
            }
            else {
               print "Decoding $sndfile into $wavdir.\n"
            }
         }
         log_system("flac $flacdecopt -d \"$inputdir/$sndfile\" -o \"$wavdir/$wavfile\"")
            unless(-f "$wavdir/$wavfile");
         # Copy file to ensure track name according to look-up or
         # actual archive data.
         if(!-f "$wavdir/$wavfile" && $sndfile =~ /\.wav$/) {
            print "WAV $wavfile is not present in $wavdir, going ",
                  "to copy the wav $sndfile to $wavdir.\n"
               if($verbose > 2);
            log_system("cp \"$inputdir/$sndfile\" \"$wavdir/$wavfile\"");
         }
         # These are the flac files we have in @tracksel, we use them as
         # sources for re-encoding.
         $wavfile =~ s/\.wav$//;
         # In any case, fill the @tracklist array, even if decoder
         # failed.
         push(@tracklist, "$wavfile");
         if(!-f "$wavdir/$wavfile.wav") {
            open(ERO,">>$wavdir/error.log")
               or print "Can not append to file ",
                        "\"$wavdir/error.log\"!\n";
            print ERO "Track $trcn on CD $cd{artist} - $cd{title} ",
                      "failed!\n";
            close(ERO);
            print "Warning: decoding $sndfile failed.\n"
               if($verbose > 0);
            log_info("Warning: decoding $sndfile failed");
         }
      }
   }
   else {
      my $tracksel_flag = 1;
      $tracksel_flag = 0 if(defined $tracksel[0] && $tracksel[0] =~ /\d/);
      foreach my $wavfile (@wavfiles) {
         push(@tracksel, $tracksel_flag) if($tracksel_flag > 0);
         $wavfile =~ s/\.wav$//;
         push(@tracklist, $wavfile);
         $tracksel_flag++ if($tracksel_flag > 0);
         $wavdir =~ s/\/$// if($wavdir =~ /\//);
         $inputdir =~ s/\/$// if($inputdir =~ /\//);
         if($wavdir ne $inputdir) {
            print "Copying $wavfile from $inputdir to $wavdir.\n\n"
               if($verbose > 2);
            log_system("cp \"$inputdir/$wavfile.wav\" \"$wavdir/$wavfile.wav\"");
         }
      }
   }
   # Question: do we really need framelist here? We already have one if
   # we used MB to update tags needed to query freedb.org. Of course,
   # this frame list has the "true" track length according to DB and not
   # according to existing files; true means @ low precision as ripit
   # did not retrieve sectors from MB but track lengths in seconds...
   @framelist = 0;
   my $prevtracklen = 0;
   my $trcn = 0;
   @secondlist = ();
   foreach my $wavfile (@tracklist) {
      $trcn++;
      # Don't alter @tracklist.
      my $trn = $wavfile;
      $trn =~ s/$/.wav/;
      # The location is now $wavdir, not $inputdir, see above.
      my $tracklen = 0;
      if(-f "$wavdir/$trn") {
         $tracklen = -s "$wavdir/$trn";
         $tracklen = int(($tracklen - 44) / 2352 / 75);
      }
      else {
         $tracklen = int(($framelist_orig[$trcn] - $framelist_orig[$trcn - 1]) / 75) if(defined $framelist_orig[$trcn]);
      }
      push(@framelist, int(($tracklen + $prevtracklen) * 75));
      push(@secondlist, $tracklen);
      $prevtracklen = $tracklen;
   }
}
########################################################################
#
# Create a toc AoH usually read out of the disc in case of re-encoding
# used to retrieve freeDB data (genre) when using MB.
#
sub create_toc {
   my @frames = @_;
   my @r = ();
   foreach my $i (@frames) {
      my $sec = int($i / 75);
      my $frame = $i % 75 if($sec > 0);
      my $min = int($sec / 60);
      $sec = $sec % 60 if($min > 0);

      my %cdtoc = ();
      $cdtoc{min} = $min;
      $cdtoc{sec} = $sec;
      $cdtoc{frame} = $frame;
      $cdtoc{frames} = $i;

      push(@r, \%cdtoc);
   }
   return @r;
}
########################################################################
#
# Create a toc AoH usually read out of the disc in case of re-encoding
# used to retrieve freeDB data (genre) when using MB.
#
sub enc_report {
   my $encline = shift;
   my $trackcn = shift;
   open(ENCLOG, "< $wavdir/enc.log");
   my @loglines = <ENCLOG>;
   close(ENCLOG);
   my $lincn = 0;
   my @outlines = ();
   foreach (@loglines) {
      if($verbose >= 3) {
         push(@outlines, $_)
         if($lincn >= $encline && $_ !~ /^\n/);
      }
      elsif($verbose == 1 || $verbose == 2) {
         print $_ if($lincn >= $encline && $_ =~ /complete\./);
      }
      $lincn++;
   }
   # Compact output.
   $encline = $lincn;
   if($outlines[0] && $verbose >= 1) {
      if($trackcn <= $#tracksel || $accuracy == 1) {
         push(@outlines, "*" x 47, "\n") if($verbose >= 3);
         unshift(@outlines, "\n", "*" x 15, " Encoder reports ",
                                  "*" x 15, "\n") if($verbose >= 3);
      }
      else {
         print "\n", "*" x 47, "\nWaiting for encoder to finish...\n\n";
      }
      print @outlines if($verbose >= 2);
   }
   return($encline);
}
########################################################################
#
# Fill the error.log with encoder msgs.
#
sub enc_print {
   my $string = shift;
   my $inter = shift;
   my $ripmsg = "The audio CD ripper reports: all done!";
   my $ripcomplete = 0;
   if(-r "$wavdir/error.log") {
      open(ERR, "$wavdir/error.log")
         or print "Can not open file error.log!\n";
      my @errlines = <ERR>;
      close(ERR);
      my @ripcomplete = grep(/^$ripmsg/, @errlines);
      $ripcomplete = 1 if(@ripcomplete);
      if(-r "$wavdir/enc.log" && $ripcomplete == 0) {
         open(ENCLOG, ">>$wavdir/enc.log");
         print ENCLOG "\n$string\n\n";
         close(ENCLOG);
      }
      else {
         print "$string\n" if($verbose > $inter);
      }
   }
   else {
      print "$string\n" if($verbose > $inter);
   }
}
########################################################################
#
# Download coverart from coverartarchive.org
#
sub get_cover {
   my $mbreid = $cd{mbreid} if($cd{mbreid});
   if(-f "$coverpath" and $overwrite ne "y") {
      print "File $coverpath exists\nand option overwrite is not set ",
            "to \"y\", no cover will be retrieved.\n\n"
         if($verbose > 2);
      return;
   }

   if(defined $mbreid and $mbreid ne "" and $coverpath ne "") {
      print "Retrieving coverart from coverartarchive.org.\n"
         if($verbose > 2);

      # wget http://coverartarchive.org/release/76df3287-6cda-33eb-8e9a-044b5e15ffdd
      # wget http://coverartarchive.org/release/76df3287-6cda-33eb-8e9a-044b5e15ffdd/829521842.jpg
      # wget http://coverartarchive.org/release/755c96ed-4c6e-4919-9542-8d78efa90244/3415268642-500.jpg

      eval {
         my $ua = LWP::UserAgent->new();
         $ua->env_proxy();
         $ua->agent("ripit/$version");
         my $url = "http://coverartarchive.org/release/$mbreid/front";
         print "Request on $url.\n" if($verbose > 4);
         my $response = $ua->get($url);
         if ($response->is_error()) {
            printf "%s\n", $response->status_line;
         }
         else {
            my $content = $response->content();
            $response = $ua->get(
               $url,
               ':content_file' => "$coverpath");
         }
      }
   }
   elsif($coverpath eq "") {
      print "No coverpath stated to retrieve coverart to.\n"
         if($verbose > 2);
   }
   else {
      print "No MB-release ID (MBREID) found to retrieve coverart ",
            "from coverartarchive.org.\n" if($verbose > 2);
   }
   if(defined $cd{dgid} and $cd{dgid} =~ /\d+/) {
      print "Retrieving coverart from discogs.com.\n"
         if($verbose > 2);
      my $dgid = $cd{dgid};
      chomp $dgid;

      my $dgcoverpath = $coverpath;
      if(-f "$coverpath" && $coverpath =~ /jpeg/) {
         $dgcoverpath =~ s/\.jpeg/-$dgid.jpeg/;
      }
      elsif(-f "$coverpath" && $coverpath =~ /jpg/) {
         $dgcoverpath =~ s/\.jpg/-$dgid.jpg/;
      }
      elsif(-f "$coverpath" && $coverpath =~ /png/) {
         $dgcoverpath =~ s/\.png/-$dgid.png/;
      }
      elsif(-f "$coverpath") {
         $dgcoverpath =~ s/$/-$dgid/;
      }

      eval {
         my $ua = LWP::UserAgent->new();
         $ua->env_proxy();
         $ua->agent("ripit/$version");
         my $base_url = "http://www.discogs.com/viewimages?release=$dgid";
         my @pics = ();
         print "Request on $base_url.\n" if($verbose > 3);
         my $response = $ua->get($base_url);
         if ($response->is_error()) {
            printf "%s\n", $response->status_line;
         }
         else {
            my $content = $response->content();
            my @content = split(/\n/, $content);
            my @url = grep(/http:\/\/s.pixogs.com\/image\/R-$dgid/, @content);
            foreach(@url) {
               s;.?img src="http://s.pixogs;http://s.pixogs;;
               push(@pics, split(/"\s+\/><\/span><\/p>/, $_));
            }
            foreach(@pics) {
               s;.*?http://s.pixogs;http://s.pixogs;;
               s;".*$;;;
            }
         }
         print "Request on $pics[0].\n" if($verbose > 3);
         $response = $ua->get($pics[0], Referer => $base_url);
         if ($response->is_error()) {
            printf "%s\n", $response->status_line;
         }
         else {
            my $content = $response->content();
            $response = $ua->get(
               $pics[0],
               ':content_file' => "$dgcoverpath");
         }
         # Sometimes the artwork downloaded is a gif instead of an
         # expected jpeg.
         if(defined $pics[0] && $pics[0] =~ /\.gif$/) {
            # Convert the gif to a jpg using the same file name.
            log_system("convert \"$dgcoverpath\" \"$dgcoverpath\"");
         }
      }
   }
}
########################################################################
#
# Split the tracktag into its artist part and track part if
# VA style is used.
sub split_tags {
   my $tracktag = shift;
   my $delim = shift;

   my $artistag = "";
   if($vatag % 2 == 1) {
      ($artistag, $tracktag) = split(/$delim/, $tracktag);
      $tracktag =~ s/\)// if($delim =~ /\(/);
      $tracktag =~ s/^\s*//;
      $artistag =~ s/\s*$//;
      # If artistag got all info, rather use it as tracktag...
      if($tracktag eq "") {
         $tracktag = $artistag;
         $artistag = "";
      }
   }
   else {
      ($tracktag, $artistag) = split(/$delim/, $tracktag);
      $artistag =~ s/\)// if($delim =~ /\(/);
      $artistag =~ s/^\s*//;
      $tracktag =~ s/\s*$//;
   }

   return($artistag, $tracktag);
}
########################################################################
#
# Delete lock files in case utftag is used and the encoding command
# can not hold the clean-up parts.
sub del_lock {
   my $wavdir = shift;
   my $lockfile = shift;
   my $ret = 2;
   open(LOCK, "$wavdir/$lockfile");
   my @locklines = <LOCK>;
   close(LOCK);

   my @shorts = grep(s/^short-in:\s//, @locklines);
   my @full = grep(s/^full-out:\s//, @locklines);
   chomp(my $shortname = $shorts[0]) if(defined $shorts[0]);
   chomp(my $ripnam = $full[0]) if(defined $full[0]);
   if(defined $shortname && -r "$shortname") {
      log_system("mv \"$shortname\" \"$ripnam\" &");
      unlink("$wavdir/$lockfile");
      $ret = 0;
   }
   return($ret);
}
########################################################################
#
sub check_audio {
   if($ripper == 2) {
      my $mcn = undef;
      push(@audio, ' ');
      # open(ICEDAX, "icedax -D $scsi_cddev -g -H -J -Q -v trackid 2>&1 |")
      open(ICEDAX, "icedax -D $scsi_cddev -g -H -J -Q -v toc 2>&1 |")
         or print "\nFailed to run icedax command: $!\n";
      while(<ICEDAX>) {
         chomp;
         # Example output:
         # T15:  146378 41:31.48 audio linear copydenied stereo title '' from ''
         # T16:  333251  2:21.54 data uninterrupted copydenied N/A
         # T17:  343880  0:00.31 audio linear copydenied stereo title '' from ''
         if(/T(\d+):\s+\d+\s+\d+:\d{2}\.\d{2}\s([a-z]*)\s.*$/) {
            my ($num, $typ) = ($1, $2);
            $typ = ($typ eq "data" ? '*' : ' ');
            $audio[$num] = $typ;
         }
         elsif(/Media catalog number: (.+)/i) {
            $mcn = $1;
         }
      }
      close(ICEDAX);
   }
   else {
      my $tcn = 0;
      # cdparanoia -Q |& grep \"^\\s*[[:digit:]]\" | wc -l
      open(CDPARA, "cdparanoia -d $scsi_cddev -Q 2>&1 |")
         or print "\nFailed to run cdparanoia command: $!\n";
      while(<CDPARA>) {
         chomp;
         if(/^\s+(\d+)\.\s+(\d+).*/) {
            my ($num, $ff) = ($1, $2);
            while($tcn < $num) {
               $audio[$tcn] = '*';
               $tcn++;
            }
            $audio[$num] = ' ';
            $tcn++;
         }
      }
      close(CDPARA);
      $audio[0] = ' ';
   }
}
