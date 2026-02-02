package LANraragi::Plugin::Download::Wnacg;

use strict;
use warnings;
no warnings 'uninitialized';

# 確保在容器環境內能找到 LRR 的核心模組
use lib '/home/koyomi/lanraragi/lib';
use LANraragi::Utils::Logging qw(get_plugin_logger);
use Cwd 'abs_path';

sub plugin_info {
    return (
        name         => "Wnacg Downloader",
        type         => "download",
        namespace    => "wnacg",
        author       => "Gemini CLI",
        version      => "5.2",
        description  => "Download from wnacg.com (Enhanced URL Normalization + Full Title)",
        url_regex    => 'https?://(?:www\.)?wnacg\.(?:com|org|net).*(?:aid-|view-|photos-|download-)\d+.*'
    );
}

sub provide_url {
    shift;
    my ($lrr_info, %params) = @_;
    my $logger = get_plugin_logger();
    my $url = $lrr_info->{url};

    $logger->info("--- Wnacg Mojo v5.2 Triggered: $url ---");
    
    # 強化版 URL 正規化 (全面導向 photos-index)
    if ($url =~ m#(?:aid-|view-aid-|photos-slide-aid-|photos-index-aid-|download-index-aid-)(\d+)#) {
        my $aid = $1;
        my ($base) = $url =~ m#^(https?://[^/]+)#;
        $url = "$base/photos-index-aid-$aid.html";
        $logger->info("Normalized URL to Index: $url");
    }
    
    # 使用 LRR 提供的 UserAgent
    my $ua = $lrr_info->{user_agent};
    $ua->max_redirects(5);
    $ua->transactor->name('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36');

    my $tx = $ua->get($url);
    my $res = $tx->result;

    if ($res->is_success) {
        my $html = $res->body;
        
        # 1. 提取完整標題
        my $title = "";
        if ($html =~ m#<h2>(.*?)</h2>#is) {
            $title = $1;
            $title =~ s#<[^>]*>##g; 
            $title =~ s#[\r\n\t]# #g;
            $title =~ s#\s+# #g;
            $title =~ s#[\/\\:\*\?"<>\|]#_#g; 
            $title =~ s#^\s+|\s+$##g;
            
            if (length($title) > 200) { $title = substr($title, 0, 200); }
            $logger->info("Extracted Title: $title");
        }

        # 2. 獲取 AID 用於下載頁面
        my $aid = "";
        if ($url =~ m#aid-(\d+)#) { $aid = $1; }

        if ($aid) {
            my ($base) = $url =~ m#^(https?://[^/]+)#;
            my $dl_page = "$base/download-index-aid-$aid.html";
            
            $logger->info("Accessing Download Page: $dl_page");
            my $dl_res = $ua->get($dl_page)->result;
            
            if ($dl_res->is_success) {
                my $dl_html = $dl_res->body;
                if ($dl_html =~ m|href="([^"]+\.zip[^"]*)"|i) {
                    my $zip_url = $1;
                    $zip_url = "https:" . $zip_url if $zip_url =~ m|^//|;
                    
                    if ($lrr_info->{tempdir}) {
                        my $filename = $title || "wnacg_$aid";
                        my $save_path = $lrr_info->{tempdir} . "/$filename.zip";
                        
                        $logger->info("Downloading ZIP to $save_path...");
                        eval {
                            $ua->get($zip_url, { Referer => $dl_page })->result->save_to($save_path);
                        };
                        
                        if (!$@ && -s $save_path) {
                            $logger->info("ZIP Download successful.");
                            return ( file_path => abs_path($save_path) );
                        }
                        $logger->error("ZIP Download failed: $@");
                    }
                }
            }
        }

        # 3. 備援：圖片清單
        my @images;
        my ($base) = $url =~ m|^(https?://[^/]+)|;
        while ($html =~ m|//[^"']+/data/thumb/([^\s"']+)|gi) {
            my $path = $1;
            push @images, "$base/data/f/" . $path;
        }
        
        if (scalar @images > 0) {
            $logger->info("SUCCESS: Found " . scalar @images . " images. Returning list.");
            return ( url_list => \@images );
        }
    } else {
        $logger->error("Wnacg Access Error: " . $res->code);
        return ( error => "HTTP " . $res->code );
    }

    return ( error => "No content found on Wnacg." );
}

1;