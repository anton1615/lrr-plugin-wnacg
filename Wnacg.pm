package LANraragi::Plugin::Download::Wnacg;

use strict;
use warnings;
no warnings 'uninitialized';

# 確保在容器環境內能找到 LRR 的核心模組
use lib '/home/koyomi/lanraragi/lib';
use LANraragi::Utils::Logging qw(get_plugin_logger);
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Cwd 'abs_path';

sub plugin_info {
    return (
        name         => "Wnacg Downloader",
        type         => "download",
        namespace    => "wnacg",
        author       => "Gemini CLI",
        version      => "5.4",
        description  => "Download from wnacg.com (Manual Scrape + Deflate Compression)",
        url_regex    => 'https?://(?:www\.)?wnacg\.(?:com|org|net).*(?:aid-|view-|photos-)\d+.*'
    );
}

sub provide_url {
    shift;
    my ($lrr_info, %params) = @_;
    my $logger = get_plugin_logger();
    my $url = $lrr_info->{url};

    $logger->info("--- Wnacg Mojo v5.4 Triggered (Manual Pack Mode) ---");
    
    # URL 正規化
    if ($url =~ m#(?:aid-|view-aid-|photos-slide-aid-|photos-index-aid-|download-index-aid-)(\d+)#) {
        my $aid = $1;
        my ($base) = $url =~ m#^(https?://[^/]+)#;
        $url = "$base/photos-index-aid-$aid.html";
    }
    
    my $ua = $lrr_info->{user_agent};
    $ua->max_redirects(5);
    $ua->transactor->name('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36');

    my $tx = $ua->get($url);
    my $res = $tx->result;

    if ($res->is_success) {
        my $html = $res->body;
        
        # 1. 提取標題
        my $title = "";
        if ($html =~ m#<h2>(.*?)</h2>#is) {
            $title = $1;
            $title =~ s#<[^>]*>##g; 
            $title =~ s#[
	]# #g;
            $title =~ s#\s+# #g;
            $title =~ s#[\/\\:\*?"<>\|]#_#g; 
            $title =~ s#^\s+|\s+$##g;
            if (length($title) > 150) { $title = substr($title, 0, 150); }
        }

        # 2. 獲取圖片路徑前綴與總張數 (Wnacg 特色：預測式抓取)
        my $img_prefix = "";
        if ($html =~ m#//[^"']+/data/thumb/([^\s"']+/與嘅)\.jpg#i) {
            $img_prefix = $1; # 格式如: 202105/12345/1
            $img_prefix =~ s#/與嘅$##; # 拿掉最後的檔名，剩下目錄路徑
        }

        my $total_images = 0;
        if ($html =~ m#<span>(\d+)張圖片</span>#i) {
            $total_images = $1;
        }

        if ($img_prefix && $total_images > 0 && $lrr_info->{tempdir}) {
            my ($base_domain) = $html =~ m#//([^"']+)/data/thumb/#;
            my $work_dir = $lrr_info->{tempdir} . "/wnacg_tmp";
            mkdir $work_dir;
            
            $logger->info("Scraping $total_images images from $base_domain...");
            
            my $downloaded = 0;
            for (my $i = 1; $i <= $total_images; $i++) {
                my $img_url = "https://$base_domain/data/f/$img_prefix/$i.jpg";
                my $save_to = sprintf("%s/%03d.jpg", $work_dir, $i);
                
                eval {
                    my $img_tx = $ua->get($img_url => { Referer => $url });
                    if ($img_tx->result->is_success) {
                        $img_tx->result->save_to($save_to);
                        $downloaded++;
                    }
                };
            }

            if ($downloaded > 0) {
                my $zip_path = $lrr_info->{tempdir} . "/$title.zip";
                my $zip = Archive::Zip->new();
                for (my $i = 1; $i <= $total_images; $i++) {
                    my $img_file = sprintf("%03d.jpg", $i);
                    my $path = "$work_dir/$img_file";
                    if (-e $path) {
                        my $member = $zip->addFile($path, $img_file);
                        $member->desiredCompressionMethod(COMPRESSION_DEFLATED); # 啟用壓縮
                    }
                }
                $zip->writeToFileNamed($zip_path);
                return ( file_path => abs_path($zip_path) );
            }
        }
    }
    return ( error => "Wnacg manual fetch failed." );
}

1;