package LANraragi::Plugin::Download::Wnacg;

use strict;
use warnings;

use LANraragi::Utils::Logging qw(get_logger);
use LANraragi::Utils::Generic qw(get_html);

# Plugin Metadata
sub plugin_info {
    return (
        name         => "Wnacg Downloader",
        type         => "download",
        namespace    => "wnacg",
        author       => "Gemini CLI",
        version      => "1.8",
        description  => "Download from wnacg.com (Direct ZIP or Image List)",
        url_regex    => 'https?:\/\/(?:www\.)?wnacg\.(?:com|org|net)\/(?:photos-(?:index|slide)-aid-|view-)\d+.*',
        parameters   => []
    );
}

# Download Logic
sub provide_url {
    shift; # Drop class name
    my $lrr_info = shift;
    my $logger = get_logger( "Wnacg", "plugins" );
    my $url = $lrr_info->{url};

    # Normalize URL: slide -> index
    $url =~ s/photos-slide/photos-index/;

    $logger->info("Processing Wnacg URL: $url");

    my $html = get_html($url);
    if (!$html) {
        return ( error => "Could not fetch Wnacg page." );
    }

    # 策略 1: 尋找直接下載 ZIP 的頁面
    # Wnacg 的下載連結通常在 <a class="btn" href="/download-index-aid-xxxx.html">
    if ($html =~ /href="(\/download-index-aid-\d+\.html)"/i) {
        my $download_page_url = "https://www.wnacg.org" . $1;
        $logger->info("Found download page: $download_page_url");
        
        my $dl_html = get_html($download_page_url);
        if ($dl_html && $dl_html =~ /href="([^"]+\.zip[^"]*)"/i) {
            my $zip_url = $1;
            if ($zip_url =~ /^\/\//) { $zip_url = "https:" . $zip_url; }
            $logger->info("Found direct ZIP URL: $zip_url");
            return (
                url => $zip_url,
                title => "Wnacg Archive (ZIP)"
            );
        }
    }

    # 策略 2: 備援 - 抓取圖片清單
    my @images;
    while ($html =~ /\/\/www\.wnacg\.(?:com|org|net)\/data\/t\/([^\s"']+)/gi) {
        my $path = $1;
        $path =~ s/\/t\//\/f\//; # thumb to full
        push @images, "https://www.wnacg.org/data/f/" . $path;
    }

    my %seen;
    @images = grep { !$seen{$_}++ } @images;

    if (scalar @images > 0) {
        $logger->info("Falling back to image list: " . scalar @images . " images.");
        return (
            url_list => \@images,
            title    => "Wnacg Archive"
        );
    }

    return ( error => "No content found on Wnacg." );
}

1;
