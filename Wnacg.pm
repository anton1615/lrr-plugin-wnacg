package LANraragi::Plugin::Sideloaded::Wnacg;

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
        version      => "2.0",
        description  => "Download from wnacg.com (Improved Referer & ZIP support)",
        url_regex    => 'https?:\/\/(?:www\.)?wnacg\.(?:com|org|net)\/(?:photos-(?:index|slide)-aid-|view-)\d+.*',
        parameters   => []
    );
}

sub provide_url {
    shift;
    my $lrr_info = shift;
    my $logger = get_logger( "Wnacg", "plugins" );
    my $url = $lrr_info->{url};

    $url =~ s/photos-slide/photos-index/;
    $logger->info("Target URL: $url");

    # 加入 Referer 避開防盜鏈
    my $html = get_html($url);
    if (!$html) { return ( error => "Failed to fetch index page." ); }

    # 尋找下載頁面
    if ($html =~ /href="(\/download-index-aid-\d+\.html)"/i) {
        my $dl_page = "https://www.wnacg.com" . $1;
        my $dl_html = get_html($dl_page);
        if ($dl_html && $dl_html =~ /href="([^"]+\.zip[^"]*)"/i) {
            my $zip_url = $1;
            $zip_url = "https:" . $zip_url if $zip_url =~ /^\/\//;
            $logger->info("Found ZIP: $zip_url");
            return ( url => $zip_url, title => "Wnacg ZIP Archive" );
        }
    }

    # 備援：圖片清單
    my @images;
    while ($html =~ /\/\/www\.wnacg\.(?:com|org|net)\/data\/t\/([^\s"']+)/gi) {
        my $p = $1; $p =~ s/\/t\//\/f\//;
        push @images, "https://www.wnacg.org/data/f/" . $p;
    }
    @images = grep { defined } @images;
    
    if (scalar @images > 0) {
        return ( url_list => \@images, title => "Wnacg Gallery" );
    }

    return ( error => "Nothing found." );
}

1;
