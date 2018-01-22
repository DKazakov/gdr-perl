#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use LWP::UserAgent;
use JSON::XS;
use HTTP::Request;
use List::Util qw/min max/;
use MIME::Base64 qw/encode_base64/;
use GD::Graph::mixed;
use Term::ReadKey;
use Math::Round;
use Getopt::Long;

my $graph = GD::Graph::mixed->new(1300, 500);

$graph->set(
    default_type => 'lines',
    transparent => 0,
    bgclr => 'white',
    x_label_skip => 10,
);

my ($x, $y) = ();
my $base = 19.6;
my $limit = 40;
my $mul = 0.1;
for my $step (0..($limit - $base)/$mul) {
    my $price = $base + $step * $mul;
    my $gdr = (7100/4) * ($price - 19.6);
    push @$x, $price;
    push @$y, $gdr * 60;
}


my $data = [
    $x,
    $y,
];

my $gd = $graph->plot($data);
my $base64 = encode_base64($gd->gif);
printf "\033]1337;File=name=%s;size=%i;inline=1:%s\a\n", encode_base64('file.gif'), length $base64, $base64;
