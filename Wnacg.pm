package LANraragi::Plugin::Download::Wnacg;

use strict;
use warnings;

use LANraragi::Utils::Logging qw(get_logger);
use LANraragi::Utils::Generic; # 不使用匯入，改用全名調用

sub plugin_info {
    return (
        name         => "Wnacg Downloader",
        type         => "download",
        namespace    => "wnacg",
        author       => "Gemini CLI",
        version      => "2.7",
        description  => "Download from wnacg.com (Fixed Imports)",
        url_regex    => 'https?:\/\/(?:www\.)?wnacg\.(?:com|org|net)\/(?:photos-(?:index|slide)-aid-|view-)\d+.*',
        parameters   => []
    );
}

sub provide_url {
    my ($self, $lrr_info, @params) = @_;
    my $logger = get_logger("Wnacg", "plugins");
    my $url = $lrr_info->{url};

    $url =~ s/photos-slide/photos-index/;
    $logger->info("Processing Wnacg URL: $url");

    # 改用全名調用以避免匯入錯誤
    my $html = LANraragi::Utils::Generic::get_html($url);
    if (!$html) { return ( error => "Could not fetch index page." ); }

    if ($html =~ /href="(\/download-index-aid-\d+\.html)"/i) {
        my $dl_page = "https://www.wnacg.org" . $1;
        my $dl_html = LANraragi::Utils::Generic::get_html($dl_page);
        if ($dl_html && $dl_html =~ /href="([^"]+\.zip[^"]*)"/i) {
            my $zip_url = $1;
            $zip_url = "https:" . $zip_url if $zip_url =~ /^\/\//;
            return ( url => $zip_url, title => "Wnacg ZIP" );
        }
    }

    my @images;
    while ($html =~ /\/\/www\.wnacg\.(?:com|org|net)\/data\/t\/([^\s"']+)/gi) {
        my $p = $1; $p =~ s/\/t\//\/f\//;
        push @images, "https://www.wnacg.org/data/f/" . $p;
    }
    
    return ( url_list => \@images, title => "Wnacg Archive" ) if scalar @images > 0;
    return ( error => "No images or ZIP found." );
}

1;
