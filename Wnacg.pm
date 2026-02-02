package LANraragi::Plugin::Download::Wnacg;

use strict;
use warnings;

use LANraragi::Utils::Logging qw(get_logger);
use LANraragi::Utils::Generic;

sub plugin_info {
    return (
        name         => "Wnacg Downloader",
        type         => "download",
        namespace    => "wnacg",
        author       => "Gemini CLI",
        version      => "3.1",
        description  => "Download from wnacg.com (Universal URL Support)",
        # 擴大正則範圍，支援 com, org, net 
        url_regex    => 'https?:\/\/(?:www\.)?wnacg\.(?:com|org|net).*(?:aid-|view-)\d+.*',
        parameters   => []
    );
}

sub provide_url {
    my ($self, $lrr_info, @params) = @_;
    my $logger = get_logger("Wnacg", "plugins");
    my $url = $lrr_info->{url};

    $logger->info("--- Wnacg Triggered ---");
    $logger->info("Input URL: $url");

    # Normalize to index
    $url =~ s/photos-slide/photos-index/;
    # Ensure domain matches wnacg.com for internal logic
    $url =~ s/wnacg\.(org|net)/wnacg.com/;

    my $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

    my $html = LANraragi::Utils::Generic::get_html($url, $ua);
    if (!$html) { return ( error => "Empty HTML" ); }

    # ZIP Logic
    if ($html =~ /href="(\/download-index-aid-(\d+)\.html)"/i) {
        my $aid = $2;
        my $dl_page = "https://www.wnacg.com/download-index-aid-$aid.html";
        my $dl_html = LANraragi::Utils::Generic::get_html($dl_page, $ua);
        if ($dl_html && $dl_html =~ /href="([^"]+\.zip[^"]*)"/i) {
            my $zip_url = $1;
            $zip_url = "https:" . $zip_url if $zip_url =~ /^\/\//;
            $logger->info("SUCCESS: $zip_url");
            return ( url => $zip_url, title => "Wnacg ZIP $aid" );
        }
    }

    # Image List Logic
    my @images;
    while ($html =~ /\/\/www\.wnacg\.(?:com|org|net)\/data\/t\/([^\s"']+)/gi) {
        my $p = $1; $p =~ s/\/t\//\/f\//;
        push @images, "https://www.wnacg.com/data/f/" . $p;
    }
    
    if (scalar @images > 0) {
        $logger->info("SUCCESS: Images Found");
        return ( url_list => \@images, title => "Wnacg Archive" );
    }

    return ( error => "Check LRR Logs" );
}

1;