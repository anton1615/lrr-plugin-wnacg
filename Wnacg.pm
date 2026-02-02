package LANraragi::Plugin::Download::Wnacg;

use strict;
use warnings;
no warnings 'uninitialized';

use LANraragi::Utils::Logging qw(get_plugin_logger);

sub plugin_info {
    return (
        name         => "Wnacg Downloader",
        type         => "download",
        namespace    => "wnacg",
        author       => "Gemini CLI",
        version      => "4.1",
        description  => "Download from wnacg.com (Standard List Return)",
        url_regex    => 'https?:\/\/(?:www\.)?wnacg\.(?:com|org|net).*(?:aid-|view-)\d+.*'
    );
}

sub provide_url {
    shift;
    my ($lrr_info, %params) = @_;
    my $logger = get_plugin_logger();
    my $url = $lrr_info->{url};

    $logger->info("--- Wnacg Mojo v4.0 Triggered ---");
    
    # Normalize URL
    $url =~ s/photos-slide/photos-index/;
    
    # 使用 LRR 提供的 UserAgent (具備快取與 Session 管理)
    my $ua = $lrr_info->{user_agent};
    $ua->max_redirects(5);

    my $tx = $ua->get($url);
    my $res = $tx->result;

    if ($res->is_success) {
        my $html = $res->body;
        $logger->info("Index page fetched. Size: " . length($html));

        # 策略 1: ZIP 下載
        if ($html =~ m|href="(/download-index-aid-(\d+)\.html)"|i) {
            my $aid = $2;
            my ($base) = $url =~ m|^(https?://[^/]+)|;
            my $dl_page = "$base/download-index-aid-$aid.html";
            
            my $dl_res = $ua->get($dl_page)->result;
            if ($dl_res->is_success) {
                my $dl_html = $dl_res->body;
                if ($dl_html =~ m|href="([^"]+\.zip[^"]*)"|i) {
                    my $zip_url = $1;
                    $zip_url = "https:" . $zip_url if $zip_url =~ m|^//|;
                    $logger->info("SUCCESS: Found ZIP URL: $zip_url");
                    # 遵循官方規格回傳 download_url 列表
                    return ( download_url => $zip_url );
                }
            }
        }

        # 策略 2: 圖片清單
        my @images;
        while ($html =~ m|//[^"']+/data/thumb/([^\s"']+)|gi) {
            my $path = $1;
            push @images, "https://www.wnacg.org/data/f/" . $path;
        }
        
        if (scalar @images > 0) {
            $logger->info("SUCCESS: Found " . scalar @images . " images.");
            # 如果是多圖下載，LRR 核心會處理 url_list
            return ( url_list => \@images );
        }
    } else {
        return ( error => "HTTP " . $res->code );
    }

    return ( error => "No content found on Wnacg." );
}

1;