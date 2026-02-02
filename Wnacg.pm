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
        version      => "4.5",
        description  => "Download from wnacg.com (List Return + Encoding Fix)",
        url_regex    => 'https?:\/\/(?:www\.)?wnacg\.(?:com|org|net).*(?:aid-|view-)\d+.*'
    );
}

sub provide_url {
    shift;
    my ($lrr_info, %params) = @_;
    my $logger = get_plugin_logger();
    my $url = $lrr_info->{url};

    $logger->info("--- Wnacg Mojo v4.5 Triggered ---");
    
    # Normalize URL
    $url =~ s/photos-slide/photos-index/;
    
    # 使用 LRR 提供的 UserAgent
    my $ua = $lrr_info->{user_agent};
    $ua->max_redirects(5);

    my $tx = $ua->get($url);
    my $res = $tx->result;

    if ($res->is_success) {
        my $html = $res->body;
        $logger->info("Index page fetched. Size: " . length($html));

        # 提取標題作為檔名建議 (強化清理)
        my $title = "wnacg_download";
        if ($html =~ m|<h2>(.*?)</h2>|is) {
            $title = $1;
            $title =~ s/<[^>]*>//g; # 移除 HTML 標籤
            $title =~ s/[\r\n\t]//g; # 移除換行符
            $title =~ s/[\/\\:\*\?"<>\|]/_/g; # 移除非法字元
            $title =~ s/^\s+|\s+$//g; # 修剪空白
            $logger->info("Extracted title: $title");
        }

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

                    # 下載並存檔
                    if ($lrr_info->{tempdir}) {
                        my $save_path = $lrr_info->{tempdir} . "/$title.zip";
                        $logger->info("Downloading ZIP to $save_path...");
                        eval {
                            $ua->get($zip_url)->result->save_to($save_path);
                        };
                        if ($@) {
                            $logger->error("Download/Save failed: $@");
                            return ( download_url => $zip_url );
                        }
                        return ( path => $save_path );
                    }
                    
                    return ( download_url => $zip_url );
                }
            }
        }

        # 策略 2: 圖片清單
        my @images;
        my ($base) = $url =~ m|^(https?://[^/]+)|;
        while ($html =~ m|//[^"']+/data/thumb/([^\s"']+)|gi) {
            my $path = $1;
            push @images, "$base/data/f/" . $path;
        }
        
        if (scalar @images > 0) {
            $logger->info("SUCCESS: Found " . scalar @images . " images.");
            return ( url_list => \@images );
        }
    } else {
        return ( error => "HTTP " . $res->code );
    }

    return ( error => "No content found on Wnacg." );
}

1;