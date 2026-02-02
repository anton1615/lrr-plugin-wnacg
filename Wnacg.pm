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
        version      => "3.6",
        description  => "Download from wnacg.com (Fixed Mojo success method)",
        url_regex    => 'https?:\/\/(?:www\.)?wnacg\.(?:com|org|net).*(?:aid-|view-)\d+.*',
        parameters   => []
    );
}

sub provide_url {
    my ($self, $lrr_info, @params) = @_;
    my $logger = get_plugin_logger();
    my $url = $lrr_info->{url};

    $logger->info("--- Wnacg Mojo v3.6 Triggered ---");
    
    # Normalize URL
    $url =~ s/photos-slide/photos-index/;
    # Wnacg 台灣區常導向 .org，這裡統一處理
    $url =~ s/wnacg\.(com|net)/wnacg.org/;

    my $ua = Mojo::UserAgent->new;
    $ua->transactor->name("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
    $ua->max_redirects(3); # 處理可能的重定向

    # 獲取主頁
    my $tx = $ua->get($url);
    my $res = $tx->result;

    if ($res->is_success) {
        my $html = $res->body;
        $logger->info("Fetched index page successfully.");

        # 策略 1: ZIP 下載
        if ($html =~ /href="(\/download-index-aid-(\d+)\.html)"/i) {
            my $aid = $2;
            my $dl_page = "https://www.wnacg.org/download-index-aid-$aid.html";
            my $dl_res = $ua->get($dl_page)->result;
            
            if ($dl_res->is_success) {
                my $dl_html = $dl_res->body;
                if ($dl_html =~ /href="([^"]+\.zip[^"]*)"/i) {
                    my $zip_url = $1;
                    $zip_url = "https:" . $zip_url if $zip_url =~ /^\/\//;
                    $logger->info("SUCCESS: Found direct ZIP URL: $zip_url");
                    return ( url => $zip_url, title => "Wnacg ZIP $aid" );
                }
            }
        }

        # 策略 2: 圖片清單
        my @images;
        while ($html =~ /\/\/www\.wnacg\.(?:com|org|net)\/data\/t\/([^\s"']+)/gi) {
            my $p = $1; $p =~ s/\/t\//\/f\//;
            push @images, "https://www.wnacg.org/data/f/" . $p;
        }
        
        if (scalar @images > 0) {
            $logger->info("SUCCESS: Extracted " . scalar @images . " images.");
            return ( url_list => \@images, title => "Wnacg Archive" );
        }
    } else {
        my $err = $tx->error;
        $logger->error("Mojo error: " . $err->{message});
        return ( error => "Mojo error: " . $err->{message} );
    }

    return ( error => "No content found on Wnacg." );
}

1;