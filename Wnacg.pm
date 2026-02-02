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
        version      => "5.1",
        description  => "Download from wnacg.com (Full Title + file_path Fix)",
        url_regex    => 'https?:\/\/(?:www\.)?wnacg\.(?:com|org|net).*(?:aid-|view-|photos-)\d+.*'
    );
}

sub provide_url {
    shift;
    my ($lrr_info, %params) = @_;
    my $logger = get_plugin_logger();
    my $url = $lrr_info->{url};

    $logger->info("--- Wnacg Mojo v5.1 Triggered: $url ---");
    
    # Normalize URL (Handle photos-slide and photos-index)
    $url =~ s#photos-slide#photos-index#;
    $url =~ s#view-aid-#photos-index-aid-#;
    
    # 使用 LRR 提供的 UserAgent
    my $ua = $lrr_info->{user_agent};
    $ua->max_redirects(5);
    $ua->transactor->name('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36');

    my $tx = $ua->get($url);
    my $res = $tx->result;

    if ($res->is_success) {
        my $html = $res->body;
        $logger->info("Index page fetched. Size: " . length($html));

        # 1. 提取完整標題 (參考 nHentai v2.8 邏輯)
        my $title = "";
        if ($html =~ m#<h2>(.*?)</h2>#is) {
            $title = $1;
            $title =~ s#<[^>]*>##g; # 移除 HTML 標籤
            $title =~ s#[\r\n\t]# #g; # 換行轉空格
            $title =~ s#\s+# #g; # 縮減連續空格
            $title =~ s#[\/\\:\*\?"<>\|]#_#g; # 移除非法字元
            $title =~ s#^\s+|\s+$##g; # 修剪空白
            
            if (length($title) > 200) {
                $title = substr($title, 0, 200);
            }
            $logger->info("Extracted Title: $title");
        }

        # 2. 策略 1: 優先嘗試 ZIP 直接下載
        if ($html =~ m|href="(\/download-index-aid-(\d+)\.html)"|i) {
            my $aid = $2;
            my ($base) = $url =~ m|^(https?://[^/]+)|;
            my $dl_page = "$base/download-index-aid-$aid.html";
            
            my $dl_res = $ua->get($dl_page)->result;
            if ($dl_res->is_success) {
                my $dl_html = $dl_res->body;
                if ($dl_html =~ m|href="([^"]+\.zip[^"]*)"|i) {
                    my $zip_url = $1;
                    $zip_url = "https:" . $zip_url if $zip_url =~ m|^//|;
                    
                    if ($lrr_info->{tempdir}) {
                        # 使用清理後的標題作為暫存檔名
                        my $filename = $title || "wnacg_$aid";
                        my $save_path = $lrr_info->{tempdir} . "/$filename.zip";
                        
                        $logger->info("Downloading ZIP to $save_path (Referer: $dl_page)...");
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

        # 3. 策略 2: 圖片清單 (備援)
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
        return ( error => "HTTP " . $res->code );
    }

    return ( error => "No content found on Wnacg." );
}

1;
