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
        version      => "5.5",
        description  => "Download from wnacg.com (Re-compression Mode for optimal size/naming)",
        url_regex    => 'https?:\/\/(?:www\.)?wnacg\.(?:com|org|net).*(?:aid-|view-|photos-|download-)\d+.*'
    );
}

sub provide_url {
    shift;
    my ($lrr_info, %params) = @_;
    my $logger = get_plugin_logger();
    my $url = $lrr_info->{url};

    $logger->info("--- Wnacg Mojo v5.5 Triggered: $url ---");
    
    # URL 正規化
    if ($url =~ m#(?:aid-|view-aid-|photos-slide-aid-|photos-index-aid-|download-index-aid-)(\d+)#) {
        my $aid = $1;
        my ($base) = $url =~ m#^(https?:\/\/[^/]+)#;
        $url = "$base/photos-index-aid-$aid.html";
    }
    
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
            $title =~ s#[\/\\:\*?"<>\|]#_#g; 
            $title =~ s#^\s+|\s+$##g;
            if (length($title) > 150) { $title = substr($title, 0, 150); }
        }

        # 2. 獲取 AID 用於下載官方 ZIP
        my $aid = "";
        if ($url =~ m#aid-(\d+)#) { $aid = $1; }

        if ($aid) {
            my ($base) = $url =~ m#^(https?:\/\/[^/]+)#;
            my $dl_page = "$base/download-index-aid-$aid.html";
            
            $logger->info("Accessing Download Page: $dl_page");
            my $dl_res = $ua->get($dl_page)->result;
            
            if ($dl_res->is_success) {
                my $dl_html = $dl_res->body;
                if ($dl_html =~ m|href="([^"]+\.zip[^"]*)"|i) {
                    my $zip_url = $1;
                    $zip_url = "https:" . $zip_url if $zip_url =~ m|^//|;
                    
                    if ($lrr_info->{tempdir}) {
                        my $raw_zip = $lrr_info->{tempdir} . "/raw_$aid.zip";
                        my $final_zip = $lrr_info->{tempdir} . "/$title.zip";
                        
                        $logger->info("Downloading official ZIP...");
                        eval {
                            $ua->get($zip_url, { Referer => $dl_page })->result->save_to($raw_zip);
                        };
                        
                        if (!$@ && -s $raw_zip) {
                            $logger->info("Official ZIP downloaded. Re-compressing...");
                            
                            # 關鍵：讀取原始 ZIP 並重新壓縮寫入
                            my $zip_in = Archive::Zip->new();
                            if ($zip_in->read($raw_zip) == AZ_OK) {
                                my $zip_out = Archive::Zip->new();
                                foreach my $member ($zip_in->members()) {
                                    my $m = $zip_out->addMember($member);
                                    $m->desiredCompressionMethod(COMPRESSION_DEFLATED);
                                }
                                $zip_out->writeToFileNamed($final_zip);
                                
                                unlink $raw_zip; # 刪除原始虛大檔案
                                return ( file_path => abs_path($final_zip) );
                            }
                        }
                        $logger->error("Wnacg ZIP processing failed.");
                    }
                }
            }
        }
    }
    return ( error => "Wnacg download failed (v5.5)." );
}

1;
