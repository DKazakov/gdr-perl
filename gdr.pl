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

use constant VALUE => 1775;

use Data::Dumper qw/Dumper/;

$| = 1;

my $fixedPrice = 0;
my $type = "simple";
my @size = GetTerminalSize();
my $stepCount = 1;
my $timeout = 10;
my $showHelp = 0;
my $windowHeight = 0;

GetOptions(
    "timeout=i", \$timeout,
    "type=s", \$type,
    "price=f", \$fixedPrice,
    "height=i", \$windowHeight,
    "help", \$showHelp
);

showHelp() and exit(0) if $showHelp;

print "\033[2J\033[0;0H";

do {
    my ($prices, $values, $currents) = map { request($_->[0], $_->[1], $_->[2])->{'d'} } (
        ['POST', 'http://charts.londonstockexchange.com/WebCharts/services/ChartWService.asmx/GetPrices', '{"request":{"SampleTime":"1d","TimeFrame":"1m","RequestedDataSetType":"ohlc","ChartPriceType":"price","Key":"MAIL.LID","OffSet":-60,"FromDate":null,"ToDate":null,"UseDelay":true,"KeyType":"Topic","KeyType2":"Topic","Language":"en"}}'],
        ['POST', 'http://charts.londonstockexchange.com/WebCharts/services/ChartWService.asmx/GetCvals', '{"request":{"SampleTime":"1d","TimeFrame":"1m","RequestedDataSetType":"cvals","ChartPriceType":"price","Key":"MAIL.LID","OffSet":-60,"UseDelay":true,"KeyType":"Topic","KeyType2":"Topic","Language":"en"}}'],
        ['POST', 'http://charts.londonstockexchange.com/WebCharts/services/ChartWService.asmx/GetPrices', '{"request":{"SampleTime":"1mm","TimeFrame":"1d","RequestedDataSetType":"ohlc","ChartPriceType":"price","Key":"MAIL.LID","OffSet":-60,"FromDate":null,"ToDate":null,"UseDelay":true,"KeyType":"Topic","KeyType2":"Topic","Language":"en"}}']
    );
    my $dollar = request('GET', 'https://api.fixer.io/latest?base=USD&symbols=RUB')->{'rates'}->{'RUB'};
#   Raiffeisen, now broken
#    my $dollar = request('GET', 'https://online.raiffeisen.ru/rest/exchange/rate/info?currencyDest=RUB&currencySource=USD&scope=4')->{'buyRate'};
    printf "\r%s\033[0;0H", ' ' x $size[0];
    my ($padding, $height) = printForecast($dollar, $currents->[$#$currents]->[1]);
    printf "\r\033[0;%iH", $padding + 1;
    if ($ENV{'TERM_PROGRAM'} eq 'iTerm.app') {
        drawGraph($padding, $prices, $values, [map { $currents->[$#$currents]->[1] } 0..$#$prices ]);
    } else {
        printf "\timages not supported\n";
        printf "\r\033[%i;%iH", $height, $padding + 1;
    }
    printTextResult($prices, $values, $currents, $dollar, $fixedPrice);
    if ($type eq "daemon") {
        my $division = length $timeout;
        for (my $to = 1; $to < $timeout; $to++) {
            printf "\r%s%s | countdown: %${division}i second", ' ' x $to, '.' x ($timeout - $to), $timeout - $to;
            sleep 1;
        }
        $stepCount = 1;
    }
} while ($type eq "daemon");

exit();

sub request {
    my ($method, $url, $content) = @_;

    printf "\r%s\tload %s ", '.' x $stepCount++, $url;

    my $ua = LWP::UserAgent->new(
        ssl_opts => {
            verify_hostname => 0
        },
        timeout => 10
    );
    my $request = HTTP::Request->new($method => $url);
    if ($content) {
        $request->content_type('application/json');
        $request->content($content);
    }

    my $response = $ua->request($request);
    if ($response->code != 200) {
        printf "\e[1m\e[31mbad response!\e[0m %s\n", $response->code;
        printf $response->content;
        exit(1);
    }
    return JSON::XS->new->decode($response->content);
}

sub printTextResult {
    my ($prices, $values, $currents, $dollar, $fixedPrice) = @_;

    my $current = $currents->[$#$currents]->[1];
    my @prices = map {$_->[1]} reverse @$prices;
    my @values = map {$_->[1] || 0} reverse @$values;
    my $gdr = gdr([@prices], [@values]);
    my $fgdr = gdr([$current, @prices], [$values[$#values], @values]);
    my $dollarPrice = int($gdr * ($fixedPrice || $current));
    my $roublePrice = int($dollar * $dollarPrice);
    my $froublePrice = int($fgdr * $current * $dollar);
    $dollarPrice =~ s/(?<=\d)(?=(\d{3})+(?!\d))/ /g;
    $roublePrice =~ s/(?<=\d)(?=(\d{3})+(?!\d))/ /g;
    $froublePrice =~ s/(?<=\d)(?=(\d{3})+(?!\d))/ /g;

    binmode STDOUT, ":utf8";
    printf "\r%s", ' ' x $size[0];
    printf "\rСтоимость сейчас: %.2f %s", $current, $current < $prices[0] && "\x{1F621}" || "\x{1F600}";
    printf "\nGDR: %.2f \e[3;0;0m(%s)\e[0m\nОбщая стоимость: %s доллара (%s рублей при курсе %.2f)\n", 
        $gdr, $fixedPrice && sprintf(" (для стоимости %.2f", $fixedPrice) || sprintf("прогноз: %.2f => %s рублей", $fgdr, $froublePrice), $dollarPrice, $roublePrice, $dollar;
}

sub drawGraph {
    my $padding = shift;
    my @ranges = @_;
    my @prices = ();
    my @values = ();
    my @dates = ();
    my @gdrs = ();
    for my $i (0..$#{$ranges[0]}) {
        my $price = $ranges[0]->[$i]->[1];
        my $value = $ranges[1]->[$i]->[1];
        my $date1 = $ranges[0]->[$i]->[0] || 0;
        my $date2 = $ranges[1]->[$i]->[0] || 0;
        if ($date1 > $date2) {
            splice @{$ranges[1]}, $i, 1;
            $value = $ranges[1]->[$i]->[1];
            $date2 = $ranges[1]->[$i]->[0];
        } elsif ($date1 < $date2) {
            splice @{$ranges[0]}, $i, 1;
            $price = $ranges[0]->[$i]->[1];
            $date1 = $ranges[0]->[$i]->[0];
        }
        push @prices, $price || 0;
        push @values, $value || 0;
        push @dates, $date1 / 1000;
        if ($i > 1) {
            my $vlength = $#values;
            push @gdrs, gdr([@prices[$#prices-2..$#prices]], [@values[$#values-2..$#values]]);
        }
    }

    my ($maxp, $minp, $maxv, $minv, $maxg, $ming) = (max(@prices), min(@prices), max(@values), min(@values), max(@gdrs), min(@gdrs));
    my $mul1 = ($maxp - $minp) / ($maxv - $minv);
    my @approximatedValues = map {sprintf "%.2f", $minp + ($_ - $minv) * $mul1 } @values;
    my $mul2 = ($maxp - $minp) / ($maxg - $ming);
    my @approximatedGDRS = map {sprintf "%.2f", $minp + ($_ - $ming) * $mul2 } @gdrs;
    my $graph = GD::Graph::mixed->new(($size[0] - $padding) * 7, int(($windowHeight || ($size[1] - 7)) * 15 / 2));
    my @months = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
    my $data = [
        [map {my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($_);sprintf "%02i %s", $mday, $months[$mon]} @dates],
        [@prices],
        [@approximatedValues],
        $ranges[2],
        [undef, undef, @approximatedGDRS]
    ];

    $graph->set(
        types => ['area', 'linespoints', 'lines', 'lines'],
        dclrs => ['#FF0000', '#00FF00', '#0000FF', '#000000'],
        default_type => 'area',
        transparent => 0,
        bgclr => 'white',
        l_margin => 10,
        b_margin => 10,
        y_max_value => nearest(0.1, max(@approximatedValues, $ranges[2]->[0]) * 1.02),
        y_min_value => nearest(0.1, min(@approximatedValues, $ranges[2]->[0]) * 0.98),
        x_label_skip => 2,
        bar_width => 0.1,
    );
    $graph->set_legend(
        sprintf("price, max: %.2f, min: %.2f, last: %.2f", max(@prices), min(@prices), $prices[$#prices]),
        sprintf("scaled value, max: %i, min: %i", $maxv, $minv),
        sprintf("current price %.2f", $ranges[2]->[0]), ,
        sprintf("scaled GDR's, max: %.2f, min: %.2f, now: %.2f", $maxg, $ming, $gdrs[$#gdrs])
    );
    my $gd = $graph->plot($data);
    my $base64 = encode_base64($gd->gif);
    printf "\033]1337;File=name=%s;size=%i;inline=1:%s\a\n", encode_base64('file.gif'), length $base64, $base64;
}

sub gdr {
    my ($prices, $values) = @_;

    return VALUE - (VALUE * 19.6/(($prices->[0] * $values->[0] + $prices->[1] * $values->[1] + $prices->[2] * $values->[2])/($values->[0] + $values->[1] + $values->[2])));
}

sub printForecast {
    my $course = shift;
    my $current = shift;
    my $k = 1;
    my $val = sub { return (7100/4) * ($_[0] - 19.6) * $k };
    my $col = sub { return $_[0] % 2 && "\e[0m" || "\e[48;05;242m" };
    my $first = 1;
    my $length = 0;
    my $height = 0;
    my $string = '';
    my $currentstr = ' ';

    for (my $price = 27; $price < 37; $price += 0.5) {
        my $value = $val->($price) / 1000;
        my $rvalue = $value * $course / 1000;
        my $color = $rvalue > 1.65 && $first && !($first = 0) && "\e[48;05;196m" || $col->($price * 2);
        if ($currentstr eq ' ' && $price > $current * 0.98) {
            $currentstr = '>';
            $color = "\e[48;05;34m"
        } elsif ($currentstr eq '>') {
            $currentstr = " \0";
        }

        $string = sprintf "%.2f: %.3f (%.3f)", $price, $value, $rvalue;
        $length = max($length, length $string);
        $height += 1;
        printf "%s%s%s\n", $color, $string, $col->(1);
    }
    return ($length, $height);
}

sub showHelp {
    printf <<EOH;
--timeout - set timeout for daemon, default: 10
--type - daemon or simple
--price - set current price (not GDR)
--height - set view height (strings)
--help - show this message and exit
EOH
}
