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
        version      => "3.5",
        description  => "Download from wnacg.com (Modern Mojo::UserAgent)",
        url_regex    => 'https?:\/\/(?:www\.)?wnacg\.(?:com|org|net).*(?:aid-|view-)\d+.*',
        parameters   => []
    );
}

sub provide_url {
    my ($self, $lrr_info, @params) = @_;
    my $logger = get_plugin_logger();
    my $url = $lrr_info->{url};

    $logger->info("--- Wnacg Mojo Triggered ---");
    
    # Normalize URL
    $url =~ s/photos-slide/photos-index/;
    $url =~ s/wnacg\.(org|net)/wnacg.com/;

    my $ua = Mojo::UserAgent->new;
    $ua->transactor->name("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");

    # 獲取主頁
    my $tx = $ua->get($url);
    if (my $res = $tx->success) {
        my $html = $res->body;

        # 策略 1: ZIP 下載
        if ($html =~ /href="(\/download-index-aid-(\d+)\.html)"/i) {
            my $aid = $2;
            my $dl_page = "https://www.wnacg.com/download-index-aid-$aid.html";
            my $dl_tx = $ua->get($dl_page);
            if (my $dl_res = $dl_tx->success) {
                my $dl_html = $dl_res->body;
                if ($dl_html =~ /href="([^"]+\.zip[^"]*)"/i) {
                    my $zip_url = $1;
                    $zip_url = "https:" . $zip_url if $zip_url =~ /^\/\//;
                    $logger->info("SUCCESS: $zip_url");
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
            $logger->info("SUCCESS: Images Found");
            return ( url_list => \@images, title => "Wnacg Archive" );
        }
    } else {
        my $err = $tx->error;
        return ( error => "Mojo error: " . $err->{message} );
    }

    return ( error => "No content found." );
}

1;
