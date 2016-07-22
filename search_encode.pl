#!/usr/bin/perl

# search_encode.pl: A general framework to query and retrieve data from the
# ENCODE repository using the REST API. Copyright (C) 2015, Adam Diehl,
# adadiehl@umich.edu
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use JSON;
use WWW::Mechanize;
use Getopt::Long;
use Encode qw(encode_utf8 decode_utf8);
use Digest::MD5 qw(md5_hex);
use URI::Escape;

my $usage =
"\nsearch_encode.pl

A general framework to query and retrieve experiment data from the ENCODE
repository. Capable of returning metadata for search results in tabular format
or as json data, as well as downloading all or user-specified types of
datafiles from the resulting experiments.


USAGE:

search_encode.pl <search term> <params string> [OPTIONS]

<search term>
    Text string to search for within the ENCODE portal.

<params string>
    Comma-delimited sting of key:value pairs corresponding to columns in the
    given database table. See the schema at the address above. Some columns
    have sub-keys that can be searched. Some examples are available in Box 3:
    API Resources, in \"Deciphering ENCODE\", available at
    http://www.cell.com/trends/genetics/fulltext/S0168-9525%2816%2900017-2
    
    Possible keys of interest for experiments:
        biosample_term_name: tissue/cell used in assay
        assay_term_name: type of assay (e.g., ChIP-seq)
        target.investigated_as: type of target (e.g, transcription factor)
        target.label: name of factor probed (e.g., CTCF)
        status: status of experiment (released/revoked)

    Use the empty string \"\" for no parameters.


OPTIONS:

--download
    Download files associated with the results. Type(s) of files may be
    specified with the --file-type flag. Currently only tested for results
    of type \"experiment\". May behave unpredictably for other types!

--output-type <type_1,...,type_n>
    Used with --download, limits results to files of given type(s).
    Multiple types may be supplied as a comma-separated list. File types are
    matched against the \"output_type\" column of the file records, and
    available values will vary depending on the experiment. Common values are:

    * reads: raw sequnence reads (usually fastq format)
    * alignments: sequence alignment (usually BAM format)
    * peaks: processed peaks from some peak caller (often bed or bigBed)
    * signal: raw signal (often bigWig format)

--file-format <format_1,...,format_n>
    Used with --output-type, restrict downloads to a given file format, e.g.,
    bam, bigBed. Available values vary depending on the specific experiment.
    This MUST contain a value for every file type supplied with --output-type
    or it will throw an error. Specify \"0\" for all types not requiring a
    file type.
    
--file-format-type <type_1,...,type_n>
    Used with --output-type, restrict downloads to a given file format type,
    e.g., \"broadPeak\" or \"narrowPeak\". See notes for --file-format.

--download-path <path>
    Location (absolute or relative to workding directory) to write downloaded
    files.

--out-root <root>
    String to prepend to output files.

--check-exists
    Check to see if a file already exists before downloading and do not
    retrieve if found.

--save-json
    Save the JSON metadata for every file downloaded. This can be useful for
    identifying individual files and properties later on when retrieving
    multiple files, especially if further programmatic processing is
    anticipated.

--no-header
    Do not print a header line with column names to the metadata file.

--count-only
    Return only the number of results for the search. Do not retrieve
    any metadata or files. Suppresses --download (and related options) and
    --save-json.

--by-biosample
    Convert the search term to a biosample term name, for which search
    results will be returned. The search term is not directly queried with
    this option, but rather converted into a search parameter. This can be
    useful when a search for a specific cell line is yielding either no
    results or imprecise results.

--help
    Display this message


NOTES:

* A search string of \"*\" will return all results matching the rest of the
parameters. This can be useful if you want to retrieve the same type of data
for all available cell types, for instance.

* Most table columns in the ENCODE database tables are visible to the search
algorithm and you may chain as many as you would like onto your query.
Please consult the schema, at https://www.encodeproject.org/profiles/graph.svg
to see the columns for each data table.

* Columns in tables referenced by the primary table may also be searched. (All
links are described in the schema) For instance, to search for experiments for
human only based on scientific name, you need to use the \"replicates\"
coumn, which (indirectly) references the \"organism\" table:
&replicates.library.biosample.donor.organism.scientific_name=Homo sapiens

