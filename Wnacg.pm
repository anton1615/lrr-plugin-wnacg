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
        version      => "3.7",
        description  => "Download from wnacg.com (HTML Debug Mode)",
        url_regex    => 'https?:\/\/(?:www\.)?wnacg\.(?:com|org|net).*(?:aid-|view-)\d+.*',
        parameters   => []
    );
}

sub provide_url {
    my ($self, $lrr_info, @params) = @_;
    my $logger = get_plugin_logger();
    my $url = $lrr_info->{url};

    $logger->info("--- Wnacg Debug v3.7 ---");
    $url =~ s/photos-slide/photos-index/;
    # 嘗試不強改域名，保持原始輸入
    $logger->info("Fetching: $url");

    my $ua = Mojo::UserAgent->new;
    $ua->transactor->name("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
    $ua->max_redirects(5);

    my $tx = $ua->get($url);
    my $res = $tx->result;

    if ($res->is_success) {
        my $html = $res->body;
        $logger->info("HTML received (Length: " . length($html) . ")");

        # 輸出部分 HTML 到日誌以供分析
        $logger->info("HTML Snippet: " . substr($html, 0, 500));

        # 策略 1: ZIP
        if ($html =~ /href="(\/download-index-aid-(\d+)\.html)"/i) {
            my $aid = $2;
            $logger->info("Found aid: $aid");
            return ( url => "https://www.wnacg.org/download-index-aid-$aid.html", title => "Wnacg ZIP $aid" );
        }

        # 策略 2: 圖片 (更寬鬆的正則)
        my @images;
        while ($html =~ /data-original=["']([^"']+\/data\/t\/[^"']+)["']/gi) {
            my $p = $1; $p =~ s/\/t\//\/f\//;
            $p = "https:" . $p if $p =~ /^\/\//;
            push @images, $p;
        }
        
        if (scalar @images > 0) {
            $logger->info("Found " . scalar @images . " images.");
            return ( url_list => \@images, title => "Wnacg Gallery" );
        }
    } else {
        $logger->error("HTTP Error: " . $res->code);
    }

    return ( error => "No content. Check logs for HTML snippet." );
}

1;
