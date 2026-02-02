package LANraragi::Plugin::Download::Wnacg;

use strict;
use warnings;

use LANraragi::Utils::Logging qw(get_logger);
use LANraragi::Utils::Generic qw(get_html);

sub plugin_info {
    return (
        name         => "Wnacg Downloader",
        type         => "download",
        namespace    => "wnacg",
        author       => "Gemini CLI",
        version      => "2.6",
        description  => "Download from wnacg.com (Fixed Package Name)",
        url_regex    => 'https?:\/\/(?:www\.)?wnacg\.(?:com|org|net)\/(?:photos-(?:index|slide)-aid-|view-)\d+.*',
        parameters   => []
    );
}

sub provide_url {
    my ($self, $lrr_info, @params) = @_;
    my $logger = get_logger("Wnacg", "plugins");
    my $url = $lrr_info->{url};

    $url =~ s/photos-slide/photos-index/;
    $logger->info("Target: $url");

    my $html = get_html($url);
    if (!$html) { return ( error => "No HTML content received from Wnacg." ); }

    # 策略 1: 尋找直接下載 ZIP 頁面
    if ($html =~ /href="(\/download-index-aid-\d+\.html)"/i) {
        my $dl_page = "https://www.wnacg.org" . $1;
        my $dl_html = get_html($dl_page);
        if ($dl_html && $dl_html =~ /href="([^"]+\.zip[^"]*)"/i) {
            my $zip_url = $1;
            $zip_url = "https:" . $zip_url if $zip_url =~ /^\/\//;
            $logger->info("Found direct ZIP URL: $zip_url");
            return ( url => $zip_url, title => "Wnacg ZIP" );
        }
    }

    # 策略 2: 備援抓取圖片清單
    my @images;
    while ($html =~ /\/\/www\.wnacg\.(?:com|org|net)\/data\/t\/([^\s"']+)/gi) {
        my $p = $1; $p =~ s/\/t\//\/f\//;
        push @images, "https://www.wnacg.org/data/f/" . $p;
    }
    
    if (scalar @images > 0) {
        $logger->info("Falling back to image list: " . scalar @images . " images.");
        return ( url_list => \@images, title => "Wnacg Archive" );
    }

    return ( error => "No images or ZIP found on Wnacg." );
}

1;