* Fields in the JSON with values specified as a folder location usually are
available to directly search through the parameter string by specifying as
&field.column=value. E.g., &documents.attachment.download=file.pdf will
find files referencing file.pdf.

* All column names and values are CaSe-SeNsItIvE

* Database values may include white-space. To include a term with white space
in your query, put it in quotes when supplying it at the command line.

* The same key may be used multiple times with different values and results
matching any of the values will be returned. This can be useful to retrieve
data for multiple cell types or transcription factors, for example.

* An excellent tutorial on using the API and navigating the JSON data is
available at: https://www.encodeproject.org/help/rest-api/


EXAMPLES

* Find all experiments that used the GAIIx protocol from Michael Snyder's
lab and print results as a data table:

search_encode.pl \"*\" \"&documents.attachment.download=ChIP-Seq_protocol_Snyder_lab_GAIIx.pdf\"

* Same as above, but only for experiments performed on GM12878 cells:

search_encode.pl \"GM12878\" \"&documents.attachment.download=ChIP-Seq_protocol_Snyder_lab_GAIIx.pdf\"

* Same as previous, but download all peak annotations in bigBed format:

search_encode.pl \"GM12878\" \"&documents.attachment.download=ChIP-Seq_protocol_Snyder_lab_GAIIx.pdf\" --download --output-type \"peaks\" --file-format \"bigBed\"


CREDITS AND LICENSE:

Copyright (C) 2016, Adam Diehl

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

Any questions/comments regarding this program may be directed to Adam Diehl:
adadiehl\@umich.edu

Originally published in \"Deciphering ENCODE\". If you use this tool in your
research, please cite:

Diehl AD and Boyle AP (2016) Deciphering ENCODE.
Trends in Genetics. (rest of reference here...)             

\n";

my $search_str = $ARGV[0];
my $params = $ARGV[1];

my $help = 0;
my $download = 0;
my $output_type_str;
my $file_format_str;
my $file_format_type_str;
my $download_path = "";
my $out_root = "";
my $save_json = 0;
my $rec_type = "experiment";
my $no_header = 0;
my $count_only = 0;
my $by_biosample = 0;
my $check_exists = 0;

GetOptions (
    "help" => \$help,
    "download" => \$download,
    "output-type=s" => \$output_type_str,
    "file-format=s" => \$file_format_str,
    "file-format-type=s" => \$file_format_type_str,
    "download-path=s" => \$download_path,
    "out-root=s" => \$out_root,
    "save-json" => \$save_json,
    "rec-type=s" => \$rec_type,
    "no-header" => \$no_header,
    "count-only" => \$count_only,
    "by-biosample" => \$by_biosample,
    "check-exists" => \$check_exists
    );

# Check for proper usage and help option and exit with usage message as needed.
if ($help || $#ARGV+1 < 2) {
    die "$usage\n";
}

# Check for other options and do some sanity checks...
if (defined($output_type_str) && !$download) {
    die "\n--output-type only works with --download. Try --help.\n";
}
if (defined($file_format_type_str) && !defined($file_format_str)) {
    die "\n--file-format-type requires --file-format. Try --help.\n";
}
if ($download_path ne "" && !$download) {
    die "\n--download-path requires --download. Try --help\n";
}
if ($download && !defined($output_type_str)) {
    print STDERR "\nWarning: --download will retrieve all accepted files associated with search results. If this is not what you want, use --file-type to specify which type(s) you would like to download. See --help.\n\n";
}
if ($rec_type ne "experiment") {
    print STDERR "\nWarning: --rec_type other than \"experiment\" has not been well tested and may produces unpredictable results!\n";
}
if ($count_only && $download) {
    print STDERR "\nWarning: --count-only overrides --download. No data will be retrieved! (see --help if this is not what you want)\n";
}

# Check the download path for a trailing slash and add one if needed
if ($download_path ne "") {
    if ($download_path !~ m/\/$/) {
	$download_path .= '/';
    }
}

# If file types have been specified, process the string(s).
my @output_types;
if (defined($output_type_str)) {
    @output_types = split /,/, $output_type_str;
}

