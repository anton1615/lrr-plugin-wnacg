package LANraragi::Plugin::Download::Wnacg;

use strict;
use warnings;

use Mojo::UserAgent;
use LANraragi::Utils::Logging qw(get_plugin_logger);

sub plugin_info {
    return (
        name         => "Wnacg Downloader",
        type         => "download",
        namespace    => "wnacg",
        author       => "Gemini CLI",
        version      => "3.8",
        description  => "Download from wnacg.com (Regex Fixed)",
        url_regex    => 'https?:\/\/(?:www\.)?wnacg\.(?:com|org|net).*(?:aid-|view-)\d+.*',
        parameters   => []
    );
}

sub provide_url {
    my ($self, $lrr_info, @params) = @_;
    my $logger = get_plugin_logger();
    my $url = $lrr_info->{url};

    $logger->info("--- Wnacg Mojo v3.8 ---");
    
    # Normalize URL
    $url =~ s/photos-slide/photos-index/;
    
    my $ua = Mojo::UserAgent->new;
    $ua->transactor->name("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
    $ua->max_redirects(5);

    my $tx = $ua->get($url);
    my $res = $tx->result;

    if ($res->is_success) {
        my $html = $res->body;
        $logger->info("Index page fetched. Bytes: " . length($html));

        # 策略 1: ZIP 下載 (使用 | 定界符避免斜槓轉義問題)
        if ($html =~ m|href="(/download-index-aid-(\d+)\.html)"|i) {
            my $aid = $2;
            my $base_url = $url;
            $base_url =~ s|/photos-index.*||; # 取得域名根目錄
            
            my $dl_page = "$base_url/download-index-aid-$aid.html";
            $logger->info("Found download page: $dl_page");
            
            my $dl_res = $ua->get($dl_page)->result;
            if ($dl_res->is_success) {
                my $dl_html = $dl_res->body;
                if ($dl_html =~ m|href="([^"]+\.zip[^"]*)"|i) {
                    my $zip_url = $1;
                    $zip_url = "https:" . $zip_url if $zip_url =~ m|^//|;
                    $logger->info("SUCCESS: ZIP URL: $zip_url");
                    return ( url => $zip_url, title => "Wnacg ZIP $aid" );
                }
            }
        }

        # 策略 2: 圖片清單
        my @images;
        # 匹配 data/thumb/ 並轉為 data/f/ (原圖)
        while ($html =~ m|//[^"']+/data/thumb/([^\s"']+)|gi) {
            my $path = $1;
            # Wnacg CDN 可能是 t1.qy0.ru 等
            push @images, "https://www.wnacg.org/data/f/" . $path;
        }
        
        if (scalar @images > 0) {
            $logger->info("SUCCESS: Found " . scalar @images . " images.");
            return ( url_list => \@images, title => "Wnacg Archive" );
        }
    } else {
        $logger->error("HTTP Error: " . $res->code);
    }

    return ( error => "No content found. Please check logs." );
}

1;