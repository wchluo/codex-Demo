#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use File::Basename;
use File::Path qw(make_path);
use File::stat;

# 脚本功能：
#   1. --prepare 模式下挂载 ISO，分析片段并生成 tasks.csv 任务文件；
#   2. 经人工确认后使用 --run 模式按任务提取 m2ts 并封装为 MKV。
#
# 基本用法：
#   perl process_iso.pl --prepare *.iso --season S01
#   # 检查 tasks.csv 后
#   perl process_iso.pl --run --tasks tasks.csv

my $opt_prepare;                  # --prepare 阶段：扫描 ISO 并生成任务列表
my $opt_run;                      # --run 阶段：根据任务列表进行提取和分装
my $tasks = "tasks.csv";          # 任务列表文件名
my $season = "S01";              # 剧集编号，默认 S01
my $mount_base = "/root/temp/mountdir"; # ISO 挂载目录根路径
GetOptions(
    'prepare' => \$opt_prepare,
    'run'     => \$opt_run,
    'tasks=s' => \$tasks,
    'season=s'=> \$season,
) or die "Usage: $0 --prepare iso1 iso2... | --run --tasks tasks.csv\n";

# 将 "HH:MM:SS" 字符串转换为秒数
sub parse_duration {
    my ($str) = @_;
    my @t = split(/:/, $str);
    return $t[0]*3600 + $t[1]*60 + $t[2];
}

# 获取文件大小（字节）
sub get_filesize {
    my ($path) = @_;
    my $st = stat($path);
    return $st ? $st->size : 0;
}

if ($opt_prepare) {
    die "No ISO files specified\n" unless @ARGV;
    # 写入任务列表，供后续确认
    open(my $fh, '>', $tasks) or die "Cannot write $tasks: $!";
    print $fh "iso,mount,title_index,m2ts,season,episode,filesize,duration\n";
    my $count = 1;
    foreach my $iso (@ARGV) {
        my $mount_dir = "$mount_base/iso$count";
        make_path($mount_dir);
        # 挂载 ISO
        system("mount -o loop '$iso' '$mount_dir'") == 0 or die "mount failed for $iso";
        my @out = `bd_list_titles '$mount_dir'`;
        my @titles;
        foreach my $line (@out) {
            if ($line =~ /^(\d+)\s*:\s*([0-9:]+)\s+(\d+\.m2ts)/) {
                push @titles, { index=>$1, duration=>$2, file=>$3 };
            }
        }
        # 计算最长时长
        my $max = 0;
        foreach my $t (@titles) {
            my $sec = parse_duration($t->{duration});
            $t->{seconds} = $sec;
            $max = $sec if $sec > $max;
        }
        my $threshold = $max * 0.5;
        # 选择时长超过阈值的条目
        my @sel = grep { $_->{seconds} >= $threshold } @titles;
        @sel = sort { $a->{index} <=> $b->{index} } @sel;
        my %seen;
        my $epnum = 1;
        foreach my $t (@sel) {
            my $path = "$mount_dir/BDMV/STREAM/$t->{file}";
            my $size = get_filesize($path);
            next if $seen{$t->{seconds}}{$size}++; # 去重
            my $episode = sprintf("E%02d", $epnum++);
            print $fh join(',', $iso,$mount_dir,$t->{index},$t->{file},$season,$episode,$size,$t->{duration}), "\n";
        }
        system("umount '$mount_dir'") == 0 or warn "umount failed for $iso";
        $count++;
    }
    close $fh;
    print "Tasks written to $tasks. Review and run with --run to process.\n";
}

if ($opt_run) {
    # 读取经人工确认后的任务列表
    open(my $fh,'<',$tasks) or die "Cannot open $tasks: $!";
    my @jobs;
    while(my $line=<$fh>){
        chomp $line;
        next if $line =~ /^iso,/;      # 跳过表头
        my ($iso_path,$mount_dir,$idx,$file,$task_season,$episode,$size,$dur)=split /,/, $line;
        push @jobs,{iso=>$iso_path,mount=>$mount_dir,index=>$idx,file=>$file,season=>$task_season,episode=>$episode};
    }
    close $fh;

    foreach my $job (@jobs){
        make_path($job->{mount});
        # 再次挂载 ISO
        system("mount -o loop '$job->{iso}' '$job->{mount}'") == 0 or die "mount failed";
        my $out_m2ts = "$job->{season}_$job->{episode}.m2ts";
        # 提取指定标题
        system("bd_splice '$job->{mount}' $job->{index} '$out_m2ts'") == 0 or die "bd_splice failed";
        my $out_mkv = "$job->{season}_$job->{episode}.mkv";
        # 无损封装为 MKV
        system("ffmpeg -i '$out_m2ts' -c copy '$out_mkv'") == 0 or warn "ffmpeg failed";
        unlink $out_m2ts;
        system("umount '$job->{mount}'") == 0 or warn "umount failed";
    }
}