my @file_formats;
if (defined($file_format_str)) {
    @file_formats = split /,/, $file_format_str;
    if ($#file_formats != $#output_types) {
        die "\n--file-format and --output-type must have the same number of fields!\n";
    }
}

my @file_format_types;
if (defined($file_format_type_str)) {
    @file_format_types = split /,/, $file_format_type_str;
    if ($#file_format_types != $#output_types) {
        die "\n--file-format-type and --output-type must have the same number of fields!\n";
    }
}

# Set up the virtual browser
my $mech = WWW::Mechanize->new(
    ssl_opts => {
        verify_hostname => 0,
        # Quick and dirty hack to avoid errors about missing SSL certificates.
    },
    );
# Set the history stack depth to 0 -- prevents memory usage from getting out of
# hand for large queries.
$mech->stack_depth( 0 );

####################
# Stage 1: Build the query URL and run the primary query against the ENCODE
# Portal.

my $URL;

# Handle biosample-based queries with a preliminary query to get the
# biosample term name based on the search term.
my $biosample;
if ($by_biosample) {
    print STDERR "\nSearching ENCODE for a biosample matching $search_str...\n";
    $biosample = &get_biosample($mech, $search_str);
    if (!defined($biosample)) {
	die "Cannot find a biosample matching $search_str!\n";
    }
    $search_str = "*";
    $biosample = uri_escape($biosample);
} else {
    # Escape special characters in the search string
    $search_str = uri_escape($search_str);
}

# Build the query URL from the command line args and parameters
$URL = 'http://www.encodeproject.org/search/?searchTerm=';
$URL .= $search_str;
$URL .= "&type=";
$URL .= $rec_type;
$URL .= $params;

if (defined($biosample)) {
    $URL .= "&biosample_term_name=";
    $URL .= $biosample;
}

# &limit=all: Return all results, not just the first 25
# &frame=object: Return all non-null fields within the JSON data for results
# &format=json: Return search data in JSON format
$URL .= '&limit=all&frame=object&format=json';

print STDERR "Query URL: $URL\n";

# Retrieve the JSON data from the URL
my $json = &get_json($mech, $URL);

# Print status and result count to the terminal
print STDERR "${$json}{notification}: ${$json}{total} results found.\n\n";

if ($count_only) {
    print "${$json}{total}\n";
    exit 0;
}

# Catch requests that returned an error status from the Portal
if ( ${$json}{error_status} ) {
    exit 1;
}

#####################
# Stage Two: Find the files we need within the search results.
# Individual search results are within the embedded array @graph.

