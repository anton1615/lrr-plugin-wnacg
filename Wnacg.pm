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
        version      => "3.0",
        description  => "Download from wnacg.com (Debug Enhanced)",
        url_regex    => 'https?:\/\/(?:www\.)?wnacg\.(?:com|org|net)\/(?:photos-(?:index|slide)-aid-|view-)\d+.*',
        parameters   => []
    );
}

sub provide_url {
    my ($self, $lrr_info, @params) = @_;
    my $logger = get_logger("Wnacg", "plugins");
    my $url = $lrr_info->{url};

    $logger->info("--- Wnacg Download Start ---");
    $logger->info("Original URL: $url");

    # Normalize
    $url =~ s/photos-slide/photos-index/;
    $logger->info("Target URL: $url");

    # 模擬瀏覽器 User-Agent
    my $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

    # 使用 LRR 內建 get_html，嘗試手動解析下載頁面
    $logger->info("Fetching index page...");
    my $html = LANraragi::Utils::Generic::get_html($url, $ua);
    
    if (!$html || length($html) < 100) {
        $logger->error("Failed to fetch index page or page too small. HTML Length: " . (defined $html ? length($html) : "UNDEFINED"));
        return ( error => "Could not reach Wnacg or blocked by Cloudflare." );
    }

    # 策略 1: ZIP 下載 (最推薦)
    if ($html =~ /href="(\/download-index-aid-(\d+)\.html)"/i) {
        my $aid = $2;
        my $dl_page = "https://www.wnacg.com/download-index-aid-$aid.html";
        $logger->info("Found download page: $dl_page");
        
        my $dl_html = LANraragi::Utils::Generic::get_html($dl_page, $ua);
        if ($dl_html && $dl_html =~ /href="([^"]+\.zip[^"]*)"/i) {
            my $zip_url = $1;
            $zip_url = "https:" . $zip_url if $zip_url =~ /^\/\//;
            $logger->info("SUCCESS: Found direct ZIP URL: $zip_url");
            return ( url => $zip_url, title => "Wnacg ZIP $aid" );
        } else {
            $logger->warn("Download page found but no ZIP link extracted.");
        }
    }

    # 策略 2: 圖片清單
    $logger->info("Fallback: Searching for image thumbnails...");
    my @images;
    while ($html =~ /\/\/www\.wnacg\.(?:com|org|net)\/data\/t\/([^\s"']+)/gi) {
        my $p = $1; $p =~ s/\/t\//\/f\//;
        push @images, "https://www.wnacg.org/data/f/" . $p;
    }
    
    if (scalar @images > 0) {
        $logger->info("SUCCESS: Extracted " . scalar @images . " images.");
        return ( url_list => \@images, title => "Wnacg Archive" );
    }

    $logger->error("FAILED: No images or ZIP found. HTML snippet: " . substr($html, 0, 200));
    return ( error => "No content found on Wnacg. Check server logs." );
}

1;