my @downloads;  # To hold pointers to the files we will download
my @metadata;   # To hold metadata for the files we will download
my $n_files = 0;
foreach my $row (@{${$json}{'@graph'}}) {

    # Each row of the array contains a hash reference to a search result.
    # Make a copy of the hash for convenience.
    my %result = %{$row};

    if ($download) {
	# If we are downloading data files, use a file-centric process and
	# metadata format.
	
	my @files = @{$result{files}};
	foreach my $file (@files) {
	    
	    # Because metadata for individual files is stored in separate
	    # records, retrieve these as separate queries against the
	    # database.
	    my $url = 'http://www.encodeproject.org' . $file . '?format=json';
	    
	    # Get the JSON from the url
	    my $file_json = &get_json($mech, $url);
	    
	    # Examine the JSON to see if the file matches our criteria
	    my $use_rec = 1; # Download all files by default
	    for (my $i = 0; $i <= $#output_types ; $i++) {
		
		# If output_type does not match, reject the file
		if (@output_types) {
		    if (${$file_json}{output_type} ne $output_types[$i]) {
			$use_rec = 0;
		    }
		}
		
		# If file_format does not match, reject the file
		if (@file_formats) {
		    if (${$file_json}{file_format} ne $file_formats[$i]) {
			$use_rec = 0;
		    }
		}
		
		# If file_format_type does not match, reject the file
		if (@file_format_types) {
		    if (${$file_json}{file_format_type} 
			ne $file_format_types[$i]) {
			$use_rec = 0;
		    }
		}
	    }
	    
	    if ($use_rec) {
		# Store a pointer to the file_json in our array
		push @downloads, $file_json;
		
		# Build a row for the metadata table
		my $controls_str = join ",", &nopaths($result{possible_controls});
		my $documents_str = join ",", &nopaths($result{documents});
		
		my @row = (&nopath(${$file_json}{href}),
			   ${$file_json}{accession}, ${$file_json}{output_type},
			   ${${$file_json}{replicate}}{biological_replicate_number},
			   ${${$file_json}{replicate}}{technical_replicate_number},
			   $result{dataset_type}, $result{biosample_term_name},
			   $result{biosample_type}, $result{assay_term_name},
			   &nopath($result{target}), $result{status},
			   $result{date_released}, &nopath($result{lab}),
			   $result{accession}, $controls_str, $documents_str);
		push @metadata, \@row;
	    } else {
		# Should  not be necessary, but just to be sure there's no json
		# hanging around for files we're not using.
		undef($file_json);
	    }
	}
	
    } else { # if (!$download)
	# Prepare a row for the tabular data...
	my $files_str = join ",", &nopaths($result{files});
	my $controls_str = join ",", &nopaths($result{possible_controls});
	my $documents_str = join ",", &nopaths($result{documents});
	
	my @row = ($result{accession}, $result{dataset_type},
		   $result{biosample_term_name}, $result{biosample_type},
		   $result{assay_term_name}, &nopath($result{target}),
		   $result{status}, $result{date_released},
		   &nopath($result{lab}), $files_str, $controls_str,
		   $documents_str);
	push @metadata, \@row;
    }
}

#######################
# Stage 3: Download the data and metadata. Optionally save the file json.

# Number of files/records
my $n_results = $#metadata+1;

# Set up the metadata file handle
my $DATA;
my $outfile = $download_path . $out_root . '.metadata';
# Make sure file name does not start with a . (i.e., no path or root
# were supplied)
$outfile =~ s/^\.//;
open $DATA, '>', $outfile;

# Prepare and print the header
my @header;
if ($download) {
    # File-centric header
    @header = ("file", "accession", "output_type", "biological_replicate",
	       "technical_replicate", "dataset_type", "biosample_term_name",
	       "biosample_type", "assay_term_name", "target", "status",
	       "date_released", "lab", "parent accession", "possible_controls",
	       "documents");
} else {
    # Experiment-centric header
    @header = ("accession", "dataset_type", "biosample_term_name",
	       "biosample_type", "assay_term_name", "target", "status",
	       "date_released", "lab", "files", "possible_controls",
	       "documents");
}

unless ($no_header) {
    &print_array(\@header, "\t", $DATA);
}

# Download the files
if ($download) {
    print STDERR "Downloading $n_results files from ${$json}{total} records...\n";
}
foreach my $file_json (@downloads) {
    &download_file($mech, $file_json, $download_path, $out_root, $check_exists);
    if ($save_json) {
	&save_json($file_json, $download_path, $out_root);
    }
}

# Print the metadata
print STDERR "Writing $n_results rows of metadata to \"$outfile\"...\n";
foreach my $row (@metadata) {
    # Check for any undefined values
    for (my $i = 0; $i <= $#{$row}; $i++) {
	if (!defined(${$row}[$i])) {
	    ${$row}[$i] = '.';
	}
    }
    &print_array($row, "\t", $DATA);
}

close $DATA;

print STDERR "Done!\n";

######################
# Subroutines

sub get_json {
    # Retrieve JSON data from a URL and return it as a data structure.
    my $mech = $_[0];
    my $url = $_[1];

    my $status = eval {
	$mech->get($url);
	1
    };

    my $content;
    if (!$status) {
	# For some reason, the portal sometimes returns an error when there
	# are no results. In these cases, use a dummy json to notify the user.
	$content = '{ "notification": "ENCODE Portal returned error status: no results or bad request. Please check your query for errors!", "total": 0, "error_status": 1 }';
    } else {
	$content = $mech->content;
    }

    my $json = decode_json($content);
    return $json;
}

sub save_json {
    # Save the JSON data for a file we have downloaded.
    my $json = $_[0];
    my $download_path = $_[1];
    my $out_root = $_[2];

    my $outfile = $download_path . $out_root . '.' . ${$json}{accession} . '.json';
    $outfile =~ s/^\.//;
    open my $OUT, '>', $outfile;
    print $OUT to_json($json, {pretty=>1});
    close $OUT;
}

sub download_file {
    # Given a file record, download the file from the ENCODE repository and
    # verify the MD5 checksum.
    my $mech = $_[0];
    my $json = $_[1];
    my $download_path = $_[2];
    my $out_root = $_[3];
    my $check_exists = $_[4];

    my $url = "https://www.encodeproject.org" . ${$json}{href};
    print STDERR "Found a matching record at $url. Retrieving data...\n";
    $mech->get($url);
    
    # Make sure we got the file we were expecting by verifying the md5 checksum
    print STDERR "\tVerifying Checksum...\n";
    my $checksum = md5_hex($mech->content);
    if ($checksum ne ${$json}{md5sum}) {
	print STDERR "\tERROR: Checksums do not match. Skipping file!\n";
    } else {
	# Checksums match. Save file to the specified
	# path and file name.

        # This leaves off the .gz in names of zipped files!
	#my $outfile = $download_path . $out_root . '.' . ${$json}{accession} . '.'
	#    . ${$json}{file_format};

	my @file_parts = split /\//, ${$json}{href};

        my $outfile = $download_path . $out_root . '.' . $file_parts[$#file_parts];

	if ($check_exists && -f $outfile) {
	    # See if file already exists and move on if found
	    print STDERR "\tFile exists: $outfile. Moving on...\n";
	    return 1;
	}

	$outfile =~ s/^\.//;
	print STDERR "\tSaving file to $outfile...\n";
	$mech->save_content($outfile);
    }    
}

sub print_array {
    # A generic function to print an array to a file handle as a string with
    # the supplied delimiting.
    my $array = $_[0];
    my $delim = $_[1];
    my $fh = $_[2];

    my $out_str = join $delim, @{$array};
    print $fh "$out_str\n";
}

sub nopaths {
    # A generic function to strip the path from file or directory names stored
    # in an array.
    my @array = @{$_[0]};

    my @out;
    if ($#array < 0) {
	push @out, ".";
    } else {
	foreach my $str (@array) {
	    my $s = &nopath($str);
	    push @out, $s;
	}
    }
    return @out;
}

sub nopath {
    # Strip the path from a file or directory name.
    my $str = $_[0];
    if (!defined($str)) {
	return ".";
    }
    $str =~ s/\/$//;
    $str =~ s/\/\S+\///;
    return $str;
}

sub get_biosample {
    my ($mech, $search_str) = @_;

    my $URL = 'http://www.encodeproject.org/search/?searchTerm=';
    $URL .= $search_str;
    $URL .= "&type=biosample";
    $URL .= '&limit=all&frame=object&format=json';
    
#    print STDERR "$URL\n";

    my $json = &get_json($mech, $URL);

    if ( ${$json}{error_status} ) {
	return undef;
    }

    my %terms_hash;
    foreach my $row (@{${$json}{'@graph'}}) {
	$terms_hash{${$row}{biosample_term_name}}++;
    }

    if (!%terms_hash) {
	return undef;
    }

    my @terms;
    foreach my $key (keys(%terms_hash)) {
	my @tmp = ($key, $terms_hash{$key});
	push @terms, \@tmp;
    }

    my $biosample;
    if ($#terms > 0) {
	print STDERR "More than one possible biosample found...\n\n";
	for (my $i = 0; $i <= $#terms; $i++) {
	    print STDERR $i+1, ": $terms[$i][0] ($terms[$i][1] occurences)\n";
	}
	print STDERR "\nEnter the number of the term you want to use [1] : ";
	my $idx = <STDIN>;
	if ($idx eq '') {
	    $idx = 1;
	}
	chomp $idx;
	$idx--;

	$biosample = $terms[$idx][0];

    } else {
	$biosample = $terms[0][0];
    }
    
    print STDERR "Using \"$biosample\" as biosample term name.\n\n";
    return $biosample;
}